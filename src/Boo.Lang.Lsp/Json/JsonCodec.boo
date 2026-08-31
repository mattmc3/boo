namespace Boo.Lang.Lsp.Json

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json

class JsonCodec:
"""
Converts between JSON text and plain Boo values.

An object becomes a Dictionary[of string, object], an array a List[of object],
a string a string, an integral number a long, any other number a double, and
null a null reference. Every optional argument to System.Text.Json is passed
outright, because Boo does not apply the default values C# declares.
"""

	static def Parse(text as string) as object:
		using doc = JsonDocument.Parse(text, JsonDocumentOptions()):
			return ToValue(doc.RootElement)

	static def Stringify(value as object) as string:
		stream = MemoryStream()
		using writer = Utf8JsonWriter(stream, JsonWriterOptions()):
			Write(writer, value)
		return Encoding.UTF8.GetString(stream.ToArray())

	private static def ToValue(element as JsonElement) as object:
		kind = element.ValueKind
		if kind == JsonValueKind.Object:
			result = Dictionary[of string, object]()
			for property in element.EnumerateObject():
				result[property.Name] = ToValue(property.Value)
			return result
		if kind == JsonValueKind.Array:
			items = List[of object]()
			for item in element.EnumerateArray():
				items.Add(ToValue(item))
			return items
		if kind == JsonValueKind.String:
			return element.GetString()
		if kind == JsonValueKind.Number:
			asLong as long
			return asLong if element.TryGetInt64(asLong)
			return element.GetDouble()
		if kind == JsonValueKind.True:
			return true
		if kind == JsonValueKind.False:
			return false
		return null

	private static def Write(writer as Utf8JsonWriter, value as object):
		if value is null:
			writer.WriteNullValue()
			return

		map = value as IDictionary[of string, object]
		if map is not null:
			writer.WriteStartObject()
			for entry in map:
				writer.WritePropertyName(entry.Key)
				Write(writer, entry.Value)
			writer.WriteEndObject()
			return

		# A string is enumerable, so it has to be ruled out before the list case.
		text = value as string
		if text is not null:
			writer.WriteStringValue(text)
			return

		items = value as System.Collections.IEnumerable
		if items is not null:
			writer.WriteStartArray()
			for item in items:
				Write(writer, item)
			writer.WriteEndArray()
			return

		if value isa bool:
			writer.WriteBooleanValue(cast(bool, value))
		elif value isa double or value isa single:
			writer.WriteNumberValue(System.Convert.ToDouble(value))
		elif value isa long or value isa int or value isa short or value isa byte:
			writer.WriteNumberValue(System.Convert.ToInt64(value))
		else:
			raise ArgumentException("cannot write ${value.GetType()} as JSON")
