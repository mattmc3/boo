#region license
// Copyright (c) 2026 the Boo contributors
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
//     * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//     * Neither the name of Rodrigo B. de Oliveira nor the names of its
//     contributors may be used to endorse or promote products derived from this
//     software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#endregion

namespace boojupyter

import System
import System.Collections.Generic
import System.Reflection
import System.Threading
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Compiler.IO
import Boo.Lang.Compiler.TypeSystem
import Boo.Lang.Interpreter
import NetMQ
import NetMQ.Sockets

# Serves the Jupyter wire protocol on top of the Boo interactive interpreter,
# one thread per channel. Cell state lives in the interpreter, so a notebook
# sees the same names from one cell to the next.
class BooKernel:

	_connection as ConnectionInfo
	_signer as Signer
	_interpreter as InteractiveInterpreter
	_shell as RouterSocket
	_control as RouterSocket
	_stdin as RouterSocket
	_ioPub as PublisherSocket
	_heartbeat as ResponseSocket
	_ioPubLock = object()
	_stopped = ManualResetEventSlim(false)
	_executionCount = 0
	_running = true

	# One kernel to a process, so the cell helpers in Display can find the
	# channel to publish on without being handed one.
	static _current as BooKernel
	_parent as WireMessage

	[property(ShowWarnings)]
	_showWarnings as bool

	def constructor(connection as ConnectionInfo):
		_connection = connection
		_signer = Signer(connection.SignatureScheme, connection.Key)
		_interpreter = InteractiveInterpreter()
		_interpreter.RememberLastValue = true
		_interpreter.References.Add(typeof(BooKernel).Assembly)
		_interpreter.References.Add(typeof(Plotly.NET.GenericChart).Assembly)
		_interpreter.References.Add(typeof(Plotly.NET.CSharp.Chart).Assembly)
		_interpreter.Eval("import Boo.Lang.Interpreter.Builtins")
		_current = self

	def Run():
		_shell = RouterSocket(cast(string, null))
		_control = RouterSocket(cast(string, null))
		_stdin = RouterSocket(cast(string, null))
		_ioPub = PublisherSocket(cast(string, null))
		_heartbeat = ResponseSocket(cast(string, null))
		_shell.Bind(_connection.Address(_connection.ShellPort))
		_control.Bind(_connection.Address(_connection.ControlPort))
		_stdin.Bind(_connection.Address(_connection.StdinPort))
		_ioPub.Bind(_connection.Address(_connection.IoPubPort))
		_heartbeat.Bind(_connection.Address(_connection.HeartbeatPort))
		try:
			Spawn("boo-heartbeat", HeartbeatLoop)
			Spawn("boo-control", { Serve(_control) })
			Spawn("boo-shell", { Serve(_shell) })
			_stopped.Wait()
		ensure:
			_shell.Dispose()
			_control.Dispose()
			_stdin.Dispose()
			_ioPub.Dispose()
			_heartbeat.Dispose()

	private def Spawn(name as string, body as System.Action):
		thread = Thread(ThreadStart(body.Invoke))
		thread.Name = name
		thread.IsBackground = true
		thread.Start()

	private def HeartbeatLoop():
		while _running:
			try:
				_heartbeat.SendFrame(_heartbeat.ReceiveFrameBytes(), false)
			except:
				break

	private def Serve(socket as RouterSocket):
		while _running:
			request as WireMessage
			try:
				request = WireMessage.Receive(socket, _signer)
			except x:
				break unless _running
				Log(x)
				continue
			try:
				Publish(request, "status", Status("busy"))
				Handle(socket, request)
			except x:
				Log(x)
			ensure:
				Publish(request, "status", Status("idle"))

	private def Handle(socket as RouterSocket, request as WireMessage):
		messageType = request.MessageType
		if messageType == "kernel_info_request":
			Reply(socket, request, "kernel_info_reply", KernelInfo())
		elif messageType == "execute_request":
			Execute(socket, request)
		elif messageType == "complete_request":
			Reply(socket, request, "complete_reply", Complete(request))
		elif messageType == "is_complete_request":
			Reply(socket, request, "is_complete_reply", IsComplete(request))
		elif messageType == "comm_info_request":
			content = Ok()
			content["comms"] = Hash()
			Reply(socket, request, "comm_info_reply", content)
		elif messageType == "history_request":
			content = Ok()
			content["history"] = List[of string]()
			Reply(socket, request, "history_reply", content)
		elif messageType == "interrupt_request":
			Reply(socket, request, "interrupt_reply", Ok())
		elif messageType == "shutdown_request":
			Shutdown(socket, request)
		else:
			Log("unhandled message type: ${messageType}")

	private def Execute(socket as RouterSocket, request as WireMessage):
		code = Json.Text(request.Body, "code", string.Empty)
		silent = Json.Flag(request.Body, "silent", false)
		_executionCount++ unless silent
		_parent = request
		Publish(request, "execute_input", ExecuteInput(code))

		standardOutput = IoPubWriter({ text as string | Stream(request, "stdout", text) })
		standardError = IoPubWriter({ text as string | Stream(request, "stderr", text) })
		previousOutput = Console.Out
		previousError = Console.Error
		Console.SetOut(standardOutput)
		Console.SetError(standardError)
		try:
			result = Evaluate(code)
			if len(result.Errors) > 0:
				Fail(socket, request, "CompilerError", Describe(result.Errors))
				return
			ReportWarnings(request, result.Warnings)
			PublishResult(request) unless silent
			Reply(socket, request, "execute_reply", Completed())
		except x as TargetInvocationException:
			Fail(socket, request, x.InnerException)
		except x:
			Fail(socket, request, x)
		ensure:
			standardOutput.Flush()
			standardError.Flush()
			_parent = null
			Console.SetOut(previousOutput)
			Console.SetError(previousError)

	# A cell is one compilation unit, so a name on a line of its own parses as
	# a macro invocation. The interpreter rewrites that back to the name it
	# reads as, but only when the name is the whole input, and a cell usually
	# has statements before it.
	private def Evaluate(code as string) as CompilerContext:
		return CompilerContext(false) if len(code.Trim()) == 0
		parsed = _interpreter.Parse(StringInput("cell${_executionCount}", code))
		return parsed if len(parsed.Errors) > 0
		RewriteTrailingName(parsed.CompileUnit)
		return _interpreter.EvalCompileUnit(parsed.CompileUnit)

	static def RewriteTrailingName(unit as CompileUnit):
		return if len(unit.Modules) == 0
		statements = unit.Modules[0].Globals.Statements
		return if len(statements) < 2
		macro = statements[-1] as MacroStatement
		return if macro is null
		return unless len(macro.Arguments) == 0 and len(macro.Body.Statements) == 0
		statements.ReplaceAt(
			len(statements) - 1,
			ExpressionStatement(ReferenceExpression(macro.LexicalInfo, macro.Name)))

	static def Current() as BooKernel:
		return _current

	# Rich output for the cell being executed, one entry per representation.
	def Show(representations as Hash):
		return if _parent is null
		content = Hash()
		content["data"] = representations
		content["metadata"] = Hash()
		Publish(_parent, "display_data", content)

	private def PublishResult(parent as WireMessage):
		value = _interpreter.LastValue
		return if value is null
		_interpreter.SetValue("_", value)
		representation = Hash()
		representation["text/plain"] = Boo.Lang.Interpreter.Builtins.repr(value)
		content = Hash()
		content["execution_count"] = _executionCount
		content["data"] = representation
		content["metadata"] = Hash()
		Publish(parent, "execute_result", content)

	private def ReportWarnings(parent as WireMessage, warnings as CompilerWarningCollection):
		return unless _showWarnings
		for warning in warnings:
			Stream(parent, "stderr", "${warning}${Environment.NewLine}")

	private def Complete(request as WireMessage) as Hash:
		code = Json.Text(request.Body, "code", string.Empty)
		cursor = Json.Number(request.Body, "cursor_pos", len(code))
		cursor = len(code) if cursor < 0 or cursor > len(code)
		token = LastToken(code.Substring(0, cursor))
		dot = token.LastIndexOf(char('.'))
		if dot >= 0:
			filter = token.Substring(dot + 1)
			matches = MembersOf(token.Substring(0, dot + 1), filter)
		else:
			filter = token
			matches = NamesInScope(filter)
		content = Ok()
		content["matches"] = matches
		content["cursor_start"] = cursor - len(filter)
		content["cursor_end"] = cursor
		content["metadata"] = Hash()
		return content

	# The interpreter completes a member access by resolving a dummy name.
	private def MembersOf(target as string, filter as string) as List[of string]:
		suggestions = _interpreter.SuggestCompletionsFor("${target}__codecomplete__")
		return suggestions.Select[of List[of string]]({ entities | Matching(entities, filter) }).Value

	private static def Matching(entities as (IEntity), filter as string) as List[of string]:
		names = List[of string]()
		return names if entities is null
		for entity in entities:
			Collect(names, entity.Name, filter)
		return names

	private def NamesInScope(filter as string) as List[of string]:
		names = List[of string]()
		for entry in _interpreter.Values:
			Collect(names, entry.Key, filter)
		return names

	# Overloads share a name, so the same completion arrives more than once.
	private static def Collect(names as List[of string], name as string, filter as string):
		return unless name.StartsWith(filter)
		names.Add(name) unless names.Contains(name)

	private static def LastToken(text as string) as string:
		index = len(text)
		while index > 0:
			character = text[index - 1]
			break unless char.IsLetterOrDigit(character) or character == char('_') or character == char('.')
			index--
		return text.Substring(index)

	# Enough for jupyter console to decide whether to keep reading lines.
	private def IsComplete(request as WireMessage) as Hash:
		code = Json.Text(request.Body, "code", string.Empty)
		trimmed = code.TrimEnd()
		content = Hash()
		if len(trimmed) > 0 and (trimmed.EndsWith(":") or trimmed.EndsWith("\\") or LastLineIsIndented(trimmed)):
			content["status"] = "incomplete"
			content["indent"] = "\t"
		else:
			content["status"] = "complete"
		return content

	private static def LastLineIsIndented(code as string) as bool:
		last = code.Substring(code.LastIndexOf(char('\n')) + 1)
		return len(last) > 0 and char.IsWhiteSpace(last[0])

	private def Shutdown(socket as RouterSocket, request as WireMessage):
		content = Ok()
		content["restart"] = Json.Flag(request.Body, "restart", false)
		Reply(socket, request, "shutdown_reply", content)
		_running = false
		_stopped.Set()

	private def KernelInfo() as Hash:
		language = Hash()
		language["name"] = "boo"
		language["version"] = Version()
		language["mimetype"] = "text/x-boo"
		language["file_extension"] = ".boo"
		language["pygments_lexer"] = "boo"
		# CodeMirror has no boo mode, and boo reads close enough to python to
		# highlight well as one. Pygments does have a boo lexer, which is what
		# the console and nbconvert use.
		language["codemirror_mode"] = "python"
		content = Ok()
		content["protocol_version"] = WireMessage.ProtocolVersion
		content["implementation"] = "boo"
		content["implementation_version"] = Version()
		content["language_info"] = language
		content["banner"] = "Boo ${Version()} on .NET ${Environment.Version}"
		return content

	private static def Version() as string:
		return typeof(BooCompiler).Assembly.GetName().Version.ToString()

	private def Stream(parent as WireMessage, name as string, text as string):
		content = Hash()
		content["name"] = name
		content["text"] = text
		Publish(parent, "stream", content)

	private def Fail(socket as RouterSocket, request as WireMessage, x as Exception):
		Fail(socket, request, x.GetType().Name, Lines(x.ToString()))

	private def Fail(socket as RouterSocket, request as WireMessage, name as string, traceback as List[of string]):
		value = (traceback[0] if traceback.Count > 0 else name)
		content = Hash()
		content["ename"] = name
		content["evalue"] = value
		content["traceback"] = traceback
		Publish(request, "error", content)
		reply = Hash()
		reply["status"] = "error"
		reply["execution_count"] = _executionCount
		reply["ename"] = name
		reply["evalue"] = value
		reply["traceback"] = traceback
		Reply(socket, request, "execute_reply", reply)

	private static def Describe(errors as CompilerErrorCollection) as List[of string]:
		lines = List[of string]()
		for error in errors:
			lines.Add(error.ToString())
		return lines

	private static def Lines(text as string) as List[of string]:
		lines = List[of string]()
		lines.AddRange(text.Split((of string: "\r\n", "\n"), StringSplitOptions.None))
		return lines

	private def Completed() as Hash:
		content = Ok()
		content["execution_count"] = _executionCount
		content["user_expressions"] = Hash()
		content["payload"] = List[of string]()
		return content

	private def ExecuteInput(code as string) as Hash:
		content = Hash()
		content["code"] = code
		content["execution_count"] = _executionCount
		return content

	private static def Status(state as string) as Hash:
		content = Hash()
		content["execution_state"] = state
		return content

	private static def Ok() as Hash:
		content = Hash()
		content["status"] = "ok"
		return content

	private def Reply(socket as RouterSocket, request as WireMessage, messageType as string, content):
		WireMessage.Create(messageType, request, content).Send(socket, _signer)

	# iopub is published from several threads, and the topic frame stands in
	# for the routing identities a reply would carry.
	private def Publish(parent as WireMessage, messageType as string, content):
		message = WireMessage.Create(messageType, parent, content)
		message.Identities.Clear()
		message.Identities.Add(System.Text.Encoding.UTF8.GetBytes(messageType))
		lock _ioPubLock:
			message.Send(_ioPub, _signer)

	private static def Log(message):
		Console.Error.WriteLine("boojupyter: ${message}")
