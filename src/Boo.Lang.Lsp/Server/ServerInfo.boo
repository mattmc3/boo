namespace Boo.Lang.Lsp.Server

import System
import System.IO

class ServerInfo:
"""Identifies this server to a client during initialize."""

	public static final Name = "boolsp"

	static Version as string:
		get:
			return typeof(ServerInfo).Assembly.GetName().Version.ToString(3)

	static Build as string:
	"""
	Which executable is answering and when its code was built.

	The version alone does not say: several checkouts of the same version
	can serve one editor, and a server goes on running the build it started
	from however many times the tree is rebuilt under it.
	"""
		get:
			running = Environment.ProcessPath
			running = typeof(ServerInfo).Assembly.Location if string.IsNullOrEmpty(running)
			return "location unknown" if string.IsNullOrEmpty(running)
			return "${running}, code built ${Written()}"

	private static def Written() as string:
		try:
			location = typeof(ServerInfo).Assembly.Location
			return "unknown" if string.IsNullOrEmpty(location)
			return File.GetLastWriteTime(location).ToString("yyyy-MM-dd HH:mm:ss")
		except:
			return "unknown"

	static Banner as string:
	"""One line naming this build, for the log a client shows."""
		get:
			return "${Name} ${Version} (${Build})"
