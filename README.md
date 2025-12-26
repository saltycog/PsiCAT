# PsiCAT

A collection of bots and automations for personal use.
Only intended for my own personal use, but hey, steal my code!

## Current Discord Bot Features

- **Random Quotes**: Bot recites a random quote. Nothing fancy here.
- **Quote Management**: Server members can add, retrieve, and manage quotes with optional avatar associations
- **Avatar Handling**: Upload and manage custom avatars for quotes

## Quick Start - Remote Installation

Install PsiCAT directly on a Linux server with one command:

```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/main/install.sh)"
```

**For fresh installations**, the script will:
1. Download the latest release from GitHub
2. Extract application files
3. Verify/install .NET 8 runtime
4. Create a `psicat` system user
5. Configure the systemd service
6. Prompt for configuration

**For updates**, run the same command on an existing installation. The script will:
1. Detect the current version
2. Check for a newer release
3. Create a backup at `/opt/psicat/discord.backup`
4. Stop the service
5. Update binaries while preserving configuration and data files
6. Restart the service
7. Offer rollback instructions if needed

For detailed daemon setup information, see [Systemd Service Setup](#systemd-service-setup).

## Local Development

### Prerequisites

- .NET 8 SDK (or ASP.NET Core 8 runtime for running pre-built binaries)
- A Discord bot token (from [Discord Developer Portal](https://discord.com/developers/applications))
- A Discord server to test in (Guild ID, aka server ID, required)

### Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/YOUR_ORG/PsiCAT.git
   cd PsiCAT
   ```

2. **Configure your Discord bot:**

   Create `PsiCAT.DiscordApp/appsettings.Development.json`:
   ```json
   {
     "Discord": {
       "BotToken": "YOUR_BOT_TOKEN_HERE",
       "GuildId": YOUR_GUILD_ID_HERE,
       "EnableCommandSync": true
     },
     "PsiCat": {
       "QuotesFilePath": "Data/quotes.json",
       "AvatarBaseUrl": "http://localhost:5000",
       "DefaultAvatar": null
     }
   }
   ```

3. **Build and run:**
   ```bash
   dotnet build
   dotnet run
   ```

   The bot will start and connect to Discord. Slash commands appear in your test server after the bot connects.

4. **Initialize quotes file:**

   If `Data/quotes.json` doesn't exist, create it:
   ```json
   {
     "quotes": []
   }
   ```

### Available Commands

All commands are under the `/psicat` group:

- **`/psicat says`** - Send a random quote via webhook with optional avatar
- **`/psicat avatars list`** - List all available avatars
- **`/psicat avatars add`** - Upload a new avatar image
- **`/psicat quote add`** - Add a new quote with optional avatar

### Development Workflow

1. Make code changes
2. Run `dotnet build` to verify compilation
3. Run `dotnet run` to test
4. Commands reload automatically for guild commands (restart bot if needed for global command changes)


## Configuration

### appsettings.json

**Discord Options:**
- `BotToken` (string) - Your Discord bot token (required)
- `GuildId` (number) - Guild ID (aka server ID) for command registration (required)
- `EnableCommandSync` (bool) - Register commands to guild only (`true`, suggested) or globally (`false`)

**PsiCAT Options:**
- `QuotesFilePath` (string) - Path to quotes.json (relative to ContentRootPath)
- `AvatarBaseUrl` (string) - Base URL for avatar static files (e.g., `http://localhost:5247`)
- `DefaultAvatar` (string|null) - URL for quotes with no custom avatar, or null to show no avatar

### Example Configuration

```json
{
  "Discord": {
    "BotToken": "",
    "GuildId": 0,
    "EnableCommandSync": true
  },
  "PsiCat": {
    "QuotesFilePath": "Data/quotes.json",
    "AvatarBaseUrl": "http://localhost:5247",
    "DefaultAvatar": null
  }
}
```

## Data Files

### quotes.json

Quote database stored in `Data/quotes.json`:

```json
{
  "quotes": [
    {
      "avatar": "avatar_name",
      "text": "Quote text here"
    },
    {
      "avatar": null,
      "text": "Quote without avatar"
    }
  ]
}
```

- Loaded at application startup
- Saved atomically (temp file + move) when quotes are added
- Thread-safe writes via `SemaphoreSlim`

### Avatar Images

Avatar files stored in `wwwroot/avatars/`:
- Supported formats: `.png`, `.gif`, `.jpg`, `.jpeg`, `.webp`
- Max file size: 2 MB (enforced by upload command)
- Served as static files via ASP.NET Core

## Systemd Service Setup

For production deployment on Linux, the application runs as a systemd daemon.

### Prerequisites

- Ubuntu Server 20.04 LTS, 22.04 LTS, or 24.04 LTS
- `sudo` privileges
- Internet connection (for .NET 8 installation if needed)

### Installation via Script

The remote installation script (`install.sh`) handles all of this automatically:

```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/main/install.sh)"
```

### Manual Installation

If installing from a local build:

1. **Build release binaries:**
   ```bash
   dotnet build -c Release
   ```

2. **Run the daemon installation script:**
   ```bash
   sudo PsiCAT.DiscordApp/bin/Release/net8.0/daemon/install-service.sh
   ```

3. **Configure the application:**
   ```bash
   sudo nano /opt/psicat/discord/appsettings.json
   ```
   Set `Discord.BotToken` and `Discord.GuildId`

4. **Start the service:**
   ```bash
   sudo systemctl start psicat-discord
   ```

### Service Management

```bash
# Check status
sudo systemctl status psicat-discord

# View live logs
sudo journalctl -u psicat-discord -f

# View recent logs (last 50 lines)
sudo journalctl -u psicat-discord -n 50

# Restart
sudo systemctl restart psicat-discord

# Stop
sudo systemctl stop psicat-discord

# Disable auto-start
sudo systemctl disable psicat-discord
```

### Service Installation Details

The installation script:
- Verifies/installs .NET 8 runtime
- Creates a `psicat` system user
- Creates `/opt/psicat/discord/` directory
- Copies application files and configuration
- Installs the systemd service file
- Enables auto-start on boot
- Configures security settings (unprivileged user, restricted filesystem)

For detailed information, see `PsiCAT.DiscordApp/daemon/README.md`.

### Updating the Application

**Using the installation script (recommended):**

Simply run the installation script again. It will automatically:
- Detect the update
- Create a backup
- Update binaries
- Preserve your configuration and quote data
- Restart the service

```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/main/install.sh)"
```

**Manual update (if needed):**

```bash
# Build new release
dotnet build -c Release

# Stop the service
sudo systemctl stop psicat-discord

# Copy new binaries
sudo cp PsiCAT.DiscordApp/bin/Release/net8.0/* /opt/psicat/discord/
sudo chown -R psicat:psicat /opt/psicat/discord/

# Restart
sudo systemctl start psicat-discord
```

**Rollback to previous version (if update fails):**

If something goes wrong, the script creates a backup at `/opt/psicat/discord.backup`:

```bash
sudo systemctl stop psicat-discord
sudo rm -rf /opt/psicat/discord
sudo cp -r /opt/psicat/discord.backup /opt/psicat/discord
sudo systemctl start psicat-discord
```

## Troubleshooting

### Bot not responding to commands

- Verify bot token is correct in `appsettings.json`
- Check bot has "Send Messages" and "Use Slash Commands" permissions in the server
- Verify bot is connected: check logs for "Ready" event
- For development: ensure `EnableCommandSync` is `true` for guild-level registration

### Avatar uploads failing

- Check file size is ≤ 2 MB
- Verify file format is `.png`, `.gif`, `.jpg`, `.jpeg`, or `.webp`
- Check `wwwroot/avatars/` directory permissions
- Ensure avatar name matches regex: `^[a-zA-Z0-9_\-]{1,50}$`

### Service fails to start

```bash
sudo journalctl -u psicat-discord -n 100
```

Check for:
- Missing .NET 8 runtime
- Invalid JSON in `appsettings.json`
- Permission issues on `/opt/psicat/discord/`
- Network connectivity for Discord connection

### .NET 8 Installation Issues

If automatic installation failed during service setup:

```bash
sudo apt-get update
sudo apt-get install -y aspnetcore-runtime-8.0
```

For detailed instructions: https://learn.microsoft.com/en-us/dotnet/core/install/linux-ubuntu

## Building for Release

```bash
# Build release binaries
dotnet build -c Release

# Output in: PsiCAT.DiscordApp/bin/Release/net8.0/
```
