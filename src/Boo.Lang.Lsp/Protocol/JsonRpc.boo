namespace Boo.Lang.Lsp.Protocol

import System.Collections.Generic

class JsonRpc:
"""The JSON-RPC vocabulary the protocol defines, and the shapes of a reply."""

	public static final Version = "2.0"

	public static final ParseError = -32700
	public static final InvalidRequest = -32600
	public static final MethodNotFound = -32601
	public static final InvalidParams = -32602
	public static final InternalError = -32603

	# LSP adds these to the codes JSON-RPC reserves.
	public static final ServerNotInitialized = -32002
	public static final RequestCancelled = -32800
	public static final ContentModified = -32801

	static def Result(id as object, result as object):
		message = Envelope(id)
		message["result"] = result
		return message

	static def Error(id as object, code as int, description as string):
		return ErrorReply(id, ErrorBody(code, description))

	static def Notification(method as string, params as object):
		message = Dictionary[of string, object]()
		message["jsonrpc"] = Version
		message["method"] = method
		message["params"] = params
		return message

	static def ErrorBody(code as int, description as string):
		error = Dictionary[of string, object]()
		error["code"] = code
		error["message"] = description
		return error

	static def ErrorReply(id as object, body as Dictionary[of string, object]):
		message = Envelope(id)
		message["error"] = body
		return message

	private static def Envelope(id as object):
		message = Dictionary[of string, object]()
		message["jsonrpc"] = Version
		message["id"] = id
		return message
