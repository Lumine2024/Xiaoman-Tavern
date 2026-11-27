extends RefCounted
## Read packaged JSON through Godot's resource system, with independent mutable data.
static func read(path: String) -> Variant:
	var resource = ResourceLoader.load(path, "JSON")
	if not resource is JSON:
		push_error("Cannot load JSON resource: " + path)
		return null
	# ResourceLoader caches JSON resources. Callers may modify configuration during
	# a run or validation; never expose the shared cached dictionaries and arrays.
	var value = resource.data
	return value.duplicate(true) if value is Dictionary or value is Array else value
