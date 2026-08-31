namespace Boo.Lang.Lsp.Workspace

import System
import System.Collections.Generic
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Compiler.IO
import Boo.Lang.Compiler.Pipelines

class Analyzer:
"""
Runs a document through the compiler and reports what it complains about.

Two tiers, because they cost very differently. Parsing a large file takes
about twenty milliseconds and can run on every keystroke; binding costs tens
of milliseconds for one file and grows with the size of the project, so it
belongs behind a longer debounce.

Binding reports errors only. Warnings such as an unused import come out of the
full Compile pipeline, which emits IL; whether the server pays that to report
them is a question for later.

The compiler is not reentrant, so one analyzer serves one caller at a time.
"""

	def Parse(document as TextDocument) as List[of object]:
		return Run(document, Pipelines.Parse(BreakOnErrors: false))

	def Bind(document as TextDocument) as List[of object]:
		return Run(document, Pipelines.ResolveExpressions(BreakOnErrors: false))

	def ParseTree(document as TextDocument) as Module:
	"""
	The module as parsed, or null if the compiler could not produce one.

	The text is balanced first: half typed brackets cost the parser the whole
	structure below them, and an outline is wanted most while the file is
	still being written. Only the parse sees the repaired text.
	"""
		context = CompileText(document.Uri, BracketRepair.Repair(document.Text), Pipelines.Parse(BreakOnErrors: false))
		return null if context is null
		return null if context.CompileUnit.Modules.Count == 0
		return context.CompileUnit.Modules[0]

	def Bound(document as TextDocument) as CompilerContext:
	"""
	The document bound far enough to carry entities, or null.

	Every caller pays a full bind. Caching one per document is what M8 is for.
	"""
		return Compile(document, Pipelines.ResolveExpressions(BreakOnErrors: false))

	private def Run(document as TextDocument, pipeline as CompilerPipeline) as List[of object]:
		context = Compile(document, pipeline)
		return List[of object]() if context is null
		return Report(document, context)

	private def Compile(document as TextDocument, pipeline as CompilerPipeline) as CompilerContext:
		return CompileText(document.Uri, document.Text, pipeline)

	private def CompileText(uri as string, text as string, pipeline as CompilerPipeline) as CompilerContext:
		try:
			lock CompilerLock.Gate:
				compiler = BooCompiler()
				compiler.Parameters.Pipeline = pipeline
				compiler.Parameters.Input.Add(StringInput(uri, text))
				return compiler.Run()
		except e as Exception:
			# A compiler that fell over is a bug, but a server that stops
			# answering because of one is worse.
			Console.Error.WriteLine("boolsp: analyzing ${uri} failed: ${e.Message}")
			return null

	private def Report(document as TextDocument, context as CompilerContext) as List[of object]:
		diagnostics = List[of object]()
		for error in context.Errors:
			diagnostics.Add(Diagnostic.FromError(document, error))
		for warning in context.Warnings:
			diagnostics.Add(Diagnostic.FromWarning(document, warning))
		return diagnostics
