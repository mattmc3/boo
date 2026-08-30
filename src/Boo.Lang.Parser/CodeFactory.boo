# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of CodeFactory. Not compiled by Boo.Lang.Parser, which is C#; it
# pairs with the Boo the ANTLR Boo target emits, and is checked by
# tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import System
import System.IO
import System.Text
import Boo.Lang.Compiler.Ast

internal class CodeFactory:

	public static def EnumerableTypeReferenceFor(tr as TypeReference) as TypeReference:
		result = GenericTypeReference(tr.LexicalInfo, "System.Collections.Generic.IEnumerable")
		result.GenericArguments.Add(tr)
		return result

	public static def NewQuasiquoteModule(li as LexicalInfo) as Module:
		return Module(li, Name: ModuleNameFrom(li.FileName) + "\$" + li.Line)

	public static def ModuleNameFrom(readerName as string) as string:
		if readerName.IndexOfAny(Path.GetInvalidPathChars()) > -1:
			return EncodeModuleName(readerName)
		return Path.GetFileNameWithoutExtension(Path.GetFileName(readerName))

	private static def EncodeModuleName(name as string) as string:
		buffer = StringBuilder(name.Length)
		for ch in name:
			if char.IsLetterOrDigit(ch):
				buffer.Append(ch)
			else:
				buffer.Append("_")
		return buffer.ToString()
