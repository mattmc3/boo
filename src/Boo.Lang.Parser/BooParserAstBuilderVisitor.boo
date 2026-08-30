# The Boo half of this file. Not compiled by Boo.Lang.Parser, which is C#; it
# pairs with the Boo the ANTLR Boo target emits, and is checked against the C#
# parser by tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser

import System
import System.Collections.Generic
import System.Globalization
import System.Linq
import System.Text
import Antlr4.Runtime
import Antlr4.Runtime.Tree
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Environments

internal class BooParserAstBuilderVisitor(AbstractParseTreeVisitor[of Node], IBooParserVisitor[of Node]):
	_compileUnit as CompileUnit
	_module as Module
	_filename as string
	_sbuilder as StringBuilder = StringBuilder()

	_macroStatement as ParseTreeProperty[of MacroStatement] = ParseTreeProperty[of MacroStatement]()
	_node as ParseTreeProperty[of Node] = ParseTreeProperty[of Node]()
	_import as ParseTreeProperty[of Import] = ParseTreeProperty[of Import]()

	def constructor(compileUnit as CompileUnit, filename as string):
		if compileUnit == null:
			raise ArgumentNullException("compileUnit")

		_compileUnit = compileUnit
		_module = Module()
		_filename = filename
		_module.Name = System.IO.Path.GetFileNameWithoutExtension(_filename)

	FileName as string:
		get:
			return _filename

	def GetLexicalInfo(st as IToken) as LexicalInfo:
		return LexicalInfo(FileName, st.Line, st.Column)

	def GetLexicalInfo(ctx as ParserRuleContext) as LexicalInfo:
		if ctx == null  or  ctx.Start == null:
			return LexicalInfo.Empty

		st as IToken = ctx.Start
		return LexicalInfo(FileName, st.Line, st.Column)

	def GetLexicalInfo(tn as ITerminalNode) as LexicalInfo:
		if tn == null:
			return LexicalInfo.Empty

		sym as IToken = tn.Symbol
		return LexicalInfo(FileName, sym.Line, sym.Column)

	/// <summary>
	/// A literal run inside an interpolated string is anchored on the delimiter
	/// in front of it, the opening quote or the brace that closed the previous
	/// hole, which is where boo.g's sub-lexer left it.
	/// </summary>
	def GetInterpolatedSegmentLexicalInfo(tn as ITerminalNode) as LexicalInfo:
		sym as IToken = tn.Symbol
		return LexicalInfo(FileName, sym.Line, sym.Column - 1)

	/// <summary>
	/// Gathers the literal text between two holes of an interpolated string
	/// into one StringLiteralExpression, anchored on the delimiter in front of
	/// it.
	///
	/// A run with no text produces no node. boo.g emits one, because it lexes
	/// runs as string tokens between imaginary separators and leaves an empty
	/// token wherever a hole meets a quote or another hole.
	/// </summary>
	internal class InterpolationRun:
		_owner as BooParserAstBuilderVisitor
		_target as ExpressionInterpolationExpression
		_text as StringBuilder = StringBuilder()
		_start as LexicalInfo
		_delimiter as LexicalInfo

		def constructor(owner as BooParserAstBuilderVisitor, target as ExpressionInterpolationExpression):
			_owner = owner
			_target = target

		def DelimitedBy(node as ITerminalNode, atEnd as bool):
			symbol = node.Symbol
			column =(symbol.Column + (symbol.StopIndex - symbol.StartIndex) if atEnd else symbol.Column)
			_delimiter = LexicalInfo(_owner.FileName, symbol.Line, column)

		def Append(node as ITerminalNode, text as string):
			if _start == null:
				_start = _owner.GetInterpolatedSegmentLexicalInfo(node)

			_text.Append(text)

		def Flush():
			if _text.Length == 0:
				return

			_target.Expressions.Add(StringLiteralExpression((_start if _start is not null else _delimiter), _text.ToString()))
			_text.Length = 0
			_start = null

		def FlushLast():
			Flush()

	def SetEndSourceLocation(node as Node, token as ITerminalNode):
		if node == null  or  token == null:
			return
		SetEndSourceLocation(node, token.Symbol)

	def SetEndSourceLocation(node as Node, token as IToken):
		node.EndSourceLocation = Boo.Lang.Parser.SourceLocationFactory.ToEndSourceLocation(token)

	/// <summary>
	/// Ends a node on a token's own position rather than the end of its text,
	/// which is what boo.g does for the tokens it manufactures.
	/// </summary>
	def SetEndSourceLocationAt(node as Node, token as ITerminalNode):
		if node == null  or  token == null:
			return
		node.EndSourceLocation = Boo.Lang.Parser.SourceLocationFactory.ToSourceLocation(token.Symbol)

	/// <summary>
	/// A block bearing construct ends at the DEDENT that closed it, taken as
	/// the token's own position rather than the end of its text.
	/// </summary>
	def SetEndSourceLocation(node as Node, context as BooParser.Empty_blockContext):
		if context != null:
			SetEndSourceLocation(node, context.end_())

	def SetEndSourceLocation(node as Node, context as BooParser.EndContext):
		if node == null  or  context == null:
			return

		if context.DEDENT() == null:
			return

		node.EndSourceLocation = Boo.Lang.Parser.SourceLocationFactory.ToSourceLocation(context.DEDENT().Symbol)

	def MemberReferenceForToken(target as Expression, memberName as ITerminalNode) as MemberReferenceExpression:
		if memberName == null:
			return null

		mre as MemberReferenceExpression = MemberReferenceExpression(GetLexicalInfo(memberName))
		mre.Target = target
		mre.Name = memberName.GetText()
		return mre

	def OutsideCompilationEnvironment() as bool:
		return ActiveEnvironment.Instance == null

	def EmitWarning(warning as CompilerWarning):
		My[of CompilerWarningCollection].Instance.Add(warning)

	virtual def EmitTransientKeywordDeprecationWarning(location as LexicalInfo):
		if OutsideCompilationEnvironment():
			return
		EmitWarning( CompilerWarningFactory.ObsoleteSyntax( location, "transient keyword", "[Transient] attribute"))

	def EmitError(error as CompilerError):
		My[of CompilerErrorCollection].Instance.Add(error)

	virtual def EmitDuplicateAccessorError(location as LexicalInfo, accessor as string):
		if OutsideCompilationEnvironment():
			return
		EmitError( CompilerErrorFactory.GenericParserError( location, Exception(string.Format(Boo.Lang.Resources.StringResources.BooParser_DuplicateAccessor, accessor))))

	virtual def EmitParamAfterVarargsError(location as LexicalInfo):
		if OutsideCompilationEnvironment():
			return
		EmitError( CompilerErrorFactory.GenericParserError( location, Exception("No more args are allowed after an exploded arg")))

	def FormatPropertyWithDelimiters(deprecated as Property, leftDelimiter as string, rightDelimiter as string) as string:
		return deprecated.Name + leftDelimiter + Builtins.join(deprecated.Parameters, ", ") + rightDelimiter

	virtual def EmitIndexedPropertyDeprecationWarning(deprecated as Property):
		if OutsideCompilationEnvironment():
			return
		EmitWarning( CompilerWarningFactory.ObsoleteSyntax( deprecated, FormatPropertyWithDelimiters(deprecated, "(", ")"), FormatPropertyWithDelimiters(deprecated, "[", "]")))

	def VisitStart(context as BooParser.StartContext) as Module:
		if context == null:
			return null

		_module.LexicalInfo = LexicalInfo(FileName, 1, 1)
		_compileUnit.Modules.Add(_module)

		VisitChildren(context)

		SetEndSourceLocation(_module, context.Eof())

		return _module

	def IBooParserVisitor[of Node].VisitStart(context as BooParser.StartContext) as Node:
		return VisitStart(context)

	def VisitParse_module(context as BooParser.Parse_moduleContext, m as Module):
		CheckDocumentation(m, context.docstring())
		if context.namespace_directive() != null:
			m.Namespace = VisitNamespace_directive(context.namespace_directive())
		for imp in context.import_directive():
			added = VisitImport_directive(imp)
			if added != null:
				m.Imports.Add(added)
		if context.type_member() != null:
			for tm in context.type_member():
				member = VisitType_member(tm)
				if member != null:
					m.Members.Add(member)
		if context.module_macro() != null:
			for mm in context.module_macro():
				VisitModule_macro(mm, m)
		if context.globals() != null:
			VisitGlobals(context.globals(), m)
		if context.assembly_attribute() != null:
			for aa in context.assembly_attribute():
				VisitAssembly_attribute(aa, m)
		if context.module_attribute() != null:
			for ma in context.module_attribute():
				VisitModule_attribute(ma, m)

	def IBooParserVisitor[of Node].VisitParse_module(context as BooParser.Parse_moduleContext) as Node:
		VisitParse_module(context, _module)
		return null

	def VisitModule_macro(context as BooParser.Module_macroContext, m as Module):
		macroStatement as MacroStatement = VisitMacro_stmt(context.macro_stmt())
		m.Globals.Add(macroStatement)

	def IBooParserVisitor[of Node].VisitModule_macro(context as BooParser.Module_macroContext) as Node:
		VisitModule_macro(context, _module)
		return null

	def VisitDocstring(context as BooParser.DocstringContext):
		if context == null:
			return

		node as Node = _node.Get(context)
		if node == null:
			raise InvalidOperationException()

		VisitChildren(context)

		tqs = context.triple_quoted_string()
		node.Documentation = DocStringFormatter.Format(TqsUnquote(tqs.GetText()))

	def IBooParserVisitor[of Node].VisitDocstring(context as BooParser.DocstringContext) as Node:
		raise NotImplementedException("Should not see self")

	def CheckDocumentation(node as Node, context as BooParser.DocstringContext):
		if context != null  and  context.ChildCount > 0:
			_node.Put(context, node)
			VisitDocstring(context)

	def VisitEos(context as BooParser.EosContext):
		if context == null:
			return

		VisitChildren(context)

	def IBooParserVisitor[of Node].VisitEos(context as BooParser.EosContext) as Node:
		VisitEos(context)
		return null

	def VisitImport_directive(context as BooParser.Import_directiveContext) as Import:
		if context == null:
			return null

		node as Import = null
		if context.import_directive_() != null:
			node = VisitImport_directive_(context.import_directive_())
		else:
			node = VisitImport_directive_from_(context.import_directive_from_())

		return node

	def IBooParserVisitor[of Node].VisitImport_directive(context as BooParser.Import_directiveContext) as Node:
		return VisitImport_directive(context)

	def VisitNamespace_expression(context as BooParser.Namespace_expressionContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitIdentifier_expression(context.identifier_expression())
		if context.expression_list() != null:
			mie = MethodInvocationExpression(result)
			for expr in context.expression_list().expression():
				mie.Arguments.Add(cast(Expression, Visit(expr)))
			result = mie
		return result

	def IBooParserVisitor[of Node].VisitNamespace_expression(context as BooParser.Namespace_expressionContext) as Node:
		return VisitNamespace_expression(context)

	def VisitIdentifier_expression(context as BooParser.Identifier_expressionContext) as Expression:
		if context == null:
			return null

		return ReferenceExpression(GetLexicalInfo(context.identifier().Start), VisitIdentifier(context.identifier()))

	def IBooParserVisitor[of Node].VisitIdentifier_expression(context as BooParser.Identifier_expressionContext) as Node:
		return VisitIdentifier_expression(context)

	def VisitImport_directive_(context as BooParser.Import_directive_Context) as Import:
		if context == null:
			return null

		ns = VisitNamespace_expression(context.namespace_expression())
		Assembly as ReferenceExpression = null
		Alias as ReferenceExpression = null
		if context.FROM() != null:
			text as string
			li as LexicalInfo
			if context.identifier() != null:
				text = context.identifier().GetText()
				li = GetLexicalInfo(context.identifier())
			elif context.SINGLE_QUOTED_STRING() != null:
				text = SqsUnquote(context.SINGLE_QUOTED_STRING().GetText())
				li = GetLexicalInfo(context.SINGLE_QUOTED_STRING())
			else:
				text = DqsUnquote(context.double_quoted_string().GetText())
				li = GetLexicalInfo(context.double_quoted_string())
			Assembly = ReferenceExpression(li, text)
		if context.AS() != null:
			Alias = ReferenceExpression(GetLexicalInfo(context.ID()), context.ID().GetText())
		result = Import(ns, Assembly, Alias)
		result.LexicalInfo = GetLexicalInfo(context.IMPORT())
		return result

	def IBooParserVisitor[of Node].VisitImport_directive_(context as BooParser.Import_directive_Context) as Node:
		return VisitImport_directive_(context)

	def VisitImport_directive_from_(context as BooParser.Import_directive_from_Context) as Import:
		if context == null:
			return null

		expr as Expression = VisitIdentifier_expression(context.identifier_expression())
		if context.MULTIPLY() == null:
			mie = MethodInvocationExpression(expr)
			for sub in context.expression_list().expression():
				mie.Arguments.Add(cast(Expression, Visit(sub)))
			expr = mie
		return Import(GetLexicalInfo(context.FROM()), expr)

	def IBooParserVisitor[of Node].VisitImport_directive_from_(context as BooParser.Import_directive_from_Context) as Node:
		return VisitImport_directive_from_(context)

	def VisitNamespace_directive(context as BooParser.Namespace_directiveContext) as NamespaceDeclaration:
		if context == null:
			return null

		li = GetLexicalInfo(context.NAMESPACE())
		result = NamespaceDeclaration(context.identifier().GetText(), LexicalInfo: li)
		CheckDocumentation(result, context.docstring())
		return result

	def IBooParserVisitor[of Node].VisitNamespace_directive(context as BooParser.Namespace_directiveContext) as Node:
		return VisitNamespace_directive(context)

	def GetModifiers(context as BooParser.ModifiersContext) as TypeMemberModifiers:
		result = TypeMemberModifiers.None
		if context == null:
			return result
		for mod in context.type_member_modifier():
			if mod.Start.Type == BooParser.STATIC:
				result |= TypeMemberModifiers.Static
			elif mod.Start.Type == BooParser.PUBLIC:
				result |= TypeMemberModifiers.Public
			elif mod.Start.Type == BooParser.PROTECTED:
				result |= TypeMemberModifiers.Protected
			elif mod.Start.Type == BooParser.PRIVATE:
				result |= TypeMemberModifiers.Private
			elif mod.Start.Type == BooParser.INTERNAL:
				result |= TypeMemberModifiers.Internal
			elif mod.Start.Type == BooParser.FINAL:
				result |= TypeMemberModifiers.Final
			elif mod.Start.Type == BooParser.TRANSIENT:
				result |= TypeMemberModifiers.Transient
				EmitTransientKeywordDeprecationWarning(GetLexicalInfo(mod))
			elif mod.Start.Type == BooParser.OVERRIDE:
				result |= TypeMemberModifiers.Override
			elif mod.Start.Type == BooParser.ABSTRACT:
				result |= TypeMemberModifiers.Abstract
			elif mod.Start.Type == BooParser.VIRTUAL:
				result |= TypeMemberModifiers.Virtual
			elif mod.Start.Type == BooParser.NEW:
				result |= TypeMemberModifiers.New
			elif mod.Start.Type == BooParser.PARTIAL:
				result |= TypeMemberModifiers.Partial
		return result

	def AddAttributes(value as INodeWithAttributes, context as BooParser.AttributesContext):
		if context != null:
			for attr in context.attribute():
				added = VisitAttribute(attr)
				if added != null:
					value.Attributes.Add(added)

	def AddReturnTypeAttributes(value as CallableDefinition, context as BooParser.AttributesContext):
		if context != null:
			for attr in context.attribute():
				added = VisitAttribute(attr)
				if added != null:
					value.ReturnTypeAttributes.Add(added)

	def VisitType_member(context as BooParser.Type_memberContext) as TypeMember:
		if context == null:
			return null

		result as TypeMember
		if context.type_definition() != null:
			result = VisitType_definition(context.type_definition())
		else:
			result = VisitMethod(context.method())
		if result == null:
			return null
		AddAttributes(result, context.attributes())
		result.Modifiers = GetModifiers(context.modifiers())
		return result

	def IBooParserVisitor[of Node].VisitType_member(context as BooParser.Type_memberContext) as Node:
		return VisitType_member(context)

	def VisitType_definition(context as BooParser.Type_definitionContext) as TypeMember:
		if context == null:
			return null

		if context.class_definition() != null:
			return VisitClass_definition(context.class_definition())
		if context.interface_definition() != null:
			return VisitInterface_definition(context.interface_definition())
		if context.enum_definition() != null:
			return VisitEnum_definition(context.enum_definition())
		return VisitCallable_definition(context.callable_definition())

	def IBooParserVisitor[of Node].VisitType_definition(context as BooParser.Type_definitionContext) as Node:
		return VisitType_definition(context)

	def AddGenericParameters(node as INodeWithGenericParameters, context as BooParser.Generic_parameter_declaration_listContext):
		if context != null:
			for gpd in context.generic_parameter_declaration():
				added = VisitGeneric_parameter_declaration(gpd)
				if added != null:
					node.GenericParameters.Add(added)

	def AddParameters(node as INodeWithParameters, context as BooParser.Parameter_declaration_listContext):
		if context != null:
			va as bool = false
			for pd in context.parameter_declaration():
				if va:
					EmitParamAfterVarargsError(GetLexicalInfo(pd))
				added = VisitParameter_declaration(pd)
				if added != null:
					node.Parameters.Add(added)
				if pd.MULTIPLY() != null:
					va = true
			node.Parameters.HasParamArray = va

	def VisitCallable_definition(context as BooParser.Callable_definitionContext) as CallableDefinition:
		if context == null:
			return null

		result = CallableDefinition(GetLexicalInfo(context.ID()), Name: context.ID().GetText())
		AddGenericParameters(result, context.generic_parameter_declaration_list())
		AddParameters(result, context.parameter_declaration_list())
		if context.type_reference() != null:
			result.ReturnType = VisitType_reference(context.type_reference())
		CheckDocumentation(result, context.docstring())
		return result

	def IBooParserVisitor[of Node].VisitCallable_definition(context as BooParser.Callable_definitionContext) as Node:
		return VisitCallable_definition(context)

	def VisitEnum_definition(context as BooParser.Enum_definitionContext) as EnumDefinition:
		if context == null:
			return null

		result = EnumDefinition(GetLexicalInfo(context.ID()), Name: context.ID().GetText())
		CheckDocumentation(result, context.begin_with_doc().docstring())
		if context.PASS() == null:
			for em in context.any_enum_member():
				member = VisitAny_enum_member(em)
				if member != null:
					result.Members.Add(member)
		SetEndSourceLocation(result, context.end_())
		return result

	def IBooParserVisitor[of Node].VisitEnum_definition(context as BooParser.Enum_definitionContext) as Node:
		return VisitEnum_definition(context)

	def VisitAny_enum_member(context as BooParser.Any_enum_memberContext) as TypeMember:
		if context == null:
			return null

		if context.enum_member() != null:
			return VisitEnum_member(context.enum_member())
		return VisitSplice_type_definition_body(context.splice_type_definition_body())

	def IBooParserVisitor[of Node].VisitAny_enum_member(context as BooParser.Any_enum_memberContext) as Node:
		return VisitAny_enum_member(context)

	def VisitEnum_member(context as BooParser.Enum_memberContext) as EnumMember:
		if context == null:
			return null

		if context.ID() == null:
			return null

		result = EnumMember(GetLexicalInfo(context.ID()), context.ID().GetText())
		if context.simple_initializer() != null:
			result.Initializer = cast(Expression, Visit(context.simple_initializer()))
		AddAttributes(result, context.attributes())
		CheckDocumentation(result, context.docstring())
		return result

	def IBooParserVisitor[of Node].VisitEnum_member(context as BooParser.Enum_memberContext) as Node:
		return VisitEnum_member(context)

	def IBooParserVisitor[of Node].VisitAttributes(context as BooParser.AttributesContext) as Node:
		raise NotImplementedException("Should not see self")

	def ApplyArgumentList(node as INodeWithArguments, context as BooParser.Argument_listContext):
		for arg in context.argument():
			VisitArgument(arg, node)

	def IBooParserVisitor[of Node].VisitArgument_list(context as BooParser.Argument_listContext) as Node:
		raise NotImplementedException()

	def VisitAttribute(context as BooParser.AttributeContext) as Boo.Lang.Compiler.Ast.Attribute:
		if context == null:
			return null

		name as string
		li as LexicalInfo
		if context.TRANSIENT() != null:
			name = context.TRANSIENT().GetText()
			li = GetLexicalInfo(context.TRANSIENT())
		else:
			if context.identifier() == null:
				return null
			name = context.identifier().GetText()
			li = GetLexicalInfo(context.identifier())
		result = Boo.Lang.Compiler.Ast.Attribute(li, name)
		if context.LPAREN() != null:
			ApplyArgumentList(result, context.argument_list())
		return result

	def IBooParserVisitor[of Node].VisitAttribute(context as BooParser.AttributeContext) as Node:
		return VisitAttribute(context)

	def VisitModule_attribute(context as BooParser.Module_attributeContext, m as Module):
		added = VisitAttribute(context.attribute())
		if added != null:
			m.Attributes.Add(added)

	def IBooParserVisitor[of Node].VisitModule_attribute(context as BooParser.Module_attributeContext) as Node:
		VisitModule_attribute(context, _module)
		return null

	def VisitAssembly_attribute(context as BooParser.Assembly_attributeContext, m as Module):
		added = VisitAttribute(context.attribute())
		if added != null:
			m.AssemblyAttributes.Add(added)

	def IBooParserVisitor[of Node].VisitAssembly_attribute(context as BooParser.Assembly_attributeContext) as Node:
		VisitAssembly_attribute(context, _module)
		return null

	def AddBaseTypes(node as TypeDefinition, context as BooParser.Base_typesContext):
		if context != null:
			for bt in context.type_reference():
				added = VisitType_reference(bt)
				if added != null:
					node.BaseTypes.Add(added)

	def VisitClass_definition(context as BooParser.Class_definitionContext) as TypeMember:
		if context == null:
			return null

		result as TypeDefinition
		name as string
		li as LexicalInfo
		nameSplice as Expression = null
		if context.ID() != null:
			name = context.ID().GetText()
			li = GetLexicalInfo(context.ID())
		else:
			if context.SPLICE_BEGIN() == null:
				return null
			nameSplice =(null if context.atom() == null else cast(Expression, Visit(context.atom())))
			name = context.SPLICE_BEGIN().GetText()
			li = GetLexicalInfo(context.SPLICE_BEGIN())
		if context.CLASS() != null:
			result = ClassDefinition(li, Name: name)
		else:
			result = StructDefinition(li, Name: name)
		AddGenericParameters(result, context.generic_parameter_declaration_list())
		AddBaseTypes(result, context.base_types())
		if context.begin_with_doc() != null:
			CheckDocumentation(result, context.begin_with_doc().docstring())
		if context.PASS() == null:
			for tdm in context.any_type_definition_member():
				member = VisitAny_type_definition_member(tdm)
				if member != null:
					result.Members.Add(member)
		SetEndSourceLocation(result, context.end_())
		if nameSplice != null:
			return SpliceTypeMember(result, nameSplice)
		return result

	def IBooParserVisitor[of Node].VisitClass_definition(context as BooParser.Class_definitionContext) as Node:
		return VisitClass_definition(context)

	def VisitAny_type_definition_member(context as BooParser.Any_type_definition_memberContext) as TypeMember:
		if context == null:
			return null

		if context.type_definition_member() != null:
			return VisitType_definition_member(context.type_definition_member())
		return VisitSplice_type_definition_body(context.splice_type_definition_body())

	def IBooParserVisitor[of Node].VisitAny_type_definition_member(context as BooParser.Any_type_definition_memberContext) as Node:
		return VisitAny_type_definition_member(context)

	def VisitSplice_type_definition_body(context as BooParser.Splice_type_definition_bodyContext) as SpliceTypeDefinitionBody:
		if context == null:
			return null

		e = VisitAtom(context.atom())
		// No position of its own in boo.g, so it reports the type definition's.
		return SpliceTypeDefinitionBody(e)

	def IBooParserVisitor[of Node].VisitSplice_type_definition_body(context as BooParser.Splice_type_definition_bodyContext) as Node:
		return VisitSplice_type_definition_body(context)

	def VisitType_definition_member(context as BooParser.Type_definition_memberContext) as TypeMember:
		if context == null:
			return null

		result as TypeMember
		baseMember as TypeMember
		if context.method() != null:
			result = VisitMethod(context.method())
		elif context.event_declaration() != null:
			result = VisitEvent_declaration(context.event_declaration())
		elif context.field_or_property() != null:
			result = VisitField_or_property(context.field_or_property())
		else:
			result = VisitType_definition(context.type_definition())
		if result == null:
			return null
		if result isa SpliceTypeMember:
			baseMember = (cast(SpliceTypeMember, result)).TypeMember
		else:
			baseMember = result
		AddAttributes(baseMember, context.attributes())
		baseMember.Modifiers = GetModifiers(context.modifiers())
		return result

	def IBooParserVisitor[of Node].VisitType_definition_member(context as BooParser.Type_definition_memberContext) as Node:
		return VisitType_definition_member(context)

	def VisitAny_intf_type_member(context as BooParser.Any_intf_type_memberContext) as TypeMember:
		if context == null:
			return null

		result as TypeMember
		if context.interface_method() != null:
			result = VisitInterface_method(context.interface_method())
		elif context.event_declaration() != null:
			result = VisitEvent_declaration(context.event_declaration())
		else:
			result = VisitInterface_property(context.interface_property())
		AddAttributes(result, context.attributes())
		return result

	def IBooParserVisitor[of Node].VisitAny_intf_type_member(context as BooParser.Any_intf_type_memberContext) as Node:
		return VisitAny_intf_type_member(context)

	def VisitInterface_definition(context as BooParser.Interface_definitionContext) as TypeMember:
		if context == null:
			return null

		result as InterfaceDefinition
		name as string
		li as LexicalInfo
		nameSplice as Expression = null
		if context.ID() != null:
			name = context.ID().GetText()
			li = GetLexicalInfo(context.ID())
		else:
			if context.SPLICE_BEGIN() == null:
				return null
			nameSplice =(null if context.atom() == null else cast(Expression, Visit(context.atom())))
			name = context.SPLICE_BEGIN().GetText()
			li = GetLexicalInfo(context.SPLICE_BEGIN())
		result = InterfaceDefinition(li, Name: name)
		AddGenericParameters(result, context.generic_parameter_declaration_list())
		AddBaseTypes(result, context.base_types())
		if context.begin_with_doc() != null:
			CheckDocumentation(result, context.begin_with_doc().docstring())
		if context.PASS() == null:
			for tdm in context.any_intf_type_member():
				member = VisitAny_intf_type_member(tdm)
				if member != null:
					result.Members.Add(member)
		SetEndSourceLocation(result, context.end_())
		if nameSplice != null:
			return SpliceTypeMember(result, nameSplice)
		return result

	def IBooParserVisitor[of Node].VisitInterface_definition(context as BooParser.Interface_definitionContext) as Node:
		return VisitInterface_definition(context)

	def IBooParserVisitor[of Node].VisitBase_types(context as BooParser.Base_typesContext) as Node:
		raise NotImplementedException()

	def VisitInterface_method(context as BooParser.Interface_methodContext) as TypeMember:
		if context == null:
			return null

		name as string
		li as LexicalInfo
		nameSplice as Expression = null
		if context.member() != null:
			name = context.member().GetText()
			li = GetLexicalInfo(context.member())
		else:
			if context.SPLICE_BEGIN() == null:
				return null
			nameSplice =(null if context.atom() == null else cast(Expression, Visit(context.atom())))
			name = context.SPLICE_BEGIN().GetText()
			li = GetLexicalInfo(context.SPLICE_BEGIN())
		result = Method(li, Name: name)
		if context.generic_parameter_declaration_list() != null:
			AddGenericParameters(result, context.generic_parameter_declaration_list())
		elif context.generic_parameter_declaration() != null:
			added = VisitGeneric_parameter_declaration(context.generic_parameter_declaration())
			if added != null:
				result.GenericParameters.Add(added)
		AddParameters(result, context.parameter_declaration_list())
		if context.AS() != null:
			result.ReturnType = VisitType_reference(context.type_reference())
		CheckDocumentation(result, context.docstring())
		SetEndSourceLocation(result, context.empty_block())
		if nameSplice != null:
			return SpliceTypeMember(result, nameSplice)
		return result

	def IBooParserVisitor[of Node].VisitInterface_method(context as BooParser.Interface_methodContext) as Node:
		return VisitInterface_method(context)

	def VisitInterface_property(context as BooParser.Interface_propertyContext) as Property:
		if context == null:
			return null

		id =(context.ID() if context.ID() is not null else context.SELF())
		result = Property(GetLexicalInfo(id), Name: id.GetText())
		AddParameters(result, context.parameter_declaration_list())
		if context.AS() != null:
			result.Type = VisitType_reference(context.type_reference())
		if context.begin_with_doc() != null:
			CheckDocumentation(result, context.begin_with_doc().docstring())
		for pa in context.interface_property_accessor():
			if pa.GET() != null:
				if result.Getter != null:
					EmitDuplicateAccessorError(GetLexicalInfo(pa.GET()), "get")
				result.Getter = VisitInterface_property_accessor(pa)
			else:
				if result.Setter != null:
					EmitDuplicateAccessorError(GetLexicalInfo(pa.SET()), "set")
				result.Setter = VisitInterface_property_accessor(pa)
		SetEndSourceLocation(result, context.end_())
		return result

	def IBooParserVisitor[of Node].VisitInterface_property(context as BooParser.Interface_propertyContext) as Node:
		return VisitInterface_property(context)

	def VisitInterface_property_accessor(context as BooParser.Interface_property_accessorContext) as Method:
		if context == null:
			return null

		token =(context.GET() if context.GET() is not null else context.SET())
		if token == null:
			return null

		result = Method(GetLexicalInfo(token), Name: token.GetText())
		AddAttributes(result, context.attributes())
		SetEndSourceLocation(result, context.empty_block())
		return result

	def IBooParserVisitor[of Node].VisitInterface_property_accessor(context as BooParser.Interface_property_accessorContext) as Node:
		return VisitInterface_property_accessor(context)

	def IBooParserVisitor[of Node].VisitEmpty_block(context as BooParser.Empty_blockContext) as Node:
		return null

	def VisitEvent_declaration(context as BooParser.Event_declarationContext) as Event:
		if context == null:
			return null

		id = context.ID()
		tr = VisitType_reference(context.type_reference())
		result = Event(GetLexicalInfo(id), id.GetText(), tr)
		CheckDocumentation(result, context.docstring())
		return result

	def IBooParserVisitor[of Node].VisitEvent_declaration(context as BooParser.Event_declarationContext) as Node:
		return VisitEvent_declaration(context)

	def VisitExplicit_member_info(context as BooParser.Explicit_member_infoContext) as ExplicitMemberInfo:
		if context == null:
			return null

		ids = context.ID()
		id = ids[0]
		result = ExplicitMemberInfo(GetLexicalInfo(id))
		_sbuilder.Clear()
		_sbuilder.Append(id.GetText())
		for i in range(1, ids.Length):
			_sbuilder.Append(char('.'))
			_sbuilder.Append(ids[i].GetText())
		interfaceName = _sbuilder.ToString()
		if context.LBRACK() != null:
			// An explicitly implemented generic interface names its arguments,
			// as in `def IFoo[of int].Bar()`.
			generic = GenericTypeReference(result.LexicalInfo, interfaceName)
			AddTypeReferences(generic.GenericArguments, context.type_reference_list())
			result.InterfaceType = generic
		else:
			result.InterfaceType = SimpleTypeReference(result.LexicalInfo)
			result.InterfaceType.Name = interfaceName
		return result

	def IBooParserVisitor[of Node].VisitExplicit_member_info(context as BooParser.Explicit_member_infoContext) as Node:
		return VisitExplicit_member_info(context)

	def VisitMethod(context as BooParser.MethodContext) as TypeMember:
		if context == null:
			return null

		result as Method
		nameSplice as Expression = null
		if context.CONSTRUCTOR() != null:
			result = Constructor(GetLexicalInfo(context.CONSTRUCTOR()))
		elif context.DESTRUCTOR() != null:
			result = Destructor(GetLexicalInfo(context.DESTRUCTOR()))
		else:
			emi as ExplicitMemberInfo = null
			name as string
			li as LexicalInfo
			if context.explicit_member_info() != null:
				emi = VisitExplicit_member_info(context.explicit_member_info())
			if context.member() != null:
				name = context.member().GetText()
				li = GetLexicalInfo(context.member())
			else:
				if context.SPLICE_BEGIN() == null:
					return null
				nameSplice =(null if context.atom() == null else cast(Expression, Visit(context.atom())))
				name = context.SPLICE_BEGIN().GetText()
				li = GetLexicalInfo(context.SPLICE_BEGIN())
			if emi != null:
				result = Method(emi.LexicalInfo, Name: name, ExplicitInfo: emi)
			else:
				result = Method(li, Name: name)
		AddGenericParameters(result, context.generic_parameter_declaration_list())
		AddParameters(result, context.parameter_declaration_list())
		AddReturnTypeAttributes(result, context.attributes())
		if context.AS() != null:
			result.ReturnType = VisitType_reference(context.type_reference())
		if context.begin_block_with_doc() != null:
			CheckDocumentation(result, context.begin_block_with_doc().docstring())
		result.Body =(VisitBlock(context.block()) if VisitBlock(context.block()) is not null else result.Body)
		if context.begin_block_with_doc() != null:
			result.Body.LexicalInfo = GetLexicalInfo(context.begin_block_with_doc().INDENT())
		SetEndSourceLocation(result.Body, context.end_())
		result.EndSourceLocation = result.Body.EndSourceLocation
		if nameSplice != null:
			return SpliceTypeMember(result, nameSplice)
		return result

	def IBooParserVisitor[of Node].VisitMethod(context as BooParser.MethodContext) as Node:
		return VisitMethod(context)

	def VisitFPProperty(context as BooParser.Field_or_propertyContext) as Property:
		if context == null:
			return null

		result as Property
		emi as ExplicitMemberInfo = null
		if context.explicit_member_info() != null:
			emi = VisitExplicit_member_info(context.explicit_member_info())
		name as string
		li as LexicalInfo
		token =(context.ID() if context.ID() is not null else context.SELF())
		if token != null:
			name = token.GetText()
			li = GetLexicalInfo(token)
		else:
			if context.SPLICE_BEGIN() == null:
				return null
			// boo.g names the property after the splice token, not the atom.
			name = context.SPLICE_BEGIN().GetText()
			li = GetLexicalInfo(context.SPLICE_BEGIN())
		result = Property((emi.LexicalInfo if emi != null else li), Name: name, ExplicitInfo: emi)
		AddParameters(result, context.parameter_declaration_list())
		// After the parameters: the warning quotes them.
		if context.LPAREN() != null:
			EmitIndexedPropertyDeprecationWarning(result)
		if context.AS() != null:
			result.Type = VisitType_reference(context.type_reference())
		if context.begin_with_doc() != null:
			CheckDocumentation(result, context.begin_with_doc().docstring())
		for pa in context.property_accessor():
			if pa.GET() != null:
				if result.Getter != null:
					EmitDuplicateAccessorError(GetLexicalInfo(pa.GET()), "get")
				result.Getter = VisitProperty_accessor(pa)
			else:
				if result.Setter != null:
					EmitDuplicateAccessorError(GetLexicalInfo(pa.SET()), "set")
				result.Setter = VisitProperty_accessor(pa)
		return result

	def VisitFPField(context as BooParser.Field_or_propertyContext) as Field:
		if context == null:
			return null

		name as string
		li as LexicalInfo
		if context.ID() != null:
			name = context.ID().GetText()
			li = GetLexicalInfo(context.ID())
		elif context.SPLICE_BEGIN() != null:
			name = context.SPLICE_BEGIN().GetText()
			li = GetLexicalInfo(context.SPLICE_BEGIN())
		else:
			return null
		result = Field(li, Name: name)
		if context.AS() != null:
			result.Type = VisitType_reference(context.type_reference())
		if context.ASSIGN() != null:
			result.Initializer = VisitDeclaration_initializer(context.declaration_initializer())
		CheckDocumentation(result, context.docstring())
		return result

	def VisitField_or_property(context as BooParser.Field_or_propertyContext) as TypeMember:
		if context == null:
			return null

		result as TypeMember
		if context.property_accessor().Length > 0:
			result = VisitFPProperty(context)
		elif context.member_macro() != null:
			return VisitMember_macro(context.member_macro())
		else:
			result = VisitFPField(context)
		SetEndSourceLocation(result, context.end_())
		if context.atom() != null:
			nameSplice = cast(Expression, Visit(context.atom()))
			return SpliceTypeMember(result, nameSplice)
		return result

	def IBooParserVisitor[of Node].VisitField_or_property(context as BooParser.Field_or_propertyContext) as Node:
		return VisitField_or_property(context)

	def VisitMember_macro(context as BooParser.Member_macroContext) as StatementTypeMember:
		if context == null:
			return null

		return StatementTypeMember(VisitMacro_stmt(context.macro_stmt()))

	def IBooParserVisitor[of Node].VisitMember_macro(context as BooParser.Member_macroContext) as Node:
		return VisitMember_macro(context)

	def VisitDeclaration_initializer(context as BooParser.Declaration_initializerContext) as Expression:
		if context == null:
			return null

		result as Expression
		if context.slicing_expression() != null:
			result = VisitMethod_invocation_block(context.method_invocation_block(), VisitSlicing_expression(context.slicing_expression()))
		elif context.array_or_expression() != null:
			result = VisitArray_or_expression(context.array_or_expression())
		else:
			result = VisitCallable_expression(context.callable_expression())
		return result

	def IBooParserVisitor[of Node].VisitDeclaration_initializer(context as BooParser.Declaration_initializerContext) as Node:
		return VisitDeclaration_initializer(context)

	def VisitSimple_initializer(context as BooParser.Simple_initializerContext) as Expression:
		if context == null:
			return null

		result as Expression
		if context.array_or_expression() != null:
			result = VisitArray_or_expression(context.array_or_expression())
		else:
			result = VisitCallable_expression(context.callable_expression())
		return result

	def IBooParserVisitor[of Node].VisitSimple_initializer(context as BooParser.Simple_initializerContext) as Node:
		return VisitSimple_initializer(context)

	def VisitProperty_accessor(context as BooParser.Property_accessorContext) as Method:
		if context == null:
			return null

		token =(context.GET() if context.GET() is not null else context.SET())
		if token == null:
			return null

		result = Method(GetLexicalInfo(token), Name: token.GetText())
		AddAttributes(result, context.attributes())
		result.Modifiers = GetModifiers(context.modifiers())
		// boo.g takes the body before parsing one, so an accessor with no body
		// still has an empty block.
		body = result.Body
		if context.compound_stmt() != null:
			result.Body =(VisitCompound_stmt(context.compound_stmt()) if VisitCompound_stmt(context.compound_stmt()) is not null else body)
		return result

	def IBooParserVisitor[of Node].VisitProperty_accessor(context as BooParser.Property_accessorContext) as Node:
		return VisitProperty_accessor(context)

	def VisitGlobals(context as BooParser.GlobalsContext, m as Module):
		for statement in context.stmt_or_nested_function():
			statementNode = cast(Statement, Visit(statement))
			if statementNode != null:
				m.Globals.Add(statementNode)

	def IBooParserVisitor[of Node].VisitGlobals(context as BooParser.GlobalsContext) as Node:
		VisitGlobals(context, _module)
		return null

	def VisitBlock(context as BooParser.BlockContext) as Block:
		if context == null:
			return null

		result = Block()
		for statement in context.stmt_or_nested_function():
			statementNode = cast(Statement, Visit(statement))
			if statementNode != null:
				result.Add(statementNode)
		return result

	def IBooParserVisitor[of Node].VisitBlock(context as BooParser.BlockContext) as Node:
		return VisitBlock(context)

	def IBooParserVisitor[of Node].VisitModifiers(context as BooParser.ModifiersContext) as Node:
		raise NotImplementedException()

	def IBooParserVisitor[of Node].VisitType_member_modifier(context as BooParser.Type_member_modifierContext) as Node:
		raise NotImplementedException()

	def IBooParserVisitor[of Node].VisitParameter_modifier(context as BooParser.Parameter_modifierContext) as Node:
		raise NotImplementedException()

	def IBooParserVisitor[of Node].VisitParameter_declaration_list(context as BooParser.Parameter_declaration_listContext) as Node:
		raise NotImplementedException()

	def VisitParameter_declaration(context as BooParser.Parameter_declarationContext) as ParameterDeclaration:
		if context == null:
			return null

		name as string
		li as LexicalInfo
		nameSplice as Expression = null
		if context.ID() != null:
			name = context.ID().GetText()
			li = GetLexicalInfo(context.ID())
		else:
			if context.SPLICE_BEGIN() == null:
				return null
			nameSplice =(null if context.atom() == null else cast(Expression, Visit(context.atom())))
			name = context.SPLICE_BEGIN().GetText()
			li = GetLexicalInfo(context.SPLICE_BEGIN())
		result = ParameterDeclaration(li, Name: name)
		if context.AS() != null:
			if context.MULTIPLY() != null:
				result.Type = VisitArray_type_reference(context.array_type_reference())
			else:
				result.Type = VisitType_reference(context.type_reference())
		if context.parameter_modifier() != null  and  context.parameter_modifier().REF() != null:
			result.Modifiers = ParameterModifiers.Ref
		AddAttributes(result, context.attributes())
		if nameSplice != null:
			return SpliceParameterDeclaration(result, nameSplice)
		return result

	def IBooParserVisitor[of Node].VisitParameter_declaration(context as BooParser.Parameter_declarationContext) as Node:
		return VisitParameter_declaration(context)

	def IBooParserVisitor[of Node].VisitCallable_parameter_declaration_list(context as BooParser.Callable_parameter_declaration_listContext) as Node:
		raise NotImplementedException()

	def VisitCallable_parameter_declaration(context as BooParser.Callable_parameter_declarationContext) as ParameterDeclaration:
		if context == null:
			return null

		tr = VisitType_reference(context.type_reference())
		result = ParameterDeclaration(tr.LexicalInfo, Type: tr)
		if context.parameter_modifier() != null  and  context.parameter_modifier().REF() != null:
			result.Modifiers = ParameterModifiers.Ref
		return result

	def IBooParserVisitor[of Node].VisitCallable_parameter_declaration(context as BooParser.Callable_parameter_declarationContext) as Node:
		return VisitCallable_parameter_declaration(context)

	def AddCallableParameters(node as INodeWithParameters, context as BooParser.Callable_parameter_declaration_listContext):
		if context != null:
			va as bool = false
			for cpd in context.callable_parameter_declaration():
				if va:
					EmitParamAfterVarargsError(GetLexicalInfo(cpd))
				param = VisitCallable_parameter_declaration(cpd)
				param.Name = "arg" + node.Parameters.Count
				node.Parameters.Add(param)
				if cpd.MULTIPLY() != null:
					va = true
			node.Parameters.HasParamArray = va

	def VisitCallable_type_reference(context as BooParser.Callable_type_referenceContext) as CallableTypeReference:
		if context == null:
			return null

		result = CallableTypeReference(GetLexicalInfo(context.CALLABLE()))
		AddCallableParameters(result, context.callable_parameter_declaration_list())
		if context.AS() != null:
			result.ReturnType = VisitType_reference(context.type_reference())
		return result

	def IBooParserVisitor[of Node].VisitCallable_type_reference(context as BooParser.Callable_type_referenceContext) as Node:
		return VisitCallable_type_reference(context)

	def IBooParserVisitor[of Node].VisitGeneric_parameter_declaration_list(context as BooParser.Generic_parameter_declaration_listContext) as Node:
		raise NotImplementedException()

	def AddGenericParameterConstraints(gpd as GenericParameterDeclaration, context as BooParser.Generic_parameter_constraintsContext):
		while context != null:
			if context.CLASS() != null:
				gpd.Constraints |= GenericParameterConstraints.ReferenceType
			elif context.STRUCT() != null:
				gpd.Constraints |= GenericParameterConstraints.ValueType
			elif context.CONSTRUCTOR() != null:
				gpd.Constraints |= GenericParameterConstraints.Constructable
			else:
				added = VisitType_reference(context.type_reference())
				if added != null:
					gpd.BaseTypes.Add(added)

			context = context.generic_parameter_constraints()

	def VisitGeneric_parameter_declaration(context as BooParser.Generic_parameter_declarationContext) as GenericParameterDeclaration:
		if context == null:
			return null

		id = context.ID()
		if id == null:
			return null
		result = GenericParameterDeclaration(GetLexicalInfo(id), Name: id.GetText())
		AddGenericParameterConstraints(result, context.generic_parameter_constraints())
		return result

	def IBooParserVisitor[of Node].VisitGeneric_parameter_declaration(context as BooParser.Generic_parameter_declarationContext) as Node:
		return VisitGeneric_parameter_declaration(context)

	def IBooParserVisitor[of Node].VisitGeneric_parameter_constraints(context as BooParser.Generic_parameter_constraintsContext) as Node:
		raise NotImplementedException()

	def VisitArray_type_reference(context as BooParser.Array_type_referenceContext) as ArrayTypeReference:
		if context == null:
			return null

		// Rank stays unset unless the source states one, as in boo.g. The
		// element type overload would default it to 1 and show up in the tree.
		result = ArrayTypeReference(GetLexicalInfo(context.LPAREN()))
		result.ElementType = VisitType_reference(context.type_reference())
		if context.integer_literal() != null:
			result.Rank = VisitInteger_literal(context.integer_literal())
		return result

	def IBooParserVisitor[of Node].VisitArray_type_reference(context as BooParser.Array_type_referenceContext) as Node:
		return VisitArray_type_reference(context)

	def AddTypeReferences(container as TypeReferenceCollection, context as BooParser.Type_reference_listContext):
		if context != null:
			for tr in context.type_reference():
				added = VisitType_reference(tr)
				if added != null:
					container.Add(added)

	def IBooParserVisitor[of Node].VisitType_reference_list(context as BooParser.Type_reference_listContext) as Node:
		raise NotImplementedException()

	def VisitSplice_type_reference(context as BooParser.Splice_type_referenceContext) as SpliceTypeReference:
		if context == null:
			return null

		return SpliceTypeReference(GetLexicalInfo(context.SPLICE_BEGIN()), VisitAtom(context.atom()))

	def IBooParserVisitor[of Node].VisitSplice_type_reference(context as BooParser.Splice_type_referenceContext) as Node:
		return VisitSplice_type_reference(context)

	def ParseGenericTypeReference(context as BooParser.Type_referenceContext, id as BooParser.Type_nameContext) as TypeReference:
		result as TypeReference
		if context.LBRACK() != null:
			if context.MULTIPLY().Length > 0:
				result = GenericTypeDefinitionReference(GetLexicalInfo(id), Name: GetName(id), GenericPlaceholders: context.MULTIPLY().Length)
			else:
				gtr as GenericTypeReference = GenericTypeReference(GetLexicalInfo(id), GetName(id))
				AddTypeReferences(gtr.GenericArguments, context.type_reference_list())
				result = gtr
		else:
			if context.MULTIPLY().Length > 0:
				result = GenericTypeDefinitionReference(GetLexicalInfo(id), Name: GetName(id), GenericPlaceholders: 1)
			else:
				gtr = GenericTypeReference(GetLexicalInfo(id), GetName(id))
				added = VisitType_reference(context.type_reference())
				if added != null:
					gtr.GenericArguments.Add(added)
				result = gtr
		return result

	def ParseTypeReference(context as BooParser.Type_referenceContext) as TypeReference:
		result as TypeReference
		id = context.type_name()
		if ((context.OF() if context.OF() is not null else context.LBRACK())) != null:
			result = ParseGenericTypeReference(context, id)
		else:
			result = SimpleTypeReference(GetLexicalInfo(id), GetName(id))
		if context.NULLABLE_SUFFIX() != null:
			ntr = GenericTypeReference(result.LexicalInfo, "System.Nullable")
			ntr.GenericArguments.Add(result)
			result = ntr
		return result

	def VisitType_reference(context as BooParser.Type_referenceContext) as TypeReference:
		if context == null:
			return null

		result as TypeReference
		if context.splice_type_reference() != null:
			result = VisitSplice_type_reference(context.splice_type_reference())
		elif context.array_type_reference() != null:
			result = VisitArray_type_reference(context.array_type_reference())
		elif context.callable_type_reference() != null:
			result = VisitCallable_type_reference(context.callable_type_reference())
		else:
			result = ParseTypeReference(context)

		typeDegree = context.type_degree()
		if typeDegree == null:
			return result

		enumDegree = 0
		if typeDegree.MULTIPLY() != null:
			enumDegree += typeDegree.MULTIPLY().Length
		if typeDegree.EXPONENTIATION() != null:
			enumDegree += typeDegree.EXPONENTIATION().Length * 2
		for i in range(0, enumDegree):
			result = CodeFactory.EnumerableTypeReferenceFor(result)
		return result

	def IBooParserVisitor[of Node].VisitType_reference(context as BooParser.Type_referenceContext) as Node:
		return VisitType_reference(context)

	def IBooParserVisitor[of Node].VisitType_degree(context as BooParser.Type_degreeContext) as Node:
		raise NotSupportedException()

	def GetName(context as BooParser.Type_nameContext) as string:
		if context == null:
			return null
		if context.identifier() != null:
			return context.identifier().GetText()
		keyword =(context.CALLABLE() if context.CALLABLE() is not null else context.CHAR())
		return (null if keyword == null else keyword.GetText())

	def IBooParserVisitor[of Node].VisitType_name(context as BooParser.Type_nameContext) as Node:
		raise NotImplementedException()

	def IBooParserVisitor[of Node].VisitBegin(context as BooParser.BeginContext) as Node:
		return null

	def IBooParserVisitor[of Node].VisitBegin_with_doc(context as BooParser.Begin_with_docContext) as Node:
		raise NotImplementedException()

	def IBooParserVisitor[of Node].VisitBegin_block_with_doc(context as BooParser.Begin_block_with_docContext) as Node:
		raise NotImplementedException()

	def IBooParserVisitor[of Node].VisitEnd(context as BooParser.EndContext) as Node:
		return null

	def VisitCompound_stmt(context as BooParser.Compound_stmtContext) as Block:
		if context == null:
			return null

		if context.single_line_block() != null:
			return VisitSingle_line_block(context.single_line_block())
		result = VisitBlock(context.block())
		if result == null:
			return null
		result.LexicalInfo = GetLexicalInfo(context.INDENT())
		SetEndSourceLocation(result, context.end_())
		return result

	def IBooParserVisitor[of Node].VisitCompound_stmt(context as BooParser.Compound_stmtContext) as Node:
		return VisitCompound_stmt(context)

	def VisitSingle_line_block(context as BooParser.Single_line_blockContext) as Block:
		if context == null:
			return null

		// boo.g's single_line_block never states a position, so the block takes
		// whatever its owner has.
		result = Block()
		if context.simple_stmt() != null:
			for stmt in context.simple_stmt():
				statementNode = VisitSimple_stmt(stmt)
				if statementNode != null:
					result.Add(statementNode)
		if context.EOL() != null  and  context.EOL().Length > 0:
			SetEndSourceLocationAt(result, context.EOL().Last())
		return result

	def IBooParserVisitor[of Node].VisitSingle_line_block(context as BooParser.Single_line_blockContext) as Node:
		return VisitSingle_line_block(context)

	def VisitClosure_macro_stmt(context as BooParser.Closure_macro_stmtContext) as MacroStatement:
		if context == null:
			return null

		id = context.macro_name()
		result = MacroStatement(GetLexicalInfo(id), id.GetText())
		GetExpressionList(result.Arguments, context.expression_list())
		return result

	def IBooParserVisitor[of Node].VisitClosure_macro_stmt(context as BooParser.Closure_macro_stmtContext) as Node:
		return VisitClosure_macro_stmt(context)

	def GetMacroBlock(container as StatementCollection, context as BooParser.Macro_blockContext):
		if context.any_macro_stmt() != null:
			for stmt in context.any_macro_stmt():
				added = VisitAny_macro_stmt(stmt)
				if added != null:
					container.Add(added)

	def IBooParserVisitor[of Node].VisitMacro_block(context as BooParser.Macro_blockContext) as Node:
		raise NotImplementedException()

	def VisitAny_macro_stmt(context as BooParser.Any_macro_stmtContext) as Statement:
		if context == null:
			return null

		if context.stmt_or_nested_function() != null:
			return VisitStmt_or_nested_function(context.stmt_or_nested_function())
		return VisitType_member_stmt(context.type_member_stmt())

	def IBooParserVisitor[of Node].VisitAny_macro_stmt(context as BooParser.Any_macro_stmtContext) as Node:
		raise NotImplementedException()

	def VisitType_member_stmt(context as BooParser.Type_member_stmtContext) as TypeMemberStatement:
		if context == null:
			return null

		return TypeMemberStatement(VisitType_definition_member(context.type_definition_member()))

	def IBooParserVisitor[of Node].VisitType_member_stmt(context as BooParser.Type_member_stmtContext) as Node:
		return VisitType_member_stmt(context)

	def VisitMacro_compound_stmt(context as BooParser.Macro_compound_stmtContext) as Block:
		if context == null:
			return null

		if context.single_line_block() != null:
			return VisitSingle_line_block(context.single_line_block())
		result = Block()
		GetMacroBlock(result.Statements, context.macro_block())
		result.LexicalInfo = GetLexicalInfo(context.INDENT())
		SetEndSourceLocation(result, context.end_())
		return result

	def IBooParserVisitor[of Node].VisitMacro_compound_stmt(context as BooParser.Macro_compound_stmtContext) as Node:
		return VisitMacro_compound_stmt(context)

	def VisitMacro_stmt(context as BooParser.Macro_stmtContext) as MacroStatement:
		if context == null:
			return null

		id = context.macro_name()
		result = MacroStatement(GetLexicalInfo(id), GetMacroName(id))
		GetExpressionList(result.Arguments, context.expression_list())
		if context.begin_with_doc() != null:
			CheckDocumentation(result, context.begin_with_doc().docstring())
			GetMacroBlock(result.Body.Statements, context.macro_block())
			SetEndSourceLocation(result.Body, context.end_())
			result.Annotate("compound")
		elif context.macro_compound_stmt() != null:
			result.Body = VisitMacro_compound_stmt(context.macro_compound_stmt())
			result.Annotate("compound")
		else:
			if context.stmt_modifier() != null:
				result.Modifier = VisitStmt_modifier(context.stmt_modifier())
			CheckDocumentation(result, context.docstring())
		return result

	def IBooParserVisitor[of Node].VisitMacro_stmt(context as BooParser.Macro_stmtContext) as Node:
		return VisitMacro_stmt(context)

	def GetMacroName(context as BooParser.Macro_nameContext) as string:
		return ((context.ID() if context.ID() is not null else context.THEN())).GetText()

	def IBooParserVisitor[of Node].VisitMacro_name(context as BooParser.Macro_nameContext) as Node:
		raise NotImplementedException()

	def VisitGoto_stmt(context as BooParser.Goto_stmtContext) as GotoStatement:
		if context == null:
			return null

		return GotoStatement( GetLexicalInfo(context.GOTO()), ReferenceExpression( GetLexicalInfo(context.ID()), context.ID().GetText()))

	def IBooParserVisitor[of Node].VisitGoto_stmt(context as BooParser.Goto_stmtContext) as Node:
		return VisitGoto_stmt(context)

	def VisitLabel_stmt(context as BooParser.Label_stmtContext) as LabelStatement:
		if context == null:
			return null

		if context.ID() == null:
			return null
		return LabelStatement(GetLexicalInfo(context.COLON()), context.ID().GetText())

	def IBooParserVisitor[of Node].VisitLabel_stmt(context as BooParser.Label_stmtContext) as Node:
		return VisitLabel_stmt(context)

	def VisitNested_function(context as BooParser.Nested_functionContext) as DeclarationStatement:
		if context == null:
			return null

		id = context.ID()
		if id == null:
			return null
		name as string = id.GetText()
		be = BlockExpression(GetLexicalInfo(id))
		be.Body = VisitCompound_stmt(context.compound_stmt())
		AddParameters(be, context.parameter_declaration_list())
		if context.AS() != null:
			be.ReturnType = VisitType_reference(context.type_reference())
		result = DeclarationStatement( GetLexicalInfo(context.DEF()), Declaration( GetLexicalInfo(id), name), be)
		be[BlockExpression.ClosureNameAnnotation] = name
		return result

	def IBooParserVisitor[of Node].VisitNested_function(context as BooParser.Nested_functionContext) as Node:
		return VisitNested_function(context)

	def VisitStmt_or_nested_function(context as BooParser.Stmt_or_nested_functionContext) as Statement:
		if context == null:
			return null

		if context.nested_function() != null:
			return VisitNested_function(context.nested_function())

		return VisitStmt(context.stmt())

	def IBooParserVisitor[of Node].VisitStmt_or_nested_function(context as BooParser.Stmt_or_nested_functionContext) as Node:
		return VisitStmt_or_nested_function(context)

	def VisitStmt(context as BooParser.StmtContext) as Statement:
		if context == null:
			return null

		if context.pass_stmt() != null:
			return null
		if context.for_stmt() != null:
			return VisitFor_stmt(context.for_stmt())
		if context.while_stmt() != null:
			return VisitWhile_stmt(context.while_stmt())
		if context.if_stmt() != null:
			return VisitIf_stmt(context.if_stmt())
		if context.unless_stmt() != null:
			return VisitUnless_stmt(context.unless_stmt())
		if context.try_stmt() != null:
			return VisitTry_stmt(context.try_stmt())
		if context.macro_stmt() != null:
			return VisitMacro_stmt(context.macro_stmt())
		if context.assignment_or_method_invocation_with_block_stmt() != null:
			return VisitAssignment_or_method_invocation_with_block_stmt(context.assignment_or_method_invocation_with_block_stmt())
		if context.return_stmt() != null:
			return VisitReturn_stmt(context.return_stmt())
		if context.unpack_stmt() != null:
			return VisitUnpack_stmt(context.unpack_stmt())
		if context.declaration_stmt() != null:
			return VisitDeclaration_stmt(context.declaration_stmt())

		result as Statement
		if context.goto_stmt() != null:
			result = VisitGoto_stmt(context.goto_stmt())
		elif context.label_stmt() != null:
			result = VisitLabel_stmt(context.label_stmt())
		elif context.yield_stmt() != null:
			result = VisitYield_stmt(context.yield_stmt())
		elif context.break_stmt() != null:
			result = VisitBreak_stmt(context.break_stmt())
		elif context.continue_stmt() != null:
			result = VisitContinue_stmt(context.continue_stmt())
		elif context.raise_stmt() != null:
			result = VisitRaise_stmt(context.raise_stmt())
		else:
			result = VisitExpression_stmt(context.expression_stmt())
		if result != null  and  context.stmt_modifier() != null:
			result.Modifier = VisitStmt_modifier(context.stmt_modifier())
		return result

	// pass says a block does nothing, so it leaves no node behind. The printer
	// writes it back from Block.IsEmpty.
	def IBooParserVisitor[of Node].VisitPass_stmt(context as BooParser.Pass_stmtContext) as Node:
		return null

	def IBooParserVisitor[of Node].VisitStmt(context as BooParser.StmtContext) as Node:
		return VisitStmt(context)

	def VisitSimple_stmt(context as BooParser.Simple_stmtContext) as Statement:
		if context == null:
			return null

		if context.pass_stmt() != null:
			return null
		if context.closure_macro_stmt() != null:
			return VisitClosure_macro_stmt(context.closure_macro_stmt())
		if context.assignment_or_method_invocation() != null:
			return VisitAssignment_or_method_invocation(context.assignment_or_method_invocation())
		if context.return_expression_stmt() != null:
			return VisitReturn_expression_stmt(context.return_expression_stmt())
		if context.unpack() != null:
			return VisitUnpack(context.unpack())
		if context.declaration_stmt() != null:
			return VisitDeclaration_stmt(context.declaration_stmt())
		if context.goto_stmt() != null:
			return VisitGoto_stmt(context.goto_stmt())
		if context.label_stmt() != null:
			return VisitLabel_stmt(context.label_stmt())
		if context.yield_stmt() != null:
			return VisitYield_stmt(context.yield_stmt())
		if context.break_stmt() != null:
			return VisitBreak_stmt(context.break_stmt())
		if context.continue_stmt() != null:
			return VisitContinue_stmt(context.continue_stmt())
		if context.raise_stmt() != null:
			return VisitRaise_stmt(context.raise_stmt())
		return VisitExpression_stmt(context.expression_stmt())

	def IBooParserVisitor[of Node].VisitSimple_stmt(context as BooParser.Simple_stmtContext) as Node:
		return VisitSimple_stmt(context)

	def VisitStmt_modifier(context as BooParser.Stmt_modifierContext) as StatementModifier:
		if context == null:
			return null

		t as ITerminalNode
		type as StatementModifierType
		if context.IF() != null:
			t = context.IF()
			type = StatementModifierType.If
		elif context.UNLESS() != null:
			t = context.UNLESS()
			type = StatementModifierType.Unless
		else:
			t = context.WHILE()
			type = StatementModifierType.While
		e = VisitBoolean_expression(context.boolean_expression())
		return StatementModifier(type, e, LexicalInfo: GetLexicalInfo(t))

	def IBooParserVisitor[of Node].VisitStmt_modifier(context as BooParser.Stmt_modifierContext) as Node:
		return VisitStmt_modifier(context)

	def VisitCallable_or_expression(context as BooParser.Callable_or_expressionContext) as Expression:
		if context == null:
			return null

		if context.callable_expression() != null:
			return VisitCallable_expression(context.callable_expression())
		return VisitArray_or_expression(context.array_or_expression())

	def IBooParserVisitor[of Node].VisitCallable_or_expression(context as BooParser.Callable_or_expressionContext) as Node:
		return VisitCallable_or_expression(context)

	def VisitInternal_closure_stmt(context as BooParser.Internal_closure_stmtContext) as Statement:
		if context == null:
			return null

		if context.return_expression_stmt() != null:
			return VisitReturn_expression_stmt(context.return_expression_stmt())

		result as Statement
		if context.unpack() != null:
			result = VisitUnpack(context.unpack())
		elif context.closure_macro_stmt() != null:
			result = VisitClosure_macro_stmt(context.closure_macro_stmt())
		elif context.closure_expression_stmt() != null:
			result = VisitClosure_expression_stmt(context.closure_expression_stmt())
		elif context.raise_stmt() != null:
			result = VisitRaise_stmt(context.raise_stmt())
		else:
			result = VisitYield_stmt(context.yield_stmt())

		if context.stmt_modifier() != null:
			result.Modifier = VisitStmt_modifier(context.stmt_modifier())
		return result

	def IBooParserVisitor[of Node].VisitInternal_closure_stmt(context as BooParser.Internal_closure_stmtContext) as Node:
		return VisitInternal_closure_stmt(context)

	def VisitClosure_expression_stmt(context as BooParser.Closure_expression_stmtContext) as ExpressionStatement:
		if context == null:
			return null

		e = VisitArray_or_expression(context.array_or_expression())
		return ExpressionStatement(e.LexicalInfo, e)

	def IBooParserVisitor[of Node].VisitClosure_expression_stmt(context as BooParser.Closure_expression_stmtContext) as Node:
		return VisitClosure_expression_stmt(context)

	def VisitClosure_expression(context as BooParser.Closure_expressionContext) as BlockExpression:
		if context == null:
			return null

		result = BlockExpression(GetLexicalInfo(context.LBRACE()))
		result.Annotate("inline")
		AddParameters(result, context.parameter_declaration_list())
		for stmt in context.internal_closure_stmt():
			added = VisitInternal_closure_stmt(stmt)
			if added != null:
				result.Body.Add(added)
		SetEndSourceLocation(result.Body, context.RBRACE())
		return result

	def IBooParserVisitor[of Node].VisitClosure_expression(context as BooParser.Closure_expressionContext) as Node:
		return VisitClosure_expression(context)

	def VisitCallable_expression(context as BooParser.Callable_expressionContext) as BlockExpression:
		if context == null:
			return null

		anchor =(context.DEF() if context.DEF() is not null else context.DO())
		if anchor == null:
			body = VisitCompound_stmt(context.compound_stmt())
			if body == null:
				return null
			return BlockExpression(body.LexicalInfo, body)
		result = BlockExpression(GetLexicalInfo(anchor), VisitCompound_stmt(context.compound_stmt()))
		AddParameters(result, context.parameter_declaration_list())
		if context.AS() != null:
			result.ReturnType = VisitType_reference(context.type_reference())
		return result

	def IBooParserVisitor[of Node].VisitCallable_expression(context as BooParser.Callable_expressionContext) as Node:
		return VisitCallable_expression(context)

	def VisitTry_stmt(context as BooParser.Try_stmtContext) as TryStatement:
		if context == null:
			return null

		result = TryStatement(GetLexicalInfo(context.TRY()))
		blocks = context.compound_stmt()
		result.ProtectedBlock = VisitCompound_stmt(blocks[0])
		i = 2
		while i < context.ChildCount:
			sub = context.children[i]
			if sub isa BooParser.Exception_handlerContext:
				added = VisitException_handler(sub as BooParser.Exception_handlerContext)
				if added != null:
					result.ExceptionHandlers.Add(added)
			else:
				keyword = sub as ITerminalNode
				mode = sub.GetText()
				++i
				body = context.children[i] as BooParser.Compound_stmtContext
				block = VisitCompound_stmt(body)
				// boo.g starts the block at the keyword and lets an indented body
				// move it to the INDENT, so only a single line body keeps it.
				if keyword != null  and  body.single_line_block() != null:
					block.LexicalInfo = GetLexicalInfo(keyword)
				if mode == "failure":
					result.FailureBlock = block
				else:
					result.EnsureBlock = block
			++i
		return result

	def IBooParserVisitor[of Node].VisitTry_stmt(context as BooParser.Try_stmtContext) as Node:
		return VisitTry_stmt(context)

	def VisitException_handler(context as BooParser.Exception_handlerContext) as ExceptionHandler:
		if context == null:
			return null

		result = ExceptionHandler(GetLexicalInfo(context.EXCEPT()))
		x = context.ID()
		tr as TypeReference = null
		u = context.UNLESS()
		e as Expression = null
		if context.AS() != null:
			tr = VisitType_reference(context.type_reference())
		if context.boolean_expression() != null:
			e = VisitBoolean_expression(context.boolean_expression())
		result.Declaration = Declaration()
		result.Declaration.Type = tr

		if x != null:
			result.Declaration.LexicalInfo = GetLexicalInfo(x)
			result.Declaration.Name = x.GetText()
		else:
			result.Declaration.Name = null
			result.Flags |= ExceptionHandlerFlags.Anonymous
		if tr != null:
			result.Declaration.LexicalInfo = tr.LexicalInfo
		elif x != null:
			result.Declaration.LexicalInfo = result.LexicalInfo
		if tr == null:
			result.Flags |= ExceptionHandlerFlags.Untyped
		if e != null:
			if u != null:
				not_ as UnaryExpression = UnaryExpression(GetLexicalInfo(u))
				not_.Operator = UnaryOperatorType.LogicalNot
				not_.Operand = e
				e = not_
			result.FilterCondition = e
			result.Flags |= ExceptionHandlerFlags.Filter
		result.Block = VisitCompound_stmt(context.compound_stmt())
		return result

	def IBooParserVisitor[of Node].VisitException_handler(context as BooParser.Exception_handlerContext) as Node:
		return VisitException_handler(context)

	def VisitRaise_stmt(context as BooParser.Raise_stmtContext) as RaiseStatement:
		if context == null:
			return null

		e as Expression = null
		if context.expression() != null:
			e = VisitExpression(context.expression())
		return RaiseStatement(GetLexicalInfo(context.RAISE()), e)

	def IBooParserVisitor[of Node].VisitRaise_stmt(context as BooParser.Raise_stmtContext) as Node:
		return VisitRaise_stmt(context)

	def VisitDeclaration_stmt(context as BooParser.Declaration_stmtContext) as DeclarationStatement:
		if context == null:
			return null

		id = context.ID()
		tr = VisitType_reference(context.type_reference())
		initializer as Expression = null
		m as StatementModifier = null
		if context.ASSIGN() != null:
			if context.simple_initializer() != null:
				initializer = VisitSimple_initializer(context.simple_initializer())
			else:
				initializer = VisitDeclaration_initializer(context.declaration_initializer())
		elif context.stmt_modifier() != null:
			m = VisitStmt_modifier(context.stmt_modifier())

		d as Declaration = Declaration(GetLexicalInfo(id))
		d.Name = id.GetText()
		d.Type = tr

		result = DeclarationStatement(d.LexicalInfo)
		result.Declaration = d
		result.Initializer = initializer
		result.Modifier = m
		return result

	def IBooParserVisitor[of Node].VisitDeclaration_stmt(context as BooParser.Declaration_stmtContext) as Node:
		return VisitDeclaration_stmt(context)

	def VisitExpression_stmt(context as BooParser.Expression_stmtContext) as ExpressionStatement:
		if context == null:
			return null

		e = VisitAssignment_expression(context.assignment_expression())
		return ExpressionStatement(e.LexicalInfo, e)

	def IBooParserVisitor[of Node].VisitExpression_stmt(context as BooParser.Expression_stmtContext) as Node:
		return VisitExpression_stmt(context)

	def VisitReturn_expression_stmt(context as BooParser.Return_expression_stmtContext) as ReturnStatement:
		if context == null:
			return null

		e as Expression = null
		modifier as StatementModifier = null
		if context.array_or_expression() != null:
			e = VisitArray_or_expression(context.array_or_expression())
		if context.stmt_modifier() != null:
			modifier = VisitStmt_modifier(context.stmt_modifier())
		return ReturnStatement(GetLexicalInfo(context.RETURN()), e, modifier)

	def IBooParserVisitor[of Node].VisitReturn_expression_stmt(context as BooParser.Return_expression_stmtContext) as Node:
		return VisitReturn_expression_stmt(context)

	def VisitReturn_stmt(context as BooParser.Return_stmtContext) as ReturnStatement:
		if context == null:
			return null

		e as Expression = null
		modifier as StatementModifier = null
		if context.array_or_expression() != null:
			e = VisitArray_or_expression(context.array_or_expression())
			if context.method_invocation_block() != null:
				e = VisitMethod_invocation_block(context.method_invocation_block(), e)
			elif context.stmt_modifier() != null:
				modifier = VisitStmt_modifier(context.stmt_modifier())
		elif context.callable_expression() != null:
			e = VisitCallable_expression(context.callable_expression())
		elif context.stmt_modifier() != null:
			modifier = VisitStmt_modifier(context.stmt_modifier())
		return ReturnStatement(GetLexicalInfo(context.RETURN()), e, modifier)

	def IBooParserVisitor[of Node].VisitReturn_stmt(context as BooParser.Return_stmtContext) as Node:
		return VisitReturn_stmt(context)

	def VisitYield_stmt(context as BooParser.Yield_stmtContext) as YieldStatement:
		if context == null:
			return null

		e as Expression = null
		if context.array_or_expression() != null:
			e = VisitArray_or_expression(context.array_or_expression())
		return YieldStatement(GetLexicalInfo(context.YIELD()), e)

	def IBooParserVisitor[of Node].VisitYield_stmt(context as BooParser.Yield_stmtContext) as Node:
		return VisitYield_stmt(context)

	def VisitBreak_stmt(context as BooParser.Break_stmtContext) as BreakStatement:
		if context == null:
			return null

		return BreakStatement(GetLexicalInfo(context.BREAK()))

	def IBooParserVisitor[of Node].VisitBreak_stmt(context as BooParser.Break_stmtContext) as Node:
		return VisitBreak_stmt(context)

	def VisitContinue_stmt(context as BooParser.Continue_stmtContext) as ContinueStatement:
		if context == null:
			return null

		return ContinueStatement(GetLexicalInfo(context.CONTINUE()))

	def IBooParserVisitor[of Node].VisitContinue_stmt(context as BooParser.Continue_stmtContext) as Node:
		return VisitContinue_stmt(context)

	def VisitUnless_stmt(context as BooParser.Unless_stmtContext) as UnlessStatement:
		if context == null:
			return null

		condition = VisitExpression(context.expression())
		result = UnlessStatement(GetLexicalInfo(context.UNLESS()), Condition: condition)
		result.Block = VisitCompound_stmt(context.compound_stmt())
		return result

	def IBooParserVisitor[of Node].VisitUnless_stmt(context as BooParser.Unless_stmtContext) as Node:
		return VisitUnless_stmt(context)

	def VisitFor_stmt(context as BooParser.For_stmtContext) as ForStatement:
		if context == null:
			return null

		result = ForStatement(GetLexicalInfo(context.FOR()))
		AddDeclarations(result.Declarations, context.declaration_list())
		result.Iterator = VisitArray_or_expression(context.array_or_expression())
		blocks = context.compound_stmt()
		if blocks.Length == 0:
			return null
		result.Block = VisitCompound_stmt(blocks[0])
		blockCounter as int = 1
		if context.OR() != null:
			result.OrBlock = KeywordBlock(blocks[blockCounter], context.OR())
			++blockCounter
		if context.THEN() != null:
			result.ThenBlock = KeywordBlock(blocks[blockCounter], context.THEN())
		return result

	def IBooParserVisitor[of Node].VisitFor_stmt(context as BooParser.For_stmtContext) as Node:
		return VisitFor_stmt(context)

	def VisitWhile_stmt(context as BooParser.While_stmtContext) as WhileStatement:
		if context == null:
			return null

		e as Expression = VisitExpression(context.expression())
		blocks = context.compound_stmt()
		result = WhileStatement(e, VisitCompound_stmt(blocks[0]), LexicalInfo: GetLexicalInfo(context.WHILE()))
		blockCounter as int = 1
		if context.OR() != null:
			result.OrBlock = KeywordBlock(blocks[blockCounter], context.OR())
			++blockCounter
		if context.THEN() != null:
			result.ThenBlock = KeywordBlock(blocks[blockCounter], context.THEN())
		return result

	def IBooParserVisitor[of Node].VisitWhile_stmt(context as BooParser.While_stmtContext) as Node:
		return VisitWhile_stmt(context)

	/// <summary>
	/// A block introduced by a keyword. boo.g starts it at the keyword and lets
	/// an indented body move it to the INDENT, so only a single line body keeps
	/// the keyword's position.
	/// </summary>
	def KeywordBlock(body as BooParser.Compound_stmtContext, keyword as ITerminalNode) as Block:
		result = VisitCompound_stmt(body)
		if body.single_line_block() != null:
			result.LexicalInfo = GetLexicalInfo(keyword)
		return result

	def VisitIf_stmt(context as BooParser.If_stmtContext) as IfStatement:
		if context == null:
			return null

		e as Expression = VisitExpression(context.expression(0))
		blocks = context.compound_stmt()
		result = IfStatement(GetLexicalInfo(context.IF()), Condition: e, TrueBlock: VisitCompound_stmt(blocks[0]))
		s = result
		i = 1
		for ei in context.ELIF():
			s.FalseBlock = Block()
			elif_ as IfStatement = IfStatement(GetLexicalInfo(ei))
			elif_.TrueBlock = Block()
			elif_.Condition = VisitExpression(context.expression(i))
			s.FalseBlock.Add(elif_)
			s = elif_
			s.TrueBlock = VisitCompound_stmt(blocks[i])
			++i

		if context.ELSE() != null:
			s.FalseBlock = KeywordBlock(blocks[i], context.ELSE())

		return result

	def IBooParserVisitor[of Node].VisitIf_stmt(context as BooParser.If_stmtContext) as Node:
		return VisitIf_stmt(context)

	def VisitUnpack_stmt(context as BooParser.Unpack_stmtContext) as UnpackStatement:
		if context == null:
			return null

		result = VisitUnpack(context.unpack())
		if context.stmt_modifier() != null:
			result.Modifier = VisitStmt_modifier(context.stmt_modifier())
		return result

	def IBooParserVisitor[of Node].VisitUnpack_stmt(context as BooParser.Unpack_stmtContext) as Node:
		return VisitUnpack_stmt(context)

	def VisitUnpack(context as BooParser.UnpackContext) as UnpackStatement:
		if context == null:
			return null

		e as Expression = VisitArray_or_expression(context.array_or_expression())
		result = UnpackStatement(GetLexicalInfo(context.ASSIGN()), Expression: e)
		added = VisitDeclaration(context.declaration())
		if added != null:
			result.Declarations.Add(added)
		if context.declaration_list() != null:
			AddDeclarations(result.Declarations, context.declaration_list())
		return result

	def IBooParserVisitor[of Node].VisitUnpack(context as BooParser.UnpackContext) as Node:
		return VisitUnpack(context)

	def AddDeclarations(dc as DeclarationCollection, context as BooParser.Declaration_listContext):
		for decl in context.declaration():
			declaration = VisitDeclaration(decl)
			if declaration != null:
				dc.Add(declaration)

	def IBooParserVisitor[of Node].VisitDeclaration_list(context as BooParser.Declaration_listContext) as Node:
		raise NotImplementedException()

	def VisitDeclaration(context as BooParser.DeclarationContext) as Declaration:
		if context == null:
			return null

		id = context.ID()
		if id == null:
			return null
		tr as TypeReference = null
		if context.AS() != null:
			tr = VisitType_reference(context.type_reference())
		return Declaration(GetLexicalInfo(id), id.GetText(), tr)

	def IBooParserVisitor[of Node].VisitDeclaration(context as BooParser.DeclarationContext) as Node:
		return VisitDeclaration(context)

	def VisitArray_or_expression(context as BooParser.Array_or_expressionContext) as Expression:
		if context == null:
			return null

		exprs = context.expression()
		commas = context.COMMA()
		if exprs.Length == 0:
			return (null if commas.Length == 0 else ArrayLiteralExpression(GetLexicalInfo(commas[0])))
		result as Expression = VisitExpression(exprs[0])
		if commas.Length > 0:
			tle = ArrayLiteralExpression(result.LexicalInfo)
			tle.Items.Add(result)
			for i in range(1, exprs.Length):
				added = VisitExpression(exprs[i])
				if added != null:
					tle.Items.Add(added)
			result = tle
		return result

	def IBooParserVisitor[of Node].VisitArray_or_expression(context as BooParser.Array_or_expressionContext) as Node:
		return VisitArray_or_expression(context)

	def VisitExpression(context as BooParser.ExpressionContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitBoolean_expression(context.boolean_expression())
		mge as ExtendedGeneratorExpression = null
		ge as GeneratorExpression = null
		gens = context.generator_expression_body()
		if gens.Length > 0:
			ge = GeneratorExpression(GetLexicalInfo(context.FOR(0)))
			ge.Expression = result
			result = ge
			GetGeneratorExpressionBody(ge, gens[0])
			for i in range(1, gens.Length):
				if mge == null:
					mge = ExtendedGeneratorExpression(GetLexicalInfo(context.FOR(0)))
					mge.Items.Add(ge)
					result = mge
				ge = GeneratorExpression(GetLexicalInfo(context.FOR(i)))
				mge.Items.Add(ge)
				GetGeneratorExpressionBody(ge, gens[i])
		return result

	def IBooParserVisitor[of Node].VisitExpression(context as BooParser.ExpressionContext) as Node:
		return VisitExpression(context)

	def GetGeneratorExpressionBody(ge as GeneratorExpression, context as BooParser.Generator_expression_bodyContext):
		AddDeclarations(ge.Declarations, context.declaration_list())
		ge.Iterator = VisitBoolean_expression(context.boolean_expression())
		if context.stmt_modifier() != null:
			ge.Filter = VisitStmt_modifier(context.stmt_modifier())

	def IBooParserVisitor[of Node].VisitGenerator_expression_body(context as BooParser.Generator_expression_bodyContext) as Node:
		raise NotImplementedException()

	def VisitBoolean_expression(context as BooParser.Boolean_expressionContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitBoolean_term(context.boolean_term(0))
		ors = context.OR()
		if ors != null:
			for i in range(0, ors.Length):
				r as Expression = VisitBoolean_term(context.boolean_term(i + 1))
				be as BinaryExpression = BinaryExpression(GetLexicalInfo(ors[i]))
				be.Operator = BinaryOperatorType.Or
				be.Left = result
				be.Right = r
				result = be
		return result

	def IBooParserVisitor[of Node].VisitBoolean_expression(context as BooParser.Boolean_expressionContext) as Node:
		return VisitBoolean_expression(context)

	def VisitBoolean_term(context as BooParser.Boolean_termContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitNot_expression(context.not_expression(0))
		ands = context.AND()
		if ands != null:
			for i in range(0, ands.Length):
				r as Expression = VisitNot_expression(context.not_expression(i + 1))
				be as BinaryExpression = BinaryExpression(GetLexicalInfo(ands[i]))
				be.Operator = BinaryOperatorType.And
				be.Left = result
				be.Right = r
				result = be
		return result

	def IBooParserVisitor[of Node].VisitBoolean_term(context as BooParser.Boolean_termContext) as Node:
		return VisitBoolean_term(context)

	def VisitMethod_invocation_block(context as BooParser.Method_invocation_blockContext, e as Expression) as MethodInvocationExpression:
		result as MethodInvocationExpression =(e as MethodInvocationExpression if e as MethodInvocationExpression is not null else MethodInvocationExpression(e.LexicalInfo, e))
		argument = VisitCallable_expression(context.callable_expression())
		if argument != null:
			result.Arguments.Add(argument)
		return result

	def IBooParserVisitor[of Node].VisitMethod_invocation_block(context as BooParser.Method_invocation_blockContext) as Node:
		raise NotImplementedException()

	def VisitAst_literal_expression(context as BooParser.Ast_literal_expressionContext) as QuasiquoteExpression:
		if context == null:
			return null

		result = QuasiquoteExpression(GetLexicalInfo(context.QQ_BEGIN()))
		if context.ast_literal_block() != null:
			VisitAst_literal_block(context.ast_literal_block(), result)
		else:
			VisitAst_literal_closure(context.ast_literal_closure(), result)
		SetEndSourceLocationAt(result, context.QQ_END())
		return result

	def IBooParserVisitor[of Node].VisitAst_literal_expression(context as BooParser.Ast_literal_expressionContext) as Node:
		return VisitAst_literal_expression(context)

	def VisitAst_literal_module(context as BooParser.Ast_literal_moduleContext, e as QuasiquoteExpression):
		m = CodeFactory.NewQuasiquoteModule(e.LexicalInfo)
		e.Node = m
		VisitParse_module(context.parse_module(), m)

	def IBooParserVisitor[of Node].VisitAst_literal_module(context as BooParser.Ast_literal_moduleContext) as Node:
		raise NotImplementedException()

	def VisitAst_literal_block(context as BooParser.Ast_literal_blockContext, e as QuasiquoteExpression):
		if context.ast_literal_module() != null:
			VisitAst_literal_module(context.ast_literal_module(), e)
		else:
			members = context.type_definition_member()
			if members.Length > 0:
				collection as TypeMemberCollection = TypeMemberCollection()
				for tdm in members:
					added = VisitType_definition_member(tdm)
					if added != null:
						collection.Add(added)
				if collection.Count == 1:
					e.Node = collection[0]
				else:
					m as Module = CodeFactory.NewQuasiquoteModule(e.LexicalInfo)
					m.Members = collection
					e.Node = m
			else:
				b as Block = Block()
				statements as StatementCollection = b.Statements
				for stmt in context.stmt():
					statementNode = VisitStmt(stmt)
					if statementNode != null:
						statements.Add(statementNode)
				if b.Statements.Count == 0:
					return
				e.Node =(b if b.Statements.Count > 1 else b.Statements[0])

	def IBooParserVisitor[of Node].VisitAst_literal_block(context as BooParser.Ast_literal_blockContext) as Node:
		raise NotImplementedException()

	def VisitAst_literal_closure(context as BooParser.Ast_literal_closureContext, e as QuasiquoteExpression):
		if context == null:
			return

		exprs = context.expression()
		if exprs.Length > 0:
			node as Node = VisitExpression(exprs[0])
			if exprs.Length > 1:
				e.Node = ExpressionPair(GetLexicalInfo(context.COLON()), cast(Expression, node), VisitExpression(exprs[1]))
			else:
				e.Node = node
		elif context.import_directive_() != null:
			e.Node = VisitImport_directive_(context.import_directive_())
		else:
			block = Block()
			for stmt in context.internal_closure_stmt():
				added = VisitInternal_closure_stmt(stmt)
				if added != null:
					block.Add(added)
			if block.Statements.Count == 1:
				e.Node = block.FirstStatement
			else:
				e.Node = block

	def IBooParserVisitor[of Node].VisitAst_literal_closure(context as BooParser.Ast_literal_closureContext) as Node:
		raise NotImplementedException()

	def VisitAssignment_or_method_invocation_with_block_stmt(context as BooParser.Assignment_or_method_invocation_with_block_stmtContext) as Statement:
		if context == null:
			return null

		lhs as Expression = VisitSlicing_expression(context.slicing_expression())
		if context.ASSIGN() == null:
			lhs = VisitMethod_invocation_block(context.method_invocation_block(), lhs)
			return ExpressionStatement(lhs)
		else:
			rhs as Expression
			modifier as StatementModifier = null
			if context.callable_expression() != null:
				rhs = VisitCallable_expression(context.callable_expression())
			else:
				rhs = VisitArray_or_expression(context.array_or_expression())
				if context.method_invocation_block() != null:
					rhs = VisitMethod_invocation_block(context.method_invocation_block(), rhs)
				elif context.stmt_modifier() != null:
					modifier = VisitStmt_modifier(context.stmt_modifier())
			return ExpressionStatement( lhs.LexicalInfo, BinaryExpression(GetLexicalInfo(context.ASSIGN()), OperatorParser.ParseAssignment(context.ASSIGN().GetText()), lhs, rhs), modifier)

	def IBooParserVisitor[of Node].VisitAssignment_or_method_invocation_with_block_stmt(context as BooParser.Assignment_or_method_invocation_with_block_stmtContext) as Node:
		return VisitAssignment_or_method_invocation_with_block_stmt(context)

	def VisitAssignment_or_method_invocation(context as BooParser.Assignment_or_method_invocationContext) as Statement:
		if context == null:
			return null

		lhs as Expression = VisitSlicing_expression(context.slicing_expression())
		rhs as Expression = VisitArray_or_expression(context.array_or_expression())
		return ExpressionStatement( lhs.LexicalInfo, BinaryExpression(GetLexicalInfo(context.ASSIGN()), OperatorParser.ParseAssignment(context.ASSIGN().GetText()), lhs, rhs))

	def IBooParserVisitor[of Node].VisitAssignment_or_method_invocation(context as BooParser.Assignment_or_method_invocationContext) as Node:
		return VisitAssignment_or_method_invocation(context)

	def VisitNot_expression(context as BooParser.Not_expressionContext) as Expression:
		if context == null:
			return null

		if context.assignment_expression() != null:
			return VisitAssignment_expression(context.assignment_expression())
		result as Expression = VisitNot_expression(context.not_expression())
		return UnaryExpression(GetLexicalInfo(context.NOT()), UnaryOperatorType.LogicalNot, result)

	def IBooParserVisitor[of Node].VisitNot_expression(context as BooParser.Not_expressionContext) as Node:
		return VisitNot_expression(context)

	def VisitAssignment_expression(context as BooParser.Assignment_expressionContext) as Expression:
		if context == null:
			return null

		result = VisitConditional_expression(context.conditional_expression())
		if context.assignment_expression() != null:
			binaryOperator as BinaryOperatorType
			token = context.ASSIGN()
			if token != null:
				binaryOperator = OperatorParser.ParseAssignment(token.GetText())
			else:
				token =((((context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) if (context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) is not null else context.INPLACE_BITWISE_AND()) if ((context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) if (context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) is not null else context.INPLACE_BITWISE_AND()) is not null else context.INPLACE_SHIFT_LEFT()) if (((context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) if (context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) is not null else context.INPLACE_BITWISE_AND()) if ((context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) if (context.INPLACE_BITWISE_OR() if context.INPLACE_BITWISE_OR() is not null else context.INPLACE_EXCLUSIVE_OR()) is not null else context.INPLACE_BITWISE_AND()) is not null else context.INPLACE_SHIFT_LEFT()) is not null else context.INPLACE_SHIFT_RIGHT())
				binaryOperator = OperatorParser.ParseCondAssignment(token.GetText())
			r = VisitAssignment_expression(context.assignment_expression())
			result = BinaryExpression(GetLexicalInfo(token), binaryOperator, result, r)
		return result

	def IBooParserVisitor[of Node].VisitAssignment_expression(context as BooParser.Assignment_expressionContext) as Node:
		return VisitAssignment_expression(context)

	def VisitAny_cond_expr_value(context as BooParser.Any_cond_expr_valueContext, e as Expression) as Expression:
		r as Expression = null
		op as BinaryOperatorType
		token as ITerminalNode
		if context.ISA() != null:
			tr as TypeReference = VisitType_reference(context.type_reference())
			op = BinaryOperatorType.TypeTest
			r = TypeofExpression(tr.LexicalInfo, tr)
			token = context.ISA()
		else:
			if context.CMP_OPERATOR() != null:
				token = context.CMP_OPERATOR(); op = OperatorParser.ParseComparison(token.GetText())
			elif context.GREATER_THAN() != null:
				token = context.GREATER_THAN(); op = BinaryOperatorType.GreaterThan
			elif context.LESS_THAN() != null:
				token = context.LESS_THAN(); op = BinaryOperatorType.LessThan
			elif context.IS() != null:
				token = context.IS()
				if context.NOT() != null:
					op = BinaryOperatorType.ReferenceInequality
				else:
					op = BinaryOperatorType.ReferenceEquality
			elif context.NOT() != null:
				token = context.NOT(); op = BinaryOperatorType.NotMember
			else:
				token = context.IN(); op = BinaryOperatorType.Member
			r = VisitSum(context.sum())
		return BinaryExpression(GetLexicalInfo(token), op, e, r)

	def IBooParserVisitor[of Node].VisitAny_cond_expr_value(context as BooParser.Any_cond_expr_valueContext) as Node:
		raise NotImplementedException()

	def VisitConditional_expression(context as BooParser.Conditional_expressionContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitSum(context.sum())
		conds = context.any_cond_expr_value()
		if conds != null:
			for expr in conds:
				result = VisitAny_cond_expr_value(expr, result)
		return result

	def IBooParserVisitor[of Node].VisitConditional_expression(context as BooParser.Conditional_expressionContext) as Node:
		return VisitConditional_expression(context)

	def VisitAny_sum_value(context as BooParser.Any_sum_valueContext, e as Expression) as Expression:
		op as BinaryOperatorType
		token as ITerminalNode
		if context.ADD() != null:
			token = context.ADD(); op = BinaryOperatorType.Addition
		elif context.SUBTRACT() != null:
			token = context.SUBTRACT(); op = BinaryOperatorType.Subtraction
		elif context.BITWISE_OR() != null:
			token = context.BITWISE_OR(); op = BinaryOperatorType.BitwiseOr
		else:
			token = context.EXCLUSIVE_OR(); op = BinaryOperatorType.ExclusiveOr
		r as Expression = VisitTerm(context.term())
		return BinaryExpression(GetLexicalInfo(token), op, e, r)

	def IBooParserVisitor[of Node].VisitAny_sum_value(context as BooParser.Any_sum_valueContext) as Node:
		raise NotImplementedException()

	def VisitSum(context as BooParser.SumContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitTerm(context.term())
		terms = context.any_sum_value()
		if terms != null:
			for term in terms:
				result = VisitAny_sum_value(term, result)
		return result

	def IBooParserVisitor[of Node].VisitSum(context as BooParser.SumContext) as Node:
		return VisitSum(context)

	def VisitAny_term_value(context as BooParser.Any_term_valueContext, e as Expression) as Expression:
		op as BinaryOperatorType
		token as ITerminalNode
		if context.MULTIPLY() != null:
			token = context.MULTIPLY(); op = BinaryOperatorType.Multiply
		elif context.DIVISION() != null:
			token = context.DIVISION(); op = BinaryOperatorType.Division
		elif context.MODULUS() != null:
			token = context.MODULUS(); op = BinaryOperatorType.Modulus
		else:
			token = context.BITWISE_AND(); op = BinaryOperatorType.BitwiseAnd
		r as Expression = VisitFactor(context.factor())
		return BinaryExpression(GetLexicalInfo(token), op, e, r)

	def IBooParserVisitor[of Node].VisitAny_term_value(context as BooParser.Any_term_valueContext) as Node:
		raise NotImplementedException()

	def VisitTerm(context as BooParser.TermContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitFactor(context.factor())
		factors = context.any_term_value()
		if factors != null:
			for factor in factors:
				result = VisitAny_term_value(factor, result)
		return result

	def IBooParserVisitor[of Node].VisitTerm(context as BooParser.TermContext) as Node:
		return VisitTerm(context)

	def VisitAny_factor_value(context as BooParser.Any_factor_valueContext, e as Expression) as Expression:
		op as BinaryOperatorType
		token as ITerminalNode
		if context.SHIFT_LEFT() != null:
			token = context.SHIFT_LEFT(); op = BinaryOperatorType.ShiftLeft
		else:
			token = context.SHIFT_RIGHT(); op = BinaryOperatorType.ShiftRight
		r as Expression = VisitExponentiation(context.exponentiation())
		return BinaryExpression(GetLexicalInfo(token), op, e, r)

	def IBooParserVisitor[of Node].VisitAny_factor_value(context as BooParser.Any_factor_valueContext) as Node:
		raise NotImplementedException()

	def VisitFactor(context as BooParser.FactorContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitExponentiation(context.exponentiation())
		exps = context.any_factor_value()
		if exps != null:
			for exp in exps:
				result = VisitAny_factor_value(exp, result)
		return result

	def IBooParserVisitor[of Node].VisitFactor(context as BooParser.FactorContext) as Node:
		return VisitFactor(context)

	def VisitExponentiation(context as BooParser.ExponentiationContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitUnary_expression(context.unary_expression())
		tr as TypeReference
		if context.AS() != null:
			tr = VisitType_reference(context.type_reference())
			result = TryCastExpression(GetLexicalInfo(context.AS()), result, tr)
		elif context.CAST() != null:
			tr = VisitType_reference(context.type_reference())
			result = CastExpression(GetLexicalInfo(context.CAST()), result, tr)
		if context.exponentiation() != null:
			i as int = -1
			token as ITerminalNode
			r as Expression
			for exp in context.exponentiation():
				++i
				token = context.EXPONENTIATION(i)
				r = VisitExponentiation(exp)
				result = BinaryExpression(GetLexicalInfo(token), BinaryOperatorType.Exponentiation, result, r)
		return result

	def IBooParserVisitor[of Node].VisitExponentiation(context as BooParser.ExponentiationContext) as Node:
		return VisitExponentiation(context)

	def VisitUnary_expression(context as BooParser.Unary_expressionContext) as Expression:
		if context == null:
			return null

		op as UnaryOperatorType = UnaryOperatorType.None
		token as ITerminalNode = null
		result as Expression
		if context.integer_literal() != null:
			return VisitInteger_literal(context.integer_literal())
		if context.unary_expression() != null:
			if context.MULTIPLY() != null:
				token = context.MULTIPLY(); op = UnaryOperatorType.Explode
			elif context.SUBTRACT() != null:
				token = context.SUBTRACT(); op = UnaryOperatorType.UnaryNegation
			elif context.INCREMENT() != null:
				token = context.INCREMENT(); op = UnaryOperatorType.Increment
			elif context.DECREMENT() != null:
				token = context.DECREMENT(); op = UnaryOperatorType.Decrement
			else:
				token = context.ONES_COMPLEMENT(); op = UnaryOperatorType.OnesComplement
			result = VisitUnary_expression(context.unary_expression())
		else:
			result = VisitSlicing_expression(context.slicing_expression())
			if context.INCREMENT() != null:
				token = context.INCREMENT(); op = UnaryOperatorType.PostIncrement
			elif context.DECREMENT() != null:
				token = context.DECREMENT(); op = UnaryOperatorType.PostDecrement
		if token != null:
			result = UnaryExpression(GetLexicalInfo(token), op, result)
		return result

	def IBooParserVisitor[of Node].VisitUnary_expression(context as BooParser.Unary_expressionContext) as Node:
		return VisitUnary_expression(context)

	def VisitAtom(context as BooParser.AtomContext) as Expression:
		if context == null:
			return null

		if context.literal() != null:
			return VisitLiteral(context.literal())
		if context.char_literal() != null:
			return VisitChar_literal(context.char_literal())
		if context.reference_expression() != null:
			return VisitReference_expression(context.reference_expression())
		if context.paren_expression() != null:
			return VisitParen_expression(context.paren_expression())
		if context.cast_expression() != null:
			return VisitCast_expression(context.cast_expression())
		if context.typeof_expression() != null:
			return VisitTypeof_expression(context.typeof_expression())
		if context.splice_expression() != null:
			return VisitSplice_expression(context.splice_expression())
		return VisitOmitted_member_expression(context.omitted_member_expression())

	def IBooParserVisitor[of Node].VisitAtom(context as BooParser.AtomContext) as Node:
		return VisitAtom(context)

	def VisitOmitted_member_expression(context as BooParser.Omitted_member_expressionContext) as Expression:
		if context == null:
			return null

		memberName = VisitMember(context.member())
		return MemberReferenceForToken(OmittedExpression(GetLexicalInfo(context.DOT())), memberName)

	def IBooParserVisitor[of Node].VisitOmitted_member_expression(context as BooParser.Omitted_member_expressionContext) as Node:
		return VisitOmitted_member_expression(context)

	def VisitSplice_expression(context as BooParser.Splice_expressionContext) as SpliceExpression:
		if context == null:
			return null

		e = VisitAtom(context.atom())
		return SpliceExpression(GetLexicalInfo(context.SPLICE_BEGIN()), e)

	def IBooParserVisitor[of Node].VisitSplice_expression(context as BooParser.Splice_expressionContext) as Node:
		return VisitSplice_expression(context)

	def VisitChar_literal(context as BooParser.Char_literalContext) as Expression:
		if context == null:
			return null

		charToken = context.CHAR()
		t = context.SINGLE_QUOTED_STRING()
		if t != null:
			return CharLiteralExpression(GetLexicalInfo(t), SqsUnquote(t.GetText()))
		i = context.INT()
		if i != null:
			return CharLiteralExpression(GetLexicalInfo(i), cast(char, Boo.Lang.Parser.PrimitiveParser.ParseInt(i)))
		return MethodInvocationExpression( GetLexicalInfo(charToken), ReferenceExpression(GetLexicalInfo(charToken), charToken.GetText()))

	def IBooParserVisitor[of Node].VisitChar_literal(context as BooParser.Char_literalContext) as Node:
		return VisitChar_literal(context)

	def VisitCast_expression(context as BooParser.Cast_expressionContext) as CastExpression:
		if context == null:
			return null

		tr = VisitType_reference(context.type_reference())
		target = VisitExpression(context.expression())
		return CastExpression(GetLexicalInfo(context.CAST()), target, tr)

	def IBooParserVisitor[of Node].VisitCast_expression(context as BooParser.Cast_expressionContext) as Node:
		return VisitCast_expression(context)

	def VisitTypeof_expression(context as BooParser.Typeof_expressionContext) as TypeofExpression:
		if context == null:
			return null

		tr = VisitType_reference(context.type_reference())
		return TypeofExpression(GetLexicalInfo(context.TYPEOF()), tr)

	def IBooParserVisitor[of Node].VisitTypeof_expression(context as BooParser.Typeof_expressionContext) as Node:
		return VisitTypeof_expression(context)

	def VisitReference_expression(context as BooParser.Reference_expressionContext) as ReferenceExpression:
		if context == null:
			return null

		t = context.Start
		return ReferenceExpression(GetLexicalInfo(t), t.Text)

	def IBooParserVisitor[of Node].VisitReference_expression(context as BooParser.Reference_expressionContext) as Node:
		return VisitReference_expression(context)

	def VisitParen_expression(context as BooParser.Paren_expressionContext) as Expression:
		if context == null:
			return null

		if context.typed_array() != null:
			return VisitTyped_array(context.typed_array())
		result as Expression = VisitArray_or_expression(context.array_or_expression(0))
		if context.IF() != null:
			condition = VisitBoolean_expression(context.boolean_expression())
			falseValue = VisitArray_or_expression(context.array_or_expression(1))
			ce as ConditionalExpression = ConditionalExpression(GetLexicalInfo(context.LPAREN()))
			ce.Condition = condition
			ce.TrueValue = result
			ce.FalseValue = falseValue
			result = ce
		return result

	def IBooParserVisitor[of Node].VisitParen_expression(context as BooParser.Paren_expressionContext) as Node:
		return VisitParen_expression(context)

	def VisitTyped_array(context as BooParser.Typed_arrayContext) as ArrayLiteralExpression:
		if context == null:
			return null

		tr = VisitType_reference(context.type_reference())
		result = ArrayLiteralExpression(GetLexicalInfo(context.LPAREN()), Type: ArrayTypeReference(tr.LexicalInfo, tr))
		exprs = context.expression()
		if exprs != null:
			for expr in exprs:
				added = VisitExpression(expr)
				if added != null:
					result.Items.Add(added)
		return result

	def IBooParserVisitor[of Node].VisitTyped_array(context as BooParser.Typed_arrayContext) as Node:
		return VisitTyped_array(context)

	def VisitMember(context as BooParser.MemberContext) as ITerminalNode:
		if context == null:
			return null

		return ((((((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) if (((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) is not null else context.EVENT()) if ((((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) if (((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) is not null else context.EVENT()) is not null else context.REF()) if (((((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) if (((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) is not null else context.EVENT()) if ((((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) if (((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) if ((((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) if (((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) if ((context.ID() if context.ID() is not null else context.SET()) if (context.ID() if context.ID() is not null else context.SET()) is not null else context.GET()) is not null else context.INTERNAL()) is not null else context.PUBLIC()) is not null else context.PROTECTED()) is not null else context.EVENT()) is not null else context.REF()) is not null else context.YIELD())

	def IBooParserVisitor[of Node].VisitMember(context as BooParser.MemberContext) as Node:
		raise NotImplementedException()

	def VisitSlice_no_begin(context as BooParser.Slice_no_beginContext) as Slice:
		if context == null:
			return null

		end_ as Expression = null
		step as Expression = null
		begin as Expression = OmittedExpression.Default
		if context.expression() == null:
			// [:] states no end at all in boo.g; only [::step] omits one.
			if context.COLON().Length > 1:
				end_ = OmittedExpression.Default
		elif context.COLON().Length == 1:
			end_ = VisitExpression(context.expression())
		else:
			end_ = OmittedExpression.Default
			step = VisitExpression(context.expression())
		// No lexical info of its own: boo.g leaves it empty so a slice reports
		// the position of the slicing expression around it.
		return Slice(begin, end_, step)

	def IBooParserVisitor[of Node].VisitSlice_no_begin(context as BooParser.Slice_no_beginContext) as Node:
		raise NotImplementedException()

	def VisitSlice_with_begin(context as BooParser.Slice_with_beginContext) as Slice:
		if context == null:
			return null

		exprs = context.expression()
		begin as Expression = VisitExpression(exprs[0])
		end_ as Expression = null
		step as Expression = null
		if context.COLON().Length > 0:
			if exprs.Length == 1:
				end_ = OmittedExpression.Default
			else:
				end_ = VisitExpression(exprs[1])

			if context.COLON().Length == 2:
				step = VisitExpression(exprs.Last())
		return Slice(begin, end_, step)

	def IBooParserVisitor[of Node].VisitSlice_with_begin(context as BooParser.Slice_with_beginContext) as Node:
		raise NotImplementedException()

	def VisitSlice(context as BooParser.SliceContext, se as SlicingExpression):
		if context.slice_no_begin() != null:
			added = VisitSlice_no_begin(context.slice_no_begin())
			if added != null:
				se.Indices.Add(added)
		else:
			added2 = VisitSlice_with_begin(context.slice_with_begin())
			if added2 != null:
				se.Indices.Add(added2)

	def IBooParserVisitor[of Node].VisitSlice(context as BooParser.SliceContext) as Node:
		raise NotImplementedException()

	def VisitSafe_atom(context as BooParser.Safe_atomContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitAtom(context.atom())
		if context.NULLABLE_SUFFIX() != null:
			return UnaryExpression(result.LexicalInfo, UnaryOperatorType.SafeAccess, result)
		return result

	def IBooParserVisitor[of Node].VisitSafe_atom(context as BooParser.Safe_atomContext) as Node:
		return VisitSafe_atom(context)

	def ParseSliceTypeRefList(context as BooParser.Any_slice_expr_valueContext, e as Expression) as Expression:
		result as Expression
		lbrack = context.LBRACK()
		if context.OF() != null:
			gre = GenericReferenceExpression(GetLexicalInfo(lbrack), Target: e)
			AddTypeReferences(gre.GenericArguments, context.type_reference_list())
			result = gre
		else:
			se = SlicingExpression(GetLexicalInfo(lbrack), Target: e)
			result = se
			for sl in context.slice():
				VisitSlice(sl, se)
		if context.NULLABLE_SUFFIX() != null:
			result = UnaryExpression(result.LexicalInfo, UnaryOperatorType.SafeAccess, result)
		return result

	def ParseSliceGenericType(context as BooParser.Any_slice_expr_valueContext, e as Expression) as GenericReferenceExpression:
		genericArgument = VisitType_reference(context.type_reference())
		result = GenericReferenceExpression(GetLexicalInfo(context.OF()), Target: e)
		result.GenericArguments.Add(genericArgument)
		return result

	def ParseSliceDot(context as BooParser.Any_slice_expr_valueContext, e as Expression) as Expression:
		result as Expression
		if context.member() != null:
			result = MemberReferenceForToken(e, VisitMember(context.member()))
		else:
			begin = context.SPLICE_BEGIN()
			nameSplice = VisitAtom(context.atom())
			result = SpliceMemberReferenceExpression( GetLexicalInfo(begin), e, nameSplice)
		if context.NULLABLE_SUFFIX() != null:
			result = UnaryExpression(result.LexicalInfo, UnaryOperatorType.SafeAccess, result)
		return result

	def ParseSliceMethod(context as BooParser.Any_slice_expr_valueContext, e as Expression) as Expression:
		lparen = context.LPAREN()
		result as Expression = MethodInvocationExpression(GetLexicalInfo(lparen), e)
		args = context.argument()
		initializer as Expression = null
		if args != null:
			for arg in args:
				VisitArgument(arg, cast(MethodInvocationExpression, result))
		if context.NULLABLE_SUFFIX() != null:
			result = UnaryExpression(result.LexicalInfo, UnaryOperatorType.SafeAccess, result)
		if context.hash_literal() != null:
			initializer = VisitHash_literal(context.hash_literal())
		elif context.list_initializer() != null:
			initializer = VisitList_initializer(context.list_initializer())
		if initializer != null:
			result = CollectionInitializationExpression(result, initializer)
		return result

	def VisitAny_slice_expr_value(context as BooParser.Any_slice_expr_valueContext, e as Expression) as Expression:
		if context.LBRACK() != null:
			return ParseSliceTypeRefList(context, e)
		if context.OF() != null:
			return ParseSliceGenericType(context, e)
		if context.DOT() != null:
			return ParseSliceDot(context, e)
		return ParseSliceMethod(context, e)

	def IBooParserVisitor[of Node].VisitAny_slice_expr_value(context as BooParser.Any_slice_expr_valueContext) as Node:
		raise NotImplementedException()

	def VisitSlicing_expression(context as BooParser.Slicing_expressionContext) as Expression:
		if context == null:
			return null

		result as Expression = VisitSafe_atom(context.safe_atom())
		modifiers = context.any_slice_expr_value()
		if modifiers != null:
			for mod in modifiers:
				result = VisitAny_slice_expr_value(mod, result)
		return result

	def IBooParserVisitor[of Node].VisitSlicing_expression(context as BooParser.Slicing_expressionContext) as Node:
		return VisitSlicing_expression(context)

	def VisitList_initializer(context as BooParser.List_initializerContext) as ListLiteralExpression:
		if context == null:
			return null

		result = ListLiteralExpression(GetLexicalInfo(context.LBRACE()))
		AddListItems(result.Items, context.list_items())
		return result

	def IBooParserVisitor[of Node].VisitList_initializer(context as BooParser.List_initializerContext) as Node:
		return VisitList_initializer(context)

	def VisitLiteral(context as BooParser.LiteralContext) as Expression:
		if context == null:
			return null

		return (null if context.ChildCount == 0 else cast(Expression, Visit(context.GetChild(0))))

	def IBooParserVisitor[of Node].VisitLiteral(context as BooParser.LiteralContext) as Node:
		return VisitLiteral(context)

	def VisitSelf_literal(context as BooParser.Self_literalContext) as SelfLiteralExpression:
		if context == null:
			return null

		return SelfLiteralExpression(GetLexicalInfo(context.SELF()))

	def IBooParserVisitor[of Node].VisitSelf_literal(context as BooParser.Self_literalContext) as Node:
		return VisitSelf_literal(context)

	def VisitSuper_literal(context as BooParser.Super_literalContext) as SuperLiteralExpression:
		if context == null:
			return null

		return SuperLiteralExpression(GetLexicalInfo(context.SUPER()))

	def IBooParserVisitor[of Node].VisitSuper_literal(context as BooParser.Super_literalContext) as Node:
		return VisitSuper_literal(context)

	def VisitNull_literal(context as BooParser.Null_literalContext) as NullLiteralExpression:
		if context == null:
			return null

		return NullLiteralExpression(GetLexicalInfo(context.NULL()))

	def IBooParserVisitor[of Node].VisitNull_literal(context as BooParser.Null_literalContext) as Node:
		return VisitNull_literal(context)

	def VisitBool_literal(context as BooParser.Bool_literalContext) as BoolLiteralExpression:
		if context == null:
			return null

		if context.TRUE() != null:
			return BoolLiteralExpression(GetLexicalInfo(context.TRUE()), true)
		return BoolLiteralExpression(GetLexicalInfo(context.FALSE()), false)

	def IBooParserVisitor[of Node].VisitBool_literal(context as BooParser.Bool_literalContext) as Node:
		return VisitBool_literal(context)

	/// <summary>
	/// A numeric literal without its digit group separators. boo.g drops them in
	/// the lexer, with an operator ANTLR 4 has no equivalent for.
	/// </summary>
	static def Ungrouped(node as ITerminalNode) as string:
		return node.GetText().Replace("_", string.Empty)

	def VisitInteger_literal(context as BooParser.Integer_literalContext) as IntegerLiteralExpression:
		if context == null:
			return null

		number as string = null
		sign as ITerminalNode = context.SUBTRACT()
		i = context.INT()
		if i != null:
			number =(sign.GetText() + Ungrouped(i) if sign != null else Ungrouped(i))
			return PrimitiveParser.ParseIntegerLiteralExpression(GetLexicalInfo(i), number, false)
		l = context.LONG()
		number =(sign.GetText() + Ungrouped(l) if sign != null else Ungrouped(l))
		return PrimitiveParser.ParseIntegerLiteralExpression(GetLexicalInfo(l), number, true)

	def IBooParserVisitor[of Node].VisitInteger_literal(context as BooParser.Integer_literalContext) as Node:
		return VisitInteger_literal(context)

	def SqsUnquote(value as string) as string:
		if not value.StartsWith("'")  or  not value.EndsWith("'")  or  value.Length < 2:
			raise FormatException(string.Format("[{0}] is not a single-quoted string.", value))

		builder as StringBuilder = StringBuilder()
		# The body moves the index on, and in C# the continue still ran the
		# increment, so this cannot be a for over a range.
		i = 1
		while i < value.Length - 1:
			if value[i] == char('\\'):
				if value[i + 1] == char('u'):
					builder.Append(UnescapeCharacter(value.Substring(i, 6)))
					i += 5
				else:
					builder.Append(UnescapeCharacter(value.Substring(i, 2)))
					i += 1
			else:
				builder.Append(value[i])
			i += 1

		return builder.ToString()

	def DqsUnquote(value as string) as string:
		// An unterminated string reaches here without its closing quote.
		if value.StartsWith("\"")  and  value.EndsWith("\"")  and  value.Length > 1:
			return value.Substring(1, value.Length - 2)
		return (value.Substring(1) if value.StartsWith("\"") else value)

	def TqsUnquote(value as string) as string:
		if value.StartsWith("\"\"\"")  and  value.EndsWith("\"\"\""):
			return value.Substring(3, value.Length - 6).Replace("\\$", "$")
		raise FormatException(string.Format("[{0}] is not a triple-quoted string.", value))

	def BqsUnquote(value as string) as string:
		if value.StartsWith("`")  and  value.EndsWith("`"):
			return value.Substring(1, value.Length - 2)
		raise FormatException(string.Format("[{0}] is not a backtick-quoted string.", value))

	def VisitString_literal(context as BooParser.String_literalContext) as Expression:
		if context == null:
			return null

		e as StringLiteralExpression = null
		if context.expression_interpolation() != null:
			return VisitExpression_interpolation(context.expression_interpolation())

		dqs = context.double_quoted_string()
		if dqs != null:
			return VisitDouble_quoted_string(dqs)

		tqs = context.triple_quoted_string()
		if tqs != null:
			return VisitTriple_quoted_string(tqs)

		sqs = context.SINGLE_QUOTED_STRING()
		if sqs != null:
			e = StringLiteralExpression(GetLexicalInfo(sqs), SqsUnquote(sqs.GetText()))
			e.Annotate("quote", "'")
			return e

		bqs = context.BACKTICK_QUOTED_STRING()
		e = StringLiteralExpression(GetLexicalInfo(bqs), BqsUnquote(bqs.GetText()))
		e.Annotate("quote", "`")
		return e

	def IBooParserVisitor[of Node].VisitString_literal(context as BooParser.String_literalContext) as Node:
		return VisitString_literal(context)

	def UnescapeCharacter(escapedForm as string) as char:
		if escapedForm[0] != char('\\'):
			raise ArgumentException()

		if escapedForm[1] == char('r'):
			return char('\r')
		elif escapedForm[1] == char('n'):
			return char('\n')
		elif escapedForm[1] == char('t'):
			return char('\t')
		elif escapedForm[1] == char('a'):
			return char('\a')
		elif escapedForm[1] == char('b'):
			return char('\b')
		elif escapedForm[1] == char('f'):
			return char('\f')
		elif escapedForm[1] == char('0'):
			return char('\0')
		elif escapedForm[1] == char('u'):
			return cast(char, int.Parse(escapedForm.Substring(2), NumberStyles.HexNumber))
		else:
			return escapedForm[1]

	def VisitDouble_quoted_string(context as BooParser.Double_quoted_stringContext) as Expression:
		if context == null:
			return null

		if context.expression(0) == null  and  context.INTERPOLATED_REFERENCE(0) == null:
			content as StringBuilder = StringBuilder()
			for i in range(0, context.ChildCount):
				terminalNode as ITerminalNode = cast(ITerminalNode, context.GetChild(i))
				if terminalNode.Symbol.Type == BooParser.TEXT:
					content.Append(terminalNode.Symbol.Text)

				elif terminalNode.Symbol.Type == BooParser.DQS_ESC:
					content.Append(UnescapeCharacter(terminalNode.Symbol.Text))

				else:
					pass

			e as StringLiteralExpression = null
			e = StringLiteralExpression(GetLexicalInfo(context), content.ToString())
			e.Annotate("quote", "\"")
			return e

		result = ExpressionInterpolationExpression(GetLexicalInfo(context))
		run = InterpolationRun(self, result)
		for i in range(0, context.ChildCount):
			node as IParseTree = context.GetChild(i)
			terminalNode = node as ITerminalNode
			if terminalNode != null:
				if terminalNode.Symbol.Type == BooParser.TEXT:
					run.Append(terminalNode, terminalNode.Symbol.Text)

				elif terminalNode.Symbol.Type == BooParser.DQS_ESC:
					run.Append(terminalNode, UnescapeCharacter(terminalNode.Symbol.Text).ToString())

				elif terminalNode.Symbol.Type == BooParser.INTERPOLATED_REFERENCE:
					run.Flush()
					result.Expressions.Add(ReferenceExpression(GetLexicalInfo(terminalNode), terminalNode.GetText().Substring(1)))
					run.DelimitedBy(terminalNode, true)

				elif terminalNode.Symbol.Type == BooParser.INTERPOLATED_EXPRESSION_LBRACE or terminalNode.Symbol.Type == BooParser.INTERPOLATED_EXPRESSION_LPAREN:
					run.Flush()

				elif terminalNode.Symbol.Type == BooParser.ID:
					if result.Expressions.Count > 0:
						result.Expressions[-1].Annotate("formatString", terminalNode.GetText())

				elif terminalNode.Symbol.Type == BooParser.DOUBLE_QUOTED_STRING or terminalNode.Symbol.Type == BooParser.RBRACE or terminalNode.Symbol.Type == BooParser.RPAREN:
					run.DelimitedBy(terminalNode, false)

				else:
					pass

				continue

			ruleNode as IRuleNode = node as IRuleNode
			if ruleNode != null:
				added = VisitExpression(cast(BooParser.ExpressionContext, ruleNode))
				if added != null:
					result.Expressions.Add(added)
		run.FlushLast()

		return result

	def IBooParserVisitor[of Node].VisitDouble_quoted_string(context as BooParser.Double_quoted_stringContext) as Node:
		return VisitDouble_quoted_string(context)

	def VisitTriple_quoted_string(context as BooParser.Triple_quoted_stringContext) as Expression:
		if context == null:
			return null

		if context.expression(0) == null  and  context.INTERPOLATED_REFERENCE(0) == null:
			e as StringLiteralExpression = null
			e = StringLiteralExpression(GetLexicalInfo(context), TqsUnquote(context.GetText()))
			e.Annotate("quote", "\"\"\"")
			return e

		result = ExpressionInterpolationExpression(GetLexicalInfo(context))
		run = InterpolationRun(self, result)
		for i in range(0, context.ChildCount):
			node as IParseTree = context.GetChild(i)
			terminalNode as ITerminalNode = node as ITerminalNode
			if terminalNode != null:
				if terminalNode.Symbol.Type == BooParser.TEXT:
					run.Append(terminalNode, terminalNode.Symbol.Text.Replace("\\$", "$"))

				elif terminalNode.Symbol.Type == BooParser.INTERPOLATED_REFERENCE:
					run.Flush()
					result.Expressions.Add(ReferenceExpression(GetLexicalInfo(terminalNode), terminalNode.GetText().Substring(1)))
					run.DelimitedBy(terminalNode, true)

				elif terminalNode.Symbol.Type == BooParser.INTERPOLATED_EXPRESSION_LBRACE or terminalNode.Symbol.Type == BooParser.INTERPOLATED_EXPRESSION_LPAREN:
					run.Flush()

				elif terminalNode.Symbol.Type == BooParser.ID:
					if result.Expressions.Count > 0:
						result.Expressions[-1].Annotate("formatString", terminalNode.GetText())

				elif terminalNode.Symbol.Type == BooParser.TRIPLE_QUOTED_STRING or terminalNode.Symbol.Type == BooParser.RBRACE or terminalNode.Symbol.Type == BooParser.RPAREN:
					run.DelimitedBy(terminalNode, false)

				else:
					pass

				continue

			ruleNode as IRuleNode = node as IRuleNode
			if ruleNode != null:
				added = VisitExpression(cast(BooParser.ExpressionContext, ruleNode))
				if added != null:
					result.Expressions.Add(added)
		run.FlushLast()

		return result

	def IBooParserVisitor[of Node].VisitTriple_quoted_string(context as BooParser.Triple_quoted_stringContext) as Node:
		return VisitTriple_quoted_string(context)

	def VisitAny_expr_interpolation_item(context as BooParser.Any_expr_interpolation_itemContext, e as ExpressionInterpolationExpression) as ExpressionInterpolationExpression:
		startsep = context.ESEPARATOR(0)
		if e == null:
			e = ExpressionInterpolationExpression(GetLexicalInfo(startsep))
		param = VisitExpression(context.expression())
		formatString as ITerminalNode = null
		formatSep as ITerminalNode = null
		if context.ID() != null:
			formatString = context.ID()
			formatSep = context.COLON()
		e.Expressions.Add(param)
		if formatString != null:
			param.Annotate("formatString", formatString.GetText())
		return e

	def IBooParserVisitor[of Node].VisitAny_expr_interpolation_item(context as BooParser.Any_expr_interpolation_itemContext) as Node:
		raise NotImplementedException()

	def VisitExpression_interpolation(context as BooParser.Expression_interpolationContext) as ExpressionInterpolationExpression:
		if context == null:
			return null

		result as ExpressionInterpolationExpression = null
		for item in context.any_expr_interpolation_item():
			result = VisitAny_expr_interpolation_item(item, result)
		return result

	def IBooParserVisitor[of Node].VisitExpression_interpolation(context as BooParser.Expression_interpolationContext) as Node:
		return VisitExpression_interpolation(context)

	def VisitList_literal(context as BooParser.List_literalContext) as ListLiteralExpression:
		if context == null:
			return null

		lbrack = context.LBRACK()
		result = ListLiteralExpression(GetLexicalInfo(lbrack))
		AddListItems(result.Items, context.list_items())
		return result

	def IBooParserVisitor[of Node].VisitList_literal(context as BooParser.List_literalContext) as Node:
		return VisitList_literal(context)

	def AddListItems(items as ExpressionCollection, context as BooParser.List_itemsContext):
		for expr in context.expression():
			added = VisitExpression(expr)
			if added != null:
				items.Add(added)

	def IBooParserVisitor[of Node].VisitList_items(context as BooParser.List_itemsContext) as Node:
		raise NotImplementedException()

	def VisitHash_literal(context as BooParser.Hash_literalContext) as HashLiteralExpression:
		if context == null:
			return null

		result = HashLiteralExpression(GetLexicalInfo(context.LBRACE()))
		for pair in context.expression_pair():
			added = VisitExpression_pair(pair)
			if added != null:
				result.Items.Add(added)
		return result

	def IBooParserVisitor[of Node].VisitHash_literal(context as BooParser.Hash_literalContext) as Node:
		return VisitHash_literal(context)

	def VisitExpression_pair(context as BooParser.Expression_pairContext) as ExpressionPair:
		if context == null:
			return null

		key = VisitExpression(context.expression(0))
		t = context.COLON()
		value = VisitExpression(context.expression(1))
		return ExpressionPair(GetLexicalInfo(t), key, value)

	def IBooParserVisitor[of Node].VisitExpression_pair(context as BooParser.Expression_pairContext) as Node:
		return VisitExpression_pair(context)

	def VisitRe_literal(context as BooParser.Re_literalContext) as RELiteralExpression:
		if context == null:
			return null

		value = context.RE_LITERAL()
		expressionText as string = value.GetText()
		if expressionText.StartsWith("@"):
			expressionText = expressionText.Substring(1)

		return RELiteralExpression(GetLexicalInfo(value), expressionText)

	def IBooParserVisitor[of Node].VisitRe_literal(context as BooParser.Re_literalContext) as Node:
		return VisitRe_literal(context)

	def VisitDouble_literal(context as BooParser.Double_literalContext) as DoubleLiteralExpression:
		if context == null:
			return null

		val as string
		neg = context.SUBTRACT()
		value = context.DOUBLE()
		if value != null:
			val = Ungrouped(value)
			if neg != null:
				val = neg.GetText() + val
			return DoubleLiteralExpression(GetLexicalInfo(value), PrimitiveParser.ParseDouble(GetLexicalInfo(value), val))
		single_ = context.FLOAT()
		val = Ungrouped(single_)
		val = val.Substring(0, val.Length - 1)
		if neg != null:
			val = neg.GetText() + val
		return DoubleLiteralExpression(GetLexicalInfo(single_), PrimitiveParser.ParseDouble(GetLexicalInfo(single_), val, true), true)

	def IBooParserVisitor[of Node].VisitDouble_literal(context as BooParser.Double_literalContext) as Node:
		return VisitDouble_literal(context)

	def VisitTimespan_literal(context as BooParser.Timespan_literalContext) as TimeSpanLiteralExpression:
		if context == null:
			return null

		neg = context.SUBTRACT()
		value = context.TIMESPAN()
		val as string = Ungrouped(value)
		if neg != null:
			val = neg.GetText() + val
		return TimeSpanLiteralExpression(GetLexicalInfo(value), PrimitiveParser.ParseTimeSpan(GetLexicalInfo(value), val))

	def IBooParserVisitor[of Node].VisitTimespan_literal(context as BooParser.Timespan_literalContext) as Node:
		return VisitTimespan_literal(context)

	def GetExpressionList(ec as ExpressionCollection, context as BooParser.Expression_listContext):
		if context != null:
			for expr in context.expression():
				added = VisitExpression(expr)
				if added != null:
					ec.Add(added)

	def IBooParserVisitor[of Node].VisitExpression_list(context as BooParser.Expression_listContext) as Node:
		raise NotImplementedException()

	def VisitArgument(context as BooParser.ArgumentContext, node as INodeWithArguments):
		if context.expression_pair() != null:
			added = VisitExpression_pair(context.expression_pair())
			if added != null:
				node.NamedArguments.Add(added)
		else:
			added2 = VisitExpression(context.expression())
			if added2 != null:
				node.Arguments.Add(added2)

	def IBooParserVisitor[of Node].VisitArgument(context as BooParser.ArgumentContext) as Node:
		raise NotImplementedException()

	def VisitIdentifier(context as BooParser.IdentifierContext) as string:
		if context == null:
			return null

		_sbuilder.Clear()
		id1 = context.macro_name()
		_sbuilder.Append(id1.GetText())
		members = context.member()
		if members != null:
			for id2 in members:
				_sbuilder.Append(char('.'))
				_sbuilder.Append(id2.GetText())
		return _sbuilder.ToString()

	def IBooParserVisitor[of Node].VisitIdentifier(context as BooParser.IdentifierContext) as Node:
		raise NotImplementedException()

