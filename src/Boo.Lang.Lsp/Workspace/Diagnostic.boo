namespace Boo.Lang.Lsp.Workspace

import System
import System.Collections.Generic
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast

class Diagnostic:
"""
Turns what the compiler reports into what the client draws.

A CompilerError says where it starts and nothing about where it ends, so the
end of the range is the end of the word the client would see under the squiggle.
"""

	public static final Source = "boo"
	public static final Error = 1
	public static final Warning = 2

	static def FromError(document as TextDocument, error as CompilerError):
		return Build(document, error.LexicalInfo, Error, error.Code, error.Message)

	static def FromWarning(document as TextDocument, warning as CompilerWarning):
		return Build(document, warning.LexicalInfo, Warning, warning.Code, warning.Message)

	static def Range(start as Position, finish as Position):
		# Not named range: that name is an overloaded builtin method, so
		# assigning to it and indexing it does not reach a local.
		span = Dictionary[of string, object]()
		span["start"] = Place(start)
		span["end"] = Place(finish)
		return span

	private static def Place(position as Position):
		place = Dictionary[of string, object]()
		place["line"] = position.Line
		place["character"] = position.Character
		return place

	private static def Build(document as TextDocument, location as LexicalInfo, severity as int, code as string, message as string):
		start = Positions.FromLexicalInfo(document, location)
		diagnostic = Dictionary[of string, object]()
		diagnostic["range"] = Range(start, EndOfWord(document, location, start))
		diagnostic["severity"] = severity
		diagnostic["code"] = code
		diagnostic["source"] = Source
		diagnostic["message"] = message
		return diagnostic

	private static def EndOfWord(document as TextDocument, location as LexicalInfo, start as Position) as Position:
		# A location the compiler never set points at nothing to underline.
		return start unless location.Line > 0 and location.Column > 0

		line = document.LineText(start.Line)
		finish = start.Character
		while finish < line.Length and IsWordCharacter(line[finish]):
			finish++
		finish++ if finish == start.Character and finish < line.Length
		return Position(start.Line, finish)

	private static def IsWordCharacter(c as char) as bool:
		return char.IsLetterOrDigit(c) or c == char('_')
