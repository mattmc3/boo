# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of BooParser, holding the helpers BooParser.g4's predicates
# call. Not compiled by Boo.Lang.Parser, which is C#; it pairs with the Boo
# the ANTLR Boo target emits. See tools/antlr-boo-target/README.md.
#
namespace Boo.Lang.Parser

import System
import System.IO
import Antlr4.Runtime
import Antlr4.Runtime.Atn
import Antlr4.Runtime.Misc
import Boo.Lang.Compiler.Ast
import Boo.Lang.Parser.Util

# The C# half declares this beside BooParser, so it lives here too.
public callable ParserErrorHandler(recognizer as IRecognizer, offendingSymbol as IToken, filename as string, line as int, charPositionInLine as int, msg as string, e as RecognitionException)

partial class BooParser:

	private def IsNegativeLongLiteral() as bool:
		return InputStream.LA(1) == SUBTRACT and InputStream.LA(2) == LONG

	private static def IsValidMacroArgument(tokenType as int) as bool:
		return LPAREN != tokenType and LBRACK != tokenType and DOT != tokenType and MULTIPLY != tokenType

	protected def IsValidClosureMacroArgument(tokenType as int) as bool:
		return IsValidMacroArgument(tokenType) and SUBTRACT != tokenType

	public static def ParseReader(settings as ParserSettings, readerName as string, reader as TextReader) as CompileUnit:
		cu = CompileUnit()
		ParseModule(settings, cu, readerName, reader)
		return cu

	public static def ParseReader(readerName as string, reader as TextReader, eh as ParserErrorHandler) as CompileUnit:
		return ParseReader(ParserSettings(ErrorHandler: eh), readerName, reader)

	public static def ParseString(name as string, text as string) as CompileUnit:
		return ParseReader(name, StringReader(text), null)

	public static def ParseModule(settings as ParserSettings, cu as CompileUnit, readerName as string, reader as TextReader) as Module:
		if Readers.IsEmpty(reader):
			emptyModule = Module(LexicalInfo(readerName), CodeFactory.ModuleNameFrom(readerName))
			cu.Modules.Add(emptyModule)
			return emptyModule

		stream = AntlrInputStream(reader)
		tree as BooParser.StartContext

		# Two stage parsing: SLL is faster but rejects some input the full LL
		# mode accepts, so the first stage bails and the caller retries in LL.
		try:
			tree = CreateParser(settings.TabSize, readerName, stream, true, null).start()
		except as ParseCanceledException:
			stream.Seek(0)
			tree = CreateParser(settings.TabSize, readerName, stream, false, settings.ErrorHandler).start()

		visitor = BooParserAstBuilderVisitor(cu, readerName)
		module = visitor.VisitStart(tree)
		module.Name = CodeFactory.ModuleNameFrom(readerName)
		return module

	public static def CreateParser(readerName as string, stream as ICharStream, firstStage as bool, eh as ParserErrorHandler) as BooParser:
		return CreateParser(ParserSettings.DefaultTabSize, readerName, stream, firstStage, eh)

	public static def CreateParser(tabSize as int, readerName as string, stream as ICharStream, firstStage as bool, eh as ParserErrorHandler) as BooParser:
		booLexer = BooLexer(stream, TokenFactory: BooToken.CreateTokenFactory(tabSize))
		# A lexer of its own reports to the console, so an unterminated string
		# would never reach the compiler.
		if eh is not null:
			booLexer.RemoveErrorListeners()
			booLexer.AddErrorListener(BooLexerErrorListener(eh, readerName))

		filter = IndentTokenStreamFilter(booLexer, BooLexer.WS, BooLexer.NEWLINE,
			BooLexer.INDENT, BooLexer.DEDENT, BooLexer.EOL, BooLexer.END, BooLexer.ID)
		parser = BooParser(CommonTokenStream(filter))

		if firstStage:
			parser.Interpreter.PredictionMode = PredictionMode.SLL
			parser.ErrorHandler = BailErrorStrategy()
		else:
			parser.Interpreter.PredictionMode = PredictionMode.LL
			parser.ErrorHandler = DefaultErrorStrategy()

		parser.BuildParseTree = true
		# Always drop ANTLR's console listener. A null handler means this stage
		# reports nothing, which is what the SLL pass wants.
		parser.RemoveErrorListeners()
		parser.AddErrorListener(BooErrorListener(eh, readerName)) if eh is not null
		return parser

	public static def ParseFile(fname as string) as CompileUnit:
		return ParseFile(ParserSettings(), fname)

	public static def ParseFile(settings as ParserSettings, fname as string) as CompileUnit:
		raise ArgumentNullException("fname") if fname is null
		# `using` is a macro from Boo.Lang.Extensions, which the parser does not
		# reference, so the disposal is written out.
		reader = File.OpenText(fname)
		try:
			return ParseReader(settings, fname, reader)
		ensure:
			reader.Dispose()

	public static def ParseExpression(name as string, text as string) as Expression:
		parser = CreateParser(name, AntlrInputStream(text), false, null)
		expr = parser.expression()
		return BooParserAstBuilderVisitor(CompileUnit(), name).VisitExpression(expr)
