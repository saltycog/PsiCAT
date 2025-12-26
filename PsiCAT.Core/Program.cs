using PsiCAT.DiscordApp;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

// Register Discord application module
builder.Services.AddDiscordApp(
    builder.Configuration,
    builder.Environment.ContentRootPath,
    builder.Environment.WebRootPath);

WebApplication app = builder.Build();

// Configure HTTP pipeline
app.UseStaticFiles();

app.MapGet("/", () => "PsiCAT - Multi-Platform Bot Framework");
app.MapGet("/health", () => new
{
    status = "healthy",
    timestamp = DateTime.UtcNow,
    applications = new[] { "discord" }
});

await app.RunAsync();
