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

import System.IO
import NUnit.Framework
import boojupyter

[TestFixture]
class ConnectionInfoTestFixture:

	_path as string

	[SetUp]
	def SetUp():
		_path = Path.Combine(Path.GetTempPath(), "boojupyter-${System.Guid.NewGuid()}.json")

	[TearDown]
	def TearDown():
		File.Delete(_path) if File.Exists(_path)

	private def Write(text as string) as ConnectionInfo:
		File.WriteAllText(_path, text)
		return ConnectionInfo(_path)

	[Test]
	def ReadsThePortsAndKey():
		connection = Write("""{
			"transport": "tcp",
			"ip": "127.0.0.1",
			"shell_port": 1001,
			"iopub_port": 1002,
			"stdin_port": 1003,
			"control_port": 1004,
			"hb_port": 1005,
			"signature_scheme": "hmac-sha256",
			"key": "a-signing-key"
		}""")
		Assert.AreEqual(1001, connection.ShellPort)
		Assert.AreEqual(1002, connection.IoPubPort)
		Assert.AreEqual(1003, connection.StdinPort)
		Assert.AreEqual(1004, connection.ControlPort)
		Assert.AreEqual(1005, connection.HeartbeatPort)
		Assert.AreEqual("a-signing-key", connection.Key)
		Assert.AreEqual("hmac-sha256", connection.SignatureScheme)

	[Test]
	def BuildsATcpAddress():
		connection = Write('{"transport": "tcp", "ip": "127.0.0.1", "shell_port": 1001}')
		Assert.AreEqual("tcp://127.0.0.1:1001", connection.Address(connection.ShellPort))

	# ipc names a file per channel where tcp names a port.
	[Test]
	def BuildsAnIpcAddress():
		connection = Write('{"transport": "ipc", "ip": "/tmp/kernel", "shell_port": 1001}')
		Assert.AreEqual("ipc:///tmp/kernel-1001", connection.Address(connection.ShellPort))

	[Test]
	def FallsBackWhenFieldsAreMissing():
		connection = Write("{}")
		Assert.AreEqual("tcp", connection.Transport)
		Assert.AreEqual("127.0.0.1", connection.Ip)
		Assert.AreEqual("", connection.Key)
		Assert.AreEqual(0, connection.ShellPort)
