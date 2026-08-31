namespace Boo.Lang.Lsp.Server

import System.Collections.Generic
import Boo.Lang.Lsp.Json
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Workspace

class SignatureHelp:
"""Answers textDocument/signatureHelp."""

	public static final Method = "textDocument/signatureHelp"

	_documents as DocumentStore
	_help = CallSignature()

	def constructor(documents as DocumentStore, connection as Connection):
		_documents = documents
		connection.OnRequest(Method, Describe)

	static def Capability():
		capability = Dictionary[of string, object]()
		capability["triggerCharacters"] = List[of object](("(" as object, "," as object))
		capability["retriggerCharacters"] = List[of object](("," as object,))
		return capability

	private def Describe(params as object) as object:
		document = _documents.Get(Fields.Text(Fields.Map(params, "textDocument"), "uri"))
		return null if document is null

		position = Fields.Map(params, "position")
		return null if position is null

		found = _help.At(
			document,
			Position(Fields.Number(position, "line", 0), Fields.Number(position, "character", 0)))
		return null if found is null

		result = Dictionary[of string, object]()
		result["signatures"] = Written(found.Overloads)
		result["activeSignature"] = found.ActiveOverload
		result["activeParameter"] = found.ActiveParameter
		return result

	private static def Written(overloads as List[of Signatures.Overload]) as List[of object]:
		written = List[of object]()
		for overload in overloads:
			parameters = List[of object]()
			for parameter in overload.Parameters:
				labelled = Dictionary[of string, object]()
				labelled["label"] = parameter
				parameters.Add(labelled)

			signature = Dictionary[of string, object]()
			signature["label"] = overload.Label
			signature["parameters"] = parameters
			written.Add(signature)
		return written
