using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using PsiCAT.DiscordApp.Models;

namespace PsiCAT.DiscordApp.Services;

public class QuoteService
{
    private readonly List<Quote> _quotes = new();
    private readonly PsiCatOptions _options;
    private readonly string _contentRootPath;
    private readonly string _webRootPath;
    private readonly ILogger<QuoteService> _logger;
    private readonly SemaphoreSlim _fileLock = new(1, 1);

    public QuoteService(
        IOptions<PsiCatOptions> options,
        string contentRootPath,
        string webRootPath,
        ILogger<QuoteService> logger)
    {
        _options = options.Value;
        _contentRootPath = contentRootPath;
        _webRootPath = webRootPath;
        _logger = logger;

        LoadQuotes();
    }

    private void LoadQuotes()
    {
        try
        {
            _logger.LogInformation("ContentRootPath: {ContentRootPath}", _contentRootPath);
            _logger.LogInformation("QuotesFilePath from config: {QuotesFilePath}", _options.QuotesFilePath);

            string quotesPath = Path.Combine(_contentRootPath, _options.QuotesFilePath);

            _logger.LogInformation("Attempting to load quotes from: {QuotesPath}", quotesPath);

            if (!File.Exists(quotesPath))
            {
                _logger.LogWarning("Quotes file not found at {QuotesPath}", quotesPath);
                return;
            }

            string json = File.ReadAllText(quotesPath);
            _logger.LogInformation("Read JSON file, length: {JsonLength}", json.Length);

            QuoteCollection? collection = JsonSerializer.Deserialize<QuoteCollection>(json);
            _logger.LogInformation("Deserialized collection: {Collection}", collection);
            _logger.LogInformation("Collection.Quotes is null: {IsNull}", collection?.Quotes == null);
            _logger.LogInformation("Collection.Quotes count: {QuoteCount}", collection?.Quotes?.Count ?? 0);

            if (collection?.Quotes != null)
            {
                _quotes.AddRange(collection.Quotes);
                _logger.LogInformation("Loaded {QuoteCount} quotes", _quotes.Count);
            }
            else
            {
                _logger.LogWarning("Collection or Quotes is null after deserialization");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load quotes");
        }
    }

    public Quote? GetRandomQuote()
    {
        if (_quotes.Count == 0)
        {
            _logger.LogWarning("No quotes available");
            return null;
        }

        int index = Random.Shared.Next(_quotes.Count);
        return _quotes[index];
    }

    public string GetAvatarUrl(string? avatarName)
    {
        if (string.IsNullOrEmpty(avatarName))
        {
            return _options.DefaultAvatar ?? "";
        }

        string extension = GetAvatarFileExtension(avatarName);

        if (extension == string.Empty)
        {
            return _options.DefaultAvatar ?? "";
        }

        string encodedAvatarName = Uri.EscapeDataString(avatarName);
        return $"{_options.AvatarBaseUrl}/avatars/{encodedAvatarName}.{extension}";
    }

    /// <summary>
    /// Determines the file extension for an avatar by checking file existence.
    /// Checks for supported formats: GIF, PNG, JPG, JPEG, WebP.
    /// Returns the extension without the dot, or empty string if no file exists.
    /// </summary>
    private string GetAvatarFileExtension(string avatarName)
    {
        string avatarsPath = Path.Combine(_webRootPath, "avatars");
        string[] supportedExtensions = ["gif", "png", "jpg", "jpeg", "webp"];

        foreach (string extension in supportedExtensions)
        {
            string filePath = Path.Combine(avatarsPath, $"{avatarName}.{extension}");
            if (File.Exists(filePath))
            {
                return extension;
            }
        }

        return string.Empty;
    }

    /// <summary>
    /// Gets all avatar names from the wwwroot/avatars/ directory, sorted alphabetically.
    /// File extensions are removed from the returned names.
    /// </summary>
    /// <returns>An array of avatar names (without extensions), or an empty array if the directory doesn't exist.</returns>
    public string[] GetAllAvatarNames()
    {
        string avatarsPath = Path.Combine(_webRootPath, "avatars");

        if (!Directory.Exists(avatarsPath))
        {
            _logger.LogWarning("Avatars directory not found at {AvatarsPath}", avatarsPath);
            return [];
        }

        string[] supportedExtensions = ["gif", "png", "jpg", "jpeg", "webp"];
        string[] files = Directory.GetFiles(avatarsPath);

        List<string> avatarNames = new();
        foreach (string file in files)
        {
            string fileName = Path.GetFileName(file);
            string extension = Path.GetExtension(fileName).TrimStart('.');

            if (supportedExtensions.Contains(extension.ToLowerInvariant()))
            {
                string avatarName = Path.GetFileNameWithoutExtension(fileName);
                avatarNames.Add(avatarName);
            }
        }

        avatarNames.Sort();
        _logger.LogInformation("Found {AvatarCount} avatars", avatarNames.Count);
        return avatarNames.ToArray();
    }

    /// <summary>
    /// Adds a quote to the in-memory quote list.
    /// </summary>
    /// <param name="quote">The quote to add. Must not be null and text must not be empty or whitespace.</param>
    /// <exception cref="ArgumentNullException">Thrown when quote is null.</exception>
    /// <exception cref="ArgumentException">Thrown when quote text is null, empty, or whitespace.</exception>
    public void AddQuote(Quote quote)
    {
        ArgumentNullException.ThrowIfNull(quote);

        if (string.IsNullOrWhiteSpace(quote.Text))
        {
            throw new ArgumentException("Quote text cannot be null, empty, or whitespace.", nameof(quote));
        }

        _quotes.Add(quote);
        string avatarLog = quote.Avatar ?? "[null]";
        _logger.LogInformation("Added quote with avatar '{Avatar}': {QuoteText}", avatarLog, quote.Text);
    }

    /// <summary>
    /// Saves all quotes to the quotes file asynchronously using a thread-safe pattern.
    /// Writes to a temporary file first, then moves it to the target location to ensure atomicity.
    /// </summary>
    public async Task SaveQuotesToFileAsync()
    {
        await _fileLock.WaitAsync();
        try
        {
            string quotesPath = Path.Combine(_contentRootPath, _options.QuotesFilePath);
            string tempPath = quotesPath + ".tmp";

            QuoteCollection collection = new QuoteCollection { Quotes = _quotes };
            string json = JsonSerializer.Serialize(
                collection,
                new JsonSerializerOptions { WriteIndented = true }
            );

            await File.WriteAllTextAsync(tempPath, json);
            File.Move(tempPath, quotesPath, overwrite: true);

            _logger.LogInformation("Saved {QuoteCount} quotes to {QuotesPath}", _quotes.Count, quotesPath);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    /// <summary>
    /// Validates that an avatar name exists in the avatars directory.
    /// Returns true if the avatar file exists with a supported extension, false otherwise.
    /// </summary>
    public bool ValidateAvatarName(string avatarName)
    {
        if (string.IsNullOrWhiteSpace(avatarName))
        {
            return false;
        }

        string avatarsPath = Path.Combine(_webRootPath, "avatars");
        string[] supportedExtensions = ["gif", "png", "jpg", "jpeg", "webp"];

        foreach (string extension in supportedExtensions)
        {
            string filePath = Path.Combine(avatarsPath, $"{avatarName}.{extension}");
            if (File.Exists(filePath))
            {
                return true;
            }
        }

        return false;
    }
}
