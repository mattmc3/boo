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
import System.Text.Json

# Every System.Text.Json entry point takes optional arguments, which Boo does
# not fill in, so the awkward calls are spelled out once here.
static class Json:

	def Stringify(value) as string:
		return "null" if value is null
		return JsonSerializer.Serialize(value, value.GetType(), cast(JsonSerializerOptions, null))

	def Parse(text as string) as JsonDocument:
		return JsonDocument.Parse(text, JsonDocumentOptions())

	def Text(element as JsonElement, name as string, fallback as string) as string:
		found as JsonElement
		return fallback unless element.TryGetProperty(name, found)
		return fallback unless found.ValueKind == JsonValueKind.String
		return found.GetString()

	def Flag(element as JsonElement, name as string, fallback as bool) as bool:
		found as JsonElement
		return fallback unless element.TryGetProperty(name, found)
		return true if found.ValueKind == JsonValueKind.True
		return false if found.ValueKind == JsonValueKind.False
		return fallback

	def Number(element as JsonElement, name as string, fallback as int) as int:
		found as JsonElement
		return fallback unless element.TryGetProperty(name, found)
		return fallback unless found.ValueKind == JsonValueKind.Number
		return found.GetInt32()
