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
import System.Text.Json

# What a cell calls to put something richer than text in the notebook.
static class Display:

	def Show(representations as Hash):
		Kernel().Show(representations)

	def Text(mimeType as string, text as string):
		representations = Hash()
		representations[mimeType] = text
		Show(representations)

	def Html(html as string):
		Text("text/html", html)

	# The payload is already JSON, so it goes in parsed rather than as a
	# string the serializer would escape into a quoted blob.
	def Json(mimeType as string, json as string):
		using document = JsonDocument.Parse(json, JsonDocumentOptions()):
			representations = Hash()
			representations[mimeType] = document.RootElement
			Show(representations)

	# Jupyter picks the richest representation its client can draw, so the
	# HTML goes along for clients without the plotly renderer.
	def Plot(chart as Plotly.NET.GenericChart):
		using document = JsonDocument.Parse(Plotly.NET.GenericChart.toFigureJson(chart), JsonDocumentOptions()):
			representations = Hash()
			representations["application/vnd.plotly.v1+json"] = document.RootElement
			representations["text/html"] = Plotly.NET.GenericChart.toChartHTML(chart)
			Show(representations)

	# The common case, without the three type arguments Plotly.NET's generic
	# signature otherwise asks a Boo caller to name. Takes a plain sequence,
	# because a boo list literal is not a generic one.
	def Plot(x as System.Collections.IEnumerable, y as System.Collections.IEnumerable):
		Plot(Plotly.NET.CSharp.Chart.Line[of double, double, string](Numbers(x), Numbers(y)))

	private def Numbers(values as System.Collections.IEnumerable) as List[of double]:
		numbers = List[of double]()
		for value in values:
			numbers.Add(Convert.ToDouble(value))
		return numbers

	private def Kernel() as BooKernel:
		kernel = BooKernel.Current()
		raise InvalidOperationException("no kernel is running") unless kernel is not null
		return kernel
