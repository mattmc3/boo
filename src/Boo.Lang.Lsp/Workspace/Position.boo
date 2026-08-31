namespace Boo.Lang.Lsp.Workspace

import System

class Position:
"""A place in a document, counted from zero, in UTF-16 code units."""

	public final Line as int
	public final Character as int

	def constructor(line as int, character as int):
		Line = line
		Character = character

	override def ToString():
		return "${Line}:${Character}"

	override def Equals(other as object):
		that = other as Position
		return that is not null and that.Line == Line and that.Character == Character

	override def GetHashCode():
		return Line * 397 + Character
