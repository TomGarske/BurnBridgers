extends ScrollContainer

## Character bucket — scrollable list of built creatures waiting to be placed.
## Each row is a full-width styled Button so it's easy to click.

signal creature_selected_in_bucket(creature_id: String)

const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

var _vbox: VBoxContainer
var _token_nodes: Dictionary = {}  # creature_id → Button


func _ready() -> void:
	# Tinted background so the section is visually distinct
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.12, 0.85)
	sb.corner_radius_top_left    = 8
	sb.corner_radius_top_right   = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.border_width_left   = 1
	sb.border_width_top    = 1
	sb.border_width_right  = 1
	sb.border_width_bottom = 1
	sb.border_color = UiStyleScript.BORDER_SOFT
	add_theme_stylebox_override("panel", sb)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 3)
	add_child(_vbox)

	# Section title inside the scroll area
	var title := Label.new()
	title.text = "Built Creatures"
	UiStyleScript.style_title(title, 13)
	title.add_theme_color_override("font_color", UiStyleScript.TEXT_SECONDARY)
	_vbox.add_child(title)


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
	var cid: String  = creature_data.get("id", "")
	var cname: String = creature_data.get("name", "Unknown")
	var csize: String = creature_data.get("physical_size", "?")

	var btn := Button.new()
	btn.text = "%s  [%s]" % [cname, csize]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 30)
	UiStyleScript.style_button(btn)
	btn.pressed.connect(func() -> void: creature_selected_in_bucket.emit(cid))

	_vbox.add_child(btn)
	_token_nodes[cid] = btn
