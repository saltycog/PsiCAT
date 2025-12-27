# PsiCAT Docker Installation

This directory contains Docker and Docker Compose configuration for running PsiCAT as a containerized service.

## Files

- **docker-compose.yml** - Docker Compose service configuration
- **.env.example** - Environment variables template

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- `git` installed (for cloning repository or remote installations)
- `curl` and `jq` installed (for downloading configuration and checking for updates)
- `sudo` privileges (script requires root)
- Discord bot token (create one at https://discord.com/developers/applications)
- Discord server/guild ID

### Installation

There are two ways to install PsiCAT:

#### Option 1: Remote Installation (One-liner)

Run the installation script directly from GitHub:

```bash
sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/saltycog/PsiCAT/main/install.sh)"
```

This will:
- Clone the repository to a temporary directory
- Build the Docker image locally
- Set up the service at `/opt/psicat/discord`
- Clean up temporary files

#### Option 2: Local Installation (From Cloned Repository)

Clone the repository and run the script from the repository root:

```bash
git clone https://github.com/saltycog/PsiCAT.git
cd PsiCAT
sudo bash install.sh
```

This will:
- Use the Dockerfile in the current directory
- Build the Docker image locally
- Set up the service at `/opt/psicat/discord`

---

Either way, the installation script will:
1. Validate Docker, Docker Compose, curl, jq, and git installation
2. Create `/opt/psicat/discord` directory
3. Download `docker-compose.yml` configuration
4. Create `.env` file with configuration template
5. Build the Docker image locally from the Dockerfile
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
├── .psicat-commit              - Installed commit hash
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
1. Check the latest commit hash on the main branch
2. Compare with your installed commit hash
3. If an update is available, ask for confirmation
4. Create a backup of your configuration and data
5. Build the latest Docker image locally
6. Restart the service with the new image

Your data (`data/`, `.env`, and `.psicat-commit`) are preserved during updates.

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

To remove PsiCAT, use the uninstall script:

```bash
sudo bash /opt/psicat/discord/uninstall.sh
```

The uninstall script will:
1. Offer to back up your data and configuration
2. Stop the Docker service
3. Remove the installation directory
4. Optionally remove the Docker image

**Note**: The uninstall script backs up your data to `/tmp/psicat-backup-{timestamp}` before removal, so your quotes and avatars are safely preserved.

## Image Updates

When you run the installer script to update, it automatically:
1. Builds the Docker image locally from the Dockerfile
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
