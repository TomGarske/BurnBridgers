extends Node

## Minimal persistence layer. Saves/loads custom terrain definitions and creature state.

const SAVE_PATH      := "user://custom_terrains.json"
const GAME_SAVE_PATH := "user://game_save.json"

var custom_terrains: Array[Dictionary] = []

## Creature state
var current_creature: Dictionary = {}
var placed_creatures: Dictionary = {}    # creature_id → {data, hex: Vector2i, color: Color}
var dead_creatures:   Array[String]  = []
var character_bucket: Array[Dictionary] = []
var custom_attributes: Array = []


func _ready() -> void:
	_load_from_disk()


func save_game(path: String = GAME_SAVE_PATH) -> void:
	var placed_serial: Dictionary = {}
	for cid: String in placed_creatures.keys():
		var entry: Dictionary = placed_creatures[cid].duplicate()
		var hex: Vector2i = entry.get("hex", Vector2i(0, 0))
		entry["hex"] = [hex.x, hex.y]
		var col: Color = entry.get("color", Color.WHITE)
		entry["color"] = [col.r, col.g, col.b, col.a]
		placed_serial[cid] = entry
	var data := {
		"custom_terrains":   custom_terrains,
		"placed_creatures":  placed_serial,
		"dead_creatures":    dead_creatures,
		"character_bucket":  character_bucket,
		"custom_attributes": custom_attributes,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
	else:
		push_warning("GameState: could not write game save to %s" % path)


func load_game(path: String = GAME_SAVE_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	if parsed.has("custom_terrains") and parsed["custom_terrains"] is Array:
		custom_terrains.clear()
		for entry: Variant in parsed["custom_terrains"]:
			if entry is Dictionary:
				if entry.has("color") and entry["color"] is Array:
					var c: Array = entry["color"]
					entry["color"] = Color(float(c[0]), float(c[1]), float(c[2]),
						float(c[3])) if c.size() >= 4 else Color.WHITE
				custom_terrains.append(entry)
	if parsed.has("placed_creatures") and parsed["placed_creatures"] is Dictionary:
		placed_creatures.clear()
		for cid: String in parsed["placed_creatures"].keys():
			var entry: Dictionary = parsed["placed_creatures"][cid]
			if entry.has("hex") and entry["hex"] is Array:
				var hv: Array = entry["hex"]
				entry["hex"] = Vector2i(int(hv[0]), int(hv[1])) if hv.size() >= 2 else Vector2i(0, 0)
			if entry.has("color") and entry["color"] is Array:
				var cv: Array = entry["color"]
				entry["color"] = Color(float(cv[0]), float(cv[1]), float(cv[2]),
					float(cv[3])) if cv.size() >= 4 else Color.WHITE
			placed_creatures[cid] = entry
	if parsed.has("dead_creatures") and parsed["dead_creatures"] is Array:
		dead_creatures.assign(parsed["dead_creatures"])
	if parsed.has("character_bucket") and parsed["character_bucket"] is Array:
		character_bucket.assign(parsed["character_bucket"])
	if parsed.has("custom_attributes") and parsed["custom_attributes"] is Array:
		custom_attributes.assign(parsed["custom_attributes"])


func save() -> void:
	var serialized: Array = []
	for ct: Dictionary in custom_terrains:
		var entry := ct.duplicate()
		var c: Color = entry.get("color", Color.WHITE)
		entry["color"] = [c.r, c.g, c.b, c.a]
		serialized.append(entry)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(serialized, "\t"))
	else:
		push_warning("GameState: could not write to %s" % SAVE_PATH)


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return
	custom_terrains.clear()
	for entry: Variant in parsed:
		if not entry is Dictionary:
			continue
		if entry.has("color") and entry["color"] is Array:
			var c: Array = entry["color"]
			entry["color"] = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3])) if c.size() >= 4 else Color.WHITE
		custom_terrains.append(entry)
