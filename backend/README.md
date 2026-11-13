# Owen Tours and Travel – API

ASP.NET Core 8, clean architecture:

| Project | What it holds | Packages |
|---|---|---|
| `OwenTours.Domain` | Entities and **all business rules**: pricing, discounts, instalments, cancellation and refunds, traveller rules, payment states | none |
| `OwenTours.Application` | Use cases (BookingService, PaymentService, …), DTOs, interfaces | EF Core |
| `OwenTours.Infrastructure` | EF Core mapping to the Supabase schema, Supabase Storage/Auth, PayFast, PDFs, images, email, Hangfire jobs | Npgsql, Hangfire, QuestPDF, ImageSharp |
| `OwenTours.Api` | Controllers, Supabase JWT auth, error handling, Swagger | JwtBearer, Swashbuckle, Serilog |

```bash
dotnet build OwenTours.sln
dotnet test tests/OwenTours.Domain.Tests
dotnet run --project src/OwenTours.Api      # http://localhost:5080/swagger
```

The database schema is owned by `/supabase/migrations` (SQL), not EF migrations.

Validation: request DTOs use DataAnnotations (automatic 400s), and business rules return
`ProblemDetails` with an `errors` map per field (e.g. `travellers[0].passportNumber`), which the app shows next to each field.

`tests/OfflineTestRunner` and `tests/CompileCheck*` are only for environments without NuGet access
(they run the same test files with a tiny xUnit stand-in and type-check against API stubs). With normal NuGet access, ignore them and use `dotnet test`.
