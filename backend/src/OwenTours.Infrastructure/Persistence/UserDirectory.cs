using Microsoft.EntityFrameworkCore;
using OwenTours.Application.Services;
using OwenTours.Domain.Common;

namespace OwenTours.Infrastructure.Persistence;

/// <summary>Combines public.profiles (name, phone) with auth.users (email).</summary>
public sealed class UserDirectory(AppDbContext db) : IUserDirectory
{
    public async Task<UserContact?> GetAsync(Guid userId, CancellationToken ct)
    {
        var row = await (from p in db.Profiles.AsNoTracking()
                         join u in db.AuthUsers.AsNoTracking() on p.Id equals u.Id into users
                         from u in users.DefaultIfEmpty()
                         where p.Id == userId
                         select new { p.Id, p.FullName, p.Phone, Email = u == null ? null : u.Email })
            .FirstOrDefaultAsync(ct);
        return row is null ? null : new UserContact(row.Id, row.FullName, row.Email, row.Phone);
    }

    public async Task<IReadOnlyList<UserContact>> AdminsAsync(CancellationToken ct)
    {
        var rows = await (from p in db.Profiles.AsNoTracking()
                          join u in db.AuthUsers.AsNoTracking() on p.Id equals u.Id into users
                          from u in users.DefaultIfEmpty()
                          where p.Role == Roles.Admin
                          select new { p.Id, p.FullName, p.Phone, Email = u == null ? null : u.Email })
            .ToListAsync(ct);
        return rows.Select(r => new UserContact(r.Id, r.FullName, r.Email, r.Phone)).ToList();
    }

    public Task<Guid?> FindIdByEmailAsync(string email, CancellationToken ct) =>
        db.AuthUsers.AsNoTracking()
            .Where(u => u.Email != null && u.Email.ToLower() == email.ToLower())
            .Select(u => (Guid?)u.Id)
            .FirstOrDefaultAsync(ct);
}
