import System
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Server

def Usage():
	print "usage: boolsp [--version] [--help]"
	print ""
	print "Speaks the Language Server Protocol over stdin and stdout."
	print "Started by an editor, not usually by hand."

def Serve() as int:
	# Console.In and Console.Out would decode; the protocol is framed in bytes.
	stream = MessageStream(Console.OpenStandardInput(), Console.OpenStandardOutput())
	return LanguageServer(stream).Run()

def Run(args as (string)) as int:
	for arg in args:
		if arg == "--version" or arg == "-version":
			print "${ServerInfo.Name} ${ServerInfo.Version}"
			return 0
		if arg == "--help" or arg == "-help" or arg == "-h":
			Usage()
			return 0
		Console.Error.WriteLine("boolsp: unknown option ${arg}")
		return 2

	return Serve()

Environment.ExitCode = Run(argv)
