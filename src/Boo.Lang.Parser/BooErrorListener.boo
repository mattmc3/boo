# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of the parser and lexer error listeners. Not compiled by
# Boo.Lang.Parser, which is C#; it pairs with the Boo the ANTLR Boo target
# emits, and is checked by tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import System
import System.IO
import Antlr4.Runtime

public class BooErrorListener(BaseErrorListener):

	private _errorHandler as ParserErrorHandler
	private _filename as string

	public def constructor(eh as ParserErrorHandler, filename as string):
		_errorHandler = eh
		_filename = filename

	override def SyntaxError(output as TextWriter, recognizer as IRecognizer, offendingSymbol as IToken, line as int, charPositionInLine as int, msg as string, e as RecognitionException):
		_errorHandler(recognizer, offendingSymbol, _filename, line, charPositionInLine, msg, e)


# The lexer reports on character offsets rather than tokens, so it needs a
# listener of its own. Without one it writes to the console and a bad token
# never reaches the compiler.
public class BooLexerErrorListener(IAntlrErrorListener[of int]):

	private _errorHandler as ParserErrorHandler
	private _filename as string

	public def constructor(eh as ParserErrorHandler, filename as string):
		_errorHandler = eh
		_filename = filename

	public def SyntaxError(output as TextWriter, recognizer as IRecognizer, offendingSymbol as int, line as int, charPositionInLine as int, msg as string, e as RecognitionException):
		_errorHandler(recognizer, null, _filename, line, charPositionInLine, msg, e)
