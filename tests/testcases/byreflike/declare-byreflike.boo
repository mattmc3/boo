"""
5
"""
import System

ref struct Buffer:
	public Length as int

b = Buffer()
b.Length = 5
Console.WriteLine(b.Length)
