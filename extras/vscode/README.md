# Boo for VS Code

A thin client for `boolsp`, the Boo language server. The extension starts the
server and gets out of the way; everything it shows comes from `boolsp`.

## What works

Diagnostics as you type, the document outline, hover, and go to definition.
Completion is not wired up yet.

## Running it from source

Build the server first, from the root of a clone:

```
dotnet build Boo.slnx
```

Then install the client's one dependency and open a development host:

```
cd extras/vscode
npm install
code --extensionDevelopmentPath="$PWD" ../..
```

That second window has the extension loaded and this repository open, which is
a useful test: it holds several hundred `.boo` files.

## Finding the server

The extension looks for the server in this order:

1. `boo.server.path`, if that setting names one.
2. `src/boolsp/bin/Debug/net10.0/boolsp`, then the `Release` build, under any
   open folder. This is what a clone built with `dotnet build` produces.
3. `boolsp` on `PATH`.

## Settings

| Setting | What it does |
| --- | --- |
| `boo.server.path` | The server to run. Empty means search, as above. |
| `boo.server.arguments` | Extra arguments for the server. |
| `boo.trace.server` | `messages` or `verbose` logs the traffic to the Boo output channel. |

`Boo: Restart Language Server` restarts it without reloading the window, which
is what you want after rebuilding.

## Known rough edges

A file is compiled on its own, so a name defined in a sibling file of the same
project is reported as unknown. Roughly ten such diagnostics appear in
`src/booi/booi.boo`, for example. Reading the project's references and its
sibling files is the next milestone.

Line comments toggle with `#`. Boo accepts `//` as well and both are
highlighted, but VS Code takes only one comment marker for the toggle.
