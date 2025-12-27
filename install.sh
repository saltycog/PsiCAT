#!/bin/bash
set -euo pipefail

# PsiCAT - Docker-based Installation Script
# Builds and runs PsiCAT as a Docker container service
#
# Usage patterns:
# 1. Remote (curl): /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/main/install.sh)"
# 2. Local (from cloned repo): cd /path/to/PsiCAT && sudo bash install.sh

INSTALL_DIR="/opt/psicat/discord"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_section "PsiCAT Installation"
echo ""

# Check for required tools
log_info "Checking for required tools..."
for cmd in docker docker-compose; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required tool not found: $cmd"
        log_info "Install Docker and Docker Compose, then run this script again."
        log_info "See: https://docs.docker.com/engine/install/"
        exit 1
    fi
done
log_info "All required tools found"
echo ""

# Determine build directory
if [[ -f "Dockerfile" ]]; then
    # Local installation (user is in cloned repo)
    BUILD_DIR="$(pwd)"
    log_info "Found Dockerfile in current directory: $BUILD_DIR"
else
    # Remote installation (curl pattern)
    log_info "Dockerfile not found locally, cloning repository..."
    BUILD_DIR=$(mktemp -d)
    trap "rm -rf $BUILD_DIR" EXIT

    if ! git clone "https://github.com/saltycog/PsiCAT.git" "$BUILD_DIR" >/dev/null 2>&1; then
        log_error "Failed to clone repository from GitHub"
        exit 1
    fi
    log_info "Repository cloned"
fi

echo ""

# Stop existing service if running
if [[ -d "$INSTALL_DIR" ]]; then
    log_info "Existing installation found at $INSTALL_DIR"
    if docker ps 2>/dev/null | grep -q psicat-discord; then
        log_info "Stopping running service..."
        cd "$INSTALL_DIR"
        docker-compose down 2>/dev/null || true
    fi
else
    log_info "No existing installation found"
fi

echo ""

# Create installation directory
log_section "Setting up installation directory"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/data/avatars"
log_info "Created $INSTALL_DIR"

# Copy default data from project if not already installed
if [[ ! -f "$INSTALL_DIR/data/quotes.json" ]]; then
    if [[ -f "${BUILD_DIR}/PsiCAT.Core/Data/quotes.json" ]]; then
        log_info "Copying default quotes from project..."
        cp "${BUILD_DIR}/PsiCAT.Core/Data/quotes.json" "$INSTALL_DIR/data/quotes.json"
    else
        log_info "Creating empty quotes database..."
        cat > "$INSTALL_DIR/data/quotes.json" << 'QUOTESFILE'
[]
QUOTESFILE
    fi
fi

if [[ -d "${BUILD_DIR}/PsiCAT.Core/wwwroot/avatars" ]]; then
    for avatar in "${BUILD_DIR}/PsiCAT.Core/wwwroot/avatars"/*; do
        if [[ -f "$avatar" ]]; then
            avatar_name=$(basename "$avatar")
            if [[ ! -f "$INSTALL_DIR/data/avatars/$avatar_name" ]]; then
                log_info "Copying avatar: $avatar_name"
                cp "$avatar" "$INSTALL_DIR/data/avatars/"
            fi
        fi
    done
fi

# Copy docker-compose.yml
log_info "Copying docker-compose.yml..."
cp "${BUILD_DIR}/PsiCAT.Core/daemon/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

# Function to check if config is valid
is_configured() {
    local token=$(grep "^DISCORD_BOT_TOKEN=" "$INSTALL_DIR/.env" 2>/dev/null | cut -d'=' -f2)
    local guild=$(grep "^DISCORD_GUILD_ID=" "$INSTALL_DIR/.env" 2>/dev/null | cut -d'=' -f2)

    # Check if values are set and not empty/placeholder
    if [[ -n "$token" && "$token" != "your_bot_token_here" && \
          -n "$guild" && "$guild" != "your_guild_id_here" ]]; then
        return 0
    fi
    return 1
}

# Check if this is a new installation
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
    NEW_CONFIG="true"
else
    NEW_CONFIG="false"
fi

# Configuration section
log_section "Discord Bot Configuration"
echo ""

if [[ "$NEW_CONFIG" == "true" ]]; then
    log_info "New installation - Discord bot configuration required"
    echo ""
    echo "Get your Discord bot token from: https://discord.com/developers/applications"
    echo ""

    # Prompt for bot token
    while true; do
        read -p "Discord Bot Token: " -r BOT_TOKEN
        if [[ -n "$BOT_TOKEN" && ${#BOT_TOKEN} -gt 10 ]]; then
            break
        fi
        log_error "Invalid token - please try again"
    done

    # Prompt for guild ID
    while true; do
        read -p "Discord Guild ID: " -r GUILD_ID
        if [[ "$GUILD_ID" =~ ^[0-9]+$ && ${#GUILD_ID} -gt 5 ]]; then
            break
        fi
        log_error "Invalid guild ID - must be a number"
    done

    # Optional: Avatar base URL
    read -p "Avatar Base URL (default: http://0.0.0.0:5247): " -r AVATAR_URL
    AVATAR_URL="${AVATAR_URL:-http://0.0.0.0:5247}"

    # Write configuration file
    log_info "Writing configuration..."
    cat > "$INSTALL_DIR/.env" << ENVFILE
# Discord Bot Configuration
DISCORD_BOT_TOKEN=$BOT_TOKEN
DISCORD_GUILD_ID=$GUILD_ID

# Application Configuration
AVATAR_BASE_URL=$AVATAR_URL
ASPNETCORE_ENVIRONMENT=Production
ENVFILE

    log_info "Configuration saved"
    echo ""

else
    # Existing installation
    if is_configured; then
        log_info "Existing configuration found and is valid"
        echo ""
    else
        log_warn "Configuration found but may be incomplete"
        echo ""
        echo "Update configuration? (y/n): "
        read -p "" -r UPDATE_CONFIG

        if [[ "$UPDATE_CONFIG" =~ ^[Yy]$ ]]; then
            # Prompt for bot token
            while true; do
                read -p "Discord Bot Token: " -r BOT_TOKEN
                if [[ -n "$BOT_TOKEN" && ${#BOT_TOKEN} -gt 10 ]]; then
                    break
                fi
                log_error "Invalid token - please try again"
            done

            # Prompt for guild ID
            while true; do
                read -p "Discord Guild ID: " -r GUILD_ID
                if [[ "$GUILD_ID" =~ ^[0-9]+$ && ${#GUILD_ID} -gt 5 ]]; then
                    break
                fi
                log_error "Invalid guild ID - must be a number"
            done

            # Optional: Avatar base URL
            read -p "Avatar Base URL (default: http://0.0.0.0:5247): " -r AVATAR_URL
            AVATAR_URL="${AVATAR_URL:-http://0.0.0.0:5247}"

            # Update configuration file
            log_info "Updating configuration..."
            cat > "$INSTALL_DIR/.env" << ENVFILE
# Discord Bot Configuration
DISCORD_BOT_TOKEN=$BOT_TOKEN
DISCORD_GUILD_ID=$GUILD_ID

# Application Configuration
AVATAR_BASE_URL=$AVATAR_URL
ASPNETCORE_ENVIRONMENT=Production
ENVFILE

            log_info "Configuration updated"
            echo ""
        else
            log_info "Keeping existing configuration"
            echo ""
        fi
    fi
fi

echo ""

# Build Docker image
log_section "Building Docker image"
log_info "Building docker image (this may take a few minutes)..."
if ! docker build -t psicat:latest "$BUILD_DIR"; then
    log_error "Failed to build Docker image"
    exit 1
fi
log_info "Docker image built successfully"

echo ""

# Start the service
log_section "Starting PsiCAT service"
cd "$INSTALL_DIR"

if ! docker-compose up -d; then
    log_error "Failed to start service with docker-compose"
    exit 1
fi

log_info "Service started"

# Wait for container to start
sleep 2

# Verify container is running
if docker ps | grep -q psicat-discord; then
    log_info "Container is running"
else
    log_error "Container failed to start - check logs:"
    docker-compose logs
    exit 1
fi

echo ""
log_section "Installation Complete"
echo ""
log_info "PsiCAT is running and listening on 0.0.0.0:5247"
echo ""

if is_configured; then
    log_info "Bot is configured and starting up"
    log_info "Check connection status: docker logs -f psicat-discord"
else
    log_warn "Bot is NOT configured - it will not connect to Discord yet"
    echo ""
    echo "To configure:"
    echo "  sudo nano $INSTALL_DIR/.env"
    echo ""
    echo "Then restart the service:"
    echo "  cd $INSTALL_DIR && docker-compose restart"
    echo ""
    echo "Check logs:"
    echo "  docker logs -f psicat-discord"
fi

echo ""
log_info "Useful commands:"
echo "  View logs:        docker logs -f psicat-discord"
echo "  Restart service:  cd $INSTALL_DIR && docker-compose restart"
echo "  Stop service:     cd $INSTALL_DIR && docker-compose down"
echo "  Edit config:      sudo nano $INSTALL_DIR/.env"
echo ""
