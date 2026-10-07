# Runtime-only image: the app is published on the host first (dotnet publish -r linux-x64), so the
# build doesn't need the repo's Thor.Core sources inside the Docker context. aspnet, not runtime:
# Thor.Core references the Microsoft.AspNetCore.App framework.
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY publish/ .
ENTRYPOINT ["dotnet", "TenantLogsInAppPoc.dll"]
