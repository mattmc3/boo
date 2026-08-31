namespace Boo.Lang.Lsp.Server

import System.Collections.Generic
import Boo.Lang.Lsp.Json
import Boo.Lang.Lsp.Protocol
import Boo.Lang.Lsp.Workspace

callable DocumentChanged(document as TextDocument)

callable DocumentClosed(uri as string)

class TextDocumentSync:
"""
Keeps the document store in step with the client.

Sync is full text for now: a change carries the whole document, so the last
content change in the batch is the new text.
"""

	public static final Full = 1

	_documents as DocumentStore

	[property(Changed)]
	_changed as DocumentChanged

	[property(Closed)]
	_closed as DocumentClosed

	def constructor(documents as DocumentStore, connection as Connection):
		_documents = documents
		connection.OnNotification("textDocument/didOpen", DidOpen)
		connection.OnNotification("textDocument/didChange", DidChange)
		connection.OnNotification("textDocument/didClose", DidClose)
		connection.OnNotification("textDocument/didSave", DidSave)

	static def Capability():
		capability = Dictionary[of string, object]()
		capability["openClose"] = true
		capability["change"] = Full
		return capability

	private def DidOpen(params as object):
		document = Fields.Map(params, "textDocument")
		return if document is null
		Announce(_documents.Open(
			Fields.Text(document, "uri"),
			Fields.Text(document, "languageId"),
			Fields.Number(document, "version", 0),
			Fields.Text(document, "text")))

	private def DidChange(params as object):
		document = Fields.Map(params, "textDocument")
		return if document is null
		changes = Fields.Items(params, "contentChanges")
		return if changes.Count == 0
		text = Fields.Text(changes[changes.Count - 1], "text")
		return if text is null
		Announce(_documents.Change(Fields.Text(document, "uri"), Fields.Number(document, "version", 0), text))

	private def DidClose(params as object):
		document = Fields.Map(params, "textDocument")
		return if document is null
		uri = Fields.Text(document, "uri")
		_documents.Close(uri)
		_closed(uri) if _closed is not null

	private def Announce(document as TextDocument):
		return if document is null or _changed is null
		_changed(document)

	private def DidSave(params as object):
		# Nothing to do while sync is full text; the buffer is already current.
		pass
