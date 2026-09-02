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

namespace boojupyter.Tests

import System.Security
import NUnit.Framework
import NetMQ
import boojupyter

[TestFixture]
class WireMessageTestFixture:

	static final Header = '{"msg_type":"execute_request","session":"a-session"}'
	static final Content = '{"code":"1+1"}'

	_signer = Signer("hmac-sha256", "a-signing-key")

	private def Frames(identity as string, signature as string) as NetMQMessage:
		frames = NetMQMessage(7)
		frames.Append(System.Text.Encoding.UTF8.GetBytes(identity))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(WireMessage.Delimiter))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(signature))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(Header))
		frames.Append(System.Text.Encoding.UTF8.GetBytes("{}"))
		frames.Append(System.Text.Encoding.UTF8.GetBytes("{}"))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(Content))
		return frames

	private def Signature() as string:
		return _signer.Sign((of string: Header, "{}", "{}", Content))

	[Test]
	def ReadsTheFramesAfterTheDelimiter():
		message = WireMessage.Parse(Frames("client-1", Signature()), _signer)
		Assert.AreEqual("execute_request", message.MessageType)
		Assert.AreEqual("a-session", message.Session)
		Assert.AreEqual(Content, message.Content)
		Assert.AreEqual(1, message.Identities.Count)
		Assert.AreEqual("client-1", System.Text.Encoding.UTF8.GetString(message.Identities[0]))

	[Test]
	def ReadsTheContentBody():
		message = WireMessage.Parse(Frames("client-1", Signature()), _signer)
		Assert.AreEqual("1+1", Json.Text(message.Body, "code", ""))

	[Test]
	def RejectsAForgedSignature():
		frames = Frames("client-1", Signer("hmac-sha256", "another-key").Sign((of string: Header, "{}", "{}", Content)))
		Assert.Throws[of SecurityException]({ WireMessage.Parse(frames, _signer) })

	[Test]
	def RejectsAMessageWithoutTheDelimiter():
		frames = NetMQMessage(2)
		frames.Append(System.Text.Encoding.UTF8.GetBytes("client-1"))
		frames.Append(System.Text.Encoding.UTF8.GetBytes(Header))
		Assert.Throws[of System.FormatException]({ WireMessage.Parse(frames, _signer) })

	# A reply carries the request identities and header so the client can pair them.
	[Test]
	def AReplyPointsBackAtItsRequest():
		request = WireMessage.Parse(Frames("client-1", Signature()), _signer)
		content = Hash()
		content["status"] = "ok"
		reply = WireMessage.Create("execute_reply", request, content)
		Assert.AreEqual("execute_reply", reply.MessageType)
		Assert.AreEqual("a-session", reply.Session)
		Assert.AreEqual(request.Header, reply.ParentHeader)
		Assert.AreEqual('{"status":"ok"}', reply.Content)
		Assert.AreEqual(1, reply.Identities.Count)

	[Test]
	def SignsWhatItSends():
		request = WireMessage.Parse(Frames("client-1", Signature()), _signer)
		Assert.AreEqual(
			(of string: request.Header, "{}", "{}", Content),
			request.SignedParts)
