namespace Boo.Lang.Lsp.Workspace

import System.Collections.Generic

class DocumentStore:
"""
The documents the client has open, keyed by URI.

What is here is what the client is showing, which is not what is on disk. The
server answers from these and reads the disk only for files nobody has open.
"""

	_documents = Dictionary[of string, TextDocument]()

	Count as int:
		get: return _documents.Count

	Uris as IEnumerable[of string]:
		get: return _documents.Keys

	def Open(uri as string, languageId as string, version as int, text as string) as TextDocument:
		document = TextDocument(uri, languageId, version, text)
		_documents[uri] = document
		return document

	def Change(uri as string, version as int, text as string) as TextDocument:
	"""Returns null for a document the client never opened."""
		document = Get(uri)
		return null if document is null
		document.Update(version, text)
		return document

	def Close(uri as string):
		_documents.Remove(uri)

	def Get(uri as string) as TextDocument:
		document as TextDocument
		return document if _documents.TryGetValue(uri, document)
		return null
