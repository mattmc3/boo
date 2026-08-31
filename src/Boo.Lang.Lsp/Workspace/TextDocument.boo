namespace Boo.Lang.Lsp.Workspace

import System
import System.Collections.Generic

class TextDocument:
"""
One open document, with an index of where its lines start.

The index is rebuilt whenever the text changes, which keeps a position lookup
to a binary search rather than a scan of the whole buffer.
"""

	public final Uri as string
	public final LanguageId as string

	[property(Version)]
	_version as int

	[property(Text)]
	_text as string

	_lineStarts as List[of int]

	def constructor(uri as string, languageId as string, version as int, text as string):
		Uri = uri
		LanguageId = languageId
		Update(version, text)

	def Update(version as int, text as string):
		_version = version
		_text = text
		_lineStarts = IndexLines(text)

	LineCount as int:
		get: return _lineStarts.Count

	def LineText(line as int) as string:
		return "" if line < 0 or line >= _lineStarts.Count
		start = _lineStarts[line]
		finish = EndOfLine(line)
		return _text.Substring(start, finish - start)

	def OffsetAt(position as Position) as int:
		return 0 if position.Line < 0
		return _text.Length if position.Line >= _lineStarts.Count
		start = _lineStarts[position.Line]
		return start if position.Character < 0
		return Math.Min(start + position.Character, EndOfLine(position.Line))

	def PositionAt(offset as int) as Position:
		return Position(0, 0) if offset <= 0
		clamped = Math.Min(offset, _text.Length)
		line = LineAt(clamped)
		return Position(line, clamped - _lineStarts[line])

	private def EndOfLine(line as int) as int:
	"""The offset of the line terminator, or of the end of the text."""
		finish = _text.Length
		if line + 1 < _lineStarts.Count:
			finish = _lineStarts[line + 1] - 1
			finish-- if finish > 0 and _text[finish - 1] == char('\r')
		return finish

	private def LineAt(offset as int) as int:
		low = 0
		high = _lineStarts.Count - 1
		while low < high:
			middle = (low + high + 1) / 2
			if _lineStarts[middle] <= offset:
				low = middle
			else:
				high = middle - 1
		return low

	private static def IndexLines(text as string) as List[of int]:
		starts = List[of int]()
		starts.Add(0)
		for i in range(text.Length):
			starts.Add(i + 1) if text[i] == char('\n')
		return starts
