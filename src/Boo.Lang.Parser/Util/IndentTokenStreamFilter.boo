# Copyright (c) the Boo contributors
# All rights reserved.
#
# The Boo half of IndentTokenStreamFilter. Not compiled by Boo.Lang.Parser,
# which is C#; it pairs with the Boo the ANTLR Boo target emits, and is checked
# by tools/antlr-boo-target/test/check-boo-parser.sh.

namespace Boo.Lang.Parser.Util

import System
import System.Collections.Generic
import System.Text
import Antlr4.Runtime
import Boo.Lang.Parser

# Process whitespace tokens and generate INDENT, DEDENT virtual tokens as
# needed.
public class IndentTokenStreamFilter(ITokenSource):

	static final NewLineCharArray = (of char: char('\r'), char('\n'))

	# token input stream
	protected _source as ITokenSource

	protected _wsTokenType as int
	protected _newlineTokenType as int
	protected _indentTokenType as int
	protected _dedentTokenType as int
	protected _eosTokenType as int
	protected _endTokenType as int
	protected _idTokenType as int

	# stack of indent levels
	protected _indentStack = Stack[of int]()

	# tokens waiting to be consumed
	protected _pendingTokens = Queue[of IToken]()

	# last non whitespace token, for accurate location information
	protected _lastNonWsToken as IToken

	# first detected indentation character
	protected _expectedIndent as string

	_buffer = StringBuilder()

	public def constructor(source as ITokenSource, wsType as int, newlineTokenType as int, indentType as int, dedentType as int, eosType as int, endType as int, idType as int):
		raise ArgumentNullException("source") if source is null

		_source = source
		_wsTokenType = wsType
		_newlineTokenType = newlineTokenType
		_indentTokenType = indentType
		_dedentTokenType = dedentType
		_eosTokenType = eosType
		_endTokenType = endType
		_idTokenType = idType

		_indentStack.Push(0)  # current indent level is zero

	public InnerStream as ITokenSource:
		get:
			return _source

	public TokenFactory as ITokenFactory:
		get:
			return _source.TokenFactory
		set:
			_source.TokenFactory = value

	public Line as int:
		get:
			return _source.Line

	public Column as int:
		get:
			return _source.Column

	public InputStream as ICharStream:
		get:
			return _source.InputStream

	public SourceName as string:
		get:
			return _source.SourceName

	protected CurrentIndentLevel as int:
		get:
			return _indentStack.Peek()

	public def NextToken() as IToken:
		ProcessNextTokens() if _pendingTokens.Count == 0
		token = _pendingTokens.Dequeue()
		# In non-wsa mode `end` is just another identifier
		if token.Type == _endTokenType:
			cast(IWritableToken, token).Type = _idTokenType
		return token

	private def ResetBuffer():
		_buffer.Length = 0

	private def BufferUntilNextNonWhiteSpaceToken() as IToken:
		token as IToken = null
		while true:
			token = _source.NextToken()

			ttype = token.Type
			if token.Channel != TokenConstants.DefaultChannel:
				Enqueue(token)
				continue

			if ttype == _wsTokenType or ttype == _newlineTokenType:
				hidden = CommonToken(
					Tuple[of ITokenSource, ICharStream](token.TokenSource, token.InputStream),
					token.Type, token.Channel, token.StartIndex, token.StopIndex,
					Line: token.Line, Column: token.Column, Channel: TokenConstants.HiddenChannel)
				Enqueue(hidden)
				_buffer.Append(token.Text)
				continue

			break
		return token

	private def FlushBuffer(token as IToken):
		return if 0 == _buffer.Length

		text = _buffer.ToString()
		lines = text.Split(NewLineCharArray)

		return if lines.Length <= 1

		lastLine = lines[lines.Length - 1]

		# Protect against mixed indentation issues
		if string.Empty != lastLine:
			_expectedIndent = lastLine.Substring(0, 1) if _expectedIndent is null

			if lastLine.Replace(_expectedIndent, string.Empty) != string.Empty:
				literal as string
				if _expectedIndent == "\t":
					literal = "tabs"
				elif _expectedIndent == "\f":
					literal = "form feeds"  # The lexer allows them :p
				else:
					literal = "spaces"

				# Reported the way boo.g reports it: a parser error naming the
				# indentation in use, pointing at the first character that
				# breaks it.
				raise Boo.Lang.Compiler.CompilerErrorFactory.GenericParserError(
					Boo.Lang.Compiler.Ast.LexicalInfo(
						token.InputStream.SourceName,
						token.Line,
						lastLine.Length - lastLine.TrimStart(_expectedIndent[0]).Length + 1),
					Exception(string.Format(Boo.Lang.Resources.StringResources.BooParser_MixedIndentation, literal)))

		if lastLine.Length > CurrentIndentLevel:
			EnqueueIndent(token)
			_indentStack.Push(lastLine.Length)
		elif lastLine.Length < CurrentIndentLevel:
			EnqueueEOS(token)
			while true:
				EnqueueDedent()
				_indentStack.Pop()
				break unless lastLine.Length < CurrentIndentLevel
		else:
			EnqueueEOS(token)

	private def CheckForEOF(token as IToken):
		return if token.Type != TokenConstants.EOF

		EnqueueEOS(token)
		while CurrentIndentLevel > 0:
			EnqueueDedent()
			_indentStack.Pop()

	private def ProcessNextNonWhiteSpaceToken(token as IToken):
		_lastNonWsToken = token
		Enqueue(token)

	private def ProcessNextTokens():
		ResetBuffer()

		token = BufferUntilNextNonWhiteSpaceToken()
		FlushBuffer(token)
		CheckForEOF(token)
		ProcessNextNonWhiteSpaceToken(token)

	private def Enqueue(token as IToken):
		_pendingTokens.Enqueue(token)

	private def EnqueueIndent(prototype as IToken):
		_pendingTokens.Enqueue(CreateToken(prototype, _indentTokenType, "<INDENT>"))

	private def EnqueueDedent():
		_pendingTokens.Enqueue(CreateToken(_lastNonWsToken, _dedentTokenType, "<DEDENT>"))

	private def EnqueueEOS(prototype as IToken):
		_pendingTokens.Enqueue(CreateToken(prototype, _eosTokenType, "<EOL>"))

	private def CreateToken(prototype as IToken, newTokenType as int, newTokenText as string) as IToken:
		return BooToken(
			Tuple.Create[of ITokenSource, ICharStream](prototype.TokenSource, prototype.InputStream),
			newTokenType, newTokenText,
			prototype.InputStream.SourceName,
			prototype.StartIndex,
			prototype.StartIndex - 1,
			prototype.Line,
			ColumnAfter(prototype),
			true)

	# Where a token manufactured from this one sits: just past its text.
	private def ColumnAfter(prototype as IToken) as int:
		if prototype.Type == TokenConstants.EOF:
			return prototype.Column
		return prototype.Column + SafeGetLength(prototype.Text)

	private def SafeGetLength(s as string) as int:
		return (0 if s is null else s.Length)
