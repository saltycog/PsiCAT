namespace PsiCAT.DiscordApp.Models;

public class DiscordOptions
{
    public string BotToken { get; set; } = string.Empty;
    public ulong GuildId { get; set; }
    public bool EnableCommandSync { get; set; } = true;
}
