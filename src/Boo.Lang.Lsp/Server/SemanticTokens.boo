namespace Boo.Lang.Lsp.Server

import System.Collections.Generic
import Boo.Lang.Lsp.Json
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Workspace

class SemanticTokenHandler:
"""Answers full-document semantic token requests."""

	public static final FullMethod = "textDocument/semanticTokens/full"

	_documents as DocumentStore
	_analyzer = Analyzer()

	def constructor(documents as DocumentStore, connection as Connection):
		_documents = documents
		connection.OnRequest(FullMethod, AnswerFull)

	static def Capability() as Dictionary[of string, object]:
		return Boo.Lang.Lsp.Workspace.SemanticTokens.Capability()

	private def AnswerFull(params as object) as object:
		document = _documents.Get(Fields.Text(Fields.Map(params, "textDocument"), "uri"))
		return Empty() if document is null
		return Boo.Lang.Lsp.Workspace.SemanticTokens.Of(document, _analyzer.Bound(document))

	private static def Empty() as Dictionary[of string, object]:
		result = Dictionary[of string, object]()
		result["data"] = List[of long]()
		return result
