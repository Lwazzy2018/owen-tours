// Signature-only stand-ins for the EF Core / Npgsql APIs the code uses, so it can be type-checked
// without NuGet. Bodies throw: this assembly is never run.
#pragma warning disable CS8618, CS1998
using System.Collections;
using System.Linq.Expressions;

namespace Microsoft.EntityFrameworkCore
{
    using Microsoft.EntityFrameworkCore.ChangeTracking;
    using Microsoft.EntityFrameworkCore.Infrastructure;
    using Microsoft.EntityFrameworkCore.Query;

    public enum EntityState { Detached, Unchanged, Deleted, Modified, Added }

    public abstract class DbSet<TEntity> : IQueryable<TEntity> where TEntity : class
    {
        public abstract Type ElementType { get; }
        public abstract Expression Expression { get; }
        public abstract IQueryProvider Provider { get; }
        public abstract IEnumerator<TEntity> GetEnumerator();
        IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
        public abstract EntityEntry<TEntity> Add(TEntity entity);
        public abstract void AddRange(IEnumerable<TEntity> entities);
        public abstract EntityEntry<TEntity> Remove(TEntity entity);
        public abstract void RemoveRange(IEnumerable<TEntity> entities);
        public abstract EntityEntry<TEntity> Update(TEntity entity);
        public abstract ValueTask<TEntity?> FindAsync(params object?[]? keyValues);
    }

    public class DbContext : IDisposable
    {
        public virtual DatabaseFacade Database => throw new NotImplementedException();
        public virtual Task<int> SaveChangesAsync(CancellationToken cancellationToken = default) => throw new NotImplementedException();
        public virtual EntityEntry<TEntity> Entry<TEntity>(TEntity entity) where TEntity : class => throw new NotImplementedException();
        public virtual DbSet<TEntity> Set<TEntity>() where TEntity : class => throw new NotImplementedException();
        public void Dispose() { }
    }

    public class DbUpdateException : Exception { }
    public class DbFunctions { }

    public static class EF
    {
        public static DbFunctions Functions => throw new NotImplementedException();
    }

    public static class NpgsqlDbFunctionsExtensions
    {
        public static bool ILike(this DbFunctions _, string matchExpression, string pattern) => throw new NotImplementedException();
    }

    public static class EntityFrameworkQueryableExtensions
    {
        public static IQueryable<T> AsNoTracking<T>(this IQueryable<T> source) where T : class => source;
        public static IQueryable<T> AsSplitQuery<T>(this IQueryable<T> source) where T : class => source;

        public static IIncludableQueryable<TEntity, TProperty> Include<TEntity, TProperty>(
            this IQueryable<TEntity> source, Expression<Func<TEntity, TProperty>> navigationPropertyPath) where TEntity : class
            => throw new NotImplementedException();

        public static IIncludableQueryable<TEntity, TProperty> ThenInclude<TEntity, TPreviousProperty, TProperty>(
            this IIncludableQueryable<TEntity, IEnumerable<TPreviousProperty>> source,
            Expression<Func<TPreviousProperty, TProperty>> navigationPropertyPath) where TEntity : class
            => throw new NotImplementedException();

        public static IIncludableQueryable<TEntity, TProperty> ThenInclude<TEntity, TPreviousProperty, TProperty>(
            this IIncludableQueryable<TEntity, TPreviousProperty> source,
            Expression<Func<TPreviousProperty, TProperty>> navigationPropertyPath) where TEntity : class
            => throw new NotImplementedException();

        public static Task<List<T>> ToListAsync<T>(this IQueryable<T> source, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<T[]> ToArrayAsync<T>(this IQueryable<T> source, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<T?> FirstOrDefaultAsync<T>(this IQueryable<T> source, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<T?> FirstOrDefaultAsync<T>(this IQueryable<T> source, Expression<Func<T, bool>> predicate, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<T> FirstAsync<T>(this IQueryable<T> source, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<T> FirstAsync<T>(this IQueryable<T> source, Expression<Func<T, bool>> predicate, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<T?> SingleOrDefaultAsync<T>(this IQueryable<T> source, Expression<Func<T, bool>> predicate, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<bool> AnyAsync<T>(this IQueryable<T> source, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<bool> AnyAsync<T>(this IQueryable<T> source, Expression<Func<T, bool>> predicate, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<int> CountAsync<T>(this IQueryable<T> source, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<int> CountAsync<T>(this IQueryable<T> source, Expression<Func<T, bool>> predicate, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<int?> SumAsync<T>(this IQueryable<T> source, Expression<Func<T, int?>> selector, CancellationToken ct = default) => throw new NotImplementedException();
        public static Task<int> SumAsync<T>(this IQueryable<T> source, Expression<Func<T, int>> selector, CancellationToken ct = default) => throw new NotImplementedException();
    }

    public static class RelationalQueryableExtensions
    {
        public static Task<int> ExecuteUpdateAsync<TSource>(this IQueryable<TSource> source,
            Expression<Func<SetPropertyCalls<TSource>, SetPropertyCalls<TSource>>> setPropertyCalls, CancellationToken ct = default)
            => throw new NotImplementedException();

        public static Task<int> ExecuteDeleteAsync<TSource>(this IQueryable<TSource> source, CancellationToken ct = default)
            => throw new NotImplementedException();
    }

    public static class RelationalDatabaseFacadeExtensions
    {
        public static Task<Microsoft.EntityFrameworkCore.Storage.IDbContextTransaction> BeginTransactionAsync(this DatabaseFacade db, CancellationToken ct = default)
            => throw new NotImplementedException();
    }
}

namespace Microsoft.EntityFrameworkCore.Query
{
    public interface IIncludableQueryable<out TEntity, out TProperty> : IQueryable<TEntity> { }

    public sealed class SetPropertyCalls<TSource>
    {
        public SetPropertyCalls<TSource> SetProperty<TProperty>(Func<TSource, TProperty> propertyExpression, Func<TSource, TProperty> valueExpression) => this;
        public SetPropertyCalls<TSource> SetProperty<TProperty>(Func<TSource, TProperty> propertyExpression, TProperty valueExpression) => this;
    }
}

namespace Microsoft.EntityFrameworkCore.Infrastructure
{
    public class DatabaseFacade { }
}

namespace Microsoft.EntityFrameworkCore.Storage
{
    public interface IDbContextTransaction : IDisposable, IAsyncDisposable
    {
        Task CommitAsync(CancellationToken ct = default);
        Task RollbackAsync(CancellationToken ct = default);
    }
}

namespace Microsoft.EntityFrameworkCore.ChangeTracking
{
    public class EntityEntry<TEntity> where TEntity : class
    {
        public Microsoft.EntityFrameworkCore.EntityState State { get; set; }
        public TEntity Entity => throw new NotImplementedException();
    }
}
