extends Node2D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const UNIT_SCENE: PackedScene = preload("res://scenes/game/unit.tscn")
const GRID_WIDTH: int = 10
const GRID_HEIGHT: int = 20
const PLAYER_START_COLUMNS: int = 2
const NPC_START_COLUMNS: int = 4
const UNITS_PER_PLAYER: int = 2
const NPC_TEAM: int = 999

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var turn_manager: Node = $TurnManager
@onready var status_label: Label = $UI/StatusLabel
@onready var end_turn_button: Button = $UI/EndTurnButton

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
## unit_id (int) -> Unit node
var units: Dictionary = {}
var unit_counter: int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	turn_manager.turn_started.connect(_on_turn_started)
	turn_manager.match_over.connect(_on_match_over)
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	if multiplayer.is_server():
		_spawn_all_units()

# ---------------------------------------------------------------------------
# Unit spawning (host only)
# ---------------------------------------------------------------------------
func _spawn_all_units() -> void:
	var player_peer_ids: Array = GameManager.players.keys()
	player_peer_ids.sort()
	var player_unit_count: int = player_peer_ids.size() * UNITS_PER_PLAYER
	var player_spawn_positions: Array[Vector2i] = _build_player_spawn_positions(player_unit_count)
	var npc_spawn_positions: Array[Vector2i] = _build_npc_spawn_positions(player_unit_count)

	var player_spawn_index: int = 0
	for peer_id: int in player_peer_ids:
		var team: int = GameManager.players[peer_id]["team"]
		for _i in range(UNITS_PER_PLAYER):
			if player_spawn_index >= player_spawn_positions.size():
				push_error("[TacticalMap] Not enough player spawn positions for all units.")
				break
			_host_spawn_unit(unit_counter, player_spawn_positions[player_spawn_index], team)
			unit_counter += 1
			player_spawn_index += 1

	for npc_pos: Vector2i in npc_spawn_positions:
		_host_spawn_unit(unit_counter, npc_pos, NPC_TEAM)
		unit_counter += 1

	# Start turn manager with all registered peer IDs (NPCs are not in turn order yet)
	turn_manager.setup(player_peer_ids)

func _build_player_spawn_positions(unit_count: int) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for x in range(PLAYER_START_COLUMNS):
		for y in range(GRID_HEIGHT):
			positions.append(Vector2i(x, y))
			if positions.size() >= unit_count:
				return positions
	return positions

func _build_npc_spawn_positions(unit_count: int) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for x in range(GRID_WIDTH - 1, GRID_WIDTH - NPC_START_COLUMNS - 1, -1):
		for y in range(GRID_HEIGHT - 1, -1, -1):
			positions.append(Vector2i(x, y))
			if positions.size() >= unit_count:
				return positions
	return positions

func _host_spawn_unit(id: int, pos: Vector2i, team: int) -> void:
	_spawn_unit_local(id, pos, team)
	# Replicate to all clients
	_sync_unit_spawn.rpc(id, pos, team)

@rpc("authority", "reliable")
func _sync_unit_spawn(id: int, pos: Vector2i, team: int) -> void:
	# Skip on host — already spawned locally
	if multiplayer.is_server():
		return
	_spawn_unit_local(id, pos, team)

func _spawn_unit_local(id: int, pos: Vector2i, team: int) -> void:
	var unit: Node2D = UNIT_SCENE.instantiate()
	add_child(unit)
	unit.setup(id, pos, team)
	unit.unit_died.connect(_on_unit_died)
	units[id] = unit

# ---------------------------------------------------------------------------
# Move request (client → host validate → broadcast apply)
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_move(unit_id: int, target_pos: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != turn_manager.get_current_player():
		return
	var unit: Node2D = units.get(unit_id)
	if unit == null or not unit.can_move_to(target_pos):
		return
	if not _is_tile_in_bounds(target_pos) or _is_cell_occupied(target_pos):
		return
	apply_move.rpc(unit_id, target_pos)

@rpc("authority", "call_local", "reliable")
func apply_move(unit_id: int, target_pos: Vector2i) -> void:
	var unit: Node2D = units.get(unit_id)
	if unit:
		unit.move_to(target_pos)

# ---------------------------------------------------------------------------
# Attack request (client → host validate → broadcast apply)
# ---------------------------------------------------------------------------
@rpc("any_peer", "reliable")
func request_attack(attacker_id: int, target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != turn_manager.get_current_player():
		return
	var attacker: Node2D = units.get(attacker_id)
	var target: Node2D = units.get(target_id)
	if attacker == null or target == null:
		return
	if attacker.team == target.team:
		return
	if not attacker.can_attack(target.grid_pos):
		return
	apply_attack.rpc(attacker_id, target_id, 1)

@rpc("authority", "call_local", "reliable")
func apply_attack(attacker_id: int, target_id: int, damage: int) -> void:
	var attacker: Node2D = units.get(attacker_id)
	var target: Node2D = units.get(target_id)
	if attacker:
		attacker.has_attacked = true
	if target:
		target.take_damage(damage)

# ---------------------------------------------------------------------------
# Win condition
# ---------------------------------------------------------------------------
func _on_unit_died(unit_id: int) -> void:
	units.erase(unit_id)
	if multiplayer.is_server():
		_check_win_condition()

func _check_win_condition() -> void:
	var teams_alive: Array = []
	for unit: Node2D in units.values():
		if not teams_alive.has(unit.team):
			teams_alive.append(unit.team)
	if teams_alive.size() == 0:
		turn_manager.declare_match_over(-1)
		return

	if teams_alive.size() > 1:
		return  # Match still ongoing

	var winner_team: int = teams_alive[0] if teams_alive.size() == 1 else -1
	if winner_team == NPC_TEAM:
		# 0 is a non-peer sentinel used to display defeat for all players.
		turn_manager.declare_match_over(0)
		return
	for peer_id: int in GameManager.players:
		if GameManager.players[peer_id]["team"] == winner_team:
			turn_manager.declare_match_over(peer_id)
			return
	# Edge case: all units dead simultaneously
	turn_manager.declare_match_over(-1)

# ---------------------------------------------------------------------------
# UI event handlers
# ---------------------------------------------------------------------------
func _on_turn_started(player_id: int) -> void:
	# Reset all actions for the active player's units
	for unit: Node2D in units.values():
		unit.reset_actions()

	var is_my_turn: bool = multiplayer.get_unique_id() == player_id
	if is_my_turn:
		status_label.text = "Your Turn!"
		end_turn_button.disabled = false
	else:
		var username: String = GameManager.players.get(player_id, {}).get("username", "Opponent")
		status_label.text = "%s's Turn..." % username
		end_turn_button.disabled = true

func _on_match_over(winner_id: int) -> void:
	end_turn_button.disabled = true
	if winner_id == multiplayer.get_unique_id():
		status_label.text = "Victory!"
	elif winner_id == -1:
		status_label.text = "Draw!"
	else:
		status_label.text = "Defeat."

func _on_end_turn_pressed() -> void:
	turn_manager.end_turn()

# ---------------------------------------------------------------------------
# Grid helpers
# ---------------------------------------------------------------------------
func _is_tile_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT

func _is_cell_occupied(pos: Vector2i) -> bool:
	for unit: Node2D in units.values():
		if unit.grid_pos == pos:
			return true
	return false
