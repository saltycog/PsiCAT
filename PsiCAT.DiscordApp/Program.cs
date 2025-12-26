using Discord;
using Discord.Interactions;
using Discord.WebSocket;
using PsiCAT.DiscordApp.Interactions;
using PsiCAT.DiscordApp.Models;
using PsiCAT.DiscordApp.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<DiscordOptions>(
    builder.Configuration.GetSection("Discord"));
builder.Services.Configure<PsiCatOptions>(
    builder.Configuration.GetSection("PsiCat"));

builder.Services.AddSingleton(new DiscordSocketClient(new DiscordSocketConfig
{
    GatewayIntents = GatewayIntents.Guilds,
    LogLevel = LogSeverity.Info,
    MessageCacheSize = 100
}));

builder.Services.AddSingleton(x => new InteractionService(x.GetRequiredService<DiscordSocketClient>()));
builder.Services.AddSingleton<CommandHandler>();
builder.Services.AddSingleton<QuoteService>();
builder.Services.AddSingleton<WebhookService>();

builder.Services.AddHostedService<DiscordBotService>();
builder.Services.AddHttpClient();

var app = builder.Build();

app.UseStaticFiles();

app.MapGet("/", () => "PsiCAT Discord Application");

await app.RunAsync();
