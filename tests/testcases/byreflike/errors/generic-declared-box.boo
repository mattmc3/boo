"""
generic-declared-box.boo(9,33): BCE0190: Cannot box byref-like type 'Buffer[of int]': it has no conversion to 'object'.
"""
import System

ref struct Buffer[of T]:
	public Length as int

boxed as object = Buffer[of int]()
Console.WriteLine(boxed)
