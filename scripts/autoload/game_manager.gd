extends Node

# ---------------------------------------------------------------------------
# Enums & Constants
# ---------------------------------------------------------------------------
# GAME_OVER is set when the match ends (currently only win/draw is handled via TurnManager signal).
# TODO: assign GAME_OVER in _on_match_over handler once end-match UI flow is implemented.
enum MatchPhase { LOBBY, IN_MATCH, GAME_OVER }
const MATCH_SCENE_PATH: String = "res://scenes/game/iso_arena.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const LOBBY_SCENE_PATH: String = "res://scenes/lobby.tscn"
# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
## Registry: peer_id (int) -> { steam_id: int, username: String, team: int }
var players: Dictionary = {}
var match_phase: MatchPhase = MatchPhase.LOBBY
var _next_team_id: int = 0
var music_enabled: bool = true

signal music_enabled_changed(enabled: bool)

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func set_music_enabled(enabled: bool) -> void:
	if music_enabled == enabled:
		return
	music_enabled = enabled
	music_enabled_changed.emit(music_enabled)

# ---------------------------------------------------------------------------
# Player registration
# ---------------------------------------------------------------------------
## Any peer can call this; only the host processes it.
@rpc("any_peer", "call_local", "reliable")
func register_player_rpc(steam_id: int, username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_register_player(sender_id, steam_id, username)

func register_local_player(peer_id: int, steam_id: int, username: String) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_register_player(peer_id, steam_id, username)

func _register_player(peer_id: int, steam_id: int, username: String) -> void:
	if players.has(peer_id):
		return
	var team: int = _next_team_id
	_next_team_id += 1
	players[peer_id] = {
		"steam_id": steam_id,
		"username": username,
		"team": team
	}
	print("[GameManager] Registered player '%s' as team %d (peer %d)" % [username, team, peer_id])

# ---------------------------------------------------------------------------
# Match flow
# ---------------------------------------------------------------------------
func start_match() -> void:
	if not multiplayer.is_server():
		push_warning("[GameManager] start_match called on non-host — ignoring.")
		return
	if players.size() < 2:
		push_warning("[GameManager] Not enough players to start (%d registered, need at least 2)." % players.size())
		return
	if SteamManager.lobby_id != 0 and not SteamManager.are_all_lobby_members_ready():
		push_warning("[GameManager] Cannot start: not all lobby players are ready.")
		return

	match_phase = MatchPhase.IN_MATCH
	print("[GameManager] Starting match with %d players." % players.size())
	_load_match_scene.rpc()

@rpc("authority", "call_local", "reliable")
func _load_match_scene() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE_PATH)

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
func _on_peer_disconnected(peer_id: int) -> void:
	if players.has(peer_id):
		print("[GameManager] Player '%s' (peer %d) disconnected." % [players[peer_id]["username"], peer_id])
		players.erase(peer_id)

func reset() -> void:
	players.clear()
	match_phase = MatchPhase.LOBBY
	_next_team_id = 0

## Populates two local test players for offline development — no Steam required.
func setup_offline_test() -> void:
	players.clear()
	players[1] = {"steam_id": 0, "username": "Player 1 (Test)", "team": 0}
	players[2] = {"steam_id": 0, "username": "Player 2 (Test)", "team": 1}
	_next_team_id = 2
	match_phase = MatchPhase.IN_MATCH
	print("[GameManager] Offline test mode: 2 players registered.")
