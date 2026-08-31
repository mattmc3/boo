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

	private static def Parameters(method as IMethod) as string:
		written = List[of string]()
		for parameter in method.GetParameters():
			written.Add("${parameter.Name} as ${parameter.Type}")
		return string.Join(", ", written.ToArray())

	private static def KindOf(type as IType) as string:
		return "interface" if type.IsInterface
		return "enum" if type.IsEnum
		return "struct" if type.IsValueType
		return "class"
