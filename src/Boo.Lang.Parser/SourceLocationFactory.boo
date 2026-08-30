# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of SourceLocationFactory. Not compiled by Boo.Lang.Parser, which
# is C#; it pairs with the Boo the ANTLR Boo target emits, and is checked by
# tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import Antlr4.Runtime
import Boo.Lang.Compiler.Ast

public class SourceLocationFactory:

	public static def ToLexicalInfo(token as IToken) as LexicalInfo:
		return LexicalInfo(token.InputStream.SourceName, token.Line, token.Column)

	public static def ToSourceLocation(token as IToken) as SourceLocation:
		return SourceLocation(token.Line, token.Column)

	public static def ToEndSourceLocation(token as IToken) as SourceLocation:
		if token.Type == TokenConstants.EOF:
			return SourceLocation(token.Line, token.Column)

		text = (token.Text if token.Text is not null else "")
		booToken = token as BooToken
		if booToken is not null and booToken.MagicToken:
			text = ""
		return SourceLocation(token.Line, token.Column + text.Length - 1)
