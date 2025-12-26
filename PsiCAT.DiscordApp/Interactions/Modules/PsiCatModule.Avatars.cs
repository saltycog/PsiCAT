using System.Collections.Concurrent;
using Discord;
using Discord.Interactions;
using Microsoft.Extensions.Logging;

namespace PsiCAT.DiscordApp.Interactions.Modules;

public partial class PsiCatModule
{
    [Group("avatars", "Avatar commands")]
    public class AvatarSubcommands : InteractionModuleBase<SocketInteractionContext>
    {
        private readonly ILogger<PsiCatModule> _logger;
        private readonly string _webRootPath;
        private readonly IHttpClientFactory _httpClientFactory;

        private static readonly ConcurrentDictionary<string, string> SupportedMimeTypes = new()
        {
            ["image/png"] = ".png",
            ["image/gif"] = ".gif",
            ["image/jpeg"] = ".jpg",
            ["image/webp"] = ".webp"
        };

        private const long MaxFileSizeBytes = 2097152; // 2 MB
        private const string AvatarNamePattern = @"^[a-zA-Z0-9_\-]{1,50}$";

        public AvatarSubcommands(
            ILogger<PsiCatModule> logger,
            string webRootPath,
            IHttpClientFactory httpClientFactory)
        {
            _logger = logger;
            _webRootPath = webRootPath;
            _httpClientFactory = httpClientFactory;
        }

        /// <summary>
        /// Lists all available avatars.
        /// </summary>
        [SlashCommand("list", "List all available avatars")]
        public async Task AvatarsListAsync()
        {
            try
            {
                string avatarsPath = Path.Combine(_webRootPath, "avatars");

                if (!Directory.Exists(avatarsPath))
                {
                    await RespondAsync("Avatars directory not found!", ephemeral: true);
                    return;
                }

                string[] files = Directory.GetFiles(avatarsPath);

                if (files.Length == 0)
                {
                    await RespondAsync("No avatars available!", ephemeral: true);
                    return;
                }

                string[] avatarNames = files
                    .Select(f => Path.GetFileNameWithoutExtension(f))
                    .OrderBy(name => name)
                    .ToArray();

                string avatarList = string.Join("\n", avatarNames.Select(name => $"• {name}"));
                await RespondAsync(
                    $"Available avatars:\n{avatarList}",
                    ephemeral: true);

                _logger.LogInformation("Listed {AvatarCount} avatars", avatarNames.Length);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error executing avatars list command");
                await RespondAsync("An error occurred!", ephemeral: true);
            }
        }

        /// <summary>
        /// Adds a new avatar to the shared pool.
        /// </summary>
        [SlashCommand("add", "Add a new avatar to the shared pool")]
        public async Task AvatarsAddAsync(
            [Summary("avatarName", "Name for the avatar (without extension)")] string avatarName,
            [Summary("image", "Avatar image file")] IAttachment image)
        {
            try
            {
                await DeferAsync();

                // Validate avatar name
                if (!IsValidAvatarName(avatarName))
                {
                    await FollowupAsync(
                        "Invalid avatar name! Must be 1-50 characters, containing only letters, numbers, underscores, and hyphens.",
                        ephemeral: true);
                    return;
                }

                // Validate file size
                if (image.Size > MaxFileSizeBytes)
                {
                    await FollowupAsync(
                        $"File is too large! Maximum size is 2 MB, but your file is {image.Size / 1024.0 / 1024.0:F2} MB.",
                        ephemeral: true);
                    return;
                }

                // Validate content type
                if (!IsValidImageFormat(image.ContentType))
                {
                    await FollowupAsync(
                        "Invalid image format! Supported formats: PNG, GIF, JPG/JPEG, WebP.",
                        ephemeral: true);
                    return;
                }

                // Check if avatar with same name already exists
                if (AvatarExistsWithAnyExtension(avatarName))
                {
                    await FollowupAsync(
                        $"An avatar named '{avatarName}' already exists!",
                        ephemeral: true);
                    return;
                }

                // Get file extension from content type
                string extension = GetFileExtensionFromContentType(image.ContentType);
                string avatarsPath = Path.Combine(_webRootPath, "avatars");

                // Ensure avatars directory exists
                Directory.CreateDirectory(avatarsPath);

                string filePath = Path.Combine(avatarsPath, $"{avatarName}{extension}");
                string tempFilePath = $"{filePath}.tmp";

                try
                {
                    // Download image from URL
                    using (HttpClient client = _httpClientFactory.CreateClient())
                    {
                        using (HttpResponseMessage response = await client.GetAsync(image.Url))
                        {
                            response.EnsureSuccessStatusCode();
                            using (Stream contentStream = await response.Content.ReadAsStreamAsync())
                            {
                                using (FileStream fileStream = new(tempFilePath, FileMode.Create, FileAccess.Write))
                                {
                                    await contentStream.CopyToAsync(fileStream);
                                }
                            }
                        }
                    }

                    // Move temp file to final location
                    File.Move(tempFilePath, filePath, overwrite: true);

                    _logger.LogInformation(
                        "Avatar uploaded successfully - Name: {AvatarName}, Extension: {Extension}, Size: {FileSize} bytes, UserId: {UserId}",
                        avatarName,
                        extension,
                        new FileInfo(filePath).Length,
                        Context.User.Id);

                    await FollowupAsync(
                        $"Avatar '{avatarName}' has been added successfully!",
                        ephemeral: false);
                }
                catch (HttpRequestException ex)
                {
                    // Clean up temp file if it exists
                    if (File.Exists(tempFilePath))
                    {
                        File.Delete(tempFilePath);
                    }

                    _logger.LogError(ex, "Failed to download image for avatar '{AvatarName}'", avatarName);
                    await FollowupAsync(
                        "Failed to download image! Please check that the image file is accessible.",
                        ephemeral: true);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error executing avatars add command");
                await FollowupAsync("An error occurred!", ephemeral: true);
            }
        }

        /// <summary>
        /// Validates that the avatar name matches the required pattern.
        /// </summary>
        private static bool IsValidAvatarName(string name)
        {
            return System.Text.RegularExpressions.Regex.IsMatch(name, AvatarNamePattern);
        }

        /// <summary>
        /// Checks if an avatar with the given name exists with any supported extension.
        /// </summary>
        private bool AvatarExistsWithAnyExtension(string name)
        {
            string avatarsPath = Path.Combine(_webRootPath, "avatars");
            if (!Directory.Exists(avatarsPath))
            {
                return false;
            }

            string[] supportedExtensions = [".png", ".gif", ".jpg", ".jpeg", ".webp"];
            return supportedExtensions.Any(ext =>
                File.Exists(Path.Combine(avatarsPath, $"{name}{ext}")));
        }

        /// <summary>
        /// Gets the file extension for a given MIME type.
        /// </summary>
        private static string GetFileExtensionFromContentType(string contentType)
        {
            return SupportedMimeTypes.TryGetValue(contentType, out string? extension)
                ? extension
                : ".png"; // Default fallback
        }

        /// <summary>
        /// Validates that the content type is a supported image format.
        /// </summary>
        private static bool IsValidImageFormat(string? contentType)
        {
            return !string.IsNullOrEmpty(contentType) && SupportedMimeTypes.ContainsKey(contentType);
        }
    }
}
