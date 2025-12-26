using Discord;
using Discord.Interactions;
using Microsoft.Extensions.DependencyInjection;
using PsiCAT.DiscordApp.Services;

namespace PsiCAT.DiscordApp.Interactions.Autocomplete;

/// <summary>
/// Provides autocomplete suggestions for avatar names in Discord interactions.
/// Includes a special "[No Avatar]" option to represent null/default avatar.
/// </summary>
public class AvatarNameAutocompleteHandler : AutocompleteHandler
{
    private const int MaxSuggestions = 25;

    /// <summary>
    /// Generates avatar name suggestions based on user input.
    /// Returns up to 24 avatars plus the "[No Avatar]" option (Discord limit: 25).
    /// </summary>
    public override Task<AutocompletionResult> GenerateSuggestionsAsync(
        IInteractionContext context,
        IAutocompleteInteraction autocompleteInteraction,
        IParameterInfo parameter,
        IServiceProvider services)
    {
        QuoteService quoteService = services.GetRequiredService<QuoteService>();
        string userInput = autocompleteInteraction.Data.Current.Value?.ToString() ?? "";

        List<AutocompleteResult> suggestions = new();

        // Get all available avatars and filter by user input
        string[] avatarNames = quoteService.GetAllAvatarNames();
        List<string> filteredAvatars = avatarNames
            .Where(name => name.Contains(userInput, StringComparison.OrdinalIgnoreCase))
            .Take(MaxSuggestions - 1)
            .ToList();

        // Add filtered avatars to suggestions
        foreach (string avatarName in filteredAvatars)
        {
            suggestions.Add(new AutocompleteResult(avatarName, avatarName));
        }

        return Task.FromResult(AutocompletionResult.FromSuccess(suggestions));
    }
}
