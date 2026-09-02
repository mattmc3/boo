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
import NetMQ

USAGE = """usage: boojupyter --connection-file <path>
	   boojupyter install [--name NAME] [--display-name NAME] [--prefix DIR]"""

def Serve(connectionFile as string, showWarnings as bool) as int:
	unless File.Exists(connectionFile):
		Console.Error.WriteLine("boojupyter: no connection file at ${connectionFile}")
		return 2
	try:
		kernel = BooKernel(ConnectionInfo(connectionFile))
		kernel.ShowWarnings = showWarnings
		kernel.Run()
	ensure:
		NetMQConfig.Cleanup(false)
	return 0

def Argument(index as int) as string:
	return null if index >= len(argv)
	return argv[index]

command = "serve"
connectionFile as string = null
name = "boo"
displayName = "Boo"
prefix as string = null
showWarnings = false

index = 0
while index < len(argv):
	argument = argv[index]
	if argument == "install":
		command = "install"
	elif argument == "--help" or argument == "-h":
		command = "help"
	elif argument == "--connection-file" or argument == "-f":
		index++
		connectionFile = Argument(index)
	elif argument.StartsWith("--connection-file="):
		connectionFile = argument.Substring(len("--connection-file="))
	elif argument == "--name":
		index++
		name = Argument(index)
	elif argument == "--display-name":
		index++
		displayName = Argument(index)
	elif argument == "--warnings":
		showWarnings = true
	elif argument == "--prefix":
		index++
		prefix = Argument(index)
	else:
		Console.Error.WriteLine("boojupyter: unknown argument ${argument}")
		command = "help"
	index++

if command == "install":
	Console.WriteLine("installed the boo kernel to ${KernelSpec.Install(name, displayName, prefix)}")
elif command == "serve" and connectionFile is not null:
	Environment.ExitCode = Serve(connectionFile, showWarnings)
else:
	Console.Error.WriteLine(USAGE)
	Environment.ExitCode = 2
