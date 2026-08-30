# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of Readers. Not compiled by Boo.Lang.Parser, which is C#; it
# pairs with the Boo the ANTLR Boo target emits, and is checked by
# tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser.Util

import System.IO

internal static class Readers:

	public def IsEmpty(reader as TextReader) as bool:
		return reader.Peek() == -1
