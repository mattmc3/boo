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
import System.Security.Cryptography
import System.Text

# Signs the four JSON frames of a message with the connection file key. An
# empty key means the session is unsigned, which Jupyter allows.
class Signer:

	_hmac as HMAC

	def constructor(scheme as string, key as string):
		return if string.IsNullOrEmpty(key)
		raise ArgumentException("unsupported signature scheme: ${scheme}") unless scheme == "hmac-sha256"
		_hmac = HMACSHA256(Encoding.UTF8.GetBytes(key))

	Enabled as bool:
		get: return _hmac is not null

	def Sign(parts as (string)) as string:
		return string.Empty unless Enabled
		lock _hmac:
			_hmac.Initialize()
			last = len(parts) - 1
			for i in range(len(parts)):
				bytes = Encoding.UTF8.GetBytes(parts[i])
				if i < last:
					_hmac.TransformBlock(bytes, 0, bytes.Length, null, 0)
				else:
					_hmac.TransformFinalBlock(bytes, 0, bytes.Length)
			return System.Convert.ToHexString(_hmac.Hash).ToLowerInvariant()

	def Verify(signature as string, parts as (string)) as bool:
		return true unless Enabled
		expected = Encoding.UTF8.GetBytes(Sign(parts))
		actual = Encoding.UTF8.GetBytes((signature if signature is not null else string.Empty))
		return false unless expected.Length == actual.Length
		difference = 0
		for i in range(expected.Length):
			difference |= expected[i] ^ actual[i]
		return difference == 0
