using Serilog;
using Serilog.Debugging;
using Thor.Core.Logging;

// CloudWatch failures (credentials, IAM, region) only surface through Serilog's SelfLog.
SelfLog.Enable(message => Console.Error.WriteLine($"[serilog-selflog] {message}"));

// Content root = build output, where thor-api's linked appsettings.json is copied (matters for
// `dotnet run`; in the container the working directory already is the publish folder).
var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory,
});

builder.Host.UseThorLogging();

var app = builder.Build();

// Same order as thor-api's Program.cs: header enrichment wraps request logging, so the request
// completion line also carries TenantId.
app.UseMiddleware<HeaderLogEnrichmentMiddleware>(new Dictionary<string, string>
{
    ["X-THOR-TENANT-ID"] = "TenantId",
});
app.UseSerilogRequestLogging();

app.MapGet("/health", () => Results.Ok());

// Load-test endpoint: writes `lines` log lines for the calling tenant, plus the request completion
// line from UseSerilogRequestLogging. lines=9 → 10 log lines per request.
app.MapPost("/scan", (int? lines, ILogger<Program> logger) =>
{
    var count = Math.Clamp(lines ?? 1, 0, 100);
    for (var step = 1; step <= count; step++)
    {
        logger.LogInformation(
            "Scan step {Step} of {Total}: processed {Accounts} accounts for connector {Connector} in {ElapsedMs} ms",
            step, count, 250, "ActiveDirectory", 42);
    }

    return Results.Ok(new { logged = count });
});

app.Run();

// Flush the async + batched CloudWatch sinks on shutdown (ECS SIGTERM).
await Log.CloseAndFlushAsync();
