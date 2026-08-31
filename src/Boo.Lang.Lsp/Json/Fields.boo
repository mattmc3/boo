namespace Boo.Lang.Lsp.Json

import System
import System.Collections.Generic

class Fields:
"""
Reads values out of a parsed message.

A client may leave out anything the protocol marks optional, so every reader
answers with a default rather than raising when a field is missing or is not
of the type asked for.
"""

	static def Map(value as object, name as string) as Dictionary[of string, object]:
		return Of(value, name) as Dictionary[of string, object]

	static def Items(value as object, name as string) as List[of object]:
		found = Of(value, name) as List[of object]
		return List[of object]() if found is null
		return found

	static def Text(value as object, name as string) as string:
		return Of(value, name) as string

	static def Number(value as object, name as string, fallback as int) as int:
		found = Of(value, name)
		return fallback if found is null
		return System.Convert.ToInt32(found)

	static def Of(value as object, name as string) as object:
		map = value as IDictionary[of string, object]
		return null if map is null
		found as object
		return null unless map.TryGetValue(name, found)
		return found
