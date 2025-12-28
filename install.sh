#!/bin/bash
set -euo pipefail

# PsiCAT - Docker-based Installation Script
# Builds and runs PsiCAT as a Docker container service
#
# Usage patterns:
# 1. Remote (curl): /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/main/install.sh)"
# 2. Remote (specific branch): /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/fix/branch-name/install.sh)" -- fix/branch-name
# 3. Local (from cloned repo): cd /path/to/PsiCAT && sudo bash install.sh

INSTALL_DIR="/opt/psicat/discord"
CLONE_BRANCH="${1:-main}"

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

    if ! git clone -b "$CLONE_BRANCH" "https://github.com/saltycog/PsiCAT.git" "$BUILD_DIR" >/dev/null 2>&1; then
        log_error "Failed to clone repository from GitHub (branch: $CLONE_BRANCH)"
        exit 1
    fi
    log_info "Repository cloned (branch: $CLONE_BRANCH)"
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
    log_info "Quotes file created at: $INSTALL_DIR/data/quotes.json"
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

# Remove directory if it exists from failed previous install (prevents cp from creating nested structure)
if [[ -d "$INSTALL_DIR/appsettings.json" ]]; then
    log_warn "Removing directory at appsettings.json (from failed previous install)..."
    rm -rf "$INSTALL_DIR/appsettings.json"
fi

if [[ ! -f "$INSTALL_DIR/appsettings.json" ]]; then
    log_info "Copying configuration template..."
    cp "${BUILD_DIR}/PsiCAT.Core/appsettings.json" "$INSTALL_DIR/appsettings.json"
fi

# Check if this is an update from an older version (has .env file)
if [[ -f "$INSTALL_DIR/.env" ]]; then
    log_warn "Old .env file found - you may need to migrate settings to appsettings.json"
fi

# Ensure proper permissions for docker to access mounted volumes
chmod -R 755 "$INSTALL_DIR/data" 2>/dev/null || true
log_info "Data directory ready for mounting at: $INSTALL_DIR/data"

# Copy docker-compose.yml
log_info "Copying docker-compose.yml..."
cp "${BUILD_DIR}/PsiCAT.Core/daemon/docker-compose.yml" "$INSTALL_DIR/docker-compose.yml"

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

# Critical: Ensure appsettings.json exists as a FILE before docker-compose runs
# Docker will create it as a DIRECTORY if it doesn't exist, causing mount failure
if [[ -d "$INSTALL_DIR/appsettings.json" ]]; then
    log_warn "appsettings.json is a directory! Removing and recreating as file..."
    rm -rf "$INSTALL_DIR/appsettings.json"
fi

if [[ ! -f "$INSTALL_DIR/appsettings.json" ]]; then
    log_error "appsettings.json is missing! Attempting to copy from build directory..."
    if [[ -f "${BUILD_DIR}/PsiCAT.Core/appsettings.json" ]]; then
        cp "${BUILD_DIR}/PsiCAT.Core/appsettings.json" "$INSTALL_DIR/appsettings.json"
        log_info "appsettings.json copied successfully"
    else
        log_error "Source appsettings.json not found at: ${BUILD_DIR}/PsiCAT.Core/appsettings.json"
        log_error "Cannot proceed without configuration file"
        exit 1
    fi
fi

# Final verification
if [[ ! -f "$INSTALL_DIR/appsettings.json" ]]; then
    log_error "Failed to create appsettings.json as a file"
    log_error "Check permissions and filesystem at: $INSTALL_DIR"
    exit 1
fi

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

log_warn "IMPORTANT: Configure your bot before it will work"
echo ""
echo "Edit the configuration file:"
echo "  sudo nano $INSTALL_DIR/appsettings.json"
echo ""
echo "After editing, restart the service:"
echo "  cd $INSTALL_DIR && docker-compose restart"
echo ""

echo ""
log_info "Useful commands:"
echo "  View logs:        docker logs -f psicat-discord"
echo "  Restart service:  cd $INSTALL_DIR && docker-compose restart"
echo "  Stop service:     cd $INSTALL_DIR && docker-compose down"
echo "  Edit config:      sudo nano $INSTALL_DIR/appsettings.json"
echo ""
