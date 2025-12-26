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

# Publish PsiCAT.Core (which includes DiscordApp as dependency)
RUN dotnet publish "PsiCAT.Core/PsiCAT.Core.csproj" -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app

# Copy published application from build stage
# (Data, wwwroot, and daemon are already included in the publish output from Core's Content items)
COPY --from=build /app/publish .

# Expose HTTP and HTTPS ports
EXPOSE 5247 7011

# Set environment variables
ENV ASPNETCORE_URLS=http://+:5247
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "PsiCAT.Core.dll"]
