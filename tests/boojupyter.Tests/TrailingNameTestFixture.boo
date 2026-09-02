#region license
// Copyright (c) 2026 the Boo contributors
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

namespace boojupyter.Tests

import NUnit.Framework
import Boo.Lang.Compiler.Ast
import Boo.Lang.Parser
import boojupyter

# A name on a line of its own parses as a macro invocation, which is what the
# kernel has to undo so the last line of a cell reads as its value.
[TestFixture]
class TrailingNameTestFixture:

	private def Parse(code as string) as CompileUnit:
		return BooParser.ParseString("cell", code)

	private def Rewrite(code as string) as Statement:
		unit = Parse(code)
		BooKernel.RewriteTrailingName(unit)
		statements = unit.Modules[0].Globals.Statements
		return statements[-1]

	[Test]
	def ATrailingNameBecomesAReference():
		last = Rewrite("foo = 'bar'\nfoo")
		expression = last as ExpressionStatement
		Assert.IsNotNull(expression)
		reference = expression.Expression as ReferenceExpression
		Assert.IsNotNull(reference)
		Assert.AreEqual("foo", reference.Name)

	[Test]
	def ANameIsLeftAloneWhenItIsTheWholeCell():
		# The interpreter has its own fix-up for a single statement.
		Assert.IsTrue(Rewrite("foo") isa MacroStatement)

	[Test]
	def AMacroWithArgumentsIsLeftAlone():
		Assert.IsTrue(Rewrite("x = 1\nprint x") isa MacroStatement)

	[Test]
	def AMacroWithABodyIsLeftAlone():
		Assert.IsTrue(Rewrite("x = 1\nlock x:\n\tpass") isa MacroStatement)

	[Test]
	def AStatementThatIsNotAMacroIsLeftAlone():
		last = Rewrite("x = 1\nx + 1")
		expression = last as ExpressionStatement
		Assert.IsNotNull(expression)
		Assert.IsTrue(expression.Expression isa BinaryExpression)

	[Test]
	def AnEmptyUnitIsLeftAlone():
		BooKernel.RewriteTrailingName(CompileUnit())
