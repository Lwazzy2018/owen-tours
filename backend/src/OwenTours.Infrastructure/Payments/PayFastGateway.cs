using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OwenTours.Application.Abstractions;

namespace OwenTours.Infrastructure.Payments;

public sealed class PayFastOptions
{
    public const string Section = "PayFast";

    public bool UseSandbox { get; set; } = true;
    public string MerchantId { get; set; } = "";
    public string MerchantKey { get; set; } = "";
    public string? Passphrase { get; set; }
    /// <summary>Where PayFast sends the customer after paying / cancelling (the app watches for these).</summary>
    public string ReturnUrl { get; set; } = "";
    public string CancelUrl { get; set; } = "";
    /// <summary>Public URL of POST /api/payments/payfast/notify. Must be reachable from the internet.</summary>
    public string NotifyUrl { get; set; } = "";
    /// <summary>Check the notification comes from PayFast's servers. Turn off only for local testing.</summary>
    public bool ValidateSourceIp { get; set; } = true;
    /// <summary>Also ask PayFast's server to confirm the notification is genuine.</summary>
    public bool ValidateWithServer { get; set; } = true;

    public string Host => UseSandbox ? "sandbox.payfast.co.za" : "www.payfast.co.za";
}

/// <summary>
/// PayFast (South Africa). Checkout is an HTML form POST to PayFast; payment results arrive as an
/// ITN (instant transaction notification) to NotifyUrl. Verification follows PayFast's four checks:
/// signature, source IP, amount (done in PaymentService) and server confirmation.
/// </summary>
public sealed class PayFastGateway(HttpClient http, IOptions<PayFastOptions> options, ILogger<PayFastGateway> logger) : IPaymentGateway
{
    private readonly PayFastOptions _o = options.Value;

    // PayFast's published notification hosts and ranges.
    private static readonly string[] PayFastHosts = ["www.payfast.co.za", "sandbox.payfast.co.za", "w1w.payfast.co.za", "w2w.payfast.co.za"];
    private static readonly (IPAddress Network, int Prefix)[] PayFastRanges =
    [
        (IPAddress.Parse("197.97.145.144"), 28),
        (IPAddress.Parse("41.74.179.192"), 27),
        (IPAddress.Parse("102.216.36.0"), 28),
        (IPAddress.Parse("102.216.36.128"), 28),
        (IPAddress.Parse("144.126.193.139"), 32),
    ];

    public string Name => "payfast";

    public PaymentRedirect CreateCheckout(PaymentCheckout c)
    {
        var (first, last) = SplitName(c.CustomerName);
        // Order matters for the signature: this is PayFast's documented field order.
        var fields = new List<KeyValuePair<string, string?>>
        {
            new("merchant_id", _o.MerchantId),
            new("merchant_key", _o.MerchantKey),
            new("return_url", _o.ReturnUrl),
            new("cancel_url", _o.CancelUrl),
            new("notify_url", _o.NotifyUrl),
            new("name_first", first),
            new("name_last", last),
            new("email_address", c.CustomerEmail),
            new("m_payment_id", c.PaymentId.ToString()),
            new("amount", (c.AmountCents / 100m).ToString("0.00", CultureInfo.InvariantCulture)),
            new("item_name", Truncate(c.ItemName, 100)),
            new("custom_str1", c.BookingReference),
        };

        var signature = PayFastSignature.ForRequest(fields, _o.Passphrase);
        var form = fields.Where(f => !string.IsNullOrEmpty(f.Value)).ToDictionary(f => f.Key, f => f.Value!.Trim());
        form["signature"] = signature;
        return new PaymentRedirect($"https://{_o.Host}/eng/process", form);
    }

    public async Task<PaymentNotification> VerifyNotificationAsync(
        IReadOnlyList<KeyValuePair<string, string>> fields, string? remoteIp, CancellationToken ct)
    {
        string Get(string key) => fields.FirstOrDefault(f => f.Key == key).Value ?? "";
        var raw = JsonSerializer.Serialize(fields.ToDictionary(f => f.Key, f => f.Value));
        Guid.TryParse(Get("m_payment_id"), out var paymentId);
        var amountCents = decimal.TryParse(Get("amount_gross"), NumberStyles.Number, CultureInfo.InvariantCulture, out var amount)
            ? (int)Math.Round(amount * 100m, MidpointRounding.AwayFromZero)
            : -1;

        PaymentNotification Invalid(string reason) => new(false, reason, paymentId, Get("pf_payment_id"), amountCents, Get("payment_status"), raw);

        // 1. Signature
        if (!PayFastSignature.VerifyNotification(fields, _o.Passphrase))
            return Invalid("Signature mismatch");

        // 2. Source IP
        if (_o.ValidateSourceIp && !await IsPayFastIpAsync(remoteIp))
            return Invalid($"Notification did not come from PayFast ({remoteIp})");

        // 3. Merchant
        if (!string.Equals(Get("merchant_id"), _o.MerchantId, StringComparison.Ordinal))
            return Invalid("Merchant id mismatch");

        if (paymentId == Guid.Empty) return Invalid("Missing m_payment_id");
        if (amountCents < 0) return Invalid("Missing or invalid amount_gross");

        // 4. Server confirmation
        if (_o.ValidateWithServer)
        {
            var body = string.Join("&", fields.Where(f => f.Key != "signature").Select(f => $"{f.Key}={PayFastSignature.Encode(f.Value)}"));
            try
            {
                using var res = await http.PostAsync($"https://{_o.Host}/eng/query/validate",
                    new StringContent(body, Encoding.UTF8, "application/x-www-form-urlencoded"), ct);
                var text = (await res.Content.ReadAsStringAsync(ct)).Trim();
                if (!text.Equals("VALID", StringComparison.OrdinalIgnoreCase))
                    return Invalid($"PayFast server validation returned '{text}'");
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Could not reach PayFast to validate a notification");
                return Invalid("Could not validate with PayFast");
            }
        }

        return new PaymentNotification(true, null, paymentId, Get("pf_payment_id"), amountCents, Get("payment_status"), raw);
    }

    private async Task<bool> IsPayFastIpAsync(string? remoteIp)
    {
        if (remoteIp is null || !IPAddress.TryParse(remoteIp, out var ip)) return false;
        if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
        if (PayFastRanges.Any(r => InRange(ip, r.Network, r.Prefix))) return true;

        foreach (var host in PayFastHosts)
        {
            try
            {
                var addresses = await Dns.GetHostAddressesAsync(host);
                if (addresses.Any(a => a.Equals(ip))) return true;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "DNS lookup failed for {Host}", host);
            }
        }
        return false;
    }

    private static bool InRange(IPAddress ip, IPAddress network, int prefix)
    {
        if (ip.AddressFamily != network.AddressFamily) return false;
        var a = ip.GetAddressBytes();
        var b = network.GetAddressBytes();
        var bits = prefix;
        for (var i = 0; i < a.Length && bits > 0; i++, bits -= 8)
        {
            var mask = bits >= 8 ? 0xFF : (byte)(0xFF << (8 - bits));
            if ((a[i] & mask) != (b[i] & mask)) return false;
        }
        return true;
    }

    private static (string? First, string? Last) SplitName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return (null, null);
        var parts = name.Trim().Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
        return (Truncate(parts[0], 100), parts.Length > 1 ? Truncate(parts[1], 100) : null);
    }

    private static string Truncate(string value, int max) => value.Length <= max ? value : value[..max];
}
