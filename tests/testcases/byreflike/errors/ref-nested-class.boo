"""
ref-nested-class.boo(5,5): BCE0044: Only a struct can be declared 'ref'.
"""
class Outer:
	ref class Inner:
		pass
