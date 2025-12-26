#!/bin/bash
set -euo pipefail

# PsiCAT - Remote Installation and Update Script
# Downloads the latest release from GitHub and installs binaries + daemon
# Supports updating existing installations
# Usage: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_ORG/PsiCAT/main/install.sh)"
# Or: bash install.sh [GITHUB_REPO_URL]

# Configuration
GITHUB_REPO="${1:-saltycog/PsiCAT}"  # Default: saltycog/PsiCAT, override with argument
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
INSTALL_DIR="/opt/psicat/discord"
SERVICE_NAME="psicat-discord"
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_section "PsiCAT Installation/Update"
log_info "Repository: $GITHUB_REPO"

# Check if PsiCAT is already installed
is_installed() {
    [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/appsettings.json" ]]
}

# Extract version from release tag (v1.2.3 -> 1.2.3)
normalize_version() {
    echo "${1#v}"
}

# Compare two semantic versions: returns 1 if v1 > v2, 0 otherwise
version_greater_than() {
    local v1=$(normalize_version "$1")
    local v2=$(normalize_version "$2")

    if [[ "$v1" == "$v2" ]]; then
        return 1  # equal
    fi

    # Simple comparison: convert to comparable format
    [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]
}

# Get installed version (from systemd service or release info file)
get_installed_version() {
    if [[ -f "$INSTALL_DIR/.psicat-version" ]]; then
        cat "$INSTALL_DIR/.psicat-version"
    else
        echo "unknown"
    fi
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

# Check if installation is already in progress
if [[ -f "$INSTALL_DIR/.install-lock" ]]; then
    log_warn "Installation in progress or previous installation was interrupted"
    if prompt_yes_no "Remove lock and continue?" "y"; then
        rm -f "$INSTALL_DIR/.install-lock"
    else
        log_error "Installation cancelled"
        exit 1
    fi
fi

# Display current installation status
if is_installed; then
    INSTALLED_VERSION=$(get_installed_version)
    log_info "Current installation: $INSTALLED_VERSION"
else
    log_info "No existing installation found"
fi

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
    log_info "Stopping service..."
    systemctl stop "$SERVICE_NAME" || log_warn "Service was not running"

    # Create backup of current installation
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Removing old backup..."
        rm -rf "$BACKUP_DIR"
    fi

    log_info "Creating backup at $BACKUP_DIR"
    cp -r "$INSTALL_DIR" "$BACKUP_DIR"
fi

# Download release asset
log_info "Downloading release artifact..."
ARCHIVE_NAME=$(basename "$RELEASE_URL")
if ! curl -fsSL -o "$TEMP_DIR/$ARCHIVE_NAME" "$RELEASE_URL"; then
    log_error "Failed to download release artifact"
    if [[ "$IS_UPDATE" == "true" ]]; then
        log_error "Restoring from backup..."
        rm -rf "$INSTALL_DIR"
        cp -r "$BACKUP_DIR" "$INSTALL_DIR"
        systemctl start "$SERVICE_NAME" || log_warn "Could not restart service"
        rm -f "$INSTALL_DIR/.install-lock"
    fi
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
        if [[ "$IS_UPDATE" == "true" ]]; then
            log_error "Restoring from backup..."
            rm -rf "$INSTALL_DIR"
            cp -r "$BACKUP_DIR" "$INSTALL_DIR"
            systemctl start "$SERVICE_NAME" || log_warn "Could not restart service"
            rm -f "$INSTALL_DIR/.install-lock"
        fi
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
    if [[ "$IS_UPDATE" == "true" ]]; then
        log_error "Restoring from backup..."
        rm -rf "$INSTALL_DIR"
        cp -r "$BACKUP_DIR" "$INSTALL_DIR"
        systemctl start "$SERVICE_NAME" || log_warn "Could not restart service"
        rm -f "$INSTALL_DIR/.install-lock"
    fi
    exit 1
fi

log_info "Found daemon installation script"

# For updates, we need to preserve configuration and data
if [[ "$IS_UPDATE" == "true" ]]; then
    log_info "Preserving configuration and data files..."

    # Backup config and data before clearing install dir
    mkdir -p "$TEMP_DIR/preserved"
    [[ -f "$INSTALL_DIR/appsettings.json" ]] && cp "$INSTALL_DIR/appsettings.json" "$TEMP_DIR/preserved/"
    [[ -f "$INSTALL_DIR/appsettings.Development.json" ]] && cp "$INSTALL_DIR/appsettings.Development.json" "$TEMP_DIR/preserved/"
    [[ -d "$INSTALL_DIR/Data" ]] && cp -r "$INSTALL_DIR/Data" "$TEMP_DIR/preserved/"
    [[ -d "$INSTALL_DIR/wwwroot" ]] && cp -r "$INSTALL_DIR/wwwroot" "$TEMP_DIR/preserved/"
fi

# Make the installation script executable
chmod +x "$INSTALL_SERVICE_SCRIPT"

# Run the daemon installation script
log_section "Installing systemd daemon service"
if bash "$INSTALL_SERVICE_SCRIPT"; then
    log_info "Installation completed successfully!"
else
    log_error "Installation failed"
    if [[ "$IS_UPDATE" == "true" ]]; then
        log_error "Restoring from backup..."
        rm -rf "$INSTALL_DIR"
        cp -r "$BACKUP_DIR" "$INSTALL_DIR"
        systemctl start "$SERVICE_NAME" || log_warn "Could not restart service"
        rm -f "$INSTALL_DIR/.install-lock"
    fi
    exit 1
fi

# Restore preserved files for updates
if [[ "$IS_UPDATE" == "true" ]]; then
    log_info "Restoring configuration and data files..."
    [[ -f "$TEMP_DIR/preserved/appsettings.json" ]] && cp "$TEMP_DIR/preserved/appsettings.json" "$INSTALL_DIR/"
    [[ -f "$TEMP_DIR/preserved/appsettings.Development.json" ]] && cp "$TEMP_DIR/preserved/appsettings.Development.json" "$INSTALL_DIR/"
    [[ -d "$TEMP_DIR/preserved/Data" ]] && cp -r "$TEMP_DIR/preserved/Data"/* "$INSTALL_DIR/Data/"
    [[ -d "$TEMP_DIR/preserved/wwwroot" ]] && cp -r "$TEMP_DIR/preserved/wwwroot"/* "$INSTALL_DIR/wwwroot/"

    # Ensure permissions are correct
    chown -R psicat:psicat "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR/PsiCAT.DiscordApp"
    chmod 750 "$INSTALL_DIR/Data"
    chmod 755 "$INSTALL_DIR/wwwroot"

    log_info "Restarting service..."
    systemctl start "$SERVICE_NAME"
fi

# Write version file
echo "$RELEASE_TAG" > "$INSTALL_DIR/.psicat-version"
chown psicat:psicat "$INSTALL_DIR/.psicat-version"

# Remove lock file
rm -f "$INSTALL_DIR/.install-lock"

# Summary
if [[ "$IS_UPDATE" == "true" ]]; then
    log_section "Update Complete"
    log_info "PsiCAT has been updated to version: $RELEASE_TAG"
    log_info "Service has been restarted"
    echo ""
    log_info "Useful commands:"
    echo "  - Check status:"
    echo "    sudo systemctl status psicat-discord"
    echo ""
    echo "  - View logs:"
    echo "    sudo journalctl -u psicat-discord -f"
    echo ""
    echo "  - Restore from backup (if needed):"
    echo "    sudo systemctl stop psicat-discord"
    echo "    sudo rm -rf /opt/psicat/discord"
    echo "    sudo cp -r /opt/psicat/discord.backup /opt/psicat/discord"
    echo "    sudo systemctl start psicat-discord"
else
    log_section "Installation Complete"
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
fi
echo ""
