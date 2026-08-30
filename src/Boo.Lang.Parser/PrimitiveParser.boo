#region license
// Copyright (c) 2003, 2004, 2005 Rodrigo B. de Oliveira (rbo@acm.org)
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
//
//     * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//     * Neither the name of Rodrigo B. de Oliveira nor the names of its
//     contributors may be used to endorse or promote products derived from this
//     software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#endregion

# The Boo half of this file. Not compiled by Boo.Lang.Parser, which is C#; it
# pairs with the Boo the ANTLR Boo target emits, and is checked against the C#
# parser by tools/antlr-boo-target/test/check-boo-parser.sh.


namespace Boo.Lang.Parser

import System
import System.Globalization
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Environments

internal class PrimitiveParser:
	static def ParseTimeSpan(sourceLocation as LexicalInfo, text as string) as TimeSpan:
		try:
			return TryParseTimeSpan(sourceLocation, text)
		except x as System.OverflowException:
			GenericParserError(sourceLocation, x)
			// let the parser continue
			return TimeSpan.Zero

	static def TryParseTimeSpan(sourceLocation as LexicalInfo, text as string) as TimeSpan:
		if text.EndsWith("ms"):
			return TimeSpan.FromMilliseconds( ParseDouble(sourceLocation, text.Substring(0, text.Length - 2)))

		last as char = text[text.Length - 1]
		value as double = ParseDouble(sourceLocation, text.Substring(0, text.Length - 1))
		if last == char('s'):
			return TimeSpan.FromSeconds(value)
		elif last == char('h'):
			return TimeSpan.FromHours(value)
		elif last == char('m'):
			return TimeSpan.FromMinutes(value)
		elif last == char('d'):
			return TimeSpan.FromDays(value)
		raise ArgumentException(text, "text")

	static def ParseDouble(sourceLocation as LexicalInfo, s as string) as double:
		return ParseDouble(sourceLocation, s, false)

	static def ParseDouble(sourceLocation as LexicalInfo, s as string, isSingle as bool) as double:
		try:
			return TryParseDouble(isSingle, s)
		except x as Exception:
			GenericParserError(sourceLocation, x)
			// let the parser continue
			return double.NaN

	static def TryParseDouble(isSingle as bool, s as string) as double:
		val as double
		if isSingle:
			val = single.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture)
		else:
			val = double.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture)
		return val

	static def ParseIntegerLiteralExpression(sourceLocation as LexicalInfo, text as string, asLong as bool) as IntegerLiteralExpression:
		try:
			return TryParseIntegerLiteralExpression(sourceLocation, text, asLong)
		except x as System.OverflowException:
			GenericParserError(sourceLocation, x)
			// let the parser continue
			return IntegerLiteralExpression(sourceLocation)

	static def GenericParserError(sourceLocation as LexicalInfo, x as Exception):
		My[of CompilerErrorCollection].Instance.Add(CompilerErrorFactory.GenericParserError(sourceLocation, x))

	static def TryParseIntegerLiteralExpression(sourceLocation as LexicalInfo, text as string, asLong as bool) as IntegerLiteralExpression:
		hexPrefix as string = "0x"

		style as NumberStyles = NumberStyles.Integer | NumberStyles.AllowExponent
		hexStart as int = text.IndexOf(hexPrefix)
		negative as bool = false

		if hexStart >= 0:
			if text.StartsWith("-"):
				negative = true
			text = text.Substring(hexStart + hexPrefix.Length)
			style = NumberStyles.HexNumber

		value as long = long.Parse(RemoveLongSuffix(text), style, CultureInfo.InvariantCulture)
		if negative:
			//negative hex number
			value *= -1
		return IntegerLiteralExpression(sourceLocation, value, asLong  or  (value > int.MaxValue  or  value < int.MinValue))

	static def RemoveLongSuffix(s as string) as string:
		if s.EndsWith("l")  or  s.EndsWith("L"):
			return s.Substring(0, s.Length - 1)
		return s

	static def ParseInt(node as Antlr4.Runtime.Tree.ITerminalNode) as int:
		return cast(int, ParseIntegerLiteralExpression( SourceLocationFactory.ToLexicalInfo(node.Symbol), node.GetText(), false).Value)


