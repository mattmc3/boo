# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of ParserSettings. Not compiled by Boo.Lang.Parser, which is C#;
# it pairs with the Boo the ANTLR Boo target emits, and is checked by
# tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import System

public class ParserSettings:

	public static final DefaultTabSize = 4

	private _tabSize = DefaultTabSize

	private _errorHandler as ParserErrorHandler

	public TabSize as int:
		get:
			return _tabSize
		set:
			raise ArgumentOutOfRangeException("TabSize") if value < 1
			_tabSize = value

	public ErrorHandler as ParserErrorHandler:
		get:
			return _errorHandler
		set:
			_errorHandler = value
