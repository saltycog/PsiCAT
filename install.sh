#!/bin/bash
set -euo pipefail

# PsiCAT - Docker-based Installation and Update Script
# Builds Docker image locally and uses docker-compose to run the service
#
# Usage patterns:
# 1. Remote (curl): /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/main/install.sh)"
#    - Clones repository and builds locally
#
# 2. Local (from cloned repo): cd /path/to/PsiCAT && bash install.sh
#    - Builds from current directory
#
# Optional argument: custom GitHub repo (default: saltycog/PsiCAT)
# Example: bash install.sh myorg/MyPsiCAT

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
for cmd in docker docker-compose curl jq git; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required tool not found: $cmd"
        log_info "Install Docker and Docker Compose, then run this script again."
        log_info "See: https://docs.docker.com/engine/install/"
        exit 1
    fi
done

# Determine where to build Docker image from
if [[ -f "Dockerfile" ]]; then
    # Local installation (user cloned repo first)
    BUILD_DIR="$(pwd)"
    CLONED_BUILD_DIR=false
    log_info "Found Dockerfile in current directory"
else
    # Remote installation (curl pattern) - clone repo to temp directory
    log_info "Dockerfile not found locally, cloning repository..."
    BUILD_DIR=$(mktemp -d)
    CLONED_BUILD_DIR=true
    if ! git clone "https://github.com/${GITHUB_REPO}.git" "$BUILD_DIR" >/dev/null 2>&1; then
        log_error "Failed to clone repository"
        rm -rf "$BUILD_DIR"
        exit 1
    fi
    log_info "Repository cloned for building"
fi

# Check if installation exists
is_installed() {
    [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/docker-compose.yml" && -f "$INSTALL_DIR/.env" ]]
}

# Get installed commit hash
get_installed_commit() {
    if [[ -f "$INSTALL_DIR/.psicat-commit" ]]; then
        cat "$INSTALL_DIR/.psicat-commit"
    else
        echo ""
    fi
}

# Display current installation status
if is_installed; then
    INSTALLED_COMMIT=$(get_installed_commit)
    if [[ -n "$INSTALLED_COMMIT" ]]; then
        log_info "Current installation: ${INSTALLED_COMMIT:0:7}"
    else
        log_info "Current installation found (version unknown)"
    fi
else
    log_info "No existing installation found"
fi

echo ""

# Fetch latest commit hash from main branch
log_info "Fetching latest commit from GitHub..."
COMMIT_INFO=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/commits/main" 2>/dev/null || {
    log_error "Failed to fetch commit information"
    log_info "Ensure the repository exists and is public: https://github.com/${GITHUB_REPO}"
    exit 1
})

# Extract commit hash
LATEST_COMMIT=$(echo "$COMMIT_INFO" | jq -r '.sha' 2>/dev/null || echo "")

if [[ -z "$LATEST_COMMIT" ]]; then
    log_error "Could not parse commit information"
    echo "Response: $COMMIT_INFO" >&2
    exit 1
fi

log_info "Latest commit: ${LATEST_COMMIT:0:7}"

# Check if update is needed
if is_installed; then
    INSTALLED_COMMIT=$(get_installed_commit)
    if [[ "$INSTALLED_COMMIT" != "$LATEST_COMMIT" ]]; then
        log_info "Update available"
        echo ""
        if ! prompt_yes_no "Install update?" "y"; then
            log_info "Update cancelled"
            exit 0
        fi
        IS_UPDATE="true"
    else
        log_info "Already running latest version"
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

# Build Docker image locally
log_section "Building Docker image"
log_info "Building Docker image from Dockerfile..."
if ! docker build -t psicat:latest "$BUILD_DIR"; then
    log_error "Failed to build Docker image"
    if [[ "$CLONED_BUILD_DIR" == "true" ]]; then
        rm -rf "$BUILD_DIR"
    fi
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

# Clean up cloned build directory if we created it
if [[ "$CLONED_BUILD_DIR" == "true" ]]; then
    log_info "Cleaning up temporary build directory"
    rm -rf "$BUILD_DIR"
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

# Write commit hash file
echo "$LATEST_COMMIT" > "$INSTALL_DIR/.psicat-commit"

# Remove lock file
rm -f "$INSTALL_DIR/.install-lock"

# Summary
echo ""
if [[ "$IS_UPDATE" == "true" ]]; then
    log_section "Update Complete"
    log_info "PsiCAT has been updated to commit: ${LATEST_COMMIT:0:7}"
    log_info "Service has been restarted"
else
    log_section "Installation Complete"
    log_info "PsiCAT has been installed (commit: ${LATEST_COMMIT:0:7})"
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
