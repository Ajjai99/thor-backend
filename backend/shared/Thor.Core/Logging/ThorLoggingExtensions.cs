using Amazon;
using Amazon.CloudWatchLogs;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Formatting.Compact;
using Serilog.Sinks.AwsCloudWatch;

namespace Thor.Core.Logging;

/// <summary>
/// Bootstraps Serilog as the logging provider for a Thor service. Output format and
/// sinks (console, an external HTTP endpoint, etc.) are entirely caller-configured via
/// that service's own "Serilog" appsettings section (see Serilog.Settings.Configuration)
/// — this project does not hard-code format or sink choices.
/// </summary>
public static class ThorLoggingExtensions
{
    internal const string TenantIdProperty = "TenantId";
    private const string NoTenantKey = "";

    // Set by the infra alongside THOR_TENANT_LOG_GROUP_PREFIX: Fargate doesn't set AWS_REGION, and
    // the SDK has no instance metadata to fall back to there.
    private const string AwsRegionVariable = "THOR_AWS_REGION";

    // Open per-tenant CloudWatch sinks a process keeps at once. Past it, Serilog.Sinks.Map flushes
    // and disposes the least recently used one, bounding memory however many tenants log.
    private const int TenantLogGroupSinkLimit = 100;

    // Serilog.Sinks.Http's own default when logEventsInBatchLimit is omitted entirely.
    // Passing null explicitly means "unbounded", a different behavior — so a tenant that
    // doesn't override BatchSizeLimit must still get this value, not null.
    private const int DefaultBatchSizeLimit = 1000;

    public static IHostBuilder UseThorLogging(this IHostBuilder hostBuilder) =>
        hostBuilder.UseSerilog((context, services, loggerConfiguration) =>
        {
            loggerConfiguration
                .ReadFrom.Configuration(context.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext();

            // Per-tenant HTTP sink routing is opt-in: only wired up if the service registers
            // an ITenantLogSinkResolver. Wrapped in WriteTo.Async so resolving the sink (a
            // Master DB lookup, cached) and writing to it happen on a background thread —
            // the request thread only ever enqueues an in-memory log event and returns.
            var tenantLogSinkResolver = services.GetService<ITenantLogSinkResolver>();
            if (tenantLogSinkResolver is not null)
            {
                loggerConfiguration.WriteTo.Async(sinkConfiguration => sinkConfiguration.Map(
                    keyPropertyName: TenantIdProperty,
                    defaultKey: NoTenantKey,
                    configure: (tenantId, writeTo) =>
                    {
                        var options = string.IsNullOrEmpty(tenantId) ? null : tenantLogSinkResolver.Resolve(tenantId);
                        if (options is not null)
                        {
                            writeTo.Http(
                                options.Endpoint,
                                queueLimitBytes: null,
                                logEventsInBatchLimit: options.BatchSizeLimit ?? DefaultBatchSizeLimit);
                        }
                    }));
            }

            // Per-tenant CloudWatch log groups: on only where THOR_TENANT_LOG_GROUP_PREFIX is set
            // (deployed environments). Each event with a GUID TenantId goes to <prefix><tenantId>
            // only — ExcludeTenantLogGroupEvents, wired around the console in appsettings.json,
            // drops the same events from stdout using the same rule. Async + batched like the HTTP
            // sink above, so the request thread only enqueues; the group is created (30-day
            // retention, matching the service log groups) on a tenant's first event.
            var tenantLogGroupPrefix = TenantLogGroupRouting.ConfiguredPrefix();
            if (tenantLogGroupPrefix is not null)
            {
                var cloudWatchLogs = CreateCloudWatchLogsClient();
                loggerConfiguration.WriteTo.Async(sinkConfiguration => sinkConfiguration.Map<string>(
                    TenantLogGroupRouting.TryGetTenantId,
                    (tenantId, writeTo) => writeTo.AmazonCloudWatch(
                        new CloudWatchSinkOptions
                        {
                            LogGroupName = tenantLogGroupPrefix + tenantId,
                            CreateLogGroup = true,
                            LogGroupRetentionPolicy = LogGroupRetentionPolicy.OneMonth,
                            TextFormatter = new RenderedCompactJsonFormatter(),
                        },
                        cloudWatchLogs),
                    sinkMapCountLimit: TenantLogGroupSinkLimit));
            }
        });

    private static AmazonCloudWatchLogsClient CreateCloudWatchLogsClient()
    {
        var region = Environment.GetEnvironmentVariable(AwsRegionVariable);
        return string.IsNullOrWhiteSpace(region)
            ? new AmazonCloudWatchLogsClient()
            : new AmazonCloudWatchLogsClient(RegionEndpoint.GetBySystemName(region));
    }
}
