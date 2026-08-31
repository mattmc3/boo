namespace Boo.Lang.Lsp.Workspace

import System.Collections.Generic
import Boo.Lang.Compiler.TypeSystem

class Signatures:
"""How an entity is written for a person to read."""

	static def Of(name as string, entity as IEntity) as string:
		method = entity as IMethod
		return "def ${name}(${Parameters(method)}) as ${method.ReturnType}" if method is not null

		type = entity as IType
		return "${KindOf(type)} ${type}" if type is not null

		typed = entity as ITypedEntity
		return "${name} as ${typed.Type}" if typed is not null

		return "namespace ${name}" if entity.EntityType == EntityType.Namespace
		return name

	class Overload:
	"""One way a method can be called."""
		public Label as string
		public Parameters as List[of string]

	static def OverloadsOf(name as string, entity as IEntity) as List[of Overload]:
	"""
	Every way the name can be called, or none if it is not a method.

	Written with the wrong number of arguments a call resolves to no single
	method but to the whole group, and that is exactly when every way of
	calling it is worth showing.
	"""
		overloads = List[of Overload]()
		Collect(overloads, name, entity)
		return overloads

	private static def Collect(overloads as List[of Overload], name as string, entity as IEntity):
		method = entity as IMethod
		if method is not null:
			overloads.Add(Overload(Label: Of(name, method), Parameters: ParametersOf(method)))
			return
		group = entity as Ambiguous
		return if group is null
		for candidate in group.Entities:
			Collect(overloads, name, candidate)

	static def ParametersOf(entity as IEntity) as List[of string]:
	"""
	Each parameter of a method, written as it reads in the signature.

	Anything that is not a method takes none, and answers with an empty list
	rather than nothing, so a caller can ask without checking first.
	"""
		written = List[of string]()
		method = entity as IMethod
		return written if method is null
		for parameter in method.GetParameters():
			written.Add("${parameter.Name} as ${parameter.Type}")
		return written

	private static def Parameters(method as IMethod) as string:
		return string.Join(", ", ParametersOf(method).ToArray())

	private static def KindOf(type as IType) as string:
		return "interface" if type.IsInterface
		return "enum" if type.IsEnum
		return "struct" if type.IsValueType
		return "class"
