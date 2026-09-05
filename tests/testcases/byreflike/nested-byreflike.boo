"""
3
1
"""
import System

ref struct Wrapper:
	public s as Span[of int]

buf = array(int, 3)
buf[0] = 1
w = Wrapper()
w.s = buf.AsSpan()
Console.WriteLine(w.s.Length)
Console.WriteLine(w.s[0])
