namespace PsiCAT.DiscordApp.Models;

public class PsiCatOptions
{
    public string QuotesFilePath { get; set; } = "Data/quotes.json";
    public string AvatarBaseUrl { get; set; } = string.Empty;
    public string? DefaultAvatar { get; set; }
}
