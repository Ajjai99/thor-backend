using Serilog.Core;
using Serilog.Events;

namespace Thor.Core.Logging;

/// <summary>
/// Keeps events that go to a tenant's CloudWatch log group out of the console, so they aren't
/// shipped twice. Referenced by type name from each service's appsettings.json, on a sub-logger
/// wrapping the console sink:
/// <code>"Filter": [ { "Name": "With", "Args": { "filter": "Thor.Core.Logging.ExcludeTenantLogGroupEvents, Thor.Core" } } ]</code>
/// The configuration binder constructs it with no arguments, which is why it reads the routing
/// switch itself. When routing is off (local development) it lets everything through.
/// </summary>
public sealed class ExcludeTenantLogGroupEvents : ILogEventFilter
{
    private readonly bool routingEnabled;

    public ExcludeTenantLogGroupEvents()
        : this(TenantLogGroupRouting.ConfiguredPrefix() is not null)
    {
    }

    internal ExcludeTenantLogGroupEvents(bool routingEnabled) => this.routingEnabled = routingEnabled;

    public bool IsEnabled(LogEvent logEvent) =>
        !routingEnabled || !TenantLogGroupRouting.TryGetTenantId(logEvent, out _);
}
