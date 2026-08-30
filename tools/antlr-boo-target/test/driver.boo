import System
import System.Collections.Generic
import Antlr4.Runtime
import Toy

class Eval(CalcBaseVisitor[of int]):
	memory as Dictionary[of string, int] = Dictionary[of string, int]()

	override def VisitPrintExpr(context as CalcParser.PrintExprContext) as int:
		print Visit(context.expr())
		return 0

	override def VisitAssign(context as CalcParser.AssignContext) as int:
		value = Visit(context.expr())
		memory[context.ID().GetText()] = value
		return value

	override def VisitInt(context as CalcParser.IntContext) as int:
		return int.Parse(context.INT().GetText())

	override def VisitId(context as CalcParser.IdContext) as int:
		name = context.ID().GetText()
		return (memory[name] if memory.ContainsKey(name) else 0)

	override def VisitMulDiv(context as CalcParser.MulDivContext) as int:
		left = Visit(context.expr(0))
		right = Visit(context.expr(1))
		return (left * right if context.op.Type == CalcParser.MUL else left / right)

	override def VisitAddSub(context as CalcParser.AddSubContext) as int:
		left = Visit(context.expr(0))
		right = Visit(context.expr(1))
		return (left + right if context.op.Type == CalcParser.ADD else left - right)

	override def VisitParens(context as CalcParser.ParensContext) as int:
		return Visit(context.expr())

source = "1 + 2 * 3\n(1 + 2) * 3\na = 5\na * 2 - 1\n"
lexer = CalcLexer(AntlrInputStream(source))
parser = CalcParser(CommonTokenStream(lexer))
tree = parser.prog()
print "errors: ${parser.NumberOfSyntaxErrors}"
Eval().Visit(tree)
