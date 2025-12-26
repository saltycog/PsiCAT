#!/bin/bash
set -euo pipefail

# PsiCAT Discord Bot - systemd Service Installation Script
# This script installs PsiCAT.DiscordApp as a systemd service daemon on Ubuntu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="psicat-discord"
SERVICE_FILE="${SCRIPT_DIR}/psicat-discord.service"
INSTALL_DIR="/opt/psicat/discord"
APP_USER="psicat"
APP_GROUP="psicat"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

log_info "Starting PsiCAT Discord Bot service installation..."

# Check if service file exists
if [[ ! -f "$SERVICE_FILE" ]]; then
    log_error "Service file not found: $SERVICE_FILE"
    exit 1
fi

# Install .NET 8 runtime if needed
install_dotnet_runtime() {
    log_info "Checking for .NET 8 runtime..."

    # Check if dotnet is available and has .NET 8
    if command -v dotnet &>/dev/null && dotnet --list-runtimes | grep -q "Microsoft.AspNetCore.App 8"; then
        log_info ".NET 8 runtime already installed"
        return 0
    fi

    log_warn ".NET 8 runtime not found. Installing..."

    # Update package lists
    log_info "Updating package lists..."
    apt-get update -qq || {
        log_error "Failed to update package lists"
        return 1
    }

    # Install required packages for adding Microsoft repository
    log_info "Installing Microsoft package repository..."
    apt-get install -qq -y wget gpg || {
        log_error "Failed to install prerequisite packages"
        return 1
    }

    # Add Microsoft package signing key
    wget -q https://packages.microsoft.com/keys/microsoft.asc -O /tmp/microsoft.asc
    gpg --dearmor < /tmp/microsoft.asc > /usr/share/keyrings/microsoft-prod.gpg 2>/dev/null || {
        log_error "Failed to add Microsoft package signing key"
        rm -f /tmp/microsoft.asc
        return 1
    }
    rm -f /tmp/microsoft.asc

    # Detect Ubuntu version
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        UBUNTU_VERSION_ID="${VERSION_ID}"
    else
        log_error "Cannot detect Ubuntu version"
        return 1
    fi

    # Add Microsoft package repository based on Ubuntu version
    case "$UBUNTU_VERSION_ID" in
        24.04|24.10)
            REPO_URL="https://packages.microsoft.com/ubuntu/24.04/prod"
            ;;
        22.04)
            REPO_URL="https://packages.microsoft.com/ubuntu/22.04/prod"
            ;;
        20.04)
            REPO_URL="https://packages.microsoft.com/ubuntu/20.04/prod"
            ;;
        *)
            log_error "Unsupported Ubuntu version: $UBUNTU_VERSION_ID (requires 20.04 or later)"
            return 1
            ;;
    esac

    log_info "Adding Microsoft repository for Ubuntu $UBUNTU_VERSION_ID..."
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] $REPO_URL jammy main" | \
        tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null || {
        log_error "Failed to add Microsoft repository"
        return 1
    }

    # Update package lists again
    log_info "Updating package lists..."
    apt-get update -qq || {
        log_error "Failed to update package lists after adding repository"
        return 1
    }

    # Install ASP.NET Core 8 runtime
    log_info "Installing ASP.NET Core 8 runtime..."
    apt-get install -qq -y aspnetcore-runtime-8.0 || {
        log_error "Failed to install aspnetcore-runtime-8.0"
        return 1
    }

    # Verify installation
    if dotnet --list-runtimes | grep -q "Microsoft.AspNetCore.App 8"; then
        log_info ".NET 8 runtime installed successfully"
        return 0
    else
        log_error "Failed to verify .NET 8 runtime installation"
        return 1
    fi
}

install_dotnet_runtime || {
    log_error "Failed to install .NET 8 runtime. Please install manually."
    log_info "Visit: https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu"
    exit 1
}

# Create service user and group
if ! id "$APP_USER" &>/dev/null; then
    log_info "Creating system user: $APP_USER"
    useradd --system --home-dir /var/lib/$APP_USER --shell /usr/sbin/nologin $APP_USER
else
    log_warn "User '$APP_USER' already exists"
fi

# Create installation directory
log_info "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/Data"
mkdir -p "$INSTALL_DIR/wwwroot"

# Copy application files
log_info "Copying application files to $INSTALL_DIR"
# Copy all files from the script directory's parent (the build output)
# excluding the daemon directory itself
find "$SCRIPT_DIR/.." -maxdepth 1 -type f ! -name "*.sh" ! -name "*.service" -exec cp {} "$INSTALL_DIR" \;
find "$SCRIPT_DIR/.." -maxdepth 1 -type d ! -name "daemon" -exec cp -r {} "$INSTALL_DIR" \; 2>/dev/null || true

# Set permissions
log_info "Setting directory permissions"
chown -R $APP_USER:$APP_GROUP "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR/PsiCAT.DiscordApp"
chmod 750 "$INSTALL_DIR/Data"
chmod 755 "$INSTALL_DIR/wwwroot"

# Copy systemd service file
log_info "Installing systemd service file"
cp "$SERVICE_FILE" "/etc/systemd/system/${SERVICE_NAME}.service"
chmod 644 "/etc/systemd/system/${SERVICE_NAME}.service"

# Reload systemd daemon
log_info "Reloading systemd daemon"
systemctl daemon-reload

# Enable service (auto-start on boot)
log_info "Enabling service auto-start on boot"
systemctl enable "$SERVICE_NAME"

log_info ""
log_info "Installation completed successfully!"
log_info ""
log_info "Next steps:"
log_info "1. Configure the application:"
log_info "   Edit: $INSTALL_DIR/appsettings.json"
log_info "   Set Discord.BotToken and Discord.GuildId"
log_info ""
log_info "2. Start the service:"
log_info "   sudo systemctl start $SERVICE_NAME"
log_info ""
log_info "3. Check service status:"
log_info "   sudo systemctl status $SERVICE_NAME"
log_info ""
log_info "4. View service logs:"
log_info "   sudo journalctl -u $SERVICE_NAME -f"
log_info ""
log_info "5. Restart service:"
log_info "   sudo systemctl restart $SERVICE_NAME"
log_info ""
log_info "6. Stop service:"
log_info "   sudo systemctl stop $SERVICE_NAME"
log_info ""
