namespace Boo.Lang.Lsp.Server

import System.Collections.Generic
import Boo.Lang.Lsp.Json
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Workspace

class Completions:
"""Answers textDocument/completion."""

	public static final Method = "textDocument/completion"

	_documents as DocumentStore
	_completion = Completion()

	def constructor(documents as DocumentStore, connection as Connection):
		_documents = documents
		connection.OnRequest(Method, Suggest)

	static def Capability():
		capability = Dictionary[of string, object]()
		capability["triggerCharacters"] = List[of object](("." as object,))
		capability["resolveProvider"] = false
		return capability

	private def Suggest(params as object) as object:
		document = _documents.Get(Fields.Text(Fields.Map(params, "textDocument"), "uri"))
		return List[of object]() if document is null

		position = Fields.Map(params, "position")
		return List[of object]() if position is null

		return _completion.At(
			document,
			Position(Fields.Number(position, "line", 0), Fields.Number(position, "character", 0)))
