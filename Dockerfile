# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy solution and project files
COPY ["PsiCAT.sln", "."]
COPY ["PsiCAT.Core/PsiCAT.Core.csproj", "PsiCAT.Core/"]
COPY ["PsiCAT.DiscordApp/PsiCAT.DiscordApp.csproj", "PsiCAT.DiscordApp/"]

# Restore dependencies
RUN dotnet restore "PsiCAT.sln"

# Copy remaining source code
COPY . .

# Build the solution
RUN dotnet build "PsiCAT.sln" -c Release -o /app/build

# Publish PsiCAT.DiscordApp
RUN dotnet publish "PsiCAT.DiscordApp/PsiCAT.DiscordApp.csproj" -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app

# Copy published application from build stage
COPY --from=build /app/publish .

# Copy data files and static assets (can be overridden with volumes)
COPY PsiCAT.DiscordApp/Data ./Data
COPY PsiCAT.DiscordApp/wwwroot ./wwwroot

EXPOSE 5000

ENTRYPOINT ["dotnet", "PsiCAT.DiscordApp.dll"]
