namespace Boo.Lang.Lsp.Workspace

import System
import System.Collections.Generic
import Boo.Lang.Compiler
import Boo.Lang.Compiler.IO
import Boo.Lang.Compiler.Pipelines
import Boo.Lang.Compiler.TypeSystem
import Boo.Lang.Environments
import Boo.Lang.Interpreter

class Completion:
"""
Suggests what could follow the cursor.

The trick is the interpreter's: put a marker where the name being typed is,
bind the file, and see what the marker resolved against. That answers the
question the parser cannot, which is what the thing before the dot actually
is.

Only what follows a dot is offered, and after an import only namespaces. A
bare identifier would need the locals in scope, which is a different question
and is not answered here.
"""

	public static final Method = 2
	public static final Constructor = 4
	public static final Field = 5
	public static final Variable = 6
	public static final Class = 7
	public static final Interface = 8
	public static final Module = 9
	public static final Property = 10
	public static final Enum = 13
	public static final Event = 23

	static final Nothing = List[of object]()

	def At(document as TextDocument, position as Position) as List[of object]:
		request = Request.For(document, position)
		return List[of object]() if request is null

		context = Bind(document.Uri, request.Text)
		return List[of object]() if context is null

		items = List[of object]()
		# Collecting members resolves types lazily, so it shares the gate.
		lock CompilerLock.Gate:
			ActiveEnvironment.With(context.Environment) do:
				suggestion = context["suggestion"] as IEntity
				return if suggestion is null
				items = Gather(CodeCompletion.SuggestionsFor(suggestion, request.NamespacesOnly))
		return items

	private static def Gather(entities as (IEntity)) as List[of object]:
	"""
	One entry per name.

	Overloads and namespaces that several assemblies contribute to arrive as
	separate entities under the same name, and a list that says Compare four
	times helps nobody.
	"""
		counts = Dictionary[of string, int]()
		first = Dictionary[of string, IEntity]()
		order = List[of string]()

		for entity in entities:
			name = entity.Name
			unless counts.ContainsKey(name):
				counts[name] = 0
				first[name] = entity
				order.Add(name)
			counts[name] = counts[name] + 1

		items = List[of object]()
		for name in order:
			items.Add(Item(first[name], counts[name]))
		return items

	private def Bind(uri as string, text as string) as CompilerContext:
		pipeline = ResolveExpressions(BreakOnErrors: false)
		pipeline.Add(FindCodeCompleteSuggestion())

		try:
			lock CompilerLock.Gate:
				compiler = BooCompiler()
				compiler.Parameters.Pipeline = pipeline
				compiler.Parameters.Input.Add(StringInput(uri, text))
				return compiler.Run()
		except e as Exception:
			Console.Error.WriteLine("boolsp: completing ${uri} failed: ${e.Message}")
			return null

	private static def Item(entity as IEntity, sharing as int) as Dictionary[of string, object]:
		detail = Signatures.Of(entity.Name, entity)
		detail += "  (${sharing} overloads)" if sharing > 1

		item = Dictionary[of string, object]()
		item["label"] = entity.Name
		item["kind"] = KindOf(entity)
		item["detail"] = detail
		return item

	private static def KindOf(entity as IEntity) as int:
		kind = entity.EntityType
		return Method if kind == EntityType.Method
		return Constructor if kind == EntityType.Constructor
		return Field if kind == EntityType.Field
		return Property if kind == EntityType.Property
		return Event if kind == EntityType.Event
		return Module if kind == EntityType.Namespace
		return TypeKindOf(entity) if kind == EntityType.Type
		return Variable

	private static def TypeKindOf(entity as IEntity) as int:
		type = entity as IType
		return Class if type is null
		return Interface if type.IsInterface
		return Enum if type.IsEnum
		return Class

	private class Request:
	"""The text to bind, with the marker in place of what is being typed."""

		public final Text as string
		public final NamespacesOnly as bool

		def constructor(text as string, namespacesOnly as bool):
			Text = text
			NamespacesOnly = namespacesOnly

		static def For(document as TextDocument, position as Position) as Request:
			line = document.LineText(position.Line)
			at = position.Character
			return null if at > line.Length

			start = at
			start-- while start > 0 and IsWordCharacter(line[start - 1])

			# Only a member access has something to resolve against.
			return null if start == 0 or line[start - 1] != char('.')

			replaced = line.Substring(0, start) + FindCodeCompleteSuggestion.Marker + line.Substring(at)
			# An import line is a namespace path, not an expression, so the
			# keyword comes off before the compiler sees it.
			trimmed = replaced.TrimStart()
			if trimmed.StartsWith("import "):
				indent = replaced.Substring(0, replaced.Length - trimmed.Length)
				return Request(Replace(document, position.Line, indent + trimmed.Substring(7)), true)
			return Request(Replace(document, position.Line, replaced), false)

		private static def Replace(document as TextDocument, line as int, text as string) as string:
			lines = List[of string](document.Text.Split((char('\n'),)))
			return document.Text if line >= lines.Count
			lines[line] = text.TrimEnd(char('\r'))
			return string.Join("\n", lines.ToArray())

		private static def IsWordCharacter(c as char) as bool:
			return char.IsLetterOrDigit(c) or c == char('_')
