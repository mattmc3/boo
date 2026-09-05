"""
buf
"""
import System

interface INamed:
	def Name() as string

ref struct Buffer(INamed):
	public Length as int
	def Name() as string:
		return "buf"

b = Buffer()
Console.WriteLine(b.Name())
