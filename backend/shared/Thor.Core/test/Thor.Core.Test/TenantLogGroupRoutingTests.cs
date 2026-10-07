using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Serilog;
using Serilog.Events;
using Serilog.Parsing;
using Thor.Core.Logging;

namespace Thor.Core.Test;

/// <summary>
/// An event must land in exactly one place: its tenant's CloudWatch log group (picked up by
/// TryGetTenantId) or the console (let through by ExcludeTenantLogGroupEvents) — never both, never
/// neither. Only a GUID TenantId routes, so a junk header value can't name a log group.
/// </summary>
public class TenantLogGroupRoutingTests
{
    private const string TenantGuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

    [Theory]
    [InlineData(TenantGuid)]
    [InlineData("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")]
    public void TryGetTenantId_WithGuidString_ReturnsNormalizedId(string tenantId)
    {
        TenantLogGroupRouting.TryGetTenantId(EventWithTenant(tenantId), out var routed).Should().BeTrue();
        routed.Should().Be(TenantGuid);
    }

    [Fact]
    public void TryGetTenantId_WithGuidValue_ReturnsId()
    {
        TenantLogGroupRouting.TryGetTenantId(EventWithTenant(Guid.Parse(TenantGuid)), out var routed).Should().BeTrue();
        routed.Should().Be(TenantGuid);
    }

    [Theory]
    [InlineData("not-a-guid")]
    [InlineData("")]
    [InlineData("../../other-tenant")]
    public void TryGetTenantId_WithNonGuid_ReturnsFalse(string tenantId)
    {
        TenantLogGroupRouting.TryGetTenantId(EventWithTenant(tenantId), out _).Should().BeFalse();
    }

    [Fact]
    public void TryGetTenantId_WithoutTenant_ReturnsFalse()
    {
        TenantLogGroupRouting.TryGetTenantId(EventWithTenant(null), out _).Should().BeFalse();
    }

    [Theory]
    [InlineData(TenantGuid, false)]
    [InlineData("not-a-guid", true)]
    [InlineData(null, true)]
    public void Filter_WhenRoutingEnabled_PassesExactlyTheEventsNotRouted(string? tenantId, bool expectedOnConsole)
    {
        var logEvent = EventWithTenant(tenantId);

        new ExcludeTenantLogGroupEvents(routingEnabled: true).IsEnabled(logEvent).Should().Be(expectedOnConsole);
        TenantLogGroupRouting.TryGetTenantId(logEvent, out _).Should().Be(!expectedOnConsole);
    }

    [Theory]
    [InlineData(TenantGuid)]
    [InlineData(null)]
    public void Filter_WhenRoutingDisabled_PassesEverything(string? tenantId)
    {
        new ExcludeTenantLogGroupEvents(routingEnabled: false).IsEnabled(EventWithTenant(tenantId)).Should().BeTrue();
    }

    // The appsettings.json wiring: the console sits in a sub-logger whose filter is named by type,
    // so the configuration binder must be able to construct it with no arguments.
    [Fact]
    public void Filter_ReferencedByTypeName_IsBuiltFromConfiguration()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Serilog:WriteTo:0:Name"] = "Logger",
                ["Serilog:WriteTo:0:Args:configureLogger:Filter:0:Name"] = "With",
                ["Serilog:WriteTo:0:Args:configureLogger:Filter:0:Args:filter"] =
                    "Thor.Core.Logging.ExcludeTenantLogGroupEvents, Thor.Core",
            })
            .Build();

        var build = () => new LoggerConfiguration().ReadFrom.Configuration(configuration).CreateLogger().Dispose();

        build.Should().NotThrow();
    }

    private static LogEvent EventWithTenant(object? tenantId)
    {
        var properties = tenantId is null
            ? []
            : new[] { new LogEventProperty("TenantId", new ScalarValue(tenantId)) };

        return new LogEvent(
            DateTimeOffset.UtcNow,
            LogEventLevel.Information,
            exception: null,
            new MessageTemplateParser().Parse("Scan started"),
            properties);
    }
}
