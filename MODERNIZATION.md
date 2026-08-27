# Boo Modernization Assessment

Assessed 2026-08-27 against `main` @ `bc0aa515`. Last upstream commit 2022-07-06.
Verified locally with .NET SDK 10.0.400, Mono 6.14.1, OpenJDK 26.0.2.

## Verdict

The port is viable and the hard blocker is now solved upstream. Every API the
compiler backend needs has a .NET 10 equivalent, verified by test program
(see [Appendix A](#appendix-a-verified-net-10-api-surface)).

A build spike then confirmed it empirically: the 148,918-line C# core produces
**21 compile errors in 4 files** on `net10.0`, and stubbing those 4 files yields a
working `booc` that parses and type-checks Boo source. The work is large in
breadth (build system, deletions, tests) but the genuinely hard part is one file.

Rough shape:

| Area | Size | Risk |
|---|---|---|
| Emit backend rewrite (`EmitAssembly`/`SaveAssembly`) | ~200 lines changed, 1 new file | High |
| Build system replacement (NAnt/Gradle/autotools to MSBuild) | Full rewrite of build | Medium |
| Bootstrap chain (C#-first, two-stage) | New mechanism, no Mono | Low |
| Test runner (NUnit 2.6.3 to NUnit 3.14) | 4 attribute renames | None |
| Removed-API cleanup (CAS, GAC, CodeDom, remoting) | ~15 files | Low |
| Deleting dead weight | ~2500 files | None |

## Spike results (measured, not estimated)

Built the four C# core projects as SDK-style `net10.0` projects against the real
sources. **21 unique compile errors in 4 files, out of 148,918 lines.**

| File | Errors | What |
|---|---|---|
| `Steps/EmitAssembly.cs` | 12 | `AssemblyBuilderAccess.Save`/`RunAndSave`, `AppDomain.DefineDynamicAssembly`, 3-arg `DefineDynamicModule`, `DefineManifestResource`, `DefineResource`, `DefineUnmanagedResource`, `SetEntryPoint`, `PEFileKinds` |
| `Steps/SaveAssembly.cs` | 4 | `AssemblyBuilder.Save` x4 |
| `Util/Permissions.cs` | 3 | `EnvironmentPermission`, `FileIOPermission`, `SecurityPermission` (CS1069) |
| `Steps/InjectCallableConversions.cs` | 2 | `System.Runtime.Remoting.Messaging.AsyncResult` |
| `CompilerOutputType.cs` | (3, same as above) | `PEFileKinds` in enum initializers |

Every one was already identified in the blockers below. Nothing new appeared.

**After stubbing those 4 files crudely, all four projects build with zero errors
and `booc` runs on .NET 10:**

```
$ dotnet booc.dll -p:boo hw.boo
Boo Compiler version 0.9.7.0 (CLR 10.0.11)
[System.Runtime.CompilerServices.CompilerGlobalScopeAttribute]
public final transient class HwModule(object):

	private static def Main(argv as (string)) as void:
		Boo.Lang.Builtins.print('hello from net10 boo')
```

Three things that changes:

1. **Strong-name signing is the first thing to trip emit**, before any
   `Reflection.Emit` gap: `BCE0011: ... 'Strong-name signing is not supported on
   this platform.'` Already decided to drop signing, so this is a config change.
2. **Blocker 2 has a specific, findable cause.** See
   [blocker 2](#2-assembly-loading-and-the-reference-type-system) for the real
   mechanism, found while running step 1's compiler over the test corpus. An
   earlier draft of this section claimed the blocker had mostly evaporated, based
   on a single hello-world compile. That was wrong.
3. **IL generation itself works.** `EmitAssembly` is 5,803 lines of
   `Reflection.Emit` and it runs to completion on .NET 10, stopping only at the
   deliberate `SaveAssembly` stub.

### Methodology note

A naive `dotnet build` reports only **4** errors, not 21. Roslyn short-circuits:
the `using System.Runtime.Remoting.Messaging` failure and the `PEFileKinds` enum
initializers are declaration-phase errors, and method bodies are never bound while
those stand. Fix those 4 and the other 17 appear. Anyone re-running this should fix
declaration errors first before trusting a count.

Also observed: 322 `CA2200` warnings (rethrow losing stack trace), plus
`SYSLIB0050`/`SYSLIB0051` (serialization obsoletions) and `SYSLIB0017`
(strong naming). All pre-existing, none blocking.

## Governing principle: incremental, always green

Every step lands something that builds and runs, and leads into the next step.
No big-bang rewrite, no long-lived broken branch. Where a legacy dependency still
works on .NET 10, it stays until it actually blocks progress rather than being
replaced on principle.

That has already changed one plan: NUnit stays. NUnit 3.14 runs Boo's existing
NUnit 2 test idiom unchanged on .NET 10, at a cost of 4 attribute renames
(see [blocker 5](#5-test-stack)). xUnit becomes an optional later step instead of
a step 3 prerequisite.

## Decisions taken

- **No Mono.** Not needed at any stage. See [Bootstrap](#the-bootstrap-problem-solved).
- **C# is the bootstrap language.** Invest in the C# core, and port the Boo
  codegen scripts to C# where they block the build.
- **`net10.0` only.** Single TFM everywhere. No `netstandard`, no .NET Framework,
  no multi-targeting. .NET 10 is LTS and that is the floor.
- **NUnit 3.14 now, xUnit v3 later or never.** Incremental beats correct-on-paper.
- **Drop `itanium`.** Target x86, x64, arm64, AnyCPU.
- **1.0.0.** Major bump from 0.9.7, and unfreeze `AssemblyVersion` from `2.0.9.5`.
- **Independent fork.** No binary-compatibility obligation to `boo-lang/boo` or to
  Unity. Breaking changes to assembly identity are fine, so strong naming can go.
- **Source compatibility for existing `.boo` files where possible.** Legacy Boo
  source should keep compiling. That is a language constraint, not a binary one.
- **Language work is in scope, but sequenced after the port.**
  See [Language roadmap](#language-roadmap).
- **`booish` is in scope, late.** See [After 1.0](#booish).
- **Stay compatible with upstream `boo-lang/boo`.** Namespaces stay `Boo.Lang.*`,
  public API stays put, `booc` keeps its CLI. No gratuitous divergence. See
  [Upstream compatibility](#upstream-compatibility).
- **No packaging or distribution work.** No NuGet, no `.deb`, no installer. Build
  from source. The `install` / `distro` / `makedeb` / `boo-pkgconfig` NAnt targets
  get deleted with no replacement.
- **`.booproj` keeps its extension, gets SDK-style contents.** Free to rewrite the
  file format; the MSBuild SDK teaches `dotnet build` to recognize it.
- **`Boo.Lang.CodeDom`:** keep `BooCodeGenerator`, delete `BooCodeCompiler`.
- **`unsafe` / pointers:** keep by default, but punting to 1.1 is acceptable if
  pointer emission blocks step 2. Mark the 10 tests skipped and move on.
- **`Boo.Microsoft.Build.Tasks`:** rewrite as a real MSBuild SDK and ship it.
- **`bin/` deletion is not urgent.** Delete when the two-stage build actually
  works, not before. Leave it in git history when it goes.
- **Delete `extras/` entirely.** Tag first so it stays reachable. Modern editor
  support (Zed, VS Code, Neovim) gets written fresh, and not before 1.0.
- **Line endings are LF, enforced by `.gitattributes`.** The tree was mixed: 2,070
  tracked text files carried CRLF and 376 of those mixed CRLF and LF within a
  single file, which made content diffs unreadable. `.bat` and `.cmd` keep CRLF.

## Inventory

### What is actually here

160,343 lines of source in `src/`, 63,707 in `tests/`, plus 2,229 `.boo`
integration test cases under `tests/testcases/`.

The compiler is partly self-hosted. Bootstrapping is the central constraint on
any plan:

| Project | Language | LOC | Notes |
|---|---|---|---|
| `Boo.Lang` | C# (59 files) | 7,949 | Runtime, duck typing dispatch, `Reflection.Emit` dispatchers |
| `Boo.Lang.Compiler` | C# (592 files) | 103,354 | Pipeline, type system, emit |
| `Boo.Lang.Parser` | C# (125 files) | 36,570 | ANTLR 2.7.5 generated + vendored ANTLR C# runtime |
| `booc` | C# (3 files) | 1,045 | CLI compiler |
| `Boo.Lang.Extensions` | **Boo** (30) | 2,304 | Macros. Needs a working `booc` |
| `Boo.Lang.Useful` | **Boo** (27) | 3,249 | |
| `Boo.Lang.Interpreter` | **Boo** (9) | 1,840 | |
| `Boo.Lang.PatternMatching` | **Boo** (6) | 621 | |
| `Boo.Lang.CodeDom` | **Boo** (5) | 1,182 | |
| `booi` | **Boo** (6) | 1,046 | Script runner |
| `booish` | **Boo** (1) | 57 | REPL |
| `Boo.NAnt.Tasks` | **Boo** (5) | 801 | Delete |
| `Boo.Microsoft.Build.Tasks` | **Boo** (2) | 325 | Keep, rewrite |

The C# core (`Boo.Lang` + `Boo.Lang.Compiler` + `Boo.Lang.Parser` + `booc`) has
no Boo dependency. That is the seam the whole plan hangs on: it can be built with
plain `dotnet build` and used to compile everything else.

### Build systems currently in the repo

Four, three of them dead:

1. **NAnt** (`default.build`, 40,576 bytes, ~60 targets). The authoritative
   build. Requires NAnt built from source at pinned commit
   `e3644541bf083d8e33f450bfbd1a4147e494769c`.
2. **Gradle + kaizen** ([build.gradle](build.gradle), [settings.gradle](settings.gradle)).
   Unity's abandoned `kaizen` plugin, Gradle 1.2 wrapper (2012), resolved over
   plaintext `http://unity-technologies.github.com`. Dead.
3. **MSBuild** (9 `.sln`, 14 `.csproj`, 12 `.booproj`). Legacy non-SDK format,
   `ToolsVersion="4.0"`, TFMs spread across v2.0/v3.5/v4.0/v4.5/v4.5.1.
4. **autotools** ([configure.in.in](configure.in.in), [Makefile.am](Makefile.am),
   `extras/Makefile.am`). Dead.

Plus an abandoned .NET Core attempt: [src/Boo.Core.sln](src/Boo.Core.sln) points
at `Boo.Lang.xproj` (file does not exist), [src/global.json](src/global.json)
pins SDK `1.0.0-preview2-003131`, and `src/Boo.Lang/project.json` +
`project.lock.json` target `netstandard1.6`. That work left behind useful
artifacts: the `DNXCORE50`, `NO_SERIALIZATION_INFO`, `NO_SYSTEM_PROCESS`, and
`NO_SYSTEM_REFLECTION_EMIT` conditionals already mark most of the portability
seams in `Boo.Lang`.

### CI

- [.travis.yml](.travis.yml) targets travis-ci.org, which no longer exists.
  Pins Mono 4.2.1. Contains an encrypted `GITHUB_TOKEN`.
- [appveyor.yml](appveyor.yml) shells into Visual Studio 14.0 (VS2015) vcvarsall.
- Tests run through `nunit-console.exe` from NUnit 2.6.3, downloaded from
  Launchpad by [build-tools/bootstrap](build-tools/bootstrap).

---

## The bootstrap problem, solved

**Mono is not required at any stage.** Three independent reasons, all verified.

**1. All generated code is checked in.** Nothing has to be regenerated to build:

```
src/Boo.Lang.Compiler/Ast/Impl/        118 files, all tracked
src/Boo.Lang.Parser/BooParserBase.cs   tracked (16,673 lines)
src/Boo.Lang.Parser/BooLexer.cs        tracked
src/Boo.Lang.Parser/BooExpressionLexer.cs  tracked
src/Boo.Lang.Parser/GeneratedErrorPatterns.cs  tracked
```

**2. The C# core has zero Boo dependency.** `Boo.Lang` + `Boo.Lang.Compiler` +
`Boo.Lang.Parser` + `booc` is 148,918 of the 160,343 lines in `src/` and builds
with `dotnet build` alone. That compiler then compiles the Boo half.

**3. Bonus: the old compiler runs on .NET 10, giving a free oracle.** The
2011-era Mono-built `bin/booc.exe` executes on the .NET 10 runtime. It needs a
`runtimeconfig.json` and a ~10-line stub assembly named
`System.Security.Permissions` (the four CAS types
[Permissions.cs](src/Boo.Lang.Compiler/Util/Permissions.cs) touches). With those:

| Old `booc` on .NET 10 | Result |
|---|---|
| `booc --help` | works |
| `booc -p:parse` | works. Full parser pipeline |
| `booc -p:boo` | works. Correct transformed AST printed |
| `booc -o:x.dll` | fails at reference resolution, then would fail at `AssemblyBuilder.Save` |

Both failures are exactly blockers [1](#1-emit-backend-assemblybuildersave-does-not-exist-on-net-core)
and [2](#2-assembly-loading-and-the-reference-type-system). So without touching
Mono we get a reference implementation covering the parser, the AST, and the
semantic pipeline, which is what the emit rewrite most needs to diff against.
Worth 30 minutes to set up as a test fixture.

### What `bin/` was for

`bin/` holds 13 checked-in prebuilt Mono assemblies (1.8 MB). They were required
to build the Boo-language half of the repo and to run two code generators:

- `bin/booi.exe scripts/astgen.boo` regenerates ~90 AST classes from
  [ast.model.boo](ast.model.boo) into `src/Boo.Lang.Compiler/Ast/Impl/`
  ([default.build:1043-1063](default.build#L1043-L1063)). The `nant rebuild`
  target deletes that directory first.
- `java -cp lib/antlr-2.7.5/antlr-2.7.5.jar antlr.Tool` regenerates
  `BooParserBase.cs` (16,673 lines) and the lexers from `boo.g`/`booel.g`
  ([default.build:991-1030](default.build#L991-L1030)).

Confirmed the ANTLR 2.7.5 jar still runs on OpenJDK 26, so grammar regeneration
is not urgent either.

### Bootstrap strategy: two-stage, C#-first

1. Build the C# core (`Boo.Lang`, `Boo.Lang.Compiler`, `Boo.Lang.Parser`, `booc`)
   on `net10.0` with `dotnet build`. Zero Boo dependency, zero Mono dependency.
2. Use that fresh `booc` to compile the Boo-language projects, via an MSBuild
   targets file invoking stage-1 `booc`.

This retires `bin/` entirely, and it is the same shape the existing Gradle file
was reaching for ([build.gradle:19-22](build.gradle#L19-L22) sets
`booc.executable` to the freshly built one).

### Boo-language build scripts to port to C#

Three code generators are written in Boo and run on `booi`, which puts them
downstream of a working compiler. Two are only needed when their input changes;
one is needed early. Porting them to C# removes `booi` from the build graph:

| Script | LOC | Port priority |
|---|---|---|
| `tests/generate_regression.boo` | ~250 | **High.** Generates 2,117 of 2,590 tests. Needed for the xUnit migration |
| `scripts/astgen.boo` | - | Low. Output checked in; only runs if `ast.model.boo` changes |
| `scripts/error-patterns.boo` | - | Low. Output checked in |

`generate_regression.boo` is the one worth doing now. It uses
`Boo.Lang.PatternMatching` macros and `BooPrinterVisitor`, so a C# port needs a
regex `match` rewrite and a call into `Boo.Lang.Compiler` (which is C#, so that
part is free).

---

## Blockers, ranked

### 1. Emit backend: `AssemblyBuilder.Save` does not exist on .NET Core

This is the whole port in one file.

`.NET Core` through `.NET 8` had no way to write a `Reflection.Emit` assembly to
disk. `.NET 9` added `System.Reflection.Emit.PersistedAssemblyBuilder`.
Verified working on .NET 10.

Sites to change:

| Location | Current | Replacement |
|---|---|---|
| [SaveAssembly.cs:58-67](src/Boo.Lang.Compiler/Steps/SaveAssembly.cs#L58-L67) | `builder.Save(filename, PortableExecutableKinds, ImageFileMachine)` | `PersistedAssemblyBuilder.GenerateMetadata` + `ManagedPEBuilder` |
| [EmitAssembly.cs:5607-5608](src/Boo.Lang.Compiler/Steps/EmitAssembly.cs#L5607-L5608) | `AppDomain.CurrentDomain.DefineDynamicAssembly(...)`, 2- and 3-arg | `new PersistedAssemblyBuilder(name, coreAssembly)` for save, `AssemblyBuilder.DefineDynamicAssembly(name, access)` for in-memory |
| [EmitAssembly.cs:5630-5647](src/Boo.Lang.Compiler/Steps/EmitAssembly.cs#L5630-L5647) | `AssemblyBuilderAccess.Save` / `.RunAndSave` | Both gone. Enum is now `Run, RunAndCollect` only. Becomes a branch on persisted-vs-runtime builder |
| [EmitAssembly.cs:5623](src/Boo.Lang.Compiler/Steps/EmitAssembly.cs#L5623) | `DefineDynamicModule(name, filename, emitSymbolInfo)` | Only `DefineDynamicModule(string)` survives |
| [EmitAssembly.cs:5589-5597](src/Boo.Lang.Compiler/Steps/EmitAssembly.cs#L5589-L5597) | `ModuleBuilder.DefineManifestResource` / `.DefineResource` | Neither exists on any .NET Core version. Pass a `BlobBuilder` as `ManagedPEBuilder`'s `managedResources` |
| [EmitAssembly.cs:248](src/Boo.Lang.Compiler/Steps/EmitAssembly.cs#L248) | `UnamangedResourceHelper.CreateDefaultWin32Resources` | Feed through `ManagedPEBuilder`'s `nativeResources` (`ResourceSectionBuilder`) |

The `Platform` switch maps onto `PEHeaderBuilder(machine:, imageBase:, ...)` plus
`CorFlags`. `itanium` goes; `arm64` arrives. Verified the `Machine` enum on
.NET 10 carries `I386`, `Amd64`, `Arm`, `Arm64` (and `RiscV64`, `LoongArch64` if
anyone ever asks):

| `-platform:` | `Machine` | `CorFlags` |
|---|---|---|
| `anycpu` (default) | `Unknown` | `ILOnly` |
| `anycpu32bitpreferred` | `I386` | `ILOnly \| Requires32Bit \| Prefers32Bit` |
| `x86` | `I386` | `ILOnly \| Requires32Bit` |
| `x64` | `Amd64` | `ILOnly` |
| `arm64` | `Arm64` | `ILOnly` |
| `itanium` | removed | - |

`anycpu32bitpreferred` does not exist in Boo today. Worth adding while the switch
is open, since it is the modern default for executables.

Consequence worth naming up front: `PersistedAssemblyBuilder` cannot execute what
it emits. Today `GenerateInMemory` uses `RunAndSave` to get both. On .NET 10 the
two modes are genuinely separate objects, so the run-and-save path
([RunAssembly.cs](src/Boo.Lang.Compiler/Steps/RunAssembly.cs), `booi`, the
interpreter) has to either emit twice or save then load. Save-then-load into an
`AssemblyLoadContext` is the cleaner answer and also fixes `booi`'s inability to
unload.

Alternatives considered: `Lokad.ILPack` (serializes a runtime `AssemblyBuilder`
to disk, unmaintained, patchy generics support) and `Mono.Cecil` (full backend
rewrite, much larger change). `PersistedAssemblyBuilder` is the right call.

### 2. Assembly loading and the reference type system

**Root cause identified in step 1.** On .NET, `mscorlib.dll`, `System.dll` and
`System.Runtime.dll` are empty type-forwarding facades:

```
Assembly.Load("System").GetExportedTypes().Length          => 0
Assembly.Load("mscorlib").GetExportedTypes().Length        => 0
Assembly.Load("System.Runtime").GetExportedTypes().Length  => 0
Assembly.Load("System.Private.CoreLib").GetExportedTypes() => 1378
```

`CompilerParameters.LoadDefaultReferences` asks for exactly those three facade
names, and `ReflectionNamespaceBuilder` populates namespaces by enumerating an
assembly's exported types. Facades yield nothing, so the `System` namespace comes
back empty. Measured effect: running step 1's `booc` over
`tests/testcases/integration` with `-p:boo`, 308 of 856 files get through
semantics; of the failures, `Unknown identifier: 'System'` accounts for 366
occurrences (and `assert` for 920, which is the unbuilt `Boo.Lang.Extensions`
rather than a defect).

**Fix:** enumerate the runtime's actual assembly closure instead of legacy facade
names. `AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")` returns 174
path entries on this machine, `System.Private.CoreLib` and `System.Console`
included. `Assembly.GetForwardedTypes()` was the other candidate and is worse: it
throws `ReflectionTypeLoadException` on both `System` and `mscorlib`.

The type system wraps live `System.Type` objects
(`src/Boo.Lang.Compiler/TypeSystem/Reflection/External*.cs`, 24 files), which
means resolving a reference *loads it into the compiler process*. On .NET that
prevents cross-targeting: you cannot load reference assemblies, and you cannot
compile against a framework version other than the one `booc` is running on.
That part is a 1.1 concern, not a port blocker.

- [CompilerParameters.cs:299](src/Boo.Lang.Compiler/CompilerParameters.cs#L299)
  `Assembly.LoadWithPartialName`. Obsolete and non-functional on .NET.
- [CompilerParameters.cs:292](src/Boo.Lang.Compiler/CompilerParameters.cs#L292)
  `LoadAssemblyFromGac`. There is no GAC.
- [CompilerParameters.cs:331-348](src/Boo.Lang.Compiler/CompilerParameters.cs#L331-L348)
  `pkgconfig()` shells out to `pkg-config` for Mono package references.
- `Assembly.LoadFrom` / `LoadFile` in 8 places, including
  [booc/App.cs:155](src/booc/App.cs#L155) and
  [Steps/Parsing.cs:95](src/Boo.Lang.Compiler/Steps/Parsing.cs#L95).

Two-step fix:

- **Step 1 (required):** replace GAC/pkg-config/partial-name resolution with
  explicit `-r:` paths, and route all loads through a single
  `AssemblyLoadContext`. This is enough to get self-hosting working. The compiler
  then only targets the runtime it runs on, same as today.
- **Step 2 (do later, separately):** swap `ReflectionTypeSystemProvider` onto
  `System.Reflection.MetadataLoadContext`. It hands back `Type` subclasses, so
  the 24 `External*` wrappers mostly survive, but every `typeof(...)` comparison
  in `TypeSystem/Types.cs` and friends has to become a name-based lookup against
  the load context's core assembly. Real work, and it unlocks proper
  cross-targeting and reference-assembly support. Not on the critical path.

### 3. Code Access Security

[Util/Permissions.cs](src/Boo.Lang.Compiler/Util/Permissions.cs) wraps calls in
`EnvironmentPermission`, `FileIOPermission`, and
`SecurityPermission(ControlAppDomain)`. CAS was removed from .NET; the
`System.Security.Permissions` shims throw `PlatformNotSupportedException`.

The file already swallows all exceptions and returns `default(T)` on failure, so
on .NET it would silently disable every guarded operation. Delete the class and
inline the calls. Callers: `WithDiscoveryPermission` at
[CompilerParameters.cs:299](src/Boo.Lang.Compiler/CompilerParameters.cs#L299),
plus `WithEnvironmentPermission` / `WithAppDomainPermission`.

### 4. `System.CodeDom` provider

`src/Boo.Lang.CodeDom/` (5 Boo files, 1,182 lines) implements
`CodeDomProvider`/`ICodeCompiler`. The `System.CodeDom` package exists for .NET,
but `CompileAssemblyFromSource` and friends throw `PlatformNotSupportedException`
there by design. `BooCodeCompiler.boo` cannot work.

**Decided: keep `BooCodeGenerator`, delete `BooCodeCompiler`.** Generating Boo
source from a CodeDOM tree still works and is the half anyone used. The project
drops from 5 files to roughly 3.

### 5. Test stack

**NUnit stays, at version 3.14.** Verified: Boo's existing NUnit 2 idiom compiles
and runs unchanged against NUnit 3.14 under `dotnet test` on .NET 10. A fixture
using `[TestFixture]`, `[SetUp]`, `[TearDown]`, `[Category]`, `[Ignore]`,
`Assert.AreEqual(exp, act, message)`, `AreSame`, `IsTrue`, `IsFalse`, `IsNotNull`,
`Assert.Fail`, and `Assert.Ignore` passed 5, skipped 2, failed 0.

**Total source change to move the whole 2,590-test suite: 4 attribute renames.**
`[TestFixtureSetUp]` is the only thing NUnit 3 dropped that Boo uses; it becomes
`[OneTimeSetUp]`. Everything else is untouched.

What actually has to change:

- `NUnit` 3.14 + `NUnit3TestAdapter` + `Microsoft.NET.Test.Sdk` via PackageReference.
- Delete [nunit](nunit), [nunit.ps1](nunit.ps1), [ci](ci), [ci.ps1](ci.ps1),
  `tests/nunit.inc`, `tests/build.cmd`. `dotnet test` replaces all of it.
- `lib/moq-3.1.416.3/Moq.dll` (2009) is used by 6 test files. Replace with
  hand-written fakes: `CompilerErrorFactoryTest.cs`,
  `Steps/MacroProcessing/MacroExpanderTest.cs`,
  `TypeSystem/EntityFormatterTestBase.cs`,
  `Environments/CachingEnvironmentTest.cs`,
  `Environments/EnvironmentProvisionTest.cs`.
- The runner currently excludes categories `FailsOnMono` and `FailsOnMono4`
  ([nunit:12](nunit#L12)). Those exclusions are now meaningless. Every test in
  them needs triage: fixed, or re-tagged against the real reason.
- `tests/testcases/net2/generics/mixedbase.dll` is a checked-in binary test
  fixture. Needs source + a build step, or drop the test.

**Do not go to NUnit 4.** It removed the entire classic assert model that this
suite is built on: `AreEqual`, `AreSame`, `IsTrue`, `IsNull` are all gone in
4.6.0, leaving only `Assert.That`. That is a 600+ call-site rewrite for no gain.
NUnit 3.14 is the terminus unless and until xUnit is worth it.

#### If xUnit v3 later becomes worth it

Recorded because the analysis is done, not because it is scheduled.

**82% of the suite is machine-generated.**
[tests/generate_regression.boo](tests/generate_regression.boo) scans
`tests/testcases/` and writes ~31 fixture files from inline C# templates:

| Generated fixture group | Tests |
|---|---|
| `RegressionTestFixture` | 240 |
| `CompilerErrorsTestFixture` | 232 |
| `TypesIntegrationTestFixture` | 218 |
| `WSAParserRoundtripTestFixture` | 176 |
| `ParserRoundtripTestFixture` | 174 |
| `GenericsTestFixture` | 107 |
| `CallablesIntegrationTestFixture`, `StatementsIntegrationTestFixture` | 102, 100 |
| 23 more generated fixtures | 768 |
| **Generated total** | **2,117** |
| **Hand-written** | **473** |
| **Total `[Test]` methods** | **2,590** |

So a bulk migration means editing ~20 template strings in one script, and only
473 tests get touched by hand. Mapping for those:

| NUnit | xUnit v3 | Count |
|---|---|---|
| `[TestFixture]` | delete | 134 |
| `[Test]` | `[Fact]` | 2,590 |
| `[SetUp]` | constructor | 15 |
| `[TestFixtureSetUp]` | `IClassFixture<T>` | 4 |
| `[TearDown]` | `IDisposable` | 0 (none used) |
| `[Category("x")]` | `[Trait("Category", "x")]` | 21 |
| `[Ignore("r")]` | `[Fact(Skip = "r")]` | 17 |
| `Assert.Ignore("r")` | `Assert.Skip("r")` | in 2 generated fixtures |
| `Assert.AreEqual` | `Assert.Equal` (same arg order) | 422 |
| `Assert.AreSame` | `Assert.Same` | 79 |
| `Assert.IsTrue` / `IsFalse` | `Assert.True` / `False` | 39 / 10 |
| `Assert.IsNull` / `IsNotNull` | `Assert.Null` / `NotNull` | 17 / 34 |
| `Assert.Fail` | `Assert.Fail` | 19 |

Zero uses of `[TestCase]`, `ExpectedException`, `Assert.That`, or `Assert.Throws`,
so no parameterized-test or exception-assert rewrite at all. The one real snag is
that `Assert.AreEqual(expected, actual, message)` has no xUnit equivalent, and the
message argument is load-bearing in the main assertion of the integration suite,
[AbstractCompilerTestCase.cs:201](tests/BooCompiler.Tests/AbstractCompilerTestCase.cs#L201),
which passes the test-case filename so failures are identifiable.

Note this migration would also need `generate_regression.boo` ported to C# or a
working `booi` to regenerate from, which is a second reason it is not first.

### The test oracle

Worth stating plainly, because it is what makes the emit rewrite verifiable: each
`.boo` file under `tests/testcases/` carries its own expected stdout as a leading
docstring, compared at
[AbstractCompilerTestCase.cs:200-201](tests/BooCompiler.Tests/AbstractCompilerTestCase.cs#L200-L201).

```boo
"""
5
10
"""
class Value(System.ValueType):
	public Value as int
	...
```

2,229 such files. They are runtime-behavior assertions, not IL assertions, so
they survive the emit backend being rewritten. Combined with the old compiler
running on .NET 10 for AST-level diffing, that is enough coverage to do the emit
rewrite with confidence.

### 6. Build system

Replace all four with SDK-style MSBuild. Target `net10.0` for the toolchain.

New layout:

```
Directory.Build.props        # shared TFM, LangVersion, signing, versioning
Boo.slnx                     # single solution
src/*/*.csproj               # SDK-style, one TFM
src/*/*.booproj              # SDK-style, built by stage-1 booc
Boo.Boo.targets              # booc invocation for .booproj
.github/workflows/ci.yml     # replaces travis + appveyor
```

Things `default.build` does that MSBuild must keep doing:

- `compile-grammar`: ANTLR invocation. Keep as an opt-in target, not part of
  default build, since output is checked in.
- `generate-ast`: `astgen.boo`. Same. Needs stage-1 `booc`, so it becomes a
  manually run tool, not a build step.
- `generate-errorpatterns`: `scripts/error-patterns.boo` to
  `GeneratedErrorPatterns.cs`. Same treatment.
- `sign` / `nosign`: strong naming with [src/boo.snk](src/boo.snk). Dropped:
  independent fork, no binary-compat obligation, and .NET does not verify strong
  names at runtime anyway. `AssemblyVersion` is frozen at `2.0.9.5`
  ([default.build:8](default.build#L8)) while `version.txt` says `0.9.7`. Both
  become `1.0.0` and the freeze comment goes.
- `install` / `distro` / `makedeb` / `boo-pkgconfig`: delete outright, no
  replacement. Build from source. Packaging is a separate problem for a later day
  and none of it is load-bearing for the port.

Also delete: `il`, `il.bat`, `nant`, `nant.ps1`, `booc`, `booi` shell wrappers,
`micro-profile.build`, `build-tools/`, `configure.in.in`, `Makefile.am`,
`bin/Makefile.am`, `extras/common-properties.build`, `extras/makedeb.build`, all
per-project `default.build` files.

### 7. Source-level cleanup

- 33 legacy `TargetFrameworkVersion` declarations across `.csproj`/`.booproj`.
  Collapse to one TFM in `Directory.Build.props`.
- Conditional-compilation debt to resolve now that there is exactly one target:
  `DNXCORE50` (40 sites), `NO_SERIALIZATION_INFO` (18),
  `NO_SYSTEM_REFLECTION_EMIT` (13), `NET_2_0`, `NET_40_OR_GREATER`,
  `NO_SYSTEM_PROCESS`, `NO_REGEX`, `MONOTOUCH`. The `!DNXCORE50` branches are
  usually the .NET Framework path and the `DNXCORE50` branches the portable one,
  so most resolve by keeping the latter and deleting the `#if`.
- 63 `[Serializable]` attributes plus 3 `ISerializable` implementations.
  Harmless to keep, but they exist for `BinaryFormatter`, which is gone. Audit
  whether any codepath depended on it.
- 2 `System.Runtime.Remoting` references.
- `src/booc/booc.rsp` and `bin/booc.rsp` reference `System.Drawing`,
  `System.Security`, `System.Xml` as GAC names. Meaningless now; rewrite or drop
  the default response file.
- `LangVersion` can go to current: the C# in here is C# 3-era. Not required, but
  `var`, pattern matching, and nullable reference types would cut real volume
  from the 103k-line compiler over time.

### 8. Dead weight to delete

~2,500 files, no functional cost:

| Path | Files | Reason |
|---|---|---|
| `lib/antlr-2.7.5/` (minus the jar) | ~1,900 | Full ANTLR distro: Java, C++, Python, C# runtimes and examples. Only `antlr-2.7.5.jar` and the already-vendored C# runtime in `src/Boo.Lang.Parser/antlr/` are used |
| `lib/moq-3.1.416.3/` | 3 | Replaced by hand-written fakes |
| `bin/` | 18 | Replaced by two-stage bootstrap. **Deleted last**, once step 4 proves self-hosting |
| `extras/SharpDevelop/` | 44 | SharpDevelop 1.x addin, `.cmbx`/`.prjx`/`.xpt`/`.xft` |
| `extras/boox/`, `extras/booish.gui/` | 67 | Gtk# and WinForms GUI tools, MonoDevelop 1.x project files |
| `extras/Gendarme.Rules.*` | 3 | Gendarme is dead |
| `extras/DEBIAN/`, `extras/makedeb.build` | 4 | Mono-specific: `control` depends on five libmono packages, `postinst`/`prerm` register assemblies in the GAC, and `makedeb.build` was a NAnt target |
| `*.monolipse` (10) | 10 | Monolipse (Eclipse plugin) is dead |
| `*.prjx`, `*.cmbx` (11) | 11 | MonoDevelop 1.x / SharpDevelop 1.x |
| `.project`, `.settings/` | 2 | Eclipse |
| `src/Boo-VS2010.sln`, `src/Boo-VS2010.sln.DotSettings`, `src/Boo.Core.sln` | 3 | VS2010 and the stillborn xproj attempt |
| `src/Boo.Lang/project.json`, `project.lock.json` | 2 | Abandoned DNX-era |
| `src/global.json` | 1 | Pins SDK 1.0.0-preview2 |
| `src/TestResults/` | 2 | **18 MB** of SQL Server database files (`.mdf` + `.ldf`) from a VS2010 test run. The single largest thing in the repo |
| `src/Boo.NAnt.Tasks/` | 5 | NAnt |
| `gradle/`, `gradlew`, `gradlew.bat`, `build.gradle`, `settings.gradle`, `tools/RetargetAssembly/` | 8 | Gradle + kaizen |
| `extras/` (everything else) | ~40 | jEdit 4.1/4.2, GtkSourceView, KDE syntax, nanorc, bash completion, man pages, Debian packaging, boox, booish.gui |

**All of `extras/` goes.** Every editor integration in it targets software that no
longer ships, `boo.vim` included (2005-era vimscript, not a Neovim or Tree-sitter
grammar). Replacement editor support gets written fresh after 1.0, per
[After 1.0](#toolchain-quality).

**Tag `legacy-0.9.7` at the current commit before the first deletion.** That is
what makes all of this recoverable without touching history.

`docs/` has 3 files, two of which are `BooManifesto.sxw` (OpenOffice 1.x) and
`BooManifesto.pdf`. Convert the manifesto to Markdown.

---

## Road to 1.0

Sequenced so every step ends with something that builds and runs. The rung you are
standing on is always green, and each one is what makes the next one possible.
Only step 2 carries real risk.

### Step 0: Oracle

No Mono. Stand up the old compiler on .NET 10 as a test fixture: `bin/*.dll` + a
fabricated `runtimeconfig.json` + the 10-line `System.Security.Permissions` stub.
Gives `-p:parse` and `-p:boo` output to diff against for the whole port. Half a
day, and it is the last time `bin/` is useful.

**Green when:** `dotnet booc.dll -p:boo <file>` reproduces known AST output.

### Step 1: C# core builds on net10.0

Compiles, does not yet work. Deliberately separate from step 2 so that "does it
build" and "does it emit" fail independently.

1. SDK-style `.csproj` for `Boo.Lang`, `Boo.Lang.Compiler`, `Boo.Lang.Parser`,
   `booc`. `Directory.Build.props` with the single `net10.0` TFM.
2. Resolve the `#if` debt in those four projects. One target means most of the
   `DNXCORE50` / `NO_*` / `NET_2_0` branches collapse.
3. Delete `Util/Permissions.cs`, inline the call sites.
4. Stub `SaveAssembly` to throw. Not the point of this step.

**Green when:** `dotnet build` succeeds with zero errors on all four projects.

### Step 2: booc emits a working assembly

The critical path and the only high-risk step.

1. Replace the three facade names in `LoadDefaultReferences` with the runtime's
   real assembly closure from `TRUSTED_PLATFORM_ASSEMBLIES`. This is what fixes
   `Unknown identifier: 'System'`, and it should move the 308/856 semantics pass
   rate sharply. Do it first: it is independent of the emit work and unblocks
   measuring everything else.
2. Rewrite the emit backend against `PersistedAssemblyBuilder` +
   `ManagedPEBuilder`. Split the in-memory and persisted paths, since they are
   now different objects.
3. Wire embedded resources through `managedResources`, win32 resources through
   `nativeResources`, and the platform switch through `PEHeaderBuilder`.

**Green when:** `booc -o:hw.dll examples/hw.boo` produces an assembly that runs
under `dotnet hw.dll`.

### Step 3: Tests run

1. Bump to NUnit 3.14 + `NUnit3TestAdapter` + `Microsoft.NET.Test.Sdk`. Rename
   the 4 `[TestFixtureSetUp]` uses to `[OneTimeSetUp]`.
2. Remove Moq from the 6 files that use it.
3. Only the C#-authored test projects at first: `Boo.Lang.Tests`,
   `Boo.Lang.Runtime.Tests`, `Boo.Lang.Parser.Tests`, `booc.Tests`,
   `BooCompiler.Tests`. The Boo-authored test projects wait for step 4.
4. `BooCompiler.Tests` is the prize: 113 files driving 2,229 `.boo` testcases,
   each carrying its own expected stdout. This is the real proof step 2 is correct.
5. Triage the `FailsOnMono` / `FailsOnMono4` exclusions.

**Green when:** `dotnet test` runs and the failure list is understood, not
necessarily empty.

### Step 4: Boo-language projects build

1. Two-stage build: stage-1 `booc` compiles the `.booproj` set via an MSBuild
   targets file.
2. Order is already worked out in [build.gradle:47-138](build.gradle#L47-L138):
   `Boo.Lang.Extensions` first (it provides the macros everything else needs),
   then `Boo.Lang.Useful`, `Boo.Lang.PatternMatching`, `Boo.Lang.CodeDom`, then
   `booi`.
3. Rewrite `Boo.Microsoft.Build.Tasks` as a real MSBuild SDK, since the
   two-stage build needs the plumbing anyway. Ship it so third parties can
   `dotnet build` a `.booproj`.
4. Bring up the Boo-authored test projects.
5. Delete `bin/` last, once a clean clone has built the whole tree without it.
   No rush: it costs nothing to keep until then.

**Green when:** a clean clone builds everything with `dotnet build` and no
prebuilt compiler.

### Step 5: Clean up, CI, document

1. Tag `legacy-0.9.7`, then execute the deletion table, `extras/` included.
2. GitHub Actions replacing Travis and AppVeyor. Matrix on linux/macos/windows
   and arm64, which Mono never really delivered.
3. Rewrite README against the new build. Prerequisites section becomes one line:
   the .NET 10 SDK.

**Green when:** a stranger can clone, run `dotnet build`, and compile a `.boo`
file, on linux, macos, or windows, without reading anything but the README.

That is 1.0.0.

## After 1.0

### booish

In scope, deliberately last. `Boo.Lang.Interpreter` is the fiddliest surviving
piece: in-memory emit plus `AppDomain` plus incremental compilation state. The
`AppDomain` usage in `AbstractInterpreter.boo` and `Namespace.boo` needs an
`AssemblyLoadContext` rewrite, and with `PersistedAssemblyBuilder` unable to
execute what it emits, each REPL line has to either emit twice or save-then-load.

Nothing else depends on it, which is exactly why it goes after 1.0 ships rather
than blocking it.

### Toolchain quality

Unordered:

- Portable PDB via `GenerateMetadata`'s 3-arg overload +
  `ModuleBuilder.DefineDocument` + `ILGenerator.MarkSequencePoint`. All verified
  present. `booc -debug` is on by default today and will be emitting nothing.
- `MetadataLoadContext` type system, for compiling against reference assemblies
  and target frameworks other than the one `booc` runs on.
- Editor support, written fresh. Everything in `extras/` targeted editors that no
  longer ship, so nothing there is worth porting. The modern shape is a
  Tree-sitter grammar (covers Zed, Neovim, and Helix from one artifact) plus an
  LSP server driven by the existing compiler pipeline (covers VS Code and the
  rest). The pipeline already exposes parse and semantic phases as steps, which is
  most of what an LSP needs.
- ANTLR 2.7.5 to ANTLR 4, or a hand-written recursive-descent parser. The 2.7.5
  jar still runs on JDK 26, so this buys maintainability and error messages, not
  survival.
- Raise `LangVersion` and modernize the 103k lines of compiler C# incrementally.
- Reconsider xUnit v3.

---

## Language roadmap

Language work is in scope but strictly after the port, and incremental for the
same reason everything else is: each feature should ship on a green tree.

Two hard constraints:

1. **Existing `.boo` source keeps compiling.** The 2,229 testcase files are both
   the regression suite and the compatibility contract. Any language change that
   breaks them is wrong unless deliberately chosen.
2. **Nothing here starts before 1.0 ships.** These are compiler features, weeks
   each, not port tasks.

What is already there and worth knowing before planning more:

- `async`/`await` exists to some degree. `tests/testcases/async/` has 43 tests.
  Establishing what actually works is the first task, not adding to it.
- Generics work. `testcases/net2/generics/` has 107 tests.
- `unsafe` / pointers exist, with 10 tests and assembly verification disabled.
- Macros, syntactic attributes, and the extensible compiler pipeline are Boo's
  actual differentiator and are fully intact.

Candidate additions, roughly in order of value-per-effort:

| Feature | Notes |
|---|---|
| Modern BCL surface usable from Boo | Mostly free once the type system loads .NET 10. Verify `Span<T>`, `ValueTask`, tuples, `IAsyncEnumerable` are reachable |
| `anycpu32bitpreferred` | Trivial, comes with the platform switch rewrite |
| Nullable reference type annotations | Emit and consume `[Nullable]` metadata. Large, high value for interop with modern C# |
| Default interface methods | Consume first (cheap), implement later |
| Records / positional construction | Boo already has terse class syntax; may be redundant |
| `ref struct` / `ref` locals / `Span<T>` authoring | Requires real work in the type system and verifier |
| Generic math / static abstract interface members | Depends on default interface methods |

Recommend picking the first row and stopping there for 1.1: "everything in the
.NET 10 BCL is usable from Boo" is a shippable, testable, valuable milestone that
requires no new syntax.

---

## Upstream compatibility

The constraint is "stay compatible with upstream `boo-lang/boo`." Worth being
precise about what that can and cannot mean, because the two readings differ a
lot in cost.

**What is achievable and cheap: consumer compatibility.** Hold these fixed and
existing Boo code and existing Boo consumers keep working:

- Namespaces stay `Boo.Lang`, `Boo.Lang.Compiler`, `Boo.Lang.Parser`,
  `Boo.Lang.Extensions`, `Boo.Lang.PatternMatching`, `Boo.Lang.Useful`.
- Public API of `Boo.Lang.Compiler` (the pipeline, `CompilerParameters`,
  `CompilerStep`, the AST) stays put. Third-party compiler steps and macros are
  Boo's whole point.
- `booc` keeps its command-line surface: `-p:`, `-r:`, `-o:`, `-ducky`,
  `-noconfig`, response files.
- `.boo` source stays source-compatible. The 2,229 testcases are the contract.
- Assembly names stay as upstream: `Boo.Lang.dll`, `Boo.Lang.Compiler.dll`, and
  the rest. Anything that resolves Boo by assembly name keeps working.

**What is not achievable: merge compatibility.** Upstream's last commit is
2022-07-06 and it was a Discord link fix. This work replaces the build system,
rewrites the emit backend, and deletes ~2,500 files. Nothing here lands upstream
as a reviewable PR series; if upstream ever revives, this is a wholesale
replacement, not a merge.

That is not a reason to diverge gratuitously. It is a reason to keep the goal
stated as the first list and not the second, so effort goes into API and source
stability rather than into keeping a rebase alive against a dead branch.

**Practical consequences:**

- Do not rename namespaces, assemblies, or CLI flags for taste.
- Do keep the BSD 3-clause license and `notice.txt` attribution intact.
- Deletions and build changes are fine and expected; API changes need a reason.
- Tag `legacy-0.9.7` at the current commit before the first deletion, so
  everything removed stays reachable by tag rather than by archaeology.

---

## Open questions

None. Everything above is decided.

Two questions closed themselves rather than being answered, which is worth
recording so they do not come back:

- **Repo naming / hosting.** Only ever a question because an earlier draft made
  NuGet publication part of step 5. With packaging out of scope, nothing in the
  plan depends on where this lives or what it is called.
- **`.booproj` vs `.csproj`.** Resolved by being free to rewrite `.booproj`
  contents. Keep the extension for upstream compatibility, make the contents
  SDK-style, and let the MSBuild SDK bridge the two. The apparent tension between
  upstream compatibility and modern tooling was only in the file format, not the
  file name.

## Appendix A: Verified .NET 10 API surface

Enumerated by test program against SDK 10.0.400, not from memory.

```
AssemblyBuilderAccess values:        Run, RunAndCollect
  (Save and RunAndSave no longer exist)

AssemblyBuilder public statics:
  DefineDynamicAssembly(AssemblyName, AssemblyBuilderAccess)
  DefineDynamicAssembly(AssemblyName, AssemblyBuilderAccess, IEnumerable<CustomAttributeBuilder>)
  (no AppDomain-based overloads, no directory parameter)

AssemblyBuilder.DefineDynamicModule overloads:
  DefineDynamicModule(String)
  (the 3-arg name/filename/emitSymbolInfo overload is gone)

PersistedAssemblyBuilder instance methods:
  Save(Stream)
  Save(String)
  GenerateMetadata(out BlobBuilder ilStream, out BlobBuilder mappedFieldData)
  GenerateMetadata(out BlobBuilder, out BlobBuilder, out MetadataBuilder pdbBuilder)

ModuleBuilder members matching "Resource":
  Boolean IsResource()
  (DefineManifestResource and DefineResource do not exist)

ModuleBuilder debug symbols:
  DefineDocument(String, Guid)
  DefineDocument(String, Guid, Guid, Guid)
ILGenerator:
  MarkSequencePoint(ISymbolDocumentWriter, Int32, Int32, Int32, Int32)

ManagedPEBuilder ctor:
  PEHeaderBuilder header
  MetadataRootBuilder metadataRootBuilder
  BlobBuilder ilStream
  BlobBuilder mappedFieldData = default
  BlobBuilder managedResources = default          <- embedded resources
  ResourceSectionBuilder nativeResources = default <- win32 resources
  DebugDirectoryBuilder debugDirectoryBuilder = default
  Int32 strongNameSignatureSize = default
  MethodDefinitionHandle entryPoint = default
  CorFlags flags = default
  Func<..> deterministicIdProvider = default

PEHeaderBuilder ctor takes: Machine machine, imageBase, subsystem,
  dllCharacteristics, imageCharacteristics, alignment and stack/heap sizes
  (covers the x86 / x64 / AnyCPU switch)
```

End-to-end check that passed: build a `PersistedAssemblyBuilder`, define a type
and a static method, emit IL, `CreateType()`, `Save("Hello.dll")`. Produced a
valid 2048-byte assembly.

```
Machine enum (System.Reflection.PortableExecutable):
  Unknown, I386, WceMipsV2, Alpha, SH3, SH3Dsp, SH3E, SH4, SH5, Arm, Thumb,
  ArmThumb2, AM33, PowerPC, PowerPCFP, IA64, MIPS16, Alpha64, MipsFpu,
  MipsFpu16, Tricore, Ebc, RiscV32, RiscV64, RiscV128, LoongArch32,
  LoongArch64, Amd64, M32R, Arm64

CorFlags enum:
  ILOnly, Requires32Bit, ILLibrary, StrongNameSigned, NativeEntryPoint,
  TrackDebugData, Prefers32Bit
```

## Appendix B: Test framework options, verified

Each measured by restoring the package and reflecting over `Xunit.Assert` /
`NUnit.Framework.Assert` on `net10.0`.

**NUnit 3.14.0 (chosen).** Everything Boo uses survives:

```
Assert.AreEqual     yes (6 overloads, incl. the (exp, act, message) form)
Assert.AreSame      yes (2)
Assert.AreNotEqual  yes (2)
Assert.IsTrue       yes (4)     Assert.IsFalse    yes (4)
Assert.IsNull       yes (2)     Assert.IsNotNull  yes (2)
Assert.Fail         yes (3)     Assert.Ignore     yes (3)
Assert.That         yes (15)    Assert.Throws     yes (6)

[TestFixture] [Test] [SetUp] [TearDown] [Category] [Ignore]  all present
[TestFixtureSetUp]  MISSING -> [OneTimeSetUp]   (4 uses in this repo)
```

End-to-end check that passed: a fixture written in Boo's exact NUnit 2 idiom,
compiled against NUnit 3.14 with `NUnit3TestAdapter`, run via `dotnet test` on
`net10.0`:

```
Skipped Ignored [< 1 ms]
Skipped RuntimeIgnore [6 ms]
Passed!  - Failed: 0, Passed: 5, Skipped: 2, Total: 7 - t.dll (net10.0)
```

Both `[Ignore("reason")]` and runtime `Assert.Ignore("reason")` were honoured.

**NUnit 4.6.0 (rejected).** The classic assert model is gone:

```
Assert.AreEqual   REMOVED
Assert.AreSame    REMOVED
Assert.IsTrue     REMOVED
Assert.IsNull     REMOVED
Assert.Fail       yes (2)
Assert.Ignore     yes (2)
Assert.That       yes (21)
```

That is a 600+ call-site rewrite to reach a framework no better than 3.14 for
this codebase.

**xUnit v3 4.0.0 (deferred).** Viable, and notably the only option with a
runtime-skip that matches NUnit's `Assert.Ignore`:

```
Skip       yes (1)   <- matches NUnit Assert.Ignore
SkipWhen   yes (1)
Fail       yes (1)
Equal      yes (51 overloads, 26 with 3+ params)
Same       yes (1)
True/False yes (4/4) Null/NotNull yes (3/3)
Throws     yes (15)
```

xUnit v3 projects build as self-hosting executables (the SDK generates
`XunitAutoGeneratedEntryPoint`), so no external console runner is needed.

## Appendix C: Old compiler on .NET 10

Reproduction, for setting up the step 0 oracle:

```sh
mkdir oldbooc && cd oldbooc
cp /path/to/boo/bin/*.dll .
cp /path/to/boo/bin/booc.exe booc.dll        # .NET needs the .dll extension
cat > booc.runtimeconfig.json <<'EOF'
{ "runtimeOptions": { "tfm": "net10.0",
  "framework": { "name": "Microsoft.NETCore.App", "version": "10.0.0" } } }
EOF
# then build a stub assembly named System.Security.Permissions (AssemblyVersion
# 0.0.0.0) exposing: System.Security.PermissionState,
# System.Security.Permissions.{EnvironmentPermission, FileIOPermission,
# SecurityPermission, SecurityPermissionFlag}
dotnet booc.dll -p:boo hello.boo
```

Confirmed output on this machine, an unmodified 2011 Mono-built compiler running
on the .NET 10 runtime:

```
$ dotnet booc.dll -p:boo hw.boo
Boo Compiler version 0.9.7.0 (CLR 10.0.11)
[System.Runtime.CompilerServices.CompilerGlobalScopeAttribute]
public final transient class HwModule(object):

	private static def Main(argv as (string)) as void:
		System.Console.WriteLine('hello from boo')

	private def constructor():
		super()

hw.boo(1,1): BCE0005: Unknown identifier: 'System'.
```

The AST output is correct. The `Unknown identifier: 'System'` error is default
reference resolution failing (blocker 2), not a parser or semantics failure.

## Appendix D: Toolchain

```
dotnet   10.0.400  (only SDK installed)
mono     6.14.1    (homebrew; unused by this plan)
java     26.0.2    (Temurin; ANTLR 2.7.5 jar confirmed to run on it)
nant     not installed
```
