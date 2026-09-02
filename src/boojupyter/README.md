boojupyter
==========

A Jupyter kernel for Boo. It speaks version 5.3 of the Jupyter wire protocol
over ZeroMQ and evaluates cells with `Boo.Lang.Interpreter`, so a notebook sees
the same interpreter state from one cell to the next.

Building
--------

```
dotnet build Boo.slnx
```

The kernel is built by the same stage-1 `booc` as the rest of the Boo
libraries, so `src/booc` has to build first. That falls out of the project
references; there is nothing extra to run.

Installing
----------

```
src/boojupyter/bin/Debug/net10.0/boojupyter install
```

That writes a `kernel.json` naming the executable it was run from into the
per-user Jupyter kernels directory. Which directory that is depends on the
machine, so `install` reads `JUPYTER_DATA_DIR`, then asks `jupyter --data-dir`,
and only guesses from the platform if there is no jupyter on the path. Check it
against `jupyter --paths`. Because the spec points at the build output,
reinstall after moving or republishing the binary.

Options:

- `--name NAME` the directory the spec is written to, default `boo`
- `--display-name NAME` what the notebook UI shows, default `Boo`
- `--prefix DIR` write under `DIR` instead of the user directory

`install` also copies any `logo-*` file sitting beside the executable into the
spec directory, which is where Jupyter looks for the kernel icon.
`logo-svg.svg` is `assets/boo-logo.svg` with a `viewBox` added so it scales.

Confirm Jupyter can see it:

```
jupyter kernelspec list
```

Running
-------

Console:

```
jupyter console --kernel boo
```

Lab:

```
jupyter lab
```

In JupyterLab, pick Boo from the launcher or the kernel picker.

Jupyter starts the kernel itself; `--connection-file` is how it passes the
ports and signing key, and is not something to run by hand.

Syntax highlighting
-------------------

Two different highlighters see a notebook, and they are configured separately
in the `kernel_info_reply`:

- **The cell editor** uses CodeMirror, which has no Boo mode. The kernel
  reports `codemirror_mode` as `python`, whose indentation, `#` comments and
  `def` read close enough to Boo to be worth having. Boo-only keywords are not
  highlighted.
- **Exported and printed output** (nbconvert, `jupyter console`) uses Pygments,
  which does ship a Boo lexer. The kernel reports `pygments_lexer` as `boo`, so
  those paths highlight Boo properly.

What works
----------

- Cell execution, with state carried across cells
- `stdout` and `stderr` streamed to the notebook as the cell runs
- The value of the last expression, shown the way `booish` shows it, and bound
  to `_` for the next cell
- Compiler errors and runtime exceptions, as `error` messages with a traceback
- Tab completion of members and of names in scope
- `is_complete`, so `jupyter console` knows when a block is still open
- Rich output through `Display`, including Plotly charts

Not implemented yet
-------------------

- Interrupting a running cell. The spec asks Jupyter to interrupt by message
  rather than by signal, and the kernel replies to `interrupt_request` without
  stopping anything.
- Input from a cell. The stdin channel is bound but never read, so a cell that
  asks for input will hang.
- Comms, and so no widgets.

Charts
------

A cell reaches rich output through the `Display` class:

```boo
import boojupyter

xs = [i * 0.25 for i in range(40)]
ys = [System.Math.Sin(x) for x in xs]
Display.Plot(xs, ys)
```

`Display.Plot` also takes any Plotly.NET `GenericChart`, which is what to use
for anything beyond a line. `Display.Html`, `Display.Text` and `Display.Json`
cover the other representations; `Display.Json` is how to reach a client-side
renderer such as Vega-Lite.

A chart goes out as both `application/vnd.plotly.v1+json` and HTML, and
Jupyter draws the richest one the client understands. JupyterLab does not
ship the plotly renderer, so install plotly into the environment jupyter runs
from to see charts there. The HTML is what nbconvert exports.

Compiler warnings are hidden, because the interpreter replays its recorded
imports into every cell and an unused one would warn on each execution. Pass
`--warnings` in the spec's `argv` to see them.
