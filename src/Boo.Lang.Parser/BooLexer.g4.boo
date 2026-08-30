# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of BooLexer, holding the helpers BooLexer.g4's actions call.
# Not compiled by Boo.Lang.Parser, which is C#; it pairs with the Boo the
# ANTLR Boo target emits. See tools/antlr-boo-target/README.md.

namespace Boo.Lang.Parser

import System
import System.Collections.Generic

partial class BooLexer:

	protected _skipWhitespaceRegion as int = 0

	private final _beginInterpolationType = Stack[of int]()
	private final _endInterpolationType = Stack[of int]()

	private SkipWhitespace as bool:
		get:
			return _skipWhitespaceRegion > 0

	private static def IsDigit(ch as int) as bool:
		return ch >= cast(int, char('0')) and ch <= cast(int, char('9'))

	private def IsLetterBehind() as bool:
		return char.IsLetter(cast(char, InputStream.LA(-1)))

	# A star inside a block comment that does not close it.
	private def StarIsNotCommentEnd() as bool:
		return InputStream.LA(1) != cast(int, char('/'))

	private def EnterSkipWhitespaceRegion():
		_skipWhitespaceRegion += 1

	# Grammar actions are written in the target language, so they say no more
	# than a call. Anything with a shape to it lives here instead.
	private def HideWhitespace():
		if SkipWhitespace:
			Channel = Hidden

	private def HandleNewLine():
		# ANTLR 4 counts a line on '\n' alone, so a bare carriage return ends
		# a line for boo.g but not for the runtime.
		if Text == "\r":
			Interpreter.Line += 1
			Interpreter.Column = 0
		HideWhitespace()

	private def LeaveSkipWhitespaceRegion():
		_skipWhitespaceRegion -= 1

	private def HandleInterpolatedExpression(beginInterpolationType as int, endTokenType as int):
		_beginInterpolationType.Push(beginInterpolationType)
		_endInterpolationType.Push(endTokenType)
		PushMode(DEFAULT_MODE)

	private def HandleInterpolationToken(type as int):
		if _beginInterpolationType.Count == 0:
			return

		if _beginInterpolationType.Peek() == type:
			PushMode(DEFAULT_MODE)
		elif _endInterpolationType.Peek() == type:
			PopMode()
			if CurrentMode != DEFAULT_MODE:
				_beginInterpolationType.Pop()
				_endInterpolationType.Pop()
