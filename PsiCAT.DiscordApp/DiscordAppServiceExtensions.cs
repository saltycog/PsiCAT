using Discord;
using Discord.Interactions;
using Discord.WebSocket;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PsiCAT.DiscordApp.Interactions;
using PsiCAT.DiscordApp.Models;
using PsiCAT.DiscordApp.Services;

namespace PsiCAT.DiscordApp;

/// <summary>
/// Extension methods for registering PsiCAT Discord application services.
/// </summary>
public static class DiscordAppServiceExtensions
{
    /// <summary>
    /// Adds all PsiCAT Discord application services to the dependency injection container.
    /// </summary>
    /// <param name="services">The service collection</param>
    /// <param name="configuration">Application configuration</param>
    /// <param name="contentRootPath">The content root path of the application</param>
    /// <param name="webRootPath">The web root path of the application</param>
    /// <returns>The service collection for chaining</returns>
    public static IServiceCollection AddDiscordApp(
        this IServiceCollection services,
        IConfiguration configuration,
        string contentRootPath,
        string webRootPath)
    {
        // Use default wwwroot path if not provided
        webRootPath ??= Path.Combine(contentRootPath, "wwwroot");
        // Bind configuration options
        services.Configure<DiscordOptions>(
            configuration.GetSection("Discord"));
        services.Configure<PsiCatOptions>(
            configuration.GetSection("PsiCat"));

        // Register Discord.Net services
        services.AddSingleton(new DiscordSocketClient(new DiscordSocketConfig
        {
            GatewayIntents = GatewayIntents.Guilds,
            LogLevel = LogSeverity.Info,
            MessageCacheSize = 100
        }));

        services.AddSingleton(x =>
            new InteractionService(x.GetRequiredService<DiscordSocketClient>()));

        // Register application services
        services.AddSingleton<CommandHandler>();
        services.AddSingleton(sp =>
            new QuoteService(
                sp.GetRequiredService<IOptions<PsiCatOptions>>(),
                contentRootPath,
                webRootPath,
                sp.GetRequiredService<ILogger<QuoteService>>()));
        services.AddSingleton<WebhookService>();

        // Register hosted services (bot lifecycle and auto-quotes)
        services.AddHostedService<DiscordBotService>();
        services.AddHostedService<AutoQuoteService>();

        // HTTP client for avatar downloads
        services.AddHttpClient();

        // Register paths for module injection
        services.AddSingleton(webRootPath);

        return services;
    }
}
