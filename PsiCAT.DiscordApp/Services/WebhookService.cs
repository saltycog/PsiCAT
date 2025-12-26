using Discord;
using Discord.Webhook;
using Microsoft.Extensions.Logging;
using PsiCAT.DiscordApp.Models;

namespace PsiCAT.DiscordApp.Services;

public class WebhookService
{
    private readonly ILogger<WebhookService> _logger;

    public WebhookService(ILogger<WebhookService> logger)
    {
        _logger = logger;
    }

    public async Task SendQuoteViaWebhookAsync(
        ITextChannel channel,
        Quote quote,
        string avatarUrl)
    {
        IWebhook? webhook = null;

        try
        {
            webhook = await channel.CreateWebhookAsync("PsiCAT Quote");

            using var webhookClient = new DiscordWebhookClient(webhook);

            await webhookClient.SendMessageAsync(
                text: quote.Text,
                username: quote.Avatar ?? "PsiCAT",
                avatarUrl: string.IsNullOrEmpty(avatarUrl) ? null : avatarUrl);

            _logger.LogInformation("Quote sent via webhook");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send quote via webhook");
            throw;
        }
        finally
        {
            if (webhook != null)
            {
                try
                {
                    await webhook.DeleteAsync();
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to delete webhook");
                }
            }
        }
    }
}
