namespace Boo.Lang.Lsp.Server

import System.Collections.Generic
import Boo.Lang.Lsp.Json
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Workspace

class Navigation:
"""
Answers hover and go to definition, both from the same lookup.

Each request binds the document afresh, which is affordable for one file and
is what the cached context in M8 is meant to replace.
"""

	public static final Hover = "textDocument/hover"
	public static final Definition = "textDocument/definition"
	public static final Highlight = "textDocument/documentHighlight"

	# The client draws all three kinds the same unless it is told otherwise.
	public static final Text = 1

	_documents as DocumentStore
	_analyzer = Analyzer()

	def constructor(documents as DocumentStore, connection as Connection):
		_documents = documents
		connection.OnRequest(Hover, Describe)
		connection.OnRequest(Definition, Locate)
		connection.OnRequest(Highlight, Occurrences)

	private def Describe(params as object) as object:
		found = At(params)
		return null if found is null

		# The signature reads as Boo, what it documents reads as prose, and
		# the blank line between them is what keeps markdown from running the
		# two together.
		value = "```boo\n${found.Signature}\n```"
		value += "\n\n" + found.Documentation unless string.IsNullOrEmpty(found.Documentation)

		contents = Dictionary[of string, object]()
		contents["kind"] = "markdown"
		contents["value"] = value

		hover = Dictionary[of string, object]()
		hover["contents"] = contents
		hover["range"] = Diagnostic.Range(found.Start, found.End)
		return hover

	private def Locate(params as object) as object:
		found = At(params)
		return null if found is null or not found.HasDeclaration

		# A name is what is jumped to, and its length is not recorded, so the
		# range is empty and the editor lands on the first character.
		location = Dictionary[of string, object]()
		location["uri"] = found.DeclarationUri
		location["range"] = Diagnostic.Range(found.Declaration, found.Declaration)
		return location

	private def Occurrences(params as object) as object:
		document = _documents.Get(Fields.Text(Fields.Map(params, "textDocument"), "uri"))
		return null if document is null

		position = Fields.Map(params, "position")
		return null if position is null

		spans = Lookup.Occurrences(
			document,
			_analyzer.Bound(document),
			Position(Fields.Number(position, "line", 0), Fields.Number(position, "character", 0)))

		highlights = List[of object]()
		for span in spans:
			highlight = Dictionary[of string, object]()
			highlight["range"] = Diagnostic.Range(span.Start, span.End)
			highlight["kind"] = Text
			highlights.Add(highlight)
		return highlights

	private def At(params as object) as Lookup.Result:
		document = _documents.Get(Fields.Text(Fields.Map(params, "textDocument"), "uri"))
		return null if document is null

		position = Fields.Map(params, "position")
		return null if position is null

		return Lookup.At(
			document,
			_analyzer.Bound(document),
			Position(Fields.Number(position, "line", 0), Fields.Number(position, "character", 0)))
