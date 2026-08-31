namespace Boo.Lang.Lsp.Workspace

import System.Collections.Generic

class AnalysisQueue:
"""
What is waiting to be compiled, one document per URI.

A keystroke makes the version before it worthless, so a second submission of
the same document replaces the first rather than queueing behind it. Order of
first submission is kept, so the file the user is typing in stays ahead of the
ones that merely reference it.
"""

	_pending = Dictionary[of string, TextDocument]()
	_order = List[of string]()
	_lock = object()

	Count as int:
		get:
			lock _lock:
				return _pending.Count

	def Submit(document as TextDocument):
		lock _lock:
			_order.Add(document.Uri) unless _pending.ContainsKey(document.Uri)
			_pending[document.Uri] = document

	def Withdraw(uri as string):
		lock _lock:
			_pending.Remove(uri)
			_order.Remove(uri)

	def Drain() as List[of TextDocument]:
		drained = List[of TextDocument]()
		lock _lock:
			for uri in _order:
				document as TextDocument
				drained.Add(document) if _pending.TryGetValue(uri, document)
			_pending.Clear()
			_order.Clear()
		return drained
