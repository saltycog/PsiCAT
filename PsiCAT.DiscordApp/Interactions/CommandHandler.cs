using System.Reflection;
using Discord;
using Discord.Interactions;
using Discord.WebSocket;

namespace PsiCAT.DiscordApp.Interactions;

public class CommandHandler
{
    private readonly DiscordSocketClient _client;
    private readonly InteractionService _interactions;
    private readonly IServiceProvider _services;
    private readonly ILogger<CommandHandler> _logger;

    public CommandHandler(
        DiscordSocketClient client,
        InteractionService interactions,
        IServiceProvider services,
        ILogger<CommandHandler> logger)
    {
        _client = client;
        _interactions = interactions;
        _services = services;
        _logger = logger;
    }

    public async Task InitializeAsync()
    {
        try
        {
            await _interactions.AddModulesAsync(Assembly.GetEntryAssembly(), _services);
            _logger.LogInformation("Interaction modules loaded");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load interaction modules");
            throw;
        }
    }

    public async Task HandleInteractionAsync(SocketInteraction interaction)
    {
        try
        {
            SocketInteractionContext context = new SocketInteractionContext(_client, interaction);
            Discord.Interactions.IResult result = await _interactions.ExecuteCommandAsync(context, _services);

            if (!result.IsSuccess)
            {
                if (result.Error == InteractionCommandError.UnknownCommand)
                {
                    _logger.LogWarning("Unknown command: {CommandName}", interaction.Data);
                }
                else
                {
                    _logger.LogError("Command error: {Error}", result.ErrorReason);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling interaction");

            if (interaction.Type == InteractionType.ApplicationCommand)
            {
                try
                {
                    await interaction.RespondAsync("An error occurred!", ephemeral: true);
                }
                catch (Exception respondEx)
                {
                    _logger.LogError(respondEx, "Failed to respond to interaction error");
                }
            }
        }
    }
}
