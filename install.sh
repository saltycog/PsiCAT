#!/bin/bash
set -euo pipefail

# PsiCAT - Docker-based Remote Installation and Update Script
# Downloads the latest Docker image and uses docker-compose to run the service
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/PsiCAT/main/install.sh)"
# Or: bash install.sh [GITHUB_REPO_URL]

# Configuration
GITHUB_REPO="${1:-saltycog/PsiCAT}"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/psicat/discord"
BACKUP_DIR="${INSTALL_DIR}.backup"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "${BLUE}==>${NC} $1"
}

# Prompt user with yes/no question
prompt_yes_no() {
    local question="$1"
    local default="${2:-n}"

    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$question (Y/n): " response
            response="${response:-y}"
        else
            read -p "$question (y/N): " response
            response="${response:-n}"
        fi

        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_section "PsiCAT Docker Installation/Update"
log_info "Repository: $GITHUB_REPO"
echo ""

# Check for required tools
log_info "Checking for required tools..."
for cmd in docker docker-compose curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required tool not found: $cmd"
        log_info "Install Docker and Docker Compose, then run this script again."
        log_info "See: https://docs.docker.com/engine/install/"
        exit 1
    fi
done

# Check if installation exists
is_installed() {
    [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/docker-compose.yml" && -f "$INSTALL_DIR/.env" ]]
}

# Extract version from release tag (v1.2.3 -> 1.2.3)
normalize_version() {
    echo "${1#v}"
}

# Compare two semantic versions: returns 0 if v1 > v2
version_greater_than() {
    local v1=$(normalize_version "$1")
    local v2=$(normalize_version "$2")

    if [[ "$v1" == "$v2" ]]; then
        return 1  # equal
    fi

    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]
}

# Get installed version
get_installed_version() {
    if [[ -f "$INSTALL_DIR/.psicat-version" ]]; then
        cat "$INSTALL_DIR/.psicat-version"
    else
        echo "unknown"
    fi
}

# Display current installation status
if is_installed; then
    INSTALLED_VERSION=$(get_installed_version)
    log_info "Current installation: $INSTALLED_VERSION"
else
    log_info "No existing installation found"
fi

echo ""

# Fetch latest release info
log_info "Fetching latest release from GitHub..."
RELEASE_INFO=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null || {
    log_error "Failed to fetch release information"
    log_info "Ensure the repository exists and is public: https://github.com/${GITHUB_REPO}"
    exit 1
})

# Extract release information
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name' 2>/dev/null || echo "")

if [[ -z "$RELEASE_TAG" ]]; then
    log_error "Could not parse release information"
    echo "Response: $RELEASE_INFO" >&2
    exit 1
fi

log_info "Latest available release: $RELEASE_TAG"

# Check if update is needed
if is_installed; then
    if version_greater_than "$RELEASE_TAG" "$INSTALLED_VERSION"; then
        log_info "Update available: $INSTALLED_VERSION -> $RELEASE_TAG"
        echo ""
        if ! prompt_yes_no "Install update?" "y"; then
            log_info "Update cancelled"
            exit 0
        fi
        IS_UPDATE="true"
    else
        log_info "Already running latest version ($INSTALLED_VERSION)"
        if ! prompt_yes_no "Reinstall anyway?" "n"; then
            log_info "Installation cancelled"
            exit 0
        fi
        IS_UPDATE="false"
    fi
else
    IS_UPDATE="false"
fi

echo ""

# Prepare for update
if [[ "$IS_UPDATE" == "true" ]]; then
    touch "$INSTALL_DIR/.install-lock"

    log_section "Preparing update"
    log_info "Stopping Docker service..."
    cd "$INSTALL_DIR"
    docker-compose down || log_warn "Service was not running"

    # Create backup of current installation
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Removing old backup..."
        rm -rf "$BACKUP_DIR"
    fi

    log_info "Creating backup at $BACKUP_DIR"
    cp -r "$INSTALL_DIR" "$BACKUP_DIR"
fi

# Create installation directory
log_section "Setting up installation"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/data/avatars"

# Download docker-compose.yml
log_info "Downloading docker-compose.yml..."
if ! curl -fsSL "${GITHUB_RAW}/PsiCAT.Core/daemon/docker-compose.yml" -o "$INSTALL_DIR/docker-compose.yml"; then
    log_error "Failed to download docker-compose.yml"
    if [[ "$IS_UPDATE" == "true" ]]; then
        log_error "Restoring from backup..."
        rm -rf "$INSTALL_DIR"
        mv "$BACKUP_DIR" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        docker-compose up -d || log_warn "Could not restart service"
        rm -f "$INSTALL_DIR/.install-lock"
    fi
    exit 1
fi

# Create or update .env file
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    log_info "Creating .env configuration file..."
    cat > "$INSTALL_DIR/.env" << 'ENVFILE'
# Discord Bot Configuration
DISCORD_BOT_TOKEN=your_bot_token_here
DISCORD_GUILD_ID=your_guild_id_here

# Application Configuration
AVATAR_BASE_URL=http://localhost:5247
ASPNETCORE_ENVIRONMENT=Production
ENVFILE
    log_warn "Please edit .env file with your Discord bot token and guild ID:"
    log_warn "  sudo nano $INSTALL_DIR/.env"
else
    log_info "Found existing .env file, keeping current configuration"
fi

# Pull the latest Docker image
log_section "Pulling Docker image"
log_info "Pulling ghcr.io/saltycog/psicat:latest..."
if ! docker pull ghcr.io/saltycog/psicat:latest; then
    log_error "Failed to pull Docker image"
    if [[ "$IS_UPDATE" == "true" ]]; then
        log_error "Restoring from backup..."
        rm -rf "$INSTALL_DIR"
        mv "$BACKUP_DIR" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        docker-compose up -d || log_warn "Could not restart service"
        rm -f "$INSTALL_DIR/.install-lock"
    fi
    exit 1
fi

# Start the service
log_section "Starting PsiCAT service"
cd "$INSTALL_DIR"

if docker-compose up -d; then
    log_info "Service started successfully!"
else
    log_error "Failed to start service"
    if [[ "$IS_UPDATE" == "true" ]]; then
        log_error "Restoring from backup..."
        rm -rf "$INSTALL_DIR"
        mv "$BACKUP_DIR" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        docker-compose up -d || log_warn "Could not restart service"
        rm -f "$INSTALL_DIR/.install-lock"
    fi
    exit 1
fi

# Wait for container to be healthy
log_info "Waiting for service to be ready..."
sleep 3

if docker ps | grep -q psicat-discord; then
    log_info "Service is running"
else
    log_error "Service failed to start"
    docker-compose logs
    exit 1
fi

# Write version file
echo "$RELEASE_TAG" > "$INSTALL_DIR/.psicat-version"

# Remove lock file
rm -f "$INSTALL_DIR/.install-lock"

# Summary
echo ""
if [[ "$IS_UPDATE" == "true" ]]; then
    log_section "Update Complete"
    log_info "PsiCAT has been updated to version: $RELEASE_TAG"
    log_info "Service has been restarted"
else
    log_section "Installation Complete"
    log_info "PsiCAT has been installed (version: $RELEASE_TAG)"
fi

echo ""
log_info "Service is running at: http://localhost:5247"
echo ""
log_info "Useful commands:"
echo "  - View logs:"
echo "    docker logs -f psicat-discord"
echo ""
echo "  - Check status:"
echo "    docker ps | grep psicat"
echo ""
echo "  - Restart service:"
echo "    cd $INSTALL_DIR && docker-compose restart"
echo ""
echo "  - Stop service:"
echo "    cd $INSTALL_DIR && docker-compose down"
echo ""
echo "  - Update configuration:"
echo "    sudo nano $INSTALL_DIR/.env"
echo "    cd $INSTALL_DIR && docker-compose restart"
echo ""
