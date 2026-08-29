# Handoff: running the test suites in parallel

Branch `feat/parallel-unit-tests`, off `master` (`b7d602779`).

**Status: works, but not finished.** BooCompiler.Tests runs its fixtures
concurrently and usually passes. It still fails 0-3 tests out of 1938 on a bad
run. Do not treat this as ready to merge; it needs the last races found before
it can be trusted in CI.

## Why

Running the suites serially costs about 15s for BooCompiler.Tests alone. The
compiler was never written to be used from more than one thread, so enabling
NUnit's fixture level parallelism surfaced a pile of shared mutable state. The
goal here was never "make the compiler thread safe" in general, only "safe
enough that two compilations can run side by side in one process".

## Result

| | before | after |
|---|---|---|
| BooCompiler.Tests, serial | 15s | 15s |
| BooCompiler.Tests, parallel | ~1300 failures, then hung | 1921 passed, ~1s |
| failures per run, 10 runs (Debug) | n/a | 0 0 0 1 0 0 0 0 1 3 |

Serial runs are clean: verified 3 consecutive runs with parallelism disabled,
1921 passed.

## What is in this branch

**Test-side**

- `tests/TestParallelism.cs` — `[assembly: Parallelizable(ParallelScope.Fixtures)]`,
  linked into every C# test project by `tests/Directory.Build.props`. Fixture
  level, not `ParallelScope.All`: fixtures keep state between `SetUp` and the
  test, so only whole fixtures can be separated. `ParallelScope.All` fails
  almost every test.
- `tests/Directory.Build.props` — links the above, with a `DisableTestParallelism`
  property so a project can opt out.
- `tests/BooCompiler.Tests/ConsoleFanOut.cs` — `Console.Out` and `Console.In`
  are one slot for the whole process, and each fixture used to call
  `Console.SetOut`, taking the slot from every other fixture. This installs one
  writer that dispatches to an `AsyncLocal` target, so fixtures capture their own
  output concurrently. `AsyncLocal` and not `[ThreadStatic]`, because an async
  testcase can continue on another thread.
  This was the single biggest cause. It also explains the hang: `Console.SetIn`
  was clobbered the same way, so a test doing `RunString(code, stdin)` blocked
  forever on a reader another fixture had replaced.
- `tests/BooCompiler.Tests/AbstractCompilerTestCase.cs` — uses the fan-out, and
  names the output assembly `testcase_<FixtureName>.exe`. Every fixture used to
  emit an assembly called `testcase`, so concurrent fixtures resolved types
  against each other's.
- `tests/testcases/integration/extensions/extensions-5.boo` — this testcase
  builds its own `BooCompiler` and named its input `code`; so does
  `modules-5.boo`. Two assemblies called `code` in one process collide. Renamed
  the input here to `extensions5`. The name is arbitrary and nothing asserts on
  it.

**Compiler-side**

- `Util/MemoizedFunction.cs` — locked. Its dictionary is reached through
  `CompilerParameters.SharedTypeSystemProvider`, a static shared by every
  `CompilerParameters`. The memoized call runs outside the lock, because it
  re-enters the type system and holding the lock risks deadlock; the first
  writer wins so result identity stays stable. Uses `System.Threading.Lock`.
- `TypeSystem/Core/Namespaces.cs` — the two pooling stacks are now
  `[ThreadStatic]`. Locking them would have stopped the corruption but still
  handed one scratch collection to two threads. The file already carried a note
  predicting this would be needed; that note is still there and still true for
  the rest of the compiler.
- `TypeSystem/Reflection/ReflectionNamespace.cs` — `_cache` guarded. It did an
  unsynchronized `TryGetValue` and an `Add` from a `finally`.
- `TypeSystem/Reflection/ExternalType.cs` — `_cache` guarded. Its
  `ContainsKey` / `LoadCache` / `_cache[name]` sequence was not atomic, so two
  threads could both miss and both add.

## What is still wrong

Between 0 and 3 tests fail on a parallel run. Observed failures were
`extension_properties_1`, `reification_1`, `duck_1`, `byref_1` and
`generator_calling_external_super_with_arguments`, with an internal compiler
error of `Object reference not set to an instance of an object`. These move
around between runs, so they are more shared state rather than a specific test
being broken.

The root cause is structural and is not fixed: `CompilerParameters` has

```csharp
public static IReflectionTypeSystemProvider SharedTypeSystemProvider = new ReflectionTypeSystemProvider();
```

One process-wide provider owning a graph of lazily built, unsynchronized caches,
used by every `new CompilerParameters()`. Guarding caches one at a time is
whack-a-mole: four are guarded here and the failures merely got rarer. A survey
found 376 candidate static mutable fields across `Boo.Lang.Compiler`,
`Boo.Lang` and `Boo.Lang.Parser`; most are harmless, none were audited.

## Things that were tried and did not work

Do not repeat these.

- **Giving each `CompilerParameters` its own provider** (rather than the static).
  This is the obviously right fix and it does reduce races. It also breaks the
  bootstrap build: `BCE0039: Internal macro 'Boo.Lang.Extensions.MacroMacro'
  could not be loaded`, because macro identity depends on the macro assembly
  being mapped by the same provider. Any future attempt has to solve that first.
- **Uniquifying the assembly name in `MetaProgramming.Compilation.NewCompiler`.**
  Some testcases depend on the generated assembly keeping the module's name, for
  example `InternalMacroBootstrapping` loads one called `Test`. Broke that test.
- **Uniquifying the fallback assembly name in `EmitAssembly.UncollidedAssemblyName`**
  against a process-wide set of already emitted names. Generated code refers to
  its assembly by name, so recompiling the same module under a new name breaks
  it. Took failures from about 2 to 507.
- **`ParallelScope.All`.** Fixtures hold state across `SetUp`; only whole
  fixtures can run in parallel.

## Notes for whoever picks this up

- Measure repeatedly, in both configurations. Single runs prove nothing about a
  concurrency bug, and Debug fails more readily than Release.
- `dotnet test` prints test failures as `Build failed with N error(s)`. That
  wording means failing tests, not a compile error, unless the count is small
  and the test total collapses.
- The parallel run has hung before. Put a timeout on it.
- `tests/parser-snapshots/` is untracked here and is only gitignored on the
  ANTLR 4 branch. Do not commit it; it is about 51MB.
- There is a `.FINDINGS.md` in the working tree from a review of the ANTLR 4
  branch. It is unrelated to this work and is ignored by a global gitignore rule.
