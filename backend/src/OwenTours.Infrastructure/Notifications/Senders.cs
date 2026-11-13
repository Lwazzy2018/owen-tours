using System.Net;
using System.Net.Mail;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using OwenTours.Application.Abstractions;

namespace OwenTours.Infrastructure.Notifications;

/// <summary>Always available: writes the message to the log. Used when no email is configured.</summary>
public sealed class LogNotificationSender(ILogger<LogNotificationSender> logger) : INotificationSender
{
    public string Channel => "log";

    public Task SendAsync(OutgoingMessage m, CancellationToken ct)
    {
        logger.LogInformation("[notification:{Template}] to {Email}/{Phone}: {Subject} – {Body}", m.Template, m.ToEmail, m.ToPhone, m.Subject, m.Body);
        return Task.CompletedTask;
    }
}

public sealed class SmtpOptions
{
    public const string Section = "Smtp";
    public string? Host { get; set; }
    public int Port { get; set; } = 587;
    public bool EnableSsl { get; set; } = true;
    public string? Username { get; set; }
    public string? Password { get; set; }
    public string FromEmail { get; set; } = "owentours@outlook.com";
    public string FromName { get; set; } = "Owen Tours and Travel";
    public bool IsConfigured => !string.IsNullOrWhiteSpace(Host);
}

/// <summary>
/// Email over SMTP (e.g. Outlook/Office 365, Brevo, Mailgun). Registered only when Smtp:Host is set.
/// Add WhatsApp/SMS later by implementing INotificationSender (Channel "whatsapp" or "sms").
/// </summary>
public sealed class SmtpNotificationSender(IOptions<SmtpOptions> options) : INotificationSender
{
    private readonly SmtpOptions _o = options.Value;
    public string Channel => "email";

    public async Task SendAsync(OutgoingMessage m, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(m.ToEmail)) return;
        using var client = new SmtpClient(_o.Host, _o.Port)
        {
            EnableSsl = _o.EnableSsl,
            Credentials = string.IsNullOrEmpty(_o.Username) ? null : new NetworkCredential(_o.Username, _o.Password),
        };
        using var mail = new MailMessage(new MailAddress(_o.FromEmail, _o.FromName), new MailAddress(m.ToEmail))
        {
            Subject = m.Subject,
            Body = $"{m.Body}\n\n– {_o.FromName}\nExplore the World",
            IsBodyHtml = false,
        };
        await client.SendMailAsync(mail, ct);
    }
}
