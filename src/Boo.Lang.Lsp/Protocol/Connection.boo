namespace Boo.Lang.Lsp.Protocol

import System
import System.Collections.Generic
import Boo.Lang.Lsp.Json

callable RequestHandler(params as object) as object

callable NotificationHandler(params as object)

callable RequestGuard(method as string) as Dictionary[of string, object]

class Connection:
"""
Reads messages off a MessageStream and hands them to the registered handlers.

Dispatch is sequential: one message is answered before the next is read. A
cancellation therefore only reaches a request still waiting in the queue, which
is every request that can be cancelled until the compile worker arrives.
"""

	public static final CancelRequest = "$/cancelRequest"

	_stream as MessageStream
	_requests = Dictionary[of string, RequestHandler]()
	_notifications = Dictionary[of string, NotificationHandler]()
	_cancelled = HashSet[of string]()
	_listening = false
	_guard as RequestGuard

	def constructor(stream as MessageStream):
		_stream = stream

	def OnRequest(method as string, handler as RequestHandler):
		_requests[method] = handler

	def OnNotification(method as string, handler as NotificationHandler):
		_notifications[method] = handler

	def Guard(guard as RequestGuard):
	"""Vets every request before its handler runs; a body means refuse."""
		_guard = guard

	def Notify(method as string, params as object):
	"""Sends a notification to the client. Nothing answers it."""
		Reply(JsonRpc.Notification(method, params))

	def Listen():
	"""Answers messages until the client closes the stream or Stop is called."""
		_listening = true
		while _listening:
			message = _stream.Read()
			break if message is null
			Handle(message)

	def Stop():
		_listening = false

	private def Handle(message as string):
		parsed as Dictionary[of string, object]
		try:
			parsed = JsonCodec.Parse(message) as Dictionary[of string, object]
		except e as Exception:
			Reply(JsonRpc.Error(null, JsonRpc.ParseError, e.Message))
			return

		if parsed is null:
			Reply(JsonRpc.Error(null, JsonRpc.ParseError, "message is not a JSON object"))
			return

		id as object
		hasId = parsed.TryGetValue("id", id)
		method = parsed["method"] as string if parsed.ContainsKey("method")

		if method is null:
			# A reply to something the server asked for. Nothing wants it yet.
			return if parsed.ContainsKey("result") or parsed.ContainsKey("error")
			replyTo as object
			replyTo = id if hasId
			Reply(JsonRpc.Error(replyTo, JsonRpc.InvalidRequest, "message has no method"))
			return

		params as object
		parsed.TryGetValue("params", params)

		if hasId:
			HandleRequest(id, method, params)
		else:
			HandleNotification(method, params)

	private def HandleRequest(id as object, method as string, params as object):
		if _cancelled.Remove(KeyOf(id)):
			Reply(JsonRpc.Error(id, JsonRpc.RequestCancelled, "request ${KeyOf(id)} was cancelled"))
			return

		if _guard is not null:
			refusal = _guard(method)
			if refusal is not null:
				Reply(JsonRpc.ErrorReply(id, refusal))
				return

		handler as RequestHandler
		unless _requests.TryGetValue(method, handler):
			Reply(JsonRpc.Error(id, JsonRpc.MethodNotFound, "no handler for ${method}"))
			return

		try:
			Reply(JsonRpc.Result(id, handler(params)))
		except e as Exception:
			Reply(JsonRpc.Error(id, JsonRpc.InternalError, e.Message))

	private def HandleNotification(method as string, params as object):
		if method == CancelRequest:
			Cancel(params)
			return

		handler as NotificationHandler
		# An unknown notification is dropped, as the protocol requires.
		return unless _notifications.TryGetValue(method, handler)
		try:
			handler(params)
		except e as Exception:
			Log("${method} failed: ${e.Message}")

	private def Cancel(params as object):
		map = params as Dictionary[of string, object]
		return if map is null
		id as object
		return unless map.TryGetValue("id", id)
		_cancelled.Add(KeyOf(id))

	private static def KeyOf(id as object) as string:
		return "" if id is null
		return id.ToString()

	private def Reply(message as Dictionary[of string, object]):
		_stream.Write(JsonCodec.Stringify(message))

	private def Log(message as string):
		# stdout carries the protocol, so anything else has to go to stderr.
		Console.Error.WriteLine("boolsp: ${message}")
