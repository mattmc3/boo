"""
declared-box.boo(9,25): BCE0190: Cannot box byref-like type 'Buffer': it has no conversion to 'object'.
"""
import System

ref struct Buffer:
	public Length as int

boxed as object = Buffer()
Console.WriteLine(boxed)
