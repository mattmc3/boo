namespace Boo.Lang.Lsp.Server

import System.Collections.Generic
import Boo.Lang.Lsp.Json
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Workspace

class DocumentSymbols:
"""
Answers textDocument/documentSymbol from a parse of the open document.

Parsing rather than binding, so a file that does not compile still has an
outline: a broken line costs the symbols below it, not all of them.
"""

	public static final Method = "textDocument/documentSymbol"

	_documents as DocumentStore
	_analyzer = Analyzer()

	def constructor(documents as DocumentStore, connection as Connection):
		_documents = documents
		connection.OnRequest(Method, Answer)

	private def Answer(params as object) as object:
		document = _documents.Get(Fields.Text(Fields.Map(params, "textDocument"), "uri"))
		return List[of object]() if document is null
		return Symbols.Of(document, _analyzer.ParseTree(document))
