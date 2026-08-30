# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of BooParser, holding the helpers BooParser.g4's predicates
# call. Not compiled by Boo.Lang.Parser, which is C#; it pairs with the Boo
# the ANTLR Boo target emits. See tools/antlr-boo-target/README.md.
#
# The public API of the C# half (ParseFile, ParseString, CreateParser and
# friends) is not here. It reaches into BooToken, IndentTokenStreamFilter,
# BooErrorListener and BooParserAstBuilderVisitor, all still C#, so it cannot
# be ported until they are.

namespace Boo.Lang.Parser

import System
import Antlr4.Runtime

# The C# half declares this beside BooParser, so it lives here too.
public callable ParserErrorHandler(recognizer as IRecognizer, offendingSymbol as IToken, filename as string, line as int, charPositionInLine as int, msg as string, e as RecognitionException)

partial class BooParser:

	private def IsNegativeLongLiteral() as bool:
		return InputStream.LA(1) == SUBTRACT and InputStream.LA(2) == LONG

	private static def IsValidMacroArgument(tokenType as int) as bool:
		return LPAREN != tokenType and LBRACK != tokenType and DOT != tokenType and MULTIPLY != tokenType

	protected def IsValidClosureMacroArgument(tokenType as int) as bool:
		return IsValidMacroArgument(tokenType) and SUBTRACT != tokenType
