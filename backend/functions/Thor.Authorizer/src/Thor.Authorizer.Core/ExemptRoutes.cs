namespace Thor.Authorizer.Core;

/// <summary>
/// TEMPORARY: routes the authorizer allows without verifying any credential (JWT or API key) —
/// see AuthorizerHandler's use of this. Kept here, in the Lambda's own code, rather than as an
/// API Gateway route config that bypasses the Lambda entirely, so there's one place that decides
/// what's exempt and exempt routes still go through (best-effort) Host-based tenant resolution.
/// </summary>
public static class ExemptRoutes
{
    // API Gateway's default execute-api endpoint (no custom domain mapping) prefixes every path
    // with the stage name, so the same routes below can arrive as e.g. "/dev/scalar" or
    // "/qa/v1/register" depending on environment.
    private static readonly string[] StagePrefixes = ["dev", "qa", "prod"];

    public static bool SkipsCredentialValidation(string? httpMethod, string? path)
    {
        if (string.IsNullOrEmpty(path))
        {
            return false;
        }

        var normalized = path.Length > 1 ? path.TrimEnd('/') : path;
        normalized = StripStagePrefix(normalized);

        if (string.Equals(normalized, "/health", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (string.Equals(normalized, "/scalar", StringComparison.OrdinalIgnoreCase) ||
            normalized.StartsWith("/scalar/", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        // POST /v{version}/register — TEMPORARY. The connector presents its API key in
        // x-task-api-key (not Authorization) and RegisterController validates it itself.
        return string.Equals(httpMethod, "POST", StringComparison.OrdinalIgnoreCase) &&
            IsRegisterConnectorRoute(normalized);
    }

    private static string StripStagePrefix(string path)
    {
        var segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries);

        if (segments.Length == 0 || !StagePrefixes.Contains(segments[0], StringComparer.OrdinalIgnoreCase))
        {
            return path;
        }

        return "/" + string.Join('/', segments[1..]);
    }

    private static bool IsRegisterConnectorRoute(string path)
    {
        var segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries);

        return segments.Length == 2
            && IsVersionSegment(segments[0])
            && string.Equals(segments[1], "register", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsVersionSegment(string segment) =>
        segment.Length > 1 && segment[0] is 'v' or 'V' && segment[1..].All(char.IsDigit);
}
