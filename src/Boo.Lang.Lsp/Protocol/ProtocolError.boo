namespace Boo.Lang.Lsp.Protocol

import System

class ProtocolError(Exception):
"""Raised when the bytes on the wire are not a well formed message."""

	def constructor(message as string):
		super(message)
