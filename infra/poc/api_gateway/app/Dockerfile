# Runtime-only image: published on the host first (dotnet publish -r linux-x64), so the Docker
# context doesn't need the repo's Thor.Core sources. aspnet: it's an ASP.NET Core app.
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY publish/ .
ENTRYPOINT ["dotnet", "PlatformPoc.dll"]
