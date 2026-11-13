using System.Security.Cryptography;
using System.Text;

namespace OwenTours.Infrastructure.Payments;

/// <summary>
/// PayFast signature: MD5 of the "key=value&amp;..." string (values URL-encoded the way PHP's urlencode does,
/// spaces as '+', uppercase hex), with "&amp;passphrase=..." appended when a passphrase is set.
/// No package dependencies, so it is unit-tested with the domain tests.
/// </summary>
public static class PayFastSignature
{
    /// <summary>Signature for a payment request. Fields must be in PayFast's documented order; empty values are skipped.</summary>
    public static string ForRequest(IEnumerable<KeyValuePair<string, string?>> orderedFields, string? passphrase)
    {
        var parts = orderedFields
            .Where(kv => !string.IsNullOrEmpty(kv.Value))
            .Select(kv => $"{kv.Key}={Encode(kv.Value!.Trim())}")
            .ToList();
        return Md5(Append(string.Join("&", parts), passphrase));
    }

    /// <summary>
    /// Signature check for an ITN (payment notification): all posted fields in the order received,
    /// except "signature" itself.
    /// </summary>
    public static bool VerifyNotification(IEnumerable<KeyValuePair<string, string>> postedFieldsInOrder, string? passphrase)
    {
        var fields = postedFieldsInOrder.ToList();
        var given = fields.FirstOrDefault(kv => kv.Key == "signature").Value;
        if (string.IsNullOrEmpty(given)) return false;

        var parts = fields
            .Where(kv => kv.Key != "signature")
            .Select(kv => $"{kv.Key}={Encode(kv.Value)}");
        var expected = Md5(Append(string.Join("&", parts), passphrase));
        return CryptographicOperations.FixedTimeEquals(
            Encoding.ASCII.GetBytes(expected), Encoding.ASCII.GetBytes(given.ToLowerInvariant()));
    }

    /// <summary>Same as PHP urlencode(): letters, digits, '-', '_', '.' unchanged; space → '+'; the rest %XX uppercase.</summary>
    public static string Encode(string value)
    {
        var sb = new StringBuilder();
        foreach (var b in Encoding.UTF8.GetBytes(value))
        {
            var c = (char)b;
            if (char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.') sb.Append(c);
            else if (c == ' ') sb.Append('+');
            else sb.Append('%').Append(b.ToString("X2"));
        }
        return sb.ToString();
    }

    private static string Append(string data, string? passphrase) =>
        string.IsNullOrEmpty(passphrase) ? data : $"{data}&passphrase={Encode(passphrase.Trim())}";

    private static string Md5(string input) =>
        Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(input))).ToLowerInvariant();
}
