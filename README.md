[![CI](https://github.com/mattmc3/boo/actions/workflows/ci.yml/badge.svg)](https://github.com/mattmc3/boo/actions/workflows/ci.yml)

The Boo Programming Language (c) Rodrigo B. de Oliveira and the Boo contributors

A fork of [boo-lang/boo](https://github.com/boo-lang/boo) ported to .NET 10.
Upstream targeted .NET Framework / Mono; its last commit was July 2022.

Status
======

The compiler, its libraries, `booi` and `booish` build, and the test suite
passes. `Boo.Microsoft.Build.Tasks` is the one project still on the old build
and out of the solution: booc resolves references by loading them, so it cannot
read the reference assemblies the SDK passes for a NuGet package. See
[MODERNIZATION.md](MODERNIZATION.md) for what changed and why.

Requirements
============

- .NET 10 SDK

Nothing else. NAnt, Gradle, Mono and the bootstrap binaries are gone.

Building
========

    dotnet build Boo.slnx

This is a two stage build: the C# core produces `booc`, which then compiles the
`.booproj` projects.

Testing
=======

    dotnet test Boo.slnx

The suite verifies every assembly it generates with ilverify. Without it the
tests still run, they just skip verification:

    dotnet tool install --global dotnet-ilverify

A [justfile](justfile) wraps both, plus `clean`, `format` and `format-check`:

    just build
    just test

Compiling code
==============

`booc` is the compiler. It is not installed as a tool, so run it from the build
output:

    dotnet src/booc/bin/Debug/net10.0/booc.dll -o:now.exe examples/misc/now.boo

To see the transformations the compiler applies to your code, use the boo
pipeline:

    dotnet src/booc/bin/Debug/net10.0/booc.dll -p:boo examples/misc/now.boo

`booc` does not emit a `.runtimeconfig.json`, so running a generated executable
needs one written by hand.

To run a script without compiling it to disk, use `booi`:

    dotnet src/booi/bin/Debug/net10.0/booi.dll examples/misc/now.boo

`booish` is an interactive prompt. It reads keys directly, so it needs a
terminal:

    dotnet src/booish/bin/Debug/net10.0/booish.dll

Layout
======

- `src/` runtime and compiler
- `tests/` unit tests
- `tests/testcases/integration/` the best source on language features
- `examples/` sample programs
- `docs/` `BooManifesto.sxw` describes the project and its goals
- `lib/` dependencies (antlr)

More Information
================

Boo development Google group:
https://groups.google.com/forum/#!forum/boolang

Boo community Discord:
[https://discord.gg/J4Guxadwma](https://discord.gg/J4Guxadwma)

Contributors
============

See: https://github.com/boo-lang/boo/graphs/contributors
