# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of BooToken. Not compiled by Boo.Lang.Parser, which is C#; it
# pairs with the Boo the ANTLR Boo target emits, and is checked by
# tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import System
import Antlr4.Runtime
import Antlr4.Runtime.Misc

# A token that stores filename information.
public class BooToken(CommonToken):

	protected _fname as string

	private _magic as bool

	public static def CreateTokenFactory(tabSize as int) as ITokenFactory:
		return BooTokenCreator(tabSize)

	public def constructor(type as int):
		super(type)

	public def constructor(type as int, text as string):
		super(type, text)

	public def constructor(source as Tuple[of ITokenSource, ICharStream], type as int, channel as int, start as int, stop as int):
		super(source, type, channel, start, stop)

	public def constructor(source as Tuple[of ITokenSource, ICharStream], type as int, text as string, fname as string, start as int, stop as int, line as int, column as int, magic as bool):
		super(type, text)
		setFilename(fname)
		self.source = source
		self.StartIndex = start
		self.StopIndex = stop
		self.Line = line
		self.Column = column
		self._magic = magic

	public def setFilename(name as string):
		_fname = name

	public def getFilename() as string:
		return _fname

	public MagicToken as bool:
		get:
			return _magic

	public class BooTokenCreator(CommonTokenFactory):

		private final _tabSize as int

		public def constructor(tabSize as int):
			_tabSize = tabSize

		override def Create(source as Tuple[of ITokenSource, ICharStream], type as int, text as string, channel as int, start as int, stop as int, line as int, charPositionInLine as int) as CommonToken:
			result = BooToken(source, type, channel, start, stop)
			result.Line = line
			result.Column = ColumnOf(source.Item2, start, charPositionInLine)
			if text is not null:
				result.Text = text
			elif self.copyText and source.Item2 is not null:
				result.Text = source.Item2.GetText(Interval.Of(start, stop))
			return result

		# The 1 based column of a token, counting a tab as a jump to the next
		# tab stop. ANTLR 4 counts characters, so the text before the token on
		# its line has to be measured again here.
		private def ColumnOf(input as ICharStream, start as int, charPositionInLine as int) as int:
			if input is null or charPositionInLine <= 0:
				return charPositionInLine + 1

			lineStart = start - charPositionInLine
			if lineStart < 0:
				return charPositionInLine + 1

			prefix = input.GetText(Interval.Of(lineStart, start - 1))
			column = 1
			for c in prefix:
				if c == char('\t'):
					column = ((column - 1) / _tabSize + 1) * _tabSize + 1
				else:
					column = column + 1

			return column

		override def Create(type as int, text as string) as CommonToken:
			return BooToken(type, text)
