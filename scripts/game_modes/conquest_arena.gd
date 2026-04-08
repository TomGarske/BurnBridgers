extends "res://scripts/game_modes/ironwake_arena.gd"

## Conquest Arena: Risk-style territory control game mode.
## Each faction controls territories on the map. Fleets move between adjacent
## regions to attack and capture. Last faction standing (or most territory when
## time expires) wins.
##
## This is the scaffold — actual territory mechanics are TODO.

const _FleetSpawner := preload("res://scripts/shared/fleet_spawner.gd")
const _FleetRegistryClass := preload("res://scripts/shared/fleet_registry.gd")

# ---------------------------------------------------------------------------
# Territory data
# ---------------------------------------------------------------------------
## Territory definition: { id: String, label: String, center: Vector2,
##   adjacency: Array[String], owner_faction: int, garrison: int }
var _territories: Array[Dictionary] = []

## Faction registry: faction_id (int) -> { label: String, color: Color, is_player: bool, alive: bool }
var _factions: Dictionary = {}

## Which faction the local player controls.
var _player_faction_id: int = 0

## Number of AI factions (set from single-player setup).
var _ai_faction_count: int = 3

## Starting territory ID for the player (set from single-player setup).
var _player_start_territory: String = ""

## Turn counter for conquest phases.
var _conquest_turn: int = 0

## True once a conquest victory/defeat has been determined.
var _conquest_over: bool = false


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Disable features from parent modes that don't apply to conquest.
	local_sim_enabled = false
	whirlpool_enabled = false
	_camera_zoom_independent = true

	# Read single-player config from GameManager.
	if GameManager != null:
		_ai_faction_count = clampi(GameManager.sp_conquest_factions, 1, 5)
		_player_start_territory = GameManager.sp_conquest_start_territory

	# Call parent _ready() — inits naval helpers, iso_arena base, etc.
	super._ready()

	# Conquest-specific setup.
	_init_territories()
	_init_factions()
	_assign_starting_territories()

	# Wider default zoom for strategic overview.
	_zoom = 0.04
	_zoom_target = 0.04

	DebugOverlay.log_message("[ConquestArena] Ready. %d territories, %d factions." % [_territories.size(), _factions.size()])


# ---------------------------------------------------------------------------
# Territory initialisation (placeholder)
# ---------------------------------------------------------------------------

## Build the territory map. TODO: procedural or data-driven map generation.
func _init_territories() -> void:
	# Placeholder: create a simple grid of territories.
	var cols: int = 4
	var rows: int = 3
	var u: float = NC.UNITS_PER_LOGIC_TILE
	var map_w: float = float(NC.MAP_TILES_WIDE) * u
	var map_h: float = float(NC.MAP_TILES_HIGH) * u
	var cell_w: float = map_w / float(cols)
	var cell_h: float = map_h / float(rows)

	for r in range(rows):
		for c in range(cols):
			var tid: String = "t_%d_%d" % [r, c]
			var center := Vector2(
				(float(c) + 0.5) * cell_w,
				(float(r) + 0.5) * cell_h
			)
			var adj: Array[String] = []
			if c > 0:
				adj.append("t_%d_%d" % [r, c - 1])
			if c < cols - 1:
				adj.append("t_%d_%d" % [r, c + 1])
			if r > 0:
				adj.append("t_%d_%d" % [r - 1, c])
			if r < rows - 1:
				adj.append("t_%d_%d" % [r + 1, c])
			_territories.append({
				"id": tid,
				"label": "Region %s" % tid.to_upper(),
				"center": center,
				"adjacency": adj,
				"owner_faction": -1,  # unowned
				"garrison": 0,
			})


## Initialise faction data — player + AI opponents.
func _init_factions() -> void:
	var faction_colors: Array[Color] = [
		Color(0.22, 0.46, 1.00),  # Player blue
		Color(0.85, 0.20, 0.15),  # Red
		Color(0.14, 0.76, 0.32),  # Green
		Color(0.92, 0.72, 0.06),  # Gold
		Color(0.70, 0.22, 0.96),  # Purple
		Color(0.95, 0.55, 0.15),  # Orange
	]
	var faction_names: Array[String] = [
		"Player Fleet", "Crimson Armada", "Emerald Company",
		"Golden Corsairs", "Shadow Navy", "Iron Flotilla",
	]

	_factions.clear()
	var total: int = 1 + _ai_faction_count
	for i in range(total):
		_factions[i] = {
			"label": faction_names[i % faction_names.size()],
			"color": faction_colors[i % faction_colors.size()],
			"is_player": (i == 0),
			"alive": true,
		}
	_player_faction_id = 0


## Distribute territories among factions. TODO: smarter allocation.
func _assign_starting_territories() -> void:
	var total_factions: int = _factions.size()
	if total_factions == 0 or _territories.is_empty():
		return

	# Simple round-robin assignment.
	for i in range(_territories.size()):
		var faction_id: int = i % total_factions
		_territories[i]["owner_faction"] = faction_id
		_territories[i]["garrison"] = 3  # starting garrison

	# If player requested a specific start territory, swap ownership.
	if not _player_start_territory.is_empty():
		for t in _territories:
			if str(t.get("id", "")) == _player_start_territory:
				var prev_owner: int = int(t.get("owner_faction", 0))
				if prev_owner != _player_faction_id:
					# Find a territory owned by the player to swap.
					for other in _territories:
						if int(other.get("owner_faction", -1)) == _player_faction_id:
							other["owner_faction"] = prev_owner
							break
					t["owner_faction"] = _player_faction_id
				break


# ---------------------------------------------------------------------------
# Conquest game loop (placeholder)
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not _conquest_over:
		_tick_conquest(delta)
	super._process(delta)


## Main conquest tick — phases: reinforce, move, battle, capture.
## TODO: implement turn-based or real-time territory mechanics.
func _tick_conquest(_delta: float) -> void:
	# Placeholder: check victory each frame.
	_check_conquest_victory()


## Check if a faction has captured all territories or opponents are eliminated.
func _check_conquest_victory() -> void:
	if _conquest_over:
		return

	# Count territories per faction.
	var territory_counts: Dictionary = {}
	for t in _territories:
		var owner: int = int(t.get("owner_faction", -1))
		if owner < 0:
			continue
		territory_counts[owner] = int(territory_counts.get(owner, 0)) + 1

	# Check for total domination.
	for faction_id in _factions.keys():
		var count: int = int(territory_counts.get(faction_id, 0))
		if count == _territories.size():
			_conquest_over = true
			if faction_id == _player_faction_id:
				DebugOverlay.log_message("[ConquestArena] VICTORY — total domination!")
			else:
				DebugOverlay.log_message("[ConquestArena] DEFEAT — faction '%s' controls all territory." % str(_factions[faction_id].get("label", "")))
			return

	# Check for eliminated factions.
	for faction_id in _factions.keys():
		var fd: Dictionary = _factions[faction_id]
		if not bool(fd.get("alive", true)):
			continue
		var count: int = int(territory_counts.get(faction_id, 0))
		if count == 0:
			fd["alive"] = false
			DebugOverlay.log_message("[ConquestArena] Faction '%s' eliminated." % str(fd.get("label", "")))
			if faction_id == _player_faction_id:
				_conquest_over = true
				return


# ---------------------------------------------------------------------------
# Conquest HUD (placeholder)
# ---------------------------------------------------------------------------
func _draw() -> void:
	super._draw()
	if not _conquest_over:
		_draw_conquest_hud()
	else:
		_draw_conquest_result()


func _draw_conquest_hud() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var x: float = 16.0
	var y: float = vp.y - 120.0

	# Territory overview panel.
	var panel_h: float = 80.0
	draw_rect(Rect2(x - 4.0, y - 14.0, 240.0, panel_h), Color(0.05, 0.07, 0.12, 0.85))
	draw_rect(Rect2(x - 4.0, y - 14.0, 240.0, panel_h), Color(0.3, 0.4, 0.55, 0.9), false, 1.5)

	draw_string(font, Vector2(x, y), "CONQUEST", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.88, 0.40, 1.0))

	var line_y: float = y + 18.0
	for faction_id in _factions.keys():
		var fd: Dictionary = _factions[faction_id]
		if not bool(fd.get("alive", true)):
			continue
		var count: int = _count_faction_territories(faction_id)
		var col: Color = fd.get("color", Color.WHITE) as Color
		var label: String = "%s: %d regions" % [str(fd.get("label", "?")), count]
		draw_string(font, Vector2(x, line_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		line_y += 14.0

	# Territory markers on the map.
	for t in _territories:
		var center: Vector2 = t.get("center", Vector2.ZERO) as Vector2
		var screen_pos: Vector2 = _w2s(center.x, center.y)
		var owner: int = int(t.get("owner_faction", -1))
		var col: Color = Color(0.4, 0.4, 0.4, 0.5)
		if owner >= 0 and _factions.has(owner):
			col = _factions[owner].get("color", col) as Color
			col.a = 0.6
		draw_circle(screen_pos, 12.0, col)
		var garrison: int = int(t.get("garrison", 0))
		if garrison > 0:
			draw_string(font, screen_pos + Vector2(-4.0, 4.0), str(garrison),
				HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1, 1, 1, 0.9))


func _draw_conquest_result() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var font: Font = ThemeDB.fallback_font
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.35

	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.62))

	var player_alive: bool = bool(_factions.get(_player_faction_id, {}).get("alive", false))
	var player_count: int = _count_faction_territories(_player_faction_id)
	var title: String
	var title_col: Color
	if player_alive and player_count == _territories.size():
		title = "TOTAL DOMINATION"
		title_col = Color(0.30, 0.85, 0.40, 1.0)
	elif player_alive:
		title = "CONQUEST CONTINUES..."
		title_col = Color(0.75, 0.70, 0.60, 1.0)
	else:
		title = "DEFEATED"
		title_col = Color(0.95, 0.30, 0.25, 1.0)

	draw_string(font, Vector2(cx, cy), title,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 48, title_col)
	draw_string(font, Vector2(cx, cy + 40.0),
		"Territories held: %d / %d" % [player_count, _territories.size()],
		HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color(0.85, 0.88, 0.92, 0.9))


func _count_faction_territories(faction_id: int) -> int:
	var count: int = 0
	for t in _territories:
		if int(t.get("owner_faction", -1)) == faction_id:
			count += 1
	return count


# ---------------------------------------------------------------------------
# Overrides — disable fleet-specific behaviour that doesn't apply yet
# ---------------------------------------------------------------------------

## No fleet spawning in conquest — territory units handle forces.
func _spawn_fleets() -> void:
	pass  # TODO: spawn garrison fleets per territory


## No respawn in conquest.
func _tick_respawn(_delta: float) -> void:
	pass
