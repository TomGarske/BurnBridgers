extends Control
const UiStyleScript := preload("res://scripts/ui/ui_style.gd")

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var game_type_selector: OptionButton = $ConfigPanel/VBoxContainer/GameTypeSelector
@onready var game_type_desc: Label = $ConfigPanel/VBoxContainer/GameTypeDesc
@onready var bot_count_label: Label = $ConfigPanel/VBoxContainer/BotCountRow/BotCountLabel
@onready var bot_count_spinner: SpinBox = $ConfigPanel/VBoxContainer/BotCountRow/BotCountSpinner
@onready var difficulty_label: Label = $ConfigPanel/VBoxContainer/DifficultyRow/DifficultyLabel
@onready var difficulty_selector: OptionButton = $ConfigPanel/VBoxContainer/DifficultyRow/DifficultySelector
@onready var ship_class_title: Label = $ConfigPanel/VBoxContainer/ShipClassTitle
@onready var ship_class_selector: OptionButton = $ConfigPanel/VBoxContainer/ShipClassSelector
@onready var ship_class_desc: Label = $ConfigPanel/VBoxContainer/ShipClassDesc
# Conquest-specific
@onready var conquest_section: VBoxContainer = $ConfigPanel/VBoxContainer/ConquestSection
@onready var opponents_grid: GridContainer = $ConfigPanel/VBoxContainer/ConquestSection/OpponentsGrid
@onready var add_opponent_button: Button = $ConfigPanel/VBoxContainer/ConquestSection/AddOpponentButton
@onready var start_territory_label: Label = $ConfigPanel/VBoxContainer/ConquestSection/StartTerritoryRow/StartTerritoryLabel
@onready var start_territory_selector: OptionButton = $ConfigPanel/VBoxContainer/ConquestSection/StartTerritoryRow/StartTerritorySelector
# Buttons
@onready var launch_button: Button = $ConfigPanel/VBoxContainer/LaunchButton
@onready var back_button: Button = $ConfigPanel/VBoxContainer/BackButton

var _game_mode_ids: Array[String] = []

# Conquest opponents: array of { difficulty: int }  (0=Easy, 1=Normal, 2=Hard, 3=Admiral)
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Admiral"]
const DIFFICULTY_COLORS: Array[Color] = [
	Color(0.45, 0.80, 0.45, 1.0),  # Easy — green
	Color(0.90, 0.85, 0.40, 1.0),  # Normal — gold
	Color(0.95, 0.50, 0.25, 1.0),  # Hard — orange
	Color(0.95, 0.25, 0.25, 1.0),  # Admiral — red
]
const FACTION_ICONS: Array[String] = [
	"\u2694",  # Swords (player)
	"\u2620",  # Skull
	"\u2693",  # Anchor
	"\u269A",  # Staff
	"\u2726",  # Star
	"\u2736",  # Star 6
]
const MAX_OPPONENTS: int = 5
var _conquest_opponents: Array[Dictionary] = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_apply_theme()
	_setup_game_type_selector()
	_setup_difficulty_selector()
	_setup_ship_class_selector()
	_setup_conquest_options()
	_update_ui_for_mode(_game_mode_ids[0] if not _game_mode_ids.is_empty() else "ironwake")

func _apply_theme() -> void:
	UiStyleScript.style_button(launch_button)
	UiStyleScript.style_button(back_button)
	UiStyleScript.style_button(add_opponent_button)
	game_type_selector.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
	difficulty_selector.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
	ship_class_selector.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		accept_event()

# ---------------------------------------------------------------------------
# Game type selector
# ---------------------------------------------------------------------------
func _setup_game_type_selector() -> void:
	_game_mode_ids.clear()
	game_type_selector.clear()
	var modes: Array[Dictionary] = GameManager.get_game_modes()
	for mode in modes:
		if not bool(mode.get("enabled", true)):
			continue
		var mode_id: String = str(mode.get("id", ""))
		if mode_id.is_empty():
			continue
		_game_mode_ids.append(mode_id)
		var badge: String = str(mode.get("badge", "")).strip_edges()
		var label: String = str(mode.get("label", mode_id.capitalize()))
		if not badge.is_empty():
			label = "%s %s" % [badge, label]
		game_type_selector.add_item(label)
	if not _game_mode_ids.is_empty():
		game_type_selector.select(0)
	if not game_type_selector.item_selected.is_connected(_on_game_type_selected):
		game_type_selector.item_selected.connect(_on_game_type_selected)

func _on_game_type_selected(index: int) -> void:
	if index < 0 or index >= _game_mode_ids.size():
		return
	_update_ui_for_mode(_game_mode_ids[index])

# ---------------------------------------------------------------------------
# Difficulty selector (placeholder)
# ---------------------------------------------------------------------------
func _setup_difficulty_selector() -> void:
	difficulty_selector.clear()
	for dname in DIFFICULTY_NAMES:
		difficulty_selector.add_item(dname)
	difficulty_selector.select(1)  # Default to Normal

# ---------------------------------------------------------------------------
# Ship class selector
# ---------------------------------------------------------------------------
func _setup_ship_class_selector() -> void:
	ship_class_selector.clear()
	for i in range(ShipClassConfig.CLASS_COUNT):
		ship_class_selector.add_item(ShipClassConfig.CLASS_NAMES[i])
	ship_class_selector.select(GameManager.local_ship_class)
	_update_ship_class_desc(GameManager.local_ship_class)
	if not ship_class_selector.item_selected.is_connected(_on_ship_class_selected):
		ship_class_selector.item_selected.connect(_on_ship_class_selected)

func _on_ship_class_selected(index: int) -> void:
	GameManager.set_local_ship_class(index)
	_update_ship_class_desc(index)

func _update_ship_class_desc(index: int) -> void:
	if ship_class_desc != null and index >= 0 and index < ShipClassConfig.CLASS_DESCRIPTIONS.size():
		ship_class_desc.text = ShipClassConfig.CLASS_DESCRIPTIONS[index]

# ---------------------------------------------------------------------------
# Conquest opponents panel
# ---------------------------------------------------------------------------
func _setup_conquest_options() -> void:
	if not add_opponent_button.pressed.is_connected(_on_add_opponent_pressed):
		add_opponent_button.pressed.connect(_on_add_opponent_pressed)

	# Default: 3 opponents at Normal difficulty.
	_conquest_opponents.clear()
	for i in range(3):
		_conquest_opponents.append({"difficulty": 1})

	start_territory_selector.clear()
	start_territory_selector.add_item("Random")
	for r in range(3):
		for c in range(4):
			start_territory_selector.add_item("Region T_%d_%d" % [r, c])
	start_territory_selector.select(0)

	_rebuild_opponents_grid()


func _on_add_opponent_pressed() -> void:
	if _conquest_opponents.size() >= MAX_OPPONENTS:
		return
	_conquest_opponents.append({"difficulty": 1})
	_rebuild_opponents_grid()


func _on_remove_opponent_pressed(index: int) -> void:
	if index < 0 or index >= _conquest_opponents.size():
		return
	_conquest_opponents.remove_at(index)
	_rebuild_opponents_grid()


func _on_cycle_difficulty_pressed(index: int) -> void:
	if index < 0 or index >= _conquest_opponents.size():
		return
	var current: int = int(_conquest_opponents[index].get("difficulty", 1))
	_conquest_opponents[index]["difficulty"] = (current + 1) % DIFFICULTY_NAMES.size()
	_rebuild_opponents_grid()


func _rebuild_opponents_grid() -> void:
	# Clear existing children.
	for child in opponents_grid.get_children():
		child.queue_free()

	# Player slot (always first, non-removable).
	var player_slot := _create_slot_panel(FACTION_ICONS[0], "Player", UiStyleScript.ACCENT_SOFT, false, -1)
	opponents_grid.add_child(player_slot)

	# Bot slots.
	for i in range(_conquest_opponents.size()):
		var diff_idx: int = int(_conquest_opponents[i].get("difficulty", 1))
		var diff_name: String = DIFFICULTY_NAMES[diff_idx]
		var diff_col: Color = DIFFICULTY_COLORS[diff_idx]
		var icon: String = FACTION_ICONS[(i + 1) % FACTION_ICONS.size()]
		var slot := _create_slot_panel(icon, diff_name, diff_col, true, i)
		opponents_grid.add_child(slot)

	# Update add button visibility.
	add_opponent_button.visible = _conquest_opponents.size() < MAX_OPPONENTS
	add_opponent_button.text = "+ Add Opponent (%d/%d)" % [_conquest_opponents.size(), MAX_OPPONENTS]


func _create_slot_panel(icon_text: String, label_text: String, accent: Color, removable: bool, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(120, 80)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.18, 0.92)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = accent * Color(1, 1, 1, 0.6)
	style.content_margin_left = 6.0
	style.content_margin_top = 4.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# Icon.
	var icon_label := Label.new()
	icon_label.text = icon_text
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_label.add_theme_color_override("font_color", accent)
	vbox.add_child(icon_label)

	# Name / difficulty label.
	var name_label := Label.new()
	name_label.text = label_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", accent)
	vbox.add_child(name_label)

	if removable:
		var btn_row := HBoxContainer.new()
		btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_row.add_theme_constant_override("separation", 4)
		vbox.add_child(btn_row)

		# Cycle difficulty button.
		var diff_btn := Button.new()
		diff_btn.text = "\u21BB"  # cycle arrow
		diff_btn.tooltip_text = "Cycle difficulty"
		diff_btn.custom_minimum_size = Vector2(28, 22)
		diff_btn.add_theme_font_size_override("font_size", 12)
		diff_btn.add_theme_color_override("font_color", UiStyleScript.TEXT_PRIMARY)
		UiStyleScript.style_button(diff_btn)
		diff_btn.pressed.connect(_on_cycle_difficulty_pressed.bind(index))
		btn_row.add_child(diff_btn)

		# Remove button.
		var remove_btn := Button.new()
		remove_btn.text = "\u2715"  # X
		remove_btn.tooltip_text = "Remove opponent"
		remove_btn.custom_minimum_size = Vector2(28, 22)
		remove_btn.add_theme_font_size_override("font_size", 12)
		remove_btn.add_theme_color_override("font_color", Color(0.95, 0.35, 0.30, 1.0))
		UiStyleScript.style_button(remove_btn)
		remove_btn.pressed.connect(_on_remove_opponent_pressed.bind(index))
		btn_row.add_child(remove_btn)

	return panel


# ---------------------------------------------------------------------------
# Per-mode UI visibility
# ---------------------------------------------------------------------------
func _update_ui_for_mode(mode_id: String) -> void:
	# Update description.
	var mode: Dictionary = GameManager.get_game_mode(mode_id)
	var subtitle: String = str(mode.get("subtitle", "")).strip_edges()
	var desc: String = str(mode.get("description", "No description yet."))
	if subtitle.is_empty():
		game_type_desc.text = desc
	else:
		game_type_desc.text = "%s\n%s" % [subtitle, desc]

	# Ship class: hidden for fleet_battle and conquest.
	var show_ship_class: bool = mode_id != "fleet_battle" and mode_id != "conquest"
	ship_class_title.visible = show_ship_class
	ship_class_selector.visible = show_ship_class
	ship_class_desc.visible = show_ship_class

	# Bot count: shown for ironwake and fleet_battle; conquest uses opponents grid.
	var show_bot_count: bool = mode_id != "conquest"
	bot_count_label.visible = show_bot_count
	bot_count_spinner.visible = show_bot_count

	# Conquest section: only for conquest.
	conquest_section.visible = (mode_id == "conquest")

	# Adjust bot count range per mode.
	if mode_id == "ironwake":
		bot_count_spinner.min_value = 1
		bot_count_spinner.max_value = 4
		bot_count_spinner.value = 3
	elif mode_id == "fleet_battle":
		bot_count_spinner.min_value = 1
		bot_count_spinner.max_value = 1
		bot_count_spinner.value = 1
		# Show fleet preview in ship_class_desc area.
		ship_class_desc.visible = true
		ship_class_desc.text = "Your fleet: 1 Galley (flagship) + 2 Brigs + 2 Schooners"

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
func _on_launch_button_pressed() -> void:
	var selected_idx: int = game_type_selector.selected
	if selected_idx < 0 or selected_idx >= _game_mode_ids.size():
		return
	var mode_id: String = _game_mode_ids[selected_idx]

	# Store config in GameManager for the arena to read.
	GameManager.sp_bot_count = int(bot_count_spinner.value)
	GameManager.sp_difficulty = difficulty_selector.selected
	if mode_id == "conquest":
		GameManager.sp_conquest_factions = _conquest_opponents.size()
		var territory_idx: int = start_territory_selector.selected
		if territory_idx <= 0:
			GameManager.sp_conquest_start_territory = ""
		else:
			# Convert dropdown index back to territory id (offset by 1 for "Random").
			var adjusted: int = territory_idx - 1
			@warning_ignore("integer_division")
			var row: int = adjusted / 4
			var col: int = adjusted % 4
			GameManager.sp_conquest_start_territory = "t_%d_%d" % [row, col]

	GameManager.start_offline_test_match(mode_id)

func _on_back_button_pressed() -> void:
	_go_back()

func _go_back() -> void:
	get_tree().change_scene_to_file(GameManager.HOME_SCREEN_SCENE_PATH)
