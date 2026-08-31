namespace Boo.Lang.Lsp.Workspace

import System
import Boo.Lang.Compiler.Ast
import Boo.Lang.Parser

class Positions:
"""
The one place LSP numbering and compiler numbering meet.

LSP counts lines and characters from zero. The compiler counts lines and
columns from one, and uses values below one for a location it never set.

They also disagree about tabs. LSP counts a tab as one character; the lexer
advances it to the next tab stop, so on an indented line, which in Boo is most
of them, the column is not the character. Crossing over means replaying that
expansion against the text of the line.
"""

	public static final TabSize = ParserSettings.DefaultTabSize

	static def FromSourceLocation(location as SourceLocation) as Position:
		return Position(Below(location.Line), Below(location.Column))

	static def ToLexicalInfo(fileName as string, position as Position) as LexicalInfo:
		return LexicalInfo(fileName, position.Line + 1, position.Character + 1)

	static def FromLexicalInfo(document as TextDocument, location as SourceLocation) as Position:
		line = Below(location.Line)
		return Position(line, CharacterAt(document.LineText(line), location.Column))

	static def ToLexicalInfo(document as TextDocument, position as Position) as LexicalInfo:
		column = ColumnAt(document.LineText(position.Line), position.Character)
		return LexicalInfo(document.Uri, position.Line + 1, column)

	static def CharacterAt(line as string, column as int) as int:
	"""The character index the lexer would have called this column."""
		return 0 if column < 1
		at = 1
		for i in range(line.Length):
			return i if at >= column
			at = Advance(at, line[i])
		return line.Length

	static def ColumnAt(line as string, character as int) as int:
	"""The column the lexer would report for this character index."""
		return 1 if character < 1
		at = 1
		for i in range(Math.Min(character, line.Length)):
			at = Advance(at, line[i])
		return at

	private static def Advance(column as int, c as char) as int:
		return column + 1 unless c == char('\t')
		return column + TabSize - ((column - 1) % TabSize)

	private static def Below(oneBased as int) as int:
		return 0 if oneBased < 1
		return oneBased - 1
