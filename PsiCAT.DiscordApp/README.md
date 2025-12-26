# PsiCAT Discord App
A Discord app/bot built in C# on ASP.NET Core (.NET 8 LTS) .

### Current Features
- **Random Quotes**: Bot recites a random quote with optional custom avatar
- **Quote Management**: Server members can add, retrieve, and manage quotes with optional avatar associations
- **Avatar Handling**: Upload and manage custom avatars for quotes
- **Slash Commands**: Modern Discord slash command interface with autocomplete support

### Available Commands

All commands are under the `/psicat` group:

- **`/psicat says`** - Send a random quote via webhook with optional avatar
- **`/psicat avatars list`** - List all available avatars
- **`/psicat avatars add`** - Upload a new avatar image
- **`/psicat quote add`** - Add a new quote with optional avatar

---
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

---
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