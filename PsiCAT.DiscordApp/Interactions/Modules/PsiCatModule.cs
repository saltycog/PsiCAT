using Discord.Interactions;
using Microsoft.Extensions.Logging;
using PsiCAT.DiscordApp.Services;

namespace PsiCAT.DiscordApp.Interactions.Modules;

[Group("psicat", "PsiCAT commands")]
public partial class PsiCatModule : InteractionModuleBase<SocketInteractionContext>
{
    private readonly QuoteService _quoteService;
    private readonly WebhookService _webhookService;
    private readonly ILogger<PsiCatModule> _logger;
    private readonly string _webRootPath;
    private readonly IHttpClientFactory _httpClientFactory;

    public PsiCatModule(
        QuoteService quoteService,
        WebhookService webhookService,
        ILogger<PsiCatModule> logger,
        string webRootPath,
        IHttpClientFactory httpClientFactory)
    {
        _quoteService = quoteService;
        _webhookService = webhookService;
        _logger = logger;
        _webRootPath = webRootPath;
        _httpClientFactory = httpClientFactory;
    }
}
