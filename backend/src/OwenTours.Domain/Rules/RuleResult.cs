namespace OwenTours.Domain.Rules;

/// <summary>Errors block the action; warnings are shown to the user but allowed.</summary>
public sealed class RuleResult
{
    private readonly List<RuleMessage> _errors = [];
    private readonly List<RuleMessage> _warnings = [];

    public IReadOnlyList<RuleMessage> Errors => _errors;
    public IReadOnlyList<RuleMessage> Warnings => _warnings;
    public bool IsValid => _errors.Count == 0;

    public RuleResult Error(string field, string message)
    {
        _errors.Add(new RuleMessage(field, message));
        return this;
    }

    public RuleResult Warning(string field, string message)
    {
        _warnings.Add(new RuleMessage(field, message));
        return this;
    }

    public RuleResult Merge(RuleResult other)
    {
        _errors.AddRange(other._errors);
        _warnings.AddRange(other._warnings);
        return this;
    }
}

public sealed record RuleMessage(string Field, string Message);

/// <summary>Thrown when a business rule is broken. The API turns it into a 400/409/422 ProblemDetails response.</summary>
public class BusinessRuleException : Exception
{
    public BusinessRuleException(string message, int statusCode = 422, IReadOnlyList<RuleMessage>? errors = null)
        : base(message)
    {
        StatusCode = statusCode;
        Errors = errors ?? [];
    }

    public int StatusCode { get; }
    public IReadOnlyList<RuleMessage> Errors { get; }

    public static BusinessRuleException From(RuleResult result, string message = "Please fix the highlighted fields.") =>
        new(message, 422, result.Errors);
}
