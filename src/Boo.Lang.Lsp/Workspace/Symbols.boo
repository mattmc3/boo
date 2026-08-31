namespace Boo.Lang.Lsp.Workspace

import System.Collections.Generic

class Symbols:
"""
Builds the outline of a document from its parsed module.

Two places have to be walked, not one. A def written before any module level
code is a member of the module; the same def written after it parses as a
declaration in the module's globals, holding a closure. Walking only the
members loses every function below the first statement in a script.
"""

	public static final Module = 2
	public static final Class = 5
	public static final Method = 6
	public static final Property = 7
	public static final Field = 8
	public static final Constructor = 9
	public static final Enum = 10
	public static final Interface = 11
	public static final Function = 12
	public static final EnumMember = 22
	public static final Struct = 23
	public static final Event = 24

	static def Of(document as TextDocument, module as Boo.Lang.Compiler.Ast.Module) as List[of object]:
		symbols = List[of object]()
		return symbols if module is null

		for member in module.Members:
			symbol = FromMember(document, member, Function)
			symbols.Add(symbol) if symbol is not null

		for statement in module.Globals.Statements:
			symbol = FromGlobal(document, statement)
			symbols.Add(symbol) if symbol is not null

		return symbols

	private static def FromGlobal(document as TextDocument, statement as Boo.Lang.Compiler.Ast.Statement) as Dictionary[of string, object]:
	"""A def below module level code, which parses as a closure declaration."""
		declaration = statement as Boo.Lang.Compiler.Ast.DeclarationStatement
		return null if declaration is null
		return null unless declaration.Initializer isa Boo.Lang.Compiler.Ast.BlockExpression
		return Build(document, declaration.Declaration.Name, Function, statement, null)

	private static def FromMember(document as TextDocument, member as Boo.Lang.Compiler.Ast.TypeMember, methodKind as int) as Dictionary[of string, object]:
		kind = KindOf(member, methodKind)
		return null if kind == 0

		type = member as Boo.Lang.Compiler.Ast.TypeDefinition
		children as List[of object]
		if type is not null:
			children = List[of object]()
			for nested in type.Members:
				# A method on a type is a method; only module level defs are
				# free functions.
				child = FromMember(document, nested, Method)
				children.Add(child) if child is not null

		return Build(document, member.Name, kind, member, children)

	private static def KindOf(member as Boo.Lang.Compiler.Ast.TypeMember, methodKind as int) as int:
		return Class if member isa Boo.Lang.Compiler.Ast.ClassDefinition
		return Struct if member isa Boo.Lang.Compiler.Ast.StructDefinition
		return Interface if member isa Boo.Lang.Compiler.Ast.InterfaceDefinition
		return Enum if member isa Boo.Lang.Compiler.Ast.EnumDefinition
		return EnumMember if member isa Boo.Lang.Compiler.Ast.EnumMember
		return Constructor if member isa Boo.Lang.Compiler.Ast.Constructor
		return methodKind if member isa Boo.Lang.Compiler.Ast.Method
		return Property if member isa Boo.Lang.Compiler.Ast.Property
		return Field if member isa Boo.Lang.Compiler.Ast.Field
		return Event if member isa Boo.Lang.Compiler.Ast.Event
		return 0

	private static def Build(document as TextDocument, name as string, kind as int, node as Boo.Lang.Compiler.Ast.Node, children as List[of object]) as Dictionary[of string, object]:
		start = Positions.FromLexicalInfo(document, node.LexicalInfo)
		symbol = Dictionary[of string, object]()
		symbol["name"] = name
		symbol["kind"] = kind
		symbol["range"] = Diagnostic.Range(start, EndOf(document, node, start))
		symbol["selectionRange"] = SelectionOf(document, name, start)
		symbol["children"] = children if children is not null
		return symbol

	private static def EndOf(document as TextDocument, node as Boo.Lang.Compiler.Ast.Node, start as Position) as Position:
		finish = node.EndSourceLocation
		return Position(start.Line, document.LineText(start.Line).Length) unless finish.IsValid
		return Positions.FromLexicalInfo(document, finish)

	private static def SelectionOf(document as TextDocument, name as string, start as Position) as Dictionary[of string, object]:
	"""
	The range covering the name itself.

	A type member is pointed at its name, but a def below module level code is
	pointed at its keyword, so the name is looked up in the line rather than
	assumed to sit at the start.
	"""
		return Diagnostic.Range(start, start) if string.IsNullOrEmpty(name)
		at = document.LineText(start.Line).IndexOf(name, start.Character)
		return Diagnostic.Range(start, start) if at < 0
		return Diagnostic.Range(Position(start.Line, at), Position(start.Line, at + name.Length))
