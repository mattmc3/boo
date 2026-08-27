using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using NUnit.Framework;

namespace BooCompiler.Tests
{
	/// <summary>
	/// Collects generated assemblies and verifies them all in one ilverify run.
	/// </summary>
	/// <remarks>
	/// Verifying inside the compiler pipeline spawns ilverify once per testcase.
	/// The verification itself takes a few milliseconds; process startup takes
	/// about fifty, which over ~1900 testcases dominated the run at 1m37s.
	/// ilverify accepts many assemblies per invocation, so the suite queues them
	/// and pays for one startup.
	/// </remarks>
	internal static class VerificationQueue
	{
		private static readonly ConcurrentQueue<string> Queued = new ConcurrentQueue<string>();

		internal static string Directory
		{
			get { return Path.Combine(Path.GetTempPath(), "boo-tests", "verify"); }
		}

		/// <summary>
		/// Takes a copy of the assembly under a name that identifies the test, so
		/// ilverify's output points back at it.
		/// </summary>
		internal static void Enqueue(string assembly, string testName)
		{
			if (!File.Exists(assembly))
				return;

			System.IO.Directory.CreateDirectory(Directory);

			var name = testName + Path.GetExtension(assembly);
			var queued = Path.Combine(Directory, name);
			try
			{
				File.Copy(assembly, queued, true);
				Queued.Enqueue(queued);
			}
			catch (IOException)
			{
				// A test that could not produce an assembly has nothing to verify.
			}
		}

		internal static string VerifyAll(string referenceDirectory)
		{
			var assemblies = new List<string>();
			string queued;
			while (Queued.TryDequeue(out queued))
				assemblies.Add(queued);

			if (assemblies.Count == 0)
				return null;

			var verifier = FindVerifier();
			if (verifier == null)
				return null;

			var startInfo = new ProcessStartInfo
			{
				FileName = verifier,
				CreateNoWindow = true,
				UseShellExecute = false,
				RedirectStandardOutput = true,
				RedirectStandardError = true,
			};

			foreach (var assembly in assemblies)
				startInfo.ArgumentList.Add(assembly);

			foreach (var directory in ReferenceDirectories(referenceDirectory))
			{
				startInfo.ArgumentList.Add("-r");
				startInfo.ArgumentList.Add(Path.Combine(directory, "*.dll"));
			}

			using (var process = Process.Start(startInfo))
			{
				var output = process.StandardOutput.ReadToEnd() + process.StandardError.ReadToEnd();
				process.WaitForExit();
				return process.ExitCode == 0 ? null : Failures(output);
			}
		}

		private static IEnumerable<string> ReferenceDirectories(string referenceDirectory)
		{
			yield return Directory;
			yield return AppContext.BaseDirectory;

			if (!string.IsNullOrEmpty(referenceDirectory))
				yield return referenceDirectory;

			var runtime = Path.GetDirectoryName(typeof(object).Assembly.Location);
			if (!string.IsNullOrEmpty(runtime))
				yield return runtime;
		}

		/// <summary>
		/// Keeps the error lines and drops the per-assembly "Verified." noise.
		/// </summary>
		private static string Failures(string output)
		{
			var failures = new StringBuilder();
			foreach (var line in output.Split('\n'))
				if (line.Contains("Error [") || line.StartsWith("Error:"))
					failures.AppendLine(line.Trim());

			return failures.Length == 0 ? null : failures.ToString();
		}

		private static string FindVerifier()
		{
			var configured = Environment.GetEnvironmentVariable("BOO_ILVERIFY");
			if (!string.IsNullOrEmpty(configured))
				return File.Exists(configured) ? configured : null;

			var name = Environment.OSVersion.Platform == PlatformID.Win32NT ? "ilverify.exe" : "ilverify";
			var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

			var candidates = new List<string>();
			if (!string.IsNullOrEmpty(home))
			{
				candidates.Add(Path.Combine(home, ".dotnet", "tools", name));
				candidates.Add(Path.Combine(home, ".local", "share", "dotnet", ".dotnet", "tools", name));
			}
			foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
				if (dir.Length > 0)
					candidates.Add(Path.Combine(dir, name));

			return candidates.Find(File.Exists);
		}
	}

	/// <summary>
	/// Runs the queued verification once, after every fixture has finished.
	/// </summary>
	[SetUpFixture]
	public class VerifyGeneratedAssemblies
	{
		[OneTimeSetUp]
		public void SetUp()
		{
			if (Directory.Exists(VerificationQueue.Directory))
				Directory.Delete(VerificationQueue.Directory, true);
		}

		[OneTimeTearDown]
		public void VerifyEverythingCompiled()
		{
			var failures = VerificationQueue.VerifyAll(AppContext.BaseDirectory);
			if (failures != null)
				Assert.Fail("ilverify rejected IL from these testcases:" + Environment.NewLine + failures);
		}
	}
}
