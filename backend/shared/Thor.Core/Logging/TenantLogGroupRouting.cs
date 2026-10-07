using Serilog.Events;

namespace Thor.Core.Logging;

/// <summary>
/// The one rule deciding whether a log event goes to its tenant's own CloudWatch log group instead
/// of the service's console output. Both sides use it — the tenant branch in
/// <see cref="ThorLoggingExtensions"/> to pick events up, <see cref="ExcludeTenantLogGroupEvents"/>
/// to drop the same events from the console — so an event lands in exactly one place, never both
/// and never neither.
///
/// Routing is on only when <see cref="PrefixVariable"/> is set, which only deployed environments
/// do. TenantId must parse as a GUID: on task-api it comes from a header set by internal callers,
/// and an unchecked value would let a caller create arbitrary log groups.
/// </summary>
public static class TenantLogGroupRouting
{
    /// <summary>Log group name prefix, e.g. "/ecs/dev/thor-api/tenants/"; the tenant ID is appended.</summary>
    public const string PrefixVariable = "THOR_TENANT_LOG_GROUP_PREFIX";

    public static string? ConfiguredPrefix()
    {
        var prefix = Environment.GetEnvironmentVariable(PrefixVariable);
        return string.IsNullOrWhiteSpace(prefix) ? null : prefix;
    }

    /// <summary>
    /// True when the event carries a GUID TenantId, returned normalized (lowercase, hyphenated) so
    /// differently-cased values for one tenant share a log group. Shaped as Serilog.Sinks.Map's
    /// KeySelector so the tenant branch can use it directly.
    /// </summary>
    public static bool TryGetTenantId(LogEvent logEvent, out string tenantId)
    {
        tenantId = string.Empty;
        if (!logEvent.Properties.TryGetValue(ThorLoggingExtensions.TenantIdProperty, out var value)
            || value is not ScalarValue { Value: not null } scalar
            || !Guid.TryParse(scalar.Value.ToString(), out var id))
        {
            return false;
        }

        tenantId = id.ToString();
        return true;
    }
}
