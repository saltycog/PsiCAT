# PsiCAT Docker Installation

This directory contains Docker and Docker Compose configuration for running PsiCAT as a containerized service.

## Files

- **docker-compose.yml** - Docker Compose service configuration
- **.env.example** - Environment variables template

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- `sudo` privileges (script requires root)
- Internet connection (for image download)
- Discord bot token (create one at https://discord.com/developers/applications)
- Discord server/guild ID

### Installation

Run the root-level installation script:

```bash
sudo bash install.sh
```

The script will:
1. Validate Docker and Docker Compose installation
2. Create `/opt/psicat/discord` directory
3. Download `docker-compose.yml` configuration
4. Create `.env` file with configuration template
5. Pull the latest Docker image
6. Start the service with docker-compose

### Configuration

After installation, edit the `.env` file to add your Discord credentials:

```bash
sudo nano /opt/psicat/discord/.env
```

Required settings:
- `DISCORD_BOT_TOKEN` - Your Discord bot token
- `DISCORD_GUILD_ID` - Your Discord guild/server ID

Optional settings:
- `AVATAR_BASE_URL` - Base URL for avatar files (default: `http://localhost:5247`)
- `ASPNETCORE_ENVIRONMENT` - Set to `Production` for live use

After editing `.env`, restart the service:

```bash
cd /opt/psicat/discord
docker-compose restart
```

## Service Management

### Check Service Status
```bash
docker ps | grep psicat
```

### View Live Logs
```bash
docker logs -f psicat-discord
```

### View Recent Logs
```bash
docker logs psicat-discord | tail -50
```

### Restart the Service
```bash
cd /opt/psicat/discord
docker-compose restart
```

### Stop the Service
```bash
cd /opt/psicat/discord
docker-compose down
```

### Start the Service
```bash
cd /opt/psicat/discord
docker-compose up -d
```

## Directory Structure

After installation, the application is located at `/opt/psicat/discord/` with the following structure:

```
/opt/psicat/discord/
├── docker-compose.yml          - Docker Compose configuration
├── .env                        - Environment variables (Discord token, etc.)
├── .psicat-version             - Installed version tag
├── data/
│   ├── quotes.json             - Quote database (persistent)
│   └── avatars/                - Avatar image files (persistent)
└── [Docker manages the container runtime]
```

Data is stored locally in the `data/` directory and mounted in the container, ensuring persistence across updates and restarts.

## Automatic Restart

Docker Compose is configured with `restart: unless-stopped`, meaning:

- Container automatically restarts on failure
- Container stops only when explicitly stopped with `docker-compose down`
- Container auto-starts if system reboots (when Docker daemon is running)

## Updating the Application

To update to the latest version:

```bash
sudo bash /path/to/install.sh
```

The installer will:
1. Detect your existing installation
2. Ask if you want to update
3. Create a backup of your configuration and data
4. Pull the latest Docker image
5. Restart the service with the new image

Your data (`data/`, `.env`) is preserved during updates.

## Troubleshooting

### Container won't start

Check the logs:
```bash
docker logs psicat-discord
```

Common issues:
- Invalid Discord bot token - Verify in `.env`
- Invalid guild ID - Verify in `.env`
- Port 5247 already in use - Change port in `docker-compose.yml`
- Docker daemon not running - Start Docker with `sudo systemctl start docker`

### Bot not responding to commands

Check:
- Discord bot token is correct and valid
- Guild ID is correct (verify with Discord Developer Portal)
- Bot is invited to the server with appropriate permissions
- Container is running: `docker ps | grep psicat`
- Check logs for errors: `docker logs psicat-discord`

Restart the service:
```bash
cd /opt/psicat/discord
docker-compose restart
```

### Port already in use

If port 5247 is already in use, edit `docker-compose.yml`:

```bash
sudo nano /opt/psicat/discord/docker-compose.yml
```

Change:
```yaml
ports:
  - "5247:5247"
  - "7011:7011"
```

To:
```yaml
ports:
  - "YOUR_PORT:5247"
  - "YOUR_HTTPS_PORT:7011"
```

Then restart:
```bash
cd /opt/psicat/discord
docker-compose restart
```

### Cannot connect to Discord API

Check:
- Network connectivity: `ping discord.com`
- Firewall isn't blocking outbound connections
- Discord API isn't having issues
- Bot token isn't expired

### Docker not installed

Install Docker:
```bash
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
```

## Uninstallation

To remove PsiCAT:

```bash
# Stop the service
cd /opt/psicat/discord
docker-compose down

# Remove application directory (includes all data!)
sudo rm -rf /opt/psicat/discord

# Remove the installation script (optional)
# sudo rm /path/to/install.sh
```

**Warning**: Removing `/opt/psicat/discord` will delete all your quotes and avatars. Create a backup first:

```bash
sudo cp -r /opt/psicat/discord/data /tmp/psicat-backup
```

## Image Updates

When you run the installer script, it automatically:
1. Pulls the latest Docker image from `ghcr.io/saltycog/psicat:latest`
2. Backs up your current data and configuration
3. Restarts the container with the new image
4. Restores your data and configuration

## Accessing the Service

- **Web Interface**: http://localhost:5247
- **Bot Commands**: Available in Discord where the bot is invited
- **View Logs**: `docker logs -f psicat-discord`

## Data Backup

Your quotes and avatars are stored in `/opt/psicat/discord/data/`:

```bash
# Backup
sudo cp -r /opt/psicat/discord/data /tmp/psicat-backup

# Restore
sudo cp -r /tmp/psicat-backup/* /opt/psicat/discord/data/
sudo docker-compose restart
```
