extends VBoxContainer

## Shows stats for the currently selected creature and provides action buttons.
## Styled with UiStyle (project sci-fi palette).

signal send_to_hex_world_pressed(creature_id: String)
signal explore_pressed(creature_id: String)

const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

var _selected_id: String = ""

var _name_label: Label
var _stat_labels: Dictionary = {}  # stat key → Label
var _send_button: Button
var _explore_button: Button


func _ready() -> void:
	add_theme_constant_override("separation", 5)
	_build_ui()


func _build_ui() -> void:
	# Section title
	var title := Label.new()
	title.text = "Selected Creature"
	UiStyleScript.style_title(title, 15)
	add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", UiStyleScript.BORDER_SOFT)
	add_child(sep)

	_name_label = Label.new()
	_name_label.text = "No creature selected"
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", UiStyleScript.ACCENT_SOFT)
	add_child(_name_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 2)

	var stat_keys          := ["health", "attack", "defense", "movement_speed",
			"vision", "physical_size", "movement_types"]
	var stat_labels_display := ["Health", "Attack", "Defense", "Speed",
			"Vision", "Size", "Move Types"]

	for i in stat_keys.size():
		var key_lbl := Label.new()
		key_lbl.text = stat_labels_display[i] + ":"
		UiStyleScript.style_body(key_lbl, true)
		grid.add_child(key_lbl)

		var val_lbl := Label.new()
		val_lbl.text = "—"
		UiStyleScript.style_body(val_lbl)
		grid.add_child(val_lbl)
		_stat_labels[stat_keys[i]] = val_lbl

	add_child(grid)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)

	_send_button = Button.new()
	_send_button.text = "Place on Map"
	_send_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_send_button.disabled = true
	UiStyleScript.style_button(_send_button)
	_send_button.pressed.connect(_on_send_pressed)
	btn_row.add_child(_send_button)

	_explore_button = Button.new()
	_explore_button.text = "Explore"
	_explore_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_explore_button.disabled = true
	UiStyleScript.style_button(_explore_button)
	_explore_button.pressed.connect(_on_explore_pressed)
	btn_row.add_child(_explore_button)

	add_child(btn_row)


func show_creature(creature_data: Dictionary) -> void:
	_selected_id = creature_data.get("id", "")
	_name_label.text = creature_data.get("name", "Unknown")

	_stat_labels["health"].text         = str(creature_data.get("health", 0))
	_stat_labels["attack"].text         = str(creature_data.get("attack", 0))
	_stat_labels["defense"].text        = str(creature_data.get("defense", 0))
	_stat_labels["movement_speed"].text = str(creature_data.get("movement_speed", 1))
	_stat_labels["vision"].text         = str(creature_data.get("vision", 3))
	_stat_labels["physical_size"].text  = creature_data.get("physical_size", "?")
	var mts: Array = creature_data.get("movement_types", [])
	_stat_labels["movement_types"].text = ", ".join(mts) if mts.size() > 0 else "none"

	_send_button.disabled = _selected_id.is_empty()
	var on_map := GameState.placed_creatures.has(_selected_id)
	_explore_button.disabled = _selected_id.is_empty() or not on_map


func show_creature_by_id(creature_id: String) -> void:
	var pdata: Dictionary = GameState.placed_creatures.get(creature_id, {})
	if not pdata.is_empty():
		show_creature(pdata.get("data", {}))
		_explore_button.disabled = false
		return
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
