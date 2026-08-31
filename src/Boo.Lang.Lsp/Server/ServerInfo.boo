namespace Boo.Lang.Lsp.Server

class ServerInfo:
"""Identifies this server to a client during initialize."""

	public static final Name = "boolsp"

	static Version as string:
		get:
			return typeof(ServerInfo).Assembly.GetName().Version.ToString(3)
