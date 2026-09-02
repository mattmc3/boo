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
import System.IO

# The ports and signing key Jupyter writes out before launching a kernel.
class ConnectionInfo:

	[getter(Transport)] _transport = "tcp"
	[getter(Ip)] _ip = "127.0.0.1"
	[getter(ShellPort)] _shellPort as int
	[getter(IoPubPort)] _ioPubPort as int
	[getter(StdinPort)] _stdinPort as int
	[getter(ControlPort)] _controlPort as int
	[getter(HeartbeatPort)] _heartbeatPort as int
	[getter(SignatureScheme)] _signatureScheme = "hmac-sha256"
	[getter(Key)] _key = ""

	def constructor(path as string):
		using document = Json.Parse(File.ReadAllText(path)):
			root = document.RootElement
			_transport = Json.Text(root, "transport", _transport)
			_ip = Json.Text(root, "ip", _ip)
			_shellPort = Json.Number(root, "shell_port", 0)
			_ioPubPort = Json.Number(root, "iopub_port", 0)
			_stdinPort = Json.Number(root, "stdin_port", 0)
			_controlPort = Json.Number(root, "control_port", 0)
			_heartbeatPort = Json.Number(root, "hb_port", 0)
			_signatureScheme = Json.Text(root, "signature_scheme", _signatureScheme)
			_key = Json.Text(root, "key", _key)

	# ipc names a file per channel where tcp names a port.
	def Address(port as int) as string:
		return "ipc://${_ip}-${port}" if _transport == "ipc"
		return "${_transport}://${_ip}:${port}"
