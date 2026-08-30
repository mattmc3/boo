# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of DocStringFormatter. Not compiled by Boo.Lang.Parser, which is
# C#; it pairs with the Boo the ANTLR Boo target emits, and is checked by
# tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import System

public class DocStringFormatter:

	public static def Format(s as string) as string:
		return string.Empty if s.Length == 0

		s = s.Replace("\r\n", "\n")

		length = s.Length
		startIndex = 0
		if char('\n') == s[0]:
			startIndex += 1
			length -= 1
		if char('\n') == s[s.Length - 1]:
			length -= 1

		return s.Substring(startIndex, length) if length > 0
		return string.Empty
