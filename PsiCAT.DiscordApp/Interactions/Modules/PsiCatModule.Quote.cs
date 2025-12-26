using Discord;
using Discord.Interactions;
using Microsoft.Extensions.Logging;
using PsiCAT.DiscordApp.Interactions.Autocomplete;
using PsiCAT.DiscordApp.Models;
using PsiCAT.DiscordApp.Services;

namespace PsiCAT.DiscordApp.Interactions.Modules;

public partial class PsiCatModule
{
    /// <summary>
    /// Handles quote management commands as a nested subcommand group under /psicat.
    /// </summary>
    [Group("quote", "Quote management commands")]
    public class QuoteSubcommands : InteractionModuleBase<SocketInteractionContext>
    {
        private readonly QuoteService _quoteService;
        private readonly ILogger<PsiCatModule> _logger;

        public QuoteSubcommands(
            QuoteService quoteService,
            ILogger<PsiCatModule> logger)
        {
            _quoteService = quoteService;
            _logger = logger;
        }

        /// <summary>
        /// Adds a new quote to PsiCAT with an optional avatar.
        /// </summary>
        [SlashCommand("add", "Add a new quote to PsiCAT")]
        public async Task AddAsync(
            [Summary("avatar", "Avatar to use"),
             Autocomplete(typeof(AvatarNameAutocompleteHandler))]
            string avatarName,

            [Summary("quote", "The quote text")]
            [MaxLength(2000)]
            string quoteText)
        {
            try
            {
                await DeferAsync(ephemeral: true);

                // Validate quote text
                if (string.IsNullOrWhiteSpace(quoteText))
                {
                    await FollowupAsync("Quote text cannot be empty!", ephemeral: true);
                    return;
                }

                // Normalize avatar name: empty string or whitespace becomes null
                string? normalizedAvatar = string.IsNullOrWhiteSpace(avatarName)
                    ? null
                    : avatarName.Trim();

                // Validate avatar if provided
                if (normalizedAvatar is not null && !_quoteService.ValidateAvatarName(normalizedAvatar))
                {
                    await FollowupAsync(
                        $"Avatar '{normalizedAvatar}' does not exist! Use the autocomplete to select a valid avatar.",
                        ephemeral: true);
                    return;
                }

                // Create and add quote
                Quote quote = new Quote
                {
                    Avatar = normalizedAvatar,
                    Text = quoteText.Trim()
                };

                _quoteService.AddQuote(quote);
                await _quoteService.SaveQuotesToFileAsync();

                // Log success
                string avatarLog = normalizedAvatar ?? "[null]";
                _logger.LogInformation(
                    "Quote added successfully - Avatar: {Avatar}, Text: {QuoteText}, UserId: {UserId}",
                    avatarLog,
                    quoteText,
                    Context.User.Id);

                // Send success response
                string avatarDisplay = normalizedAvatar ?? "No Avatar";
                await FollowupAsync(
                    $"Quote added successfully!\nAvatar: {avatarDisplay}\nText: {quoteText}",
                    ephemeral: true);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error executing quote add command");
                await FollowupAsync("Failed to add quote due to an error!", ephemeral: true);
            }
        }
    }
}
