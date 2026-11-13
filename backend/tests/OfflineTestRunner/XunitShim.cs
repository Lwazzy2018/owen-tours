// A tiny stand-in for the parts of xUnit the domain tests use, plus a runner.
// Lets the real test files run where NuGet isn't available. Use `dotnet test` normally.
using System.Collections;
using System.Reflection;

namespace Xunit
{
    [AttributeUsage(AttributeTargets.Method)]
    public class FactAttribute : Attribute { }

    [AttributeUsage(AttributeTargets.Method)]
    public class TheoryAttribute : FactAttribute { }

    [AttributeUsage(AttributeTargets.Method, AllowMultiple = true)]
    public class InlineDataAttribute(params object?[] data) : Attribute
    {
        public object?[] Data { get; } = data;
    }

    public class AssertFailedException(string message) : Exception(message);

    public static class Assert
    {
        public static void True(bool condition, string? message = null) { if (!condition) throw new AssertFailedException(message ?? "Expected true"); }
        public static void False(bool condition, string? message = null) { if (condition) throw new AssertFailedException(message ?? "Expected false"); }
        public static void Null(object? value) { if (value is not null) throw new AssertFailedException($"Expected null but was {value}"); }
        public static void NotNull(object? value) { if (value is null) throw new AssertFailedException("Expected not null"); }

        public static void Equal<T>(T expected, T actual)
        {
            if (expected is IEnumerable e && actual is IEnumerable a && expected is not string)
            {
                var ex = e.Cast<object?>().ToList();
                var ac = a.Cast<object?>().ToList();
                if (!ex.SequenceEqual(ac)) throw new AssertFailedException($"Expected [{string.Join(",", ex)}] but was [{string.Join(",", ac)}]");
                return;
            }
            if (!EqualityComparer<T>.Default.Equals(expected, actual))
                throw new AssertFailedException($"Expected <{expected}> but was <{actual}>");
        }

        public static T Throws<T>(Action action) where T : Exception
        {
            try { action(); }
            catch (T ex) { return ex; }
            catch (Exception ex) { throw new AssertFailedException($"Expected {typeof(T).Name} but got {ex.GetType().Name}: {ex.Message}"); }
            throw new AssertFailedException($"Expected {typeof(T).Name} but nothing was thrown");
        }

        public static void Contains(string expectedSubstring, string? actual)
        {
            if (actual is null || !actual.Contains(expectedSubstring))
                throw new AssertFailedException($"Expected \"{actual}\" to contain \"{expectedSubstring}\"");
        }

        public static void Contains<T>(IEnumerable<T> collection, Predicate<T> filter)
        {
            if (!collection.Any(x => filter(x)))
                throw new AssertFailedException($"No item matched. Items: {string.Join(" | ", collection)}");
        }

        public static void Empty(IEnumerable collection)
        {
            if (collection.Cast<object>().Any()) throw new AssertFailedException("Expected empty collection");
        }

        public static T Single<T>(IEnumerable<T> collection)
        {
            var list = collection.ToList();
            if (list.Count != 1) throw new AssertFailedException($"Expected 1 item but found {list.Count}");
            return list[0];
        }

        public static void Single(IEnumerable collection)
        {
            var count = collection.Cast<object>().Count();
            if (count != 1) throw new AssertFailedException($"Expected 1 item but found {count}");
        }
    }
}

namespace OfflineTestRunner
{
    public static class Program
    {
        public static int Main()
        {
            var passed = 0;
            var failed = new List<string>();
            var testTypes = typeof(Program).Assembly.GetTypes()
                .Where(t => t.Namespace == "OwenTours.Domain.Tests" && t.IsClass && t.IsPublic)
                .OrderBy(t => t.Name);

            foreach (var type in testTypes)
            {
                foreach (var method in type.GetMethods().Where(m => m.GetCustomAttribute<Xunit.FactAttribute>() is not null))
                {
                    var cases = method.GetCustomAttributes<Xunit.InlineDataAttribute>().Select(d => d.Data).ToList();
                    if (cases.Count == 0) cases.Add([]);
                    foreach (var args in cases)
                    {
                        var name = $"{type.Name}.{method.Name}({string.Join(", ", args.Select(a => a ?? "null"))})";
                        try
                        {
                            var instance = Activator.CreateInstance(type);
                            var parameters = method.GetParameters();
                            var converted = args.Select((a, i) => a is null ? null : Convert.ChangeType(a,
                                Nullable.GetUnderlyingType(parameters[i].ParameterType) ?? parameters[i].ParameterType)).ToArray();
                            method.Invoke(instance, converted);
                            passed++;
                        }
                        catch (TargetInvocationException ex)
                        {
                            failed.Add($"FAIL {name}\n     {ex.InnerException?.GetType().Name}: {ex.InnerException?.Message}");
                        }
                    }
                }
            }

            foreach (var f in failed) Console.WriteLine(f);
            Console.WriteLine($"\n{passed} passed, {failed.Count} failed");
            return failed.Count == 0 ? 0 : 1;
        }
    }
}
