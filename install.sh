#!/bin/bash
set -euo pipefail

# PsiCAT - Remote Installation Script
# Downloads the latest release from GitHub and installs binaries + daemon
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/PsiCAT/main/install.sh)"
# Or: bash install.sh [GITHUB_REPO_URL]

# Configuration
GITHUB_REPO="${1:-PsiCAT/PsiCAT}"  # Default: PsiCAT/PsiCAT, override with argument
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_section "PsiCAT Installation"
log_info "Repository: $GITHUB_REPO"

# Check for required tools
for cmd in curl jq tar; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required tool not found: $cmd"
        exit 1
    fi
done

# Fetch latest release info
log_info "Fetching latest release from GitHub..."
RELEASE_INFO=$(curl -fsSL "$GITHUB_API" 2>/dev/null || {
    log_error "Failed to fetch release information"
    log_info "Ensure the repository exists and is public: https://github.com/${GITHUB_REPO}"
    exit 1
})

# Extract release information
RELEASE_TAG=$(echo "$RELEASE_INFO" | jq -r '.tag_name' 2>/dev/null || echo "")
RELEASE_URL=$(echo "$RELEASE_INFO" | jq -r '.assets[0].browser_download_url' 2>/dev/null || echo "")

if [[ -z "$RELEASE_TAG" || -z "$RELEASE_URL" ]]; then
    log_error "Could not parse release information"
    echo "Response: $RELEASE_INFO" >&2
    exit 1
fi

log_info "Found release: $RELEASE_TAG"

# Download release asset
log_info "Downloading release artifact..."
ARCHIVE_NAME=$(basename "$RELEASE_URL")
if ! curl -fsSL -o "$TEMP_DIR/$ARCHIVE_NAME" "$RELEASE_URL"; then
    log_error "Failed to download release artifact"
    exit 1
fi

log_info "Downloaded: $ARCHIVE_NAME"

# Extract archive
log_info "Extracting files..."
case "$ARCHIVE_NAME" in
    *.tar.gz)
        tar -xzf "$TEMP_DIR/$ARCHIVE_NAME" -C "$TEMP_DIR"
        ;;
    *.zip)
        unzip -q "$TEMP_DIR/$ARCHIVE_NAME" -d "$TEMP_DIR"
        ;;
    *)
        log_error "Unsupported archive format: $ARCHIVE_NAME"
        exit 1
        ;;
esac

# Find the install-service.sh script
INSTALL_SERVICE_SCRIPT=""
if [[ -f "$TEMP_DIR/PsiCAT.DiscordApp/daemon/install-service.sh" ]]; then
    INSTALL_SERVICE_SCRIPT="$TEMP_DIR/PsiCAT.DiscordApp/daemon/install-service.sh"
elif [[ -f "$TEMP_DIR/daemon/install-service.sh" ]]; then
    INSTALL_SERVICE_SCRIPT="$TEMP_DIR/daemon/install-service.sh"
fi

if [[ -z "$INSTALL_SERVICE_SCRIPT" ]]; then
    log_error "Could not find install-service.sh in archive"
    log_info "Archive contents:"
    find "$TEMP_DIR" -name "install-service.sh" 2>/dev/null || true
    exit 1
fi

log_info "Found daemon installation script"

# Make the installation script executable
chmod +x "$INSTALL_SERVICE_SCRIPT"

# Run the daemon installation script
log_section "Installing systemd daemon service"
if bash "$INSTALL_SERVICE_SCRIPT"; then
    log_info "Daemon installation completed successfully!"
else
    log_error "Daemon installation failed"
    exit 1
fi

# Summary
log_section "Installation Complete"
echo ""
log_info "PsiCAT has been installed (version: $RELEASE_TAG)"
log_info "Service name: psicat-discord"
echo ""
log_info "Next steps:"
echo "  1. Configure your bot token and guild ID:"
echo "     sudo vi /opt/psicat/discord/appsettings.json"
echo ""
echo "  2. Start the service:"
echo "     sudo systemctl start psicat-discord"
echo ""
echo "  3. Check status:"
echo "     sudo systemctl status psicat-discord"
echo ""
echo "  4. View logs:"
echo "     sudo journalctl -u psicat-discord -f"
echo ""
