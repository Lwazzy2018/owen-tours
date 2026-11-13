// Stand-in for the real AppDbContext (whose model configuration needs the Npgsql/EF packages).
#pragma warning disable CS8618
using Microsoft.EntityFrameworkCore;
using OwenTours.Domain.Entities;

namespace OwenTours.Infrastructure.Persistence
{
    public sealed class AuthUser
    {
        public Guid Id { get; set; }
        public string? Email { get; set; }
        public string? Phone { get; set; }
    }

    public sealed class AppDbContext : DbContext
    {
        public DbSet<Profile> Profiles { get; }
        public DbSet<AuthUser> AuthUsers { get; }
    }
}
