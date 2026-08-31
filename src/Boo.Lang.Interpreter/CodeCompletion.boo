namespace Boo.Lang.Interpreter

import Boo.Lang.Compiler.Ast
import Boo.Lang.Compiler.Steps
import Boo.Lang.Compiler.TypeSystem
import Boo.Lang.Compiler.TypeSystem.Services

class FindCodeCompleteSuggestion(AbstractVisitorCompilerStep):
"""
Resolves the marker left where the cursor was.

The code handed to the compiler has the name being typed replaced by the
marker, so binding it says what the thing before the dot is, and that is what
the suggestions come from.
"""

	public static final Marker = "__codecomplete__"

	override def Run():
		Visit(CompileUnit)

	override def LeaveMemberReferenceExpression(node as MemberReferenceExpression):
		if Marker == node.Name:
			suggestion as IEntity
			target = node.Target
			if target.ExpressionType is not null:
				suggestion = target.ExpressionType
			else:
				suggestion = TypeSystemServices.GetOptionalEntity(target)
			if suggestion is not null and suggestion.EntityType != EntityType.Error:
				_context["suggestion"] = suggestion
				// TODO: use target to display static members only for type reference expressions
				_context["target"] = target

class CodeCompletion:
"""What is worth offering for an entity the marker resolved to."""

	static def SuggestionsFor(entity as IEntity, namespacesOnly as bool) as (IEntity):
		ns = entity as INamespace
		return array(IEntity, 0) if ns is null
		return ChildNamespaces(ns) if namespacesOnly
		return Members(MemberCollector.CollectAllMembers(ns))

	static def Members(members as (IEntity)) as (IEntity):
		return array(
				item
				for item in members
				unless IsSpecial(item) or not IsPublic(item))

	static def ChildNamespaces(parent as INamespace) as (IEntity):
		return array(member
					for member in parent.GetMembers()
					if member.EntityType == EntityType.Namespace)

	static def IsSpecial(entity as IEntity) as bool:
		for prefix in ".", "___", "add_", "remove_", "raise_", "get_", "set_", "<":
			return true if entity.Name.StartsWith(prefix)
		return false

	static def IsPublic(entity as IEntity) as bool:
		member = entity as IMember
		return member is null or member.IsPublic
