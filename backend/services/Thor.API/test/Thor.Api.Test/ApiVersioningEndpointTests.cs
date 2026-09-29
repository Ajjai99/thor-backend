using System.Net;
using System.Net.Http.Json;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Thor.Api.Test.TestFixtures;

namespace Thor.Api.Test;

public class ApiVersioningEndpointTests : IClassFixture<ThorApiWebApplicationFactory>
{
    private readonly HttpClient _client;

    public ApiVersioningEndpointTests(ThorApiWebApplicationFactory factory)
    {
        _client = factory
            .WithWebHostBuilder(builder => builder.UseEnvironment("Development"))
            .CreateClient();
    }

    [Fact]
    public async Task Register_OnUnversionedRoute_ReturnsNotFound()
    {
        var response = await _client.PostAsJsonAsync("/register", new { roleType = "scanner" });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task RefreshRegister_OnUnversionedRoute_ReturnsNotFound()
    {
        var response = await _client.PostAsJsonAsync("/register/refresh", new { });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Register_OnV1Route_IsReachedAndReportsVersion()
    {
        var response = await _client.PostAsJsonAsync("/v1/register", new { roleType = "scanner" });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Headers.GetValues("api-version").Should().ContainSingle().Which.Should().Be("1");
        response.Headers.GetValues("api-supported-versions").Should().ContainSingle().Which.Should().Be("1.0");
    }

    [Theory]
    [InlineData("/scan-config")]
    [InlineData("/scan")]
    public async Task Scan_OnUnversionedRoute_ReturnsNotFound(string path)
    {
        var response = await _client.PostAsJsonAsync(path, new { });

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task ScanConfig_OnV1Route_IsReachedAndReportsVersion()
    {
        var response = await _client.PostAsJsonAsync(
            "/v1/scan-config", new { name = "scan-config-1", sourceIds = new[] { Guid.NewGuid() }, configValues = Array.Empty<object>() });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Headers.GetValues("api-version").Should().ContainSingle().Which.Should().Be("1");
    }

    [Fact]
    public async Task Scan_OnV1Route_IsReachedAndReportsVersion()
    {
        var response = await _client.PostAsJsonAsync("/v1/scan", new { scanConfigId = Guid.NewGuid() });

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Headers.GetValues("api-version").Should().ContainSingle().Which.Should().Be("1");
    }

    [Fact]
    public async Task OpenApiDocument_IsGeneratedPerVersion()
    {
        var response = await _client.GetAsync("/openapi/v1.json");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var document = await response.Content.ReadAsStringAsync();
        document.Should().Contain("/v1/register");
    }
}
