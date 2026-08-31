namespace Boo.Lang.Lsp.Server

class CommandLine:
"""
What the arguments asked for.

--stdio is not an option so much as a fact: it is what every client built on
vscode-languageclient appends, and stdio is the only transport this server
speaks, so it is accepted and ignored. Refusing it means exiting before the
client has been answered, which the client reports as a crash.
"""

	public static final Serve = 0
	public static final ShowVersion = 1
	public static final ShowHelp = 2
	public static final Unknown = 3

	public final Action as int
	public final UnknownOption as string

	def constructor(action as int, unknownOption as string):
		Action = action
		UnknownOption = unknownOption

	static def Parse(args as (string)) as CommandLine:
		for arg in args:
			continue if arg == "--stdio" or arg == "-stdio"
			return CommandLine(ShowVersion, null) if arg == "--version" or arg == "-version"
			return CommandLine(ShowHelp, null) if arg == "--help" or arg == "-help" or arg == "-h"
			return CommandLine(Unknown, arg)
		return CommandLine(Serve, null)
