namespace PsiCAT.DiscordApp.Models;

public class PsiCatOptions
{
    public string QuotesFilePath { get; set; } = "Data/quotes.json";
    public string AvatarBaseUrl { get; set; } = string.Empty;
    public string? DefaultAvatar { get; set; }

    // Auto-quote settings
    public bool AutoQuoteEnabled { get; set; } = false;
    public ulong AutoQuoteChannelId { get; set; } = 0;
    public int MinAutoQuoteDelay { get; set; } = 60;
    public int MaxAutoQuoteDelay { get; set; } = 43200;
}
