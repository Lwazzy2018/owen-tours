using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Common;
using OwenTours.Domain.Rules;

namespace OwenTours.Api.Infrastructure;

/// <summary>Turns exceptions into consistent ProblemDetails responses the app can show to users.</summary>
public sealed class ProblemExceptionHandler(IProblemDetailsService problems, ILogger<ProblemExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext context, Exception exception, CancellationToken ct)
    {
        var (status, title, detail, errors) = exception switch
        {
            BusinessRuleException e => (e.StatusCode, Title(e.StatusCode), e.Message,
                e.Errors.GroupBy(x => x.Field).ToDictionary(g => g.Key, g => g.Select(x => x.Message).ToArray())),
            NotFoundException e => (404, "Not found", e.Message, null),
            ForbiddenException e => (403, "Forbidden", e.Message, null),
            UnauthorizedAccessException e => (401, "Sign in required", e.Message, null),
            DbUpdateException => (409, "Conflict", "Something changed while you were saving. Please refresh and try again.", null),
            BadHttpRequestException e => (e.StatusCode, "Bad request", e.Message, null),
            OperationCanceledException => (499, "Cancelled", "The request was cancelled.", null),
            _ => (500, "Something went wrong", "An unexpected error occurred. Please try again, or contact us if it keeps happening.", null),
        };

        if (status >= 500) logger.LogError(exception, "Unhandled error on {Path}", context.Request.Path);
        else if (exception is DbUpdateException) logger.LogWarning(exception, "Database conflict on {Path}", context.Request.Path);

        context.Response.StatusCode = status;
        var problem = new ProblemDetails { Status = status, Title = title, Detail = detail, Instance = context.Request.Path };
        if (errors is not null && errors.Count > 0) problem.Extensions["errors"] = errors;
        problem.Extensions["traceId"] = context.TraceIdentifier;

        return await problems.TryWriteAsync(new ProblemDetailsContext { HttpContext = context, ProblemDetails = problem, Exception = exception });
    }

    private static string Title(int status) => status switch
    {
        400 => "Bad request",
        403 => "Not allowed",
        409 => "Conflict",
        413 => "File too large",
        415 => "Unsupported file",
        _ => "Please check your details",
    };
}
