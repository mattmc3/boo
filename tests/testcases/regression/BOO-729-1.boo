#ignore System.Windows.Forms ships only in the Windows Desktop runtime
"""
ok
"""

import System.Windows.Forms

class MyForm(Form):
	protected override def DefWndProc(ref m as Message):
		pass
		
print "ok"
