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
@onready var faction_count_label: Label = $ConfigPanel/VBoxContainer/ConquestSection/FactionCountRow/FactionCountLabel
@onready var faction_count_spinner: SpinBox = $ConfigPanel/VBoxContainer/ConquestSection/FactionCountRow/FactionCountSpinner
@onready var start_territory_label: Label = $ConfigPanel/VBoxContainer/ConquestSection/StartTerritoryRow/StartTerritoryLabel
@onready var start_territory_selector: OptionButton = $ConfigPanel/VBoxContainer/ConquestSection/StartTerritoryRow/StartTerritorySelector
# Buttons
@onready var launch_button: Button = $ConfigPanel/VBoxContainer/LaunchButton
@onready var back_button: Button = $ConfigPanel/VBoxContainer/BackButton

var _game_mode_ids: Array[String] = []

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
	difficulty_selector.add_item("Easy")
	difficulty_selector.add_item("Normal")
	difficulty_selector.add_item("Hard")
	difficulty_selector.add_item("Admiral")
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
# Conquest-specific options
# ---------------------------------------------------------------------------
func _setup_conquest_options() -> void:
	faction_count_spinner.min_value = 1
	faction_count_spinner.max_value = 5
	faction_count_spinner.value = 3
	faction_count_spinner.step = 1

	start_territory_selector.clear()
	start_territory_selector.add_item("Random")
	# Placeholder territories matching conquest_arena grid.
	for r in range(3):
		for c in range(4):
			start_territory_selector.add_item("Region T_%d_%d" % [r, c])
	start_territory_selector.select(0)

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

	# Ship class: hidden for fleet_battle (fleet composition is fixed).
	var show_ship_class: bool = mode_id != "fleet_battle"
	ship_class_title.visible = show_ship_class
	ship_class_selector.visible = show_ship_class
	ship_class_desc.visible = show_ship_class

	# Bot count: shown for ironwake and fleet_battle; conquest uses faction count instead.
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
		GameManager.sp_conquest_factions = int(faction_count_spinner.value)
		var territory_idx: int = start_territory_selector.selected
		if territory_idx <= 0:
			GameManager.sp_conquest_start_territory = ""
		else:
			# Convert index back to territory id (offset by 1 for "Random").
			var adjusted: int = territory_idx - 1
			var row: int = adjusted / 4
			var col: int = adjusted % 4
			GameManager.sp_conquest_start_territory = "t_%d_%d" % [row, col]

	GameManager.start_offline_test_match(mode_id)

func _on_back_button_pressed() -> void:
	_go_back()

func _go_back() -> void:
	get_tree().change_scene_to_file(GameManager.HOME_SCREEN_SCENE_PATH)
