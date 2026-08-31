namespace Boo.Lang.Lsp.Workspace

class CompilerLock:
"""
Every compile the server runs passes through here.

The compiler keeps state that is not per instance, so two BooCompiler runs at
once corrupt each other: the second one throws on a reference the first has
already registered. The server genuinely does compile from two threads, since
the analysis worker binds for diagnostics while the message loop answers
hover, definition, symbols and completion.

One at a time costs latency on a request that arrives mid-bind. It is the
price of a compiler that was written for batch use.
"""

	public static final Gate = object()
