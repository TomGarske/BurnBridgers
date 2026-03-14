extends Node2D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const UNIT_DRAW_SIZE: int = 52  # Slightly inset from tile edge
const TEAM_COLORS: Array[Color] = [
	Color.CORNFLOWER_BLUE,    # 0 — blue
	Color.TOMATO,             # 1 — red
	Color(0.14, 0.76, 0.32),  # 2 — green
	Color(0.92, 0.72, 0.06),  # 3 — gold
	Color(0.70, 0.22, 0.96),  # 4 — purple
	Color(0.10, 0.80, 0.90),  # 5 — cyan
	Color(0.96, 0.52, 0.08),  # 6 — orange
	Color(0.76, 0.76, 0.80),  # 7 — silver
]

# ---------------------------------------------------------------------------
# Exported fields (set at spawn time by TacticalMap)
# ---------------------------------------------------------------------------
@export var max_health: int = 2
@export var move_range: int = 3
## Attack range in Manhattan distance tiles. 1 = melee (POC). Ranged support is a future extension.
@export var attack_range: int = 1
@export var attack_damage: int = 1

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------
var unit_id: int = 0
var team: int = 0
var grid_pos: Vector2i = Vector2i.ZERO
var health: int = 0

var has_moved: bool = false
var has_attacked: bool = false

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal unit_died(unit_id: int)

# ---------------------------------------------------------------------------
# Visual
# ---------------------------------------------------------------------------
func _draw() -> void:
	var color: Color = TEAM_COLORS[team] if team < TEAM_COLORS.size() else Color.GRAY
	var half: float = UNIT_DRAW_SIZE / 2.0
	draw_rect(Rect2(-half, -half, UNIT_DRAW_SIZE, UNIT_DRAW_SIZE), color)
	draw_rect(Rect2(-half, -half, UNIT_DRAW_SIZE, UNIT_DRAW_SIZE), Color.WHITE, false, 2.0)

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func setup(id: int, start_pos: Vector2i, team_id: int) -> void:
	unit_id = id
	team = team_id
	health = max_health
	_set_grid_pos(start_pos)
	_update_health_label()
	queue_redraw()

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
func move_to(target_pos: Vector2i) -> void:
	_set_grid_pos(target_pos)
	has_moved = true

func take_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	_update_health_label()
	print("[Unit %d] Took %d damage. HP: %d/%d" % [unit_id, amount, health, max_health])
	if health <= 0:
		unit_died.emit(unit_id)
		queue_free()

func reset_actions() -> void:
	has_moved = false
	has_attacked = false

# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
func can_move_to(target: Vector2i) -> bool:
	if has_moved:
		return false
	var dist: int = abs(target.x - grid_pos.x) + abs(target.y - grid_pos.y)
	return dist > 0 and dist <= move_range

func can_attack(target_pos: Vector2i) -> bool:
	if has_attacked:
		return false
	# TODO: ranged attack (attack_range > 1) is a future extension.
	var dist: int = abs(target_pos.x - grid_pos.x) + abs(target_pos.y - grid_pos.y)
	return dist > 0 and dist <= attack_range

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
func _set_grid_pos(pos: Vector2i) -> void:
	grid_pos = pos
	position = Vector2(
		pos.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		pos.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
	)

func _update_health_label() -> void:
	var label: Label = get_node_or_null("HealthLabel")
	if label:
		label.text = "%d/%d" % [max(health, 0), max_health]
