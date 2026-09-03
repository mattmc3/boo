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


"""
git utility functions
"""
import System
import System.IO

class FileStatus:
	static def parse(line as string):
		# Porcelain is two status columns, a space, then the path.
		return FileStatus(code: line[:2], resource: line[3:])

	public code as string
	public resource as string

	def IsUntracked():
		return code == "??"

	override def ToString():
		return "${code}\t${resource}"

def git_status(resource as string):
	return parse_status(shell("git", "status --porcelain ${resource}"))

def parse_status(status as string):
	for line in lines(status):
		yield FileStatus.parse(line)

def git_untracked(resource as string):
	return (
		status.resource
		for status in git_status(resource)
		if status.IsUntracked())

def git_ignore(resource as string, whatToIgnore as string):
	using writer = File.AppendText(Path.Combine(resource, ".gitignore")):
		writer.WriteLine(whatToIgnore)

def lines(s as string):
	# Left unstripped: the status columns are leading whitespace.
	return line for line in /(\r?\n)+/.Split(s) if len(line.Trim())

def confirm(message as string):
	return "y" == prompt("${message} (y/n): ")
