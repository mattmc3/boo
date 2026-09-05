"""
5
"""
# 'ref struct' is the syntax, but the attribute it stands for still marks a type
# on its own, which is how an external byreflike type arrives.
import System
import System.Runtime.CompilerServices

[IsByRefLike]
struct Buffer:
	public Length as int

b = Buffer()
b.Length = 5
Console.WriteLine(b.Length)
