extends ScrollContainer

## Character bucket — scrollable list of built creatures waiting to be placed on the map.

signal creature_selected_in_bucket(creature_id: String)

var _vbox: VBoxContainer
var _token_nodes: Dictionary = {}  # creature_id → HBoxContainer


func _ready() -> void:
	_vbox = VBoxContainer.new()
	_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_vbox)


func add_creature(creature_data: Dictionary) -> void:
	GameState.character_bucket.append(creature_data)
	_create_token(creature_data)


func remove_creature(creature_id: String) -> void:
	GameState.character_bucket = GameState.character_bucket.filter(
		func(c: Dictionary) -> bool: return c.get("id", "") != creature_id
	)
	if _token_nodes.has(creature_id):
		_token_nodes[creature_id].queue_free()
		_token_nodes.erase(creature_id)


func _create_token(creature_data: Dictionary) -> void:
	var cid: String = creature_data.get("id", "")
	var row := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = creature_data.get("name", "Unknown")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var size_lbl := Label.new()
	size_lbl.text = "[%s]" % creature_data.get("physical_size", "?")
	row.add_child(size_lbl)

	# Make the row a button-like area
	var btn := Button.new()
	btn.text = ""
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 28)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void: creature_selected_in_bucket.emit(cid))

	# Overlay: use a MarginContainer so both labels are inside the button area
	var mc := MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := HBoxContainer.new()
	inner.add_child(name_lbl)
	inner.add_child(size_lbl)
	mc.add_child(inner)
	row.remove_child(name_lbl)
	row.remove_child(size_lbl)
	row.add_child(mc)
	row.add_child(btn)

	_vbox.add_child(row)
	_token_nodes[cid] = row
