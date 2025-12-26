using Discord.Interactions;
using PsiCAT.DiscordApp.Services;

namespace PsiCAT.DiscordApp.Interactions.Modules;

[Group("psicat", "PsiCAT commands")]
public partial class PsiCatModule : InteractionModuleBase<SocketInteractionContext>
{
    private readonly QuoteService _quoteService;
    private readonly WebhookService _webhookService;
    private readonly ILogger<PsiCatModule> _logger;
    private readonly IWebHostEnvironment _hostEnvironment;
    private readonly IHttpClientFactory _httpClientFactory;

    public PsiCatModule(
        QuoteService quoteService,
        WebhookService webhookService,
        ILogger<PsiCatModule> logger,
        IWebHostEnvironment hostEnvironment,
        IHttpClientFactory httpClientFactory)
    {
        _quoteService = quoteService;
        _webhookService = webhookService;
        _logger = logger;
        _hostEnvironment = hostEnvironment;
        _httpClientFactory = httpClientFactory;
    }
}
