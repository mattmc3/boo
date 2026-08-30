# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of OperatorParser. Not compiled by Boo.Lang.Parser, which is C#;
# it pairs with the Boo the ANTLR Boo target emits, and is checked by
# tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import System
import Boo.Lang.Compiler.Ast

public class OperatorParser:

	public static def ParseComparison(op as string) as BinaryOperatorType:
		if op == "<=":
			return BinaryOperatorType.LessThanOrEqual
		elif op == ">=":
			return BinaryOperatorType.GreaterThanOrEqual
		elif op == "==":
			return BinaryOperatorType.Equality
		elif op == "!=":
			return BinaryOperatorType.Inequality
		elif op == "=~":
			return BinaryOperatorType.Match
		elif op == "!~":
			return BinaryOperatorType.NotMatch
		raise ArgumentException(op, "op")

	public static def ParseCondAssignment(op as string) as BinaryOperatorType:
		if op == "=":
			return BinaryOperatorType.Assign
		elif op == "|=":
			return BinaryOperatorType.InPlaceBitwiseOr
		elif op == "^=":
			return BinaryOperatorType.InPlaceExclusiveOr
		elif op == "&=":
			return BinaryOperatorType.InPlaceBitwiseAnd
		elif op == "<<=":
			return BinaryOperatorType.InPlaceShiftLeft
		elif op == ">>=":
			return BinaryOperatorType.InPlaceShiftRight
		raise ArgumentException(op, "op")

	public static def ParseAssignment(op as string) as BinaryOperatorType:
		if op == "=":
			return BinaryOperatorType.Assign
		elif op == "+=":
			return BinaryOperatorType.InPlaceAddition
		elif op == "-=":
			return BinaryOperatorType.InPlaceSubtraction
		elif op == "/=":
			return BinaryOperatorType.InPlaceDivision
		elif op == "*=":
			return BinaryOperatorType.InPlaceMultiply
		elif op == "%=":
			return BinaryOperatorType.InPlaceModulus
		raise ArgumentException(op, "op")
