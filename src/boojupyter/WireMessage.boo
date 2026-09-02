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
import System.Security
import NetMQ

# One Jupyter protocol message: the routing identities a ROUTER socket needs,
# then the signed header, parent header, metadata and content frames.
class WireMessage:

	public static final Delimiter = "<IDS|MSG>"
	public static final ProtocolVersion = "5.3"
	static final EmptyObject = "{}"

	[getter(Identities)] _identities = List[of (byte)]()
	[getter(Header)] _header = EmptyObject
	[getter(ParentHeader)] _parentHeader = EmptyObject
	[getter(Metadata)] _metadata = EmptyObject
	[getter(Content)] _content = EmptyObject

	_headerDocument as System.Text.Json.JsonDocument
	_contentDocument as System.Text.Json.JsonDocument

	def constructor(header as string, parentHeader as string, metadata as string, content as string):
		_header = header
		_parentHeader = parentHeader
		_metadata = metadata
		_content = content

	MessageType as string:
		get: return Json.Text(HeaderElement, "msg_type", string.Empty)

	Session as string:
		get: return Json.Text(HeaderElement, "session", string.Empty)

	# The documents are cached because a JsonElement points back into one.
	HeaderElement as System.Text.Json.JsonElement:
		get:
			_headerDocument = Json.Parse(_header) if _headerDocument is null
			return _headerDocument.RootElement

	Body as System.Text.Json.JsonElement:
		get:
			_contentDocument = Json.Parse(_content) if _contentDocument is null
			return _contentDocument.RootElement

	SignedParts as (string):
		get: return (of string: _header, _parentHeader, _metadata, _content)

	static def Create(messageType as string, parent as WireMessage, content) as WireMessage:
		session = (parent.Session if parent is not null else string.Empty)
		parentHeader = (parent.Header if parent is not null else EmptyObject)
		message = WireMessage(NewHeader(messageType, session), parentHeader, EmptyObject, Json.Stringify(content))
		message.Identities.AddRange(parent.Identities) if parent is not null
		return message

	static def NewHeader(messageType as string, session as string) as string:
		header = Hash()
		header["msg_id"] = Guid.NewGuid().ToString()
		header["session"] = session
		header["username"] = "kernel"
		header["date"] = DateTime.UtcNow.ToString("o")
		header["msg_type"] = messageType
		header["version"] = ProtocolVersion
		return Json.Stringify(header)

	static def Receive(socket as NetMQSocket, signer as Signer) as WireMessage:
		return Parse(socket.ReceiveMultipartMessage(6), signer)

	static def Parse(frames as NetMQMessage, signer as Signer) as WireMessage:
		identities = List[of (byte)]()
		index = 0
		while index < frames.FrameCount and frames[index].ConvertToString() != Delimiter:
			identities.Add(frames[index].ToByteArray(true))
			index++
		raise FormatException("message has no ${Delimiter} delimiter") if index + 6 > frames.FrameCount
		signature = frames[index + 1].ConvertToString()
		message = WireMessage(
			frames[index + 2].ConvertToString(),
			frames[index + 3].ConvertToString(),
			frames[index + 4].ConvertToString(),
			frames[index + 5].ConvertToString())
		message.Identities.AddRange(identities)
		raise SecurityException("message signature does not match") unless signer.Verify(signature, message.SignedParts)
		return message

	def Send(socket as NetMQSocket, signer as Signer):
		frames = NetMQMessage(6)
		for identity in _identities:
			frames.Append(identity)
		frames.Append(System.Text.Encoding.UTF8.GetBytes(Delimiter))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(signer.Sign(SignedParts)))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(_header))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(_parentHeader))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(_metadata))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(_content))
		socket.SendMultipartMessage(frames)
