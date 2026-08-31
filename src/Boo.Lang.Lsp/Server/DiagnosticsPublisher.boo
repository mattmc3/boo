namespace Boo.Lang.Lsp.Server

import System.Collections.Generic
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Workspace

class DiagnosticsPublisher:
"""
Tells the client what is wrong with a document, and what no longer is.

Every publish carries the whole list for that document, so an empty list is
how a fixed file gets its squiggles taken away. A closed document is cleared
for the same reason.
"""

	public static final Method = "textDocument/publishDiagnostics"

	_connection as Connection
	_analyzer = Analyzer()

	def constructor(connection as Connection):
		_connection = connection

	def PublishSyntax(document as TextDocument):
	"""
	The fast tier, run on the message loop for every change.

	It publishes only when parsing found something. A clean parse says nothing,
	because saying nothing keeps the semantic diagnostics already on screen
	from flickering off and back on between keystrokes.
	"""
		diagnostics = _analyzer.Parse(document)
		Send(document.Uri, diagnostics) if diagnostics.Count > 0

	def PublishSemantic(document as TextDocument):
	"""The slow tier, run on the worker. Its answer is the whole truth."""
		Send(document.Uri, _analyzer.Bind(document))

	def Clear(uri as string):
		Send(uri, List[of object]())

	private def Send(uri as string, diagnostics as List[of object]):
		params = Dictionary[of string, object]()
		params["uri"] = uri
		params["diagnostics"] = diagnostics
		_connection.Notify(Method, params)
