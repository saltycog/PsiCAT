#!/bin/bash
set -euo pipefail

# PsiCAT - Uninstall Script
# Removes PsiCAT installation and optionally cleans up Docker image
#
# Usage: bash uninstall.sh
#
# This script:
# 1. Verifies installation exists
# 2. Offers to back up data before removal
# 3. Stops the service
# 4. Removes the installation directory
# 5. Optionally removes the Docker image

# Configuration
INSTALL_DIR="/opt/psicat/discord"
BACKUP_BASE_DIR="/tmp"

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

log_section "PsiCAT Uninstall"
echo ""

# Check if installation exists
if [[ ! -d "$INSTALL_DIR" ]]; then
    log_error "No PsiCAT installation found at $INSTALL_DIR"
    exit 1
fi

log_info "Found PsiCAT installation at $INSTALL_DIR"
echo ""

# Offer to back up data
log_section "Data Backup"
if prompt_yes_no "Back up data before uninstalling?" "y"; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="$BACKUP_BASE_DIR/psicat-backup-$TIMESTAMP"

    log_info "Creating backup at $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    if [[ -d "$INSTALL_DIR/data" ]]; then
        cp -r "$INSTALL_DIR/data" "$BACKUP_DIR/"
        log_info "Backed up data directory"
    fi

    if [[ -f "$INSTALL_DIR/.env" ]]; then
        cp "$INSTALL_DIR/.env" "$BACKUP_DIR/"
        log_info "Backed up .env configuration"
    fi

    log_info "Backup complete: $BACKUP_DIR"
    echo ""
else
    log_warn "Skipping backup"
    echo ""
fi

# Final confirmation
echo ""
log_warn "This will permanently remove PsiCAT from your system."
log_warn "Location: $INSTALL_DIR"
echo ""

if ! prompt_yes_no "Are you sure you want to uninstall PsiCAT?" "n"; then
    log_info "Uninstall cancelled"
    exit 0
fi

echo ""

# Stop the service
log_section "Stopping PsiCAT service"
if docker ps | grep -q psicat-discord; then
    log_info "Stopping docker-compose service..."
    cd "$INSTALL_DIR"
    docker-compose down || log_warn "Could not stop service gracefully"
else
    log_info "Service not running"
fi

echo ""

# Remove installation directory
log_section "Removing installation"
log_info "Removing $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"
log_info "Installation directory removed"

echo ""

# Offer to remove Docker image
log_section "Docker Image Cleanup"
if docker images | grep -q "psicat.*latest"; then
    if prompt_yes_no "Remove psicat:latest Docker image?" "n"; then
        log_info "Removing Docker image..."
        docker rmi psicat:latest || log_warn "Could not remove Docker image"
        log_info "Docker image removed"
    else
        log_info "Docker image preserved"
    fi
else
    log_info "No psicat:latest Docker image found"
fi

echo ""
log_section "Uninstall Complete"
log_info "PsiCAT has been uninstalled"
echo ""
