using Discord;
using Discord.WebSocket;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PsiCAT.DiscordApp.Models;

namespace PsiCAT.DiscordApp.Services;

/// <summary>
/// Background service that automatically sends random quotes to a configured Discord channel at regular intervals.
/// Implements IHostedService for lifecycle management and IDisposable for cleanup.
/// </summary>
public class AutoQuoteService : IHostedService, IDisposable
{
    private readonly DiscordSocketClient _client;
    private readonly QuoteService _quoteService;
    private readonly WebhookService _webhookService;
    private readonly IOptions<DiscordOptions> _discordOptions;
    private readonly IOptions<PsiCatOptions> _psiCatOptions;
    private readonly ILogger<AutoQuoteService> _logger;

    private Task? _timerTask;
    private CancellationTokenSource? _cancellationTokenSource;

    /// <summary>
    /// Initializes a new instance of the AutoQuoteService.
    /// </summary>
    public AutoQuoteService(
        DiscordSocketClient client,
        QuoteService quoteService,
        WebhookService webhookService,
        IOptions<DiscordOptions> discordOptions,
        IOptions<PsiCatOptions> psiCatOptions,
        ILogger<AutoQuoteService> logger)
    {
        _client = client;
        _quoteService = quoteService;
        _webhookService = webhookService;
        _discordOptions = discordOptions;
        _psiCatOptions = psiCatOptions;
        _logger = logger;
    }

    /// <summary>
    /// Starts the auto-quote service if enabled in configuration.
    /// Logs configuration and begins the background timer loop.
    /// </summary>
    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (!_psiCatOptions.Value.AutoQuoteEnabled)
        {
            _logger.LogInformation("Auto-quote service is disabled");
            return Task.CompletedTask;
        }

        _logger.LogInformation(
            "Auto-quote service starting. Channel: {ChannelId}, Delay range: {MinDelay}-{MaxDelay} seconds",
            _psiCatOptions.Value.AutoQuoteChannelId,
            _psiCatOptions.Value.MinAutoQuoteDelay,
            _psiCatOptions.Value.MaxAutoQuoteDelay);

        if (_psiCatOptions.Value.MinAutoQuoteDelay >= _psiCatOptions.Value.MaxAutoQuoteDelay)
        {
            _logger.LogWarning(
                "Auto-quote delay configuration invalid: MinDelay ({MinDelay}) >= MaxDelay ({MaxDelay})",
                _psiCatOptions.Value.MinAutoQuoteDelay,
                _psiCatOptions.Value.MaxAutoQuoteDelay);
        }

        _cancellationTokenSource = new CancellationTokenSource();
        _timerTask = RunTimerLoopAsync(_cancellationTokenSource.Token);

        return Task.CompletedTask;
    }

    /// <summary>
    /// Stops the auto-quote service gracefully.
    /// Cancels the timer loop and waits for it to complete.
    /// </summary>
    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_cancellationTokenSource == null || _timerTask == null)
        {
            _logger.LogInformation("Auto-quote service not running");
            return;
        }

        try
        {
            _cancellationTokenSource.Cancel();

            using CancellationTokenSource cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(5));

            await _timerTask.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("Auto-quote service shutdown timeout");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error stopping auto-quote service");
        }
        finally
        {
            _cancellationTokenSource?.Dispose();
            _logger.LogInformation("Auto-quote service stopped");
        }
    }

    /// <summary>
    /// Core timer loop that waits for bot connection and sends quotes at regular intervals.
    /// </summary>
    private async Task RunTimerLoopAsync(CancellationToken cancellationToken)
    {
        // Wait for bot to be connected
        while (_client.ConnectionState != ConnectionState.Connected && !cancellationToken.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);
        }

        _logger.LogInformation("Auto-quote timer started");

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                TimeSpan delay = GetRandomDelay();
                _logger.LogInformation("Next auto-quote in {DelaySeconds} seconds", delay.TotalSeconds);

                await Task.Delay(delay, cancellationToken).ConfigureAwait(false);

                if (!cancellationToken.IsCancellationRequested)
                {
                    await SendAutoQuoteAsync(cancellationToken).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in auto-quote timer loop, retrying in 1 minute");
                try
                {
                    await Task.Delay(TimeSpan.FromMinutes(1), cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
            }
        }
    }

    /// <summary>
    /// Sends a random quote to the configured channel via webhook.
    /// </summary>
    private async Task SendAutoQuoteAsync(CancellationToken cancellationToken)
    {
        if (_client.ConnectionState != ConnectionState.Connected)
        {
            _logger.LogWarning("Bot is not connected, skipping auto-quote");
            return;
        }

        SocketGuild? guild = _client.GetGuild(_discordOptions.Value.GuildId);
        if (guild == null)
        {
            _logger.LogError(
                "Guild not found: {GuildId}",
                _discordOptions.Value.GuildId);
            return;
        }

        SocketTextChannel? channel = guild.GetTextChannel(_psiCatOptions.Value.AutoQuoteChannelId);
        if (channel == null)
        {
            _logger.LogError(
                "Channel not found: {ChannelId} in guild {GuildId}",
                _psiCatOptions.Value.AutoQuoteChannelId,
                _discordOptions.Value.GuildId);
            return;
        }

        Quote? quote = _quoteService.GetRandomQuote();
        if (quote == null)
        {
            _logger.LogWarning("No quotes available for auto-quote");
            return;
        }

        string avatarUrl = _quoteService.GetAvatarUrl(quote.Avatar);

        try
        {
            await _webhookService.SendQuoteViaWebhookAsync(
                channel: channel,
                quote: quote,
                avatarUrl: avatarUrl).ConfigureAwait(false);

            _logger.LogInformation("Auto-quote sent: {QuoteText}", quote.Text);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send auto-quote: {QuoteText}", quote.Text);
        }
    }

    /// <summary>
    /// Generates a random delay between the configured minimum and maximum auto-quote delays.
    /// </summary>
    /// <returns>A TimeSpan representing the delay in seconds.</returns>
    private TimeSpan GetRandomDelay()
    {
        int delaySeconds = Random.Shared.Next(
            _psiCatOptions.Value.MinAutoQuoteDelay,
            _psiCatOptions.Value.MaxAutoQuoteDelay + 1);

        return TimeSpan.FromSeconds(delaySeconds);
    }

    /// <summary>
    /// Disposes the cancellation token source.
    /// </summary>
    public void Dispose()
    {
        _cancellationTokenSource?.Dispose();
        GC.SuppressFinalize(this);
    }
}
