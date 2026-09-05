"""
box-trycast.boo(12,5): BCE0190: Cannot box byref-like type 'Res': it has no conversion to 'System.IDisposable'.
"""
import System

ref struct Res(IDisposable):
	public N as int
	def Dispose():
		pass

r = Res()
d = r as IDisposable
Console.WriteLine(d)
