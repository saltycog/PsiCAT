using Discord;
using Discord.Interactions;
using Microsoft.Extensions.Logging;
using PsiCAT.DiscordApp.Models;

namespace PsiCAT.DiscordApp.Interactions.Modules;

public partial class PsiCatModule
{
    [SlashCommand("says", "Get a random PsiCAT quote")]
    public async Task SaysAsync()
    {
        try
        {
            await DeferAsync();

            Quote? quote = _quoteService.GetRandomQuote();
            if (quote is null)
            {
                await FollowupAsync("No quotes available!", ephemeral: true);
                return;
            }

            string avatarUrl = _quoteService.GetAvatarUrl(quote.Avatar);

            ITextChannel? channel = Context.Channel as ITextChannel;

            if (channel == null)
            {
                await FollowupAsync("This command must be used in a text channel!", ephemeral: true);
                return;
            }

            _logger.LogInformation(
                "Sending quote via webhook - QuoteText: {QuoteText}, AvatarName: {AvatarName}, AvatarUrl: {AvatarUrl}, ChannelId: {ChannelId}",
                quote.Text,
                quote.Avatar ?? "[null]",
                avatarUrl,
                channel.Id);
            await _webhookService.SendQuoteViaWebhookAsync(channel, quote, avatarUrl);
            await DeleteOriginalResponseAsync();
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Failed to send quote due to HTTP error");
            await FollowupAsync("Failed to send quote!", ephemeral: true);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error executing says command");
            await FollowupAsync("An error occurred!", ephemeral: true);
        }
    }
}
