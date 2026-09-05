"""
attribute-byreflike-field.boo(13,12): BCE0191: Byref-like type 'Buffer' cannot be a field of 'Holder'.
"""
# The checks key off the attribute, not off the 'ref struct' spelling.
import System
import System.Runtime.CompilerServices

[IsByRefLike]
struct Buffer:
	public Length as int

class Holder:
	public b as Buffer

Console.WriteLine(Holder())
