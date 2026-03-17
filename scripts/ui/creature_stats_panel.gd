extends VBoxContainer

## Shows stats for the currently selected creature and provides action buttons.

signal send_to_hex_world_pressed(creature_id: String)
signal explore_pressed(creature_id: String)

var _selected_id: String = ""

var _name_label: Label
var _stat_labels: Dictionary = {}  # stat key → Label
var _send_button: Button
var _explore_button: Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	_name_label = Label.new()
	_name_label.text = "No creature selected"
	add_child(_name_label)

	var grid := GridContainer.new()
	grid.columns = 2
	var stat_keys := ["health", "attack", "defense", "movement_speed",
			"vision", "physical_size", "movement_types"]
	var stat_labels_display := ["Health", "Attack", "Defense", "Speed",
			"Vision", "Size", "Move Types"]
	for i in stat_keys.size():
		var key_lbl := Label.new()
		key_lbl.text = stat_labels_display[i] + ":"
		grid.add_child(key_lbl)
		var val_lbl := Label.new()
		val_lbl.text = "—"
		grid.add_child(val_lbl)
		_stat_labels[stat_keys[i]] = val_lbl
	add_child(grid)

	var btn_row := HBoxContainer.new()
	_send_button = Button.new()
	_send_button.text = "Send to Hex World"
	_send_button.disabled = true
	_send_button.pressed.connect(_on_send_pressed)
	btn_row.add_child(_send_button)

	_explore_button = Button.new()
	_explore_button.text = "Explore"
	_explore_button.disabled = true
	_explore_button.pressed.connect(_on_explore_pressed)
	btn_row.add_child(_explore_button)

	add_child(btn_row)


func show_creature(creature_data: Dictionary) -> void:
	_selected_id = creature_data.get("id", "")
	_name_label.text = creature_data.get("name", "Unknown")

	_stat_labels["health"].text          = str(creature_data.get("health", 0))
	_stat_labels["attack"].text          = str(creature_data.get("attack", 0))
	_stat_labels["defense"].text         = str(creature_data.get("defense", 0))
	_stat_labels["movement_speed"].text  = str(creature_data.get("movement_speed", 1))
	_stat_labels["vision"].text          = str(creature_data.get("vision", 3))
	_stat_labels["physical_size"].text   = creature_data.get("physical_size", "?")
	var mts: Array = creature_data.get("movement_types", [])
	_stat_labels["movement_types"].text  = ", ".join(mts) if mts.size() > 0 else "none"

	_send_button.disabled = _selected_id.is_empty()
	# Explore is only meaningful when creature is on the map
	var on_map := GameState.placed_creatures.has(_selected_id)
	_explore_button.disabled = _selected_id.is_empty() or not on_map


func show_creature_by_id(creature_id: String) -> void:
	# Check placed creatures first
	var pdata: Dictionary = GameState.placed_creatures.get(creature_id, {})
	if not pdata.is_empty():
		show_creature(pdata.get("data", {}))
		# Re-enable explore since it's on the map
		_explore_button.disabled = false
		return
	# Check character bucket
	for c: Dictionary in GameState.character_bucket:
		if c.get("id", "") == creature_id:
			show_creature(c)
			return


func clear() -> void:
	_selected_id = ""
	_name_label.text = "No creature selected"
	for lbl: Label in _stat_labels.values():
		lbl.text = "—"
	_send_button.disabled = true
	_explore_button.disabled = true


func _on_send_pressed() -> void:
	if not _selected_id.is_empty():
		send_to_hex_world_pressed.emit(_selected_id)


func _on_explore_pressed() -> void:
	if not _selected_id.is_empty():
		explore_pressed.emit(_selected_id)
