import System
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Server

def Usage():
	print "usage: boolsp [--stdio] [--version] [--help]"
	print ""
	print "Speaks the Language Server Protocol over stdin and stdout."
	print "Started by an editor, not usually by hand."

def Serve() as int:
	# Console.In and Console.Out would decode; the protocol is framed in bytes.
	stream = MessageStream(Console.OpenStandardInput(), Console.OpenStandardOutput())
	return LanguageServer(stream).Run()

def Run(args as (string)) as int:
	parsed = CommandLine.Parse(args)

	if parsed.Action == CommandLine.ShowVersion:
		print "${ServerInfo.Name} ${ServerInfo.Version}"
		return 0

	if parsed.Action == CommandLine.ShowHelp:
		Usage()
		return 0

	if parsed.Action == CommandLine.Unknown:
		Console.Error.WriteLine("boolsp: unknown option ${parsed.UnknownOption}")
		return 2

	return Serve()

Environment.ExitCode = Run(argv)
