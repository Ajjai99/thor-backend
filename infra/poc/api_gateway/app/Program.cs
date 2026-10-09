using Npgsql;
using Serilog;
using Serilog.Debugging;
using Thor.Core.Logging;

// CloudWatch failures (credentials, IAM, region) only surface through Serilog's SelfLog.
SelfLog.Enable(message => Console.Error.WriteLine($"[serilog-selflog] {message}"));

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory,
});

builder.Host.UseThorLogging();

// Through RDS Proxy (TLS required there). Password auth from the Aurora-managed secret, injected by
// ECS; the real services use IAM auth instead, which doesn't change what the dashboard shows.
builder.Services.AddSingleton(_ => new NpgsqlDataSourceBuilder(new NpgsqlConnectionStringBuilder
{
    Host = RequiredEnv("DB_HOST"),
    Database = RequiredEnv("DB_NAME"),
    Username = RequiredEnv("DB_USER"),
    Password = RequiredEnv("DB_PASSWORD"),
    SslMode = SslMode.Require,
    MaxPoolSize = 20,
}.ConnectionString).Build());

var app = builder.Build();

// Same order as thor-api's Program.cs: header enrichment wraps request logging.
app.UseMiddleware<HeaderLogEnrichmentMiddleware>(new Dictionary<string, string>
{
    ["X-THOR-TENANT-ID"] = "TenantId",
});
app.UseSerilogRequestLogging();

app.MapGet("/health", () => Results.Ok());

// Writes `lines` log lines for the calling tenant (plus the request completion line).
app.MapPost("/scan", (int? lines, ILogger<Program> logger) =>
{
    var count = Math.Clamp(lines ?? 1, 0, 100);
    for (var step = 1; step <= count; step++)
    {
        logger.LogInformation(
            "Scan step {Step} of {Total}: processed {Accounts} accounts for connector {Connector}",
            step, count, 250, "ActiveDirectory");
    }

    return Results.Ok(new { logged = count });
});

// One write and one read per call, so Aurora and RDS Proxy metrics move under load.
app.MapPost("/db", async (NpgsqlDataSource db, HttpContext http, ILogger<Program> logger) =>
{
    var tenantId = http.Request.Headers["X-THOR-TENANT-ID"].ToString();
    await using var connection = await db.OpenConnectionAsync();

    await using (var insert = new NpgsqlCommand(
        "INSERT INTO poc_events (tenant_id, created_at) VALUES (@tenant, now())", connection))
    {
        insert.Parameters.AddWithValue("tenant", tenantId);
        await insert.ExecuteNonQueryAsync();
    }

    await using var count = new NpgsqlCommand(
        "SELECT count(*) FROM poc_events WHERE tenant_id = @tenant", connection);
    count.Parameters.AddWithValue("tenant", tenantId);
    var events = (long)(await count.ExecuteScalarAsync() ?? 0L);

    logger.LogInformation("Recorded event {Events} for this tenant", events);
    return Results.Ok(new { events });
});

// The table the /db endpoint uses; created once at startup.
await using (var connection = await app.Services.GetRequiredService<NpgsqlDataSource>().OpenConnectionAsync())
await using (var create = new NpgsqlCommand(
    "CREATE TABLE IF NOT EXISTS poc_events (id bigserial PRIMARY KEY, tenant_id text NOT NULL, created_at timestamptz NOT NULL)",
    connection))
{
    await create.ExecuteNonQueryAsync();
}

app.Run();

await Log.CloseAndFlushAsync();

static string RequiredEnv(string name) =>
    Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
        ? value
        : throw new InvalidOperationException($"Missing environment variable {name}");
