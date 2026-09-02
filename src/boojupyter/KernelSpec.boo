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
import System.Diagnostics
import System.IO
import System.Runtime.InteropServices

# Writes the kernel.json that tells Jupyter how to launch this kernel.
static class KernelSpec:

	def Install(name as string, displayName as string, prefix as string) as string:
		root = (prefix if prefix is not null else UserKernelsDirectory())
		directory = Path.Combine(root, name)
		Directory.CreateDirectory(directory)
		spec = Hash()
		spec["argv"] = LaunchCommand()
		spec["display_name"] = displayName
		spec["language"] = "boo"
		spec["interrupt_mode"] = "message"
		File.WriteAllText(Path.Combine(directory, "kernel.json"), Json.Stringify(spec))
		CopyLogos(directory)
		return directory

	# Jupyter serves any logo-* file next to kernel.json as a spec resource.
	private def CopyLogos(directory as string):
		source = Path.GetDirectoryName(typeof(KernelSpec).Assembly.Location)
		return if string.IsNullOrEmpty(source)
		for logo in Directory.GetFiles(source, "logo-*"):
			File.Copy(logo, Path.Combine(directory, Path.GetFileName(logo)), true)

	# Prefer the apphost the build produces, falling back to dotnet plus the dll.
	private def LaunchCommand() as List[of string]:
		argv = List[of string]()
		process = Environment.ProcessPath
		if process is not null and not IsDotnetHost(process):
			argv.Add(process)
		else:
			argv.Add("dotnet")
			argv.Add(typeof(KernelSpec).Assembly.Location)
		argv.Add("--connection-file")
		argv.Add("{connection_file}")
		return argv

	private def IsDotnetHost(path as string) as bool:
		return Path.GetFileNameWithoutExtension(path).Equals("dotnet", StringComparison.OrdinalIgnoreCase)

	private def UserKernelsDirectory() as string:
		return Path.Combine(DataDirectory(), "kernels")

	# jupyter_core has rules of its own, XDG_DATA_HOME on macOS among them, so
	# ask it where its data lives instead of guessing.
	private def DataDirectory() as string:
		configured = Environment.GetEnvironmentVariable("JUPYTER_DATA_DIR")
		return configured unless string.IsNullOrEmpty(configured)
		reported = AskJupyter()
		return reported unless string.IsNullOrEmpty(reported)
		return DefaultDataDirectory()

	private def AskJupyter() as string:
		try:
			start = ProcessStartInfo("jupyter", "--data-dir")
			start.RedirectStandardOutput = true
			start.RedirectStandardError = true
			using jupyter = Process.Start(start):
				return null if jupyter is null
				reported = jupyter.StandardOutput.ReadToEnd().Trim()
				jupyter.WaitForExit()
				return (reported if jupyter.ExitCode == 0 else null)
		except:
			return null

	private def DefaultDataDirectory() as string:
		if RuntimeInformation.IsOSPlatform(OSPlatform.Windows):
			return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "jupyter")
		share = Environment.GetEnvironmentVariable("XDG_DATA_HOME")
		return Path.Combine(share, "jupyter") unless string.IsNullOrEmpty(share)
		home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
		return Path.Combine(home, "Library", "Jupyter") if RuntimeInformation.IsOSPlatform(OSPlatform.OSX)
		return Path.Combine(home, ".local", "share", "jupyter")
