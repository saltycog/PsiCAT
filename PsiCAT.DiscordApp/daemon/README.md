# PsiCAT Discord Bot - Systemd Service Installation

This directory contains systemd service configuration and installation scripts for running PsiCAT.DiscordApp as a daemon on Ubuntu Server systems.

## Files

- **install-service.sh** - Installation script for setting up the systemd service
- **psicat-discord.service** - Systemd service configuration file

## Quick Start

### Prerequisites

- Ubuntu Server 20.04 LTS, 22.04 LTS, or 24.04 LTS
- `sudo` privileges (script requires root)
- Internet connection (for .NET 8 installation)

**Note:** .NET 8 Runtime will be automatically installed if not present.

### Installation

1. Build the project:
   ```bash
   dotnet build -c Release
   ```

2. Run the installation script (from the build output directory):
   ```bash
   sudo ./daemon/install-service.sh
   ```

   The script will:
   - Verify .NET 8 runtime is installed
   - Create a dedicated `psicat` system user
   - Create `/opt/psicat/discord` installation directory
   - Copy application files and configuration
   - Install and enable the systemd service

3. Configure the application:
   ```bash
   sudo nano /opt/psicat/discord/appsettings.json
   ```

   Set the required values:
   - `Discord.BotToken` - Your Discord bot token
   - `Discord.GuildId` - Your Discord guild/server ID
   - `PsiCat.QuotesFilePath` - Path to quotes.json (default: `Data/quotes.json`)
   - `PsiCat.AvatarBaseUrl` - Base URL for avatar files (e.g., `http://your-server:5000`)

4. Start the service:
   ```bash
   sudo systemctl start psicat-discord
   ```

## Service Management

### Check Service Status
```bash
sudo systemctl status psicat-discord
```

### View Live Logs
```bash
sudo journalctl -u psicat-discord -f
```

### View Recent Logs
```bash
sudo journalctl -u psicat-discord -n 50
```

### Restart the Service
```bash
sudo systemctl restart psicat-discord
```

### Stop the Service
```bash
sudo systemctl stop psicat-discord
```

### Disable Auto-start on Boot
```bash
sudo systemctl disable psicat-discord
```

## Directory Structure

After installation, the application is located at `/opt/psicat/discord/` with the following structure:

```
/opt/psicat/discord/
├── PsiCAT.DiscordApp           - Main executable
├── appsettings.json            - Configuration file
├── appsettings.Development.json - Development overrides (if present)
├── Data/
│   └── quotes.json             - Quote database (readable/writable by psicat user)
├── wwwroot/
│   └── avatars/                - Avatar image files
└── [various .dll and runtime files]
```

## Security Features

The systemd service is configured with the following security measures:

- **Dedicated User**: Runs as unprivileged `psicat` system user
- **Restricted Filesystem**: Read-only access to most system directories
- **Write Access**: Only `/opt/psicat/discord/Data` is writable
- **No New Privileges**: Service cannot gain additional privileges
- **Private Temp**: Uses private /tmp directory

## Automatic Restart

The service is configured to automatically restart on failure:

- Restart after 5 seconds of failure
- Maximum 5 restart attempts within 60 seconds
- After exceeding restart limits, manual intervention is required

## Updating the Application

1. Build a new release:
   ```bash
   dotnet build -c Release
   ```

2. Stop the service:
   ```bash
   sudo systemctl stop psicat-discord
   ```

3. Copy new binaries to `/opt/psicat/discord/`:
   ```bash
   sudo cp bin/Release/net8.0/* /opt/psicat/discord/
   sudo chown -R psicat:psicat /opt/psicat/discord/
   ```

4. Restart the service:
   ```bash
   sudo systemctl start psicat-discord
   ```

## Troubleshooting

### Service fails to start

Check the logs:
```bash
sudo journalctl -u psicat-discord -n 100
```

Common issues:
- Missing `.NET 8` runtime - Automatic installation failed (check script output for details)
- Invalid configuration in `appsettings.json` - Verify JSON syntax and required fields
- Permission issues - Ensure `psicat` user owns `/opt/psicat/discord/`
- Invalid Discord token - Verify bot token in configuration

### .NET 8 Installation Failed

If the automatic .NET 8 installation fails during `install-service.sh`:

1. Check the error message in the script output
2. Try installing manually:
   ```bash
   sudo apt-get update
   sudo apt-get install -y aspnetcore-runtime-8.0
   ```
3. If that fails, follow the official guide:
   https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu
4. Once installed, re-run the installation script:
   ```bash
   sudo ./daemon/install-service.sh
   ```

### Cannot connect to Discord

Check:
- Discord bot token is correct and not expired
- Guild ID is correct
- Bot has required permissions in the Discord server
- Network connectivity is working

### File permission errors

Fix permissions:
```bash
sudo chown -R psicat:psicat /opt/psicat/discord/
sudo chmod -R u+rw /opt/psicat/discord/Data
```

## Uninstallation

To remove the service:

```bash
# Stop the service
sudo systemctl stop psicat-discord

# Disable auto-start
sudo systemctl disable psicat-discord

# Remove service file
sudo rm /etc/systemd/system/psicat-discord.service

# Reload systemd
sudo systemctl daemon-reload

# Remove application directory (optional)
sudo rm -rf /opt/psicat/discord

# Remove psicat user (optional)
sudo userdel psicat
```

## Installation Script Details

The `install-service.sh` script performs the following steps:

1. Validates root privileges
2. Checks for `.NET 8` runtime; installs automatically if missing:
   - Adds Microsoft package signing key
   - Adds Microsoft package repository (supports Ubuntu 20.04, 22.04, 24.04)
   - Installs `aspnetcore-runtime-8.0` via apt
   - Verifies successful installation
3. Creates `psicat` system user if it doesn't exist
4. Creates `/opt/psicat/discord` directory structure
5. Copies application files from build output
6. Sets appropriate file permissions
7. Installs systemd service file
8. Enables service for auto-start on boot
9. Displays post-installation instructions

## Build Integration

The daemon files are automatically included in the build output via MSBuild targets in the `.csproj` file:

- `CopyDaemonFiles` target copies daemon configuration
- `install-service.sh` is made executable during build
- Files are placed in `bin/[Configuration]/net8.0/daemon/`

## Support

For issues or questions:
1. Check logs with `journalctl`
2. Verify configuration in `/opt/psicat/discord/appsettings.json`
3. Ensure system has required dependencies (.NET 8, etc.)
