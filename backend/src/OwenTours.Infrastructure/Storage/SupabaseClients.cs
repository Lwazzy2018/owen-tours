using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;
using OwenTours.Application.Abstractions;
using OwenTours.Infrastructure.Persistence;

namespace OwenTours.Infrastructure.Storage;

public sealed class SupabaseOptions
{
    public const string Section = "Supabase";

    /// <summary>e.g. https://abcdefgh.supabase.co</summary>
    public string Url { get; set; } = "";

    /// <summary>Service role key. SERVER ONLY – never put this in the Flutter app.</summary>
    public string ServiceRoleKey { get; set; } = "";

    /// <summary>Legacy HS256 JWT secret (optional). Newer projects use signing keys (JWKS) instead.</summary>
    public string? JwtSecret { get; set; }

    public string BaseUrl => Url.TrimEnd('/');
}

/// <summary>Supabase Storage via its REST API, using the service role key.</summary>
public sealed class SupabaseStorage(HttpClient http, IOptions<SupabaseOptions> options) : IFileStorage
{
    private readonly SupabaseOptions _o = options.Value;

    public async Task<StoredFile> UploadAsync(string bucket, string path, Stream content, string contentType, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{_o.BaseUrl}/storage/v1/object/{bucket}/{EncodePath(path)}");
        Authorize(req);
        req.Headers.Add("x-upsert", "true");
        req.Content = new StreamContent(content);
        req.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        req.Headers.CacheControl = new CacheControlHeaderValue { MaxAge = TimeSpan.FromDays(365), Public = true };

        using var res = await http.SendAsync(req, ct);
        await EnsureOk(res, "upload", ct);
        var isPublic = bucket is "trip-media" or "past-trip-media";
        return new StoredFile(bucket, path, isPublic ? $"{_o.BaseUrl}/storage/v1/object/public/{bucket}/{EncodePath(path)}" : null);
    }

    public async Task DeleteAsync(string bucket, string path, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Delete, $"{_o.BaseUrl}/storage/v1/object/{bucket}");
        Authorize(req);
        req.Content = JsonContent.Create(new { prefixes = new[] { path } });
        using var res = await http.SendAsync(req, ct);
        if (res.StatusCode != HttpStatusCode.NotFound) await EnsureOk(res, "delete", ct);
    }

    public async Task<string> CreateSignedUrlAsync(string bucket, string path, TimeSpan validFor, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, $"{_o.BaseUrl}/storage/v1/object/sign/{bucket}/{EncodePath(path)}");
        Authorize(req);
        req.Content = JsonContent.Create(new { expiresIn = (int)validFor.TotalSeconds });
        using var res = await http.SendAsync(req, ct);
        await EnsureOk(res, "sign", ct);
        var body = await res.Content.ReadFromJsonAsync<SignedUrlResponse>(cancellationToken: ct)
                   ?? throw new InvalidOperationException("Empty signed URL response from Supabase.");
        return $"{_o.BaseUrl}/storage/v1{body.SignedUrl}";
    }

    private void Authorize(HttpRequestMessage req)
    {
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _o.ServiceRoleKey);
        req.Headers.Add("apikey", _o.ServiceRoleKey);
    }

    private static string EncodePath(string path) => string.Join('/', path.Split('/').Select(Uri.EscapeDataString));

    private static async Task EnsureOk(HttpResponseMessage res, string action, CancellationToken ct)
    {
        if (res.IsSuccessStatusCode) return;
        var text = await res.Content.ReadAsStringAsync(ct);
        throw new HttpRequestException($"Supabase storage {action} failed ({(int)res.StatusCode}): {text}");
    }

    private sealed record SignedUrlResponse([property: JsonPropertyName("signedURL")] string SignedUrl);
}

/// <summary>Invites staff through Supabase Auth's admin API.</summary>
public sealed class SupabaseAuthAdmin(HttpClient http, IOptions<SupabaseOptions> options, UserDirectory users) : IAuthAdmin
{
    private readonly SupabaseOptions _o = options.Value;

    public async Task<Guid> InviteUserAsync(string email, string fullName, CancellationToken ct)
    {
        // Someone who already has an account just gets promoted.
        var existing = await users.FindIdByEmailAsync(email, ct);
        if (existing is not null) return existing.Value;

        using var req = new HttpRequestMessage(HttpMethod.Post, $"{_o.BaseUrl}/auth/v1/invite");
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _o.ServiceRoleKey);
        req.Headers.Add("apikey", _o.ServiceRoleKey);
        req.Content = JsonContent.Create(new { email, data = new { full_name = fullName } });

        using var res = await http.SendAsync(req, ct);
        var text = await res.Content.ReadAsStringAsync(ct);
        if (!res.IsSuccessStatusCode)
            throw new HttpRequestException($"Supabase invite failed ({(int)res.StatusCode}): {text}");

        using var doc = JsonDocument.Parse(text);
        return doc.RootElement.GetProperty("id").GetGuid();
    }
}
