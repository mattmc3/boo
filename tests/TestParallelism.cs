using NUnit.Framework;

// Fixtures run concurrently; the cases inside one do not. A fixture keeps state
// between SetUp and the test that uses it, so only whole fixtures are safe to
// separate. Linked into every C# test project by tests/Directory.Build.props.
[assembly: Parallelizable(ParallelScope.Fixtures)]
