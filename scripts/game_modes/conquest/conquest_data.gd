## conquest_data.gd
## Pure data models for the Conquest game mode.
## No Nodes, no rendering — only plain GDScript classes.
## All conquest subsystems share these model types.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum ConquestPhase {
	MATCH_SETUP,
	ROLL_FOR_ORDER,
	TERRITORY_DRAFT,
	ARMY_PLACEMENT,
	TURN_START,
	REINFORCE,
	ATTACK,
	FORTIFY,
	TURN_END,
	GAME_OVER,
}

enum TerrainType {
	DEEP_OCEAN,
	OCEAN,
	SAND,
	LAND,
}

## Starting army pools by player count (classic Risk).
const STARTING_ARMIES_BY_PLAYER_COUNT: Dictionary = {
	2: 40,
	3: 35,
	4: 30,
}


# ---------------------------------------------------------------------------
# ConquestTerritory
# ---------------------------------------------------------------------------
## One named territory on the board (corresponds to a classic Risk territory).
class ConquestTerritory:
	var territory_id: String = ""
	var display_name: String = ""
	var region_id: String = ""
	var adjacent_territory_ids: Array[String] = []
	var owner_player_id: int = -1   # -1 = unowned/neutral
	var army_count: int = 0
	var center_x: float = 0.0       # flat world-space X for rendering
	var center_y: float = 0.0       # flat world-space Y for rendering
	var sphere_pos: Vector3 = Vector3.ZERO  # unit-sphere 3D position for globe rendering
	var hex_indices: Array[int] = []        # goldberg hex indices assigned to this territory
	var is_playable: bool = true

	func _init(
		p_id: String,
		p_name: String,
		p_region: String,
		p_adj: Array[String],
		p_cx: float,
		p_cy: float
	) -> void:
		territory_id = p_id
		display_name = p_name
		region_id = p_region
		adjacent_territory_ids = p_adj
		center_x = p_cx
		center_y = p_cy

	func duplicate() -> ConquestTerritory:
		var t := ConquestTerritory.new(
			territory_id, display_name, region_id,
			adjacent_territory_ids.duplicate(),
			center_x, center_y
		)
		t.owner_player_id = owner_player_id
		t.army_count = army_count
		t.sphere_pos = sphere_pos
		t.hex_indices = hex_indices.duplicate()
		t.is_playable = is_playable
		return t


# ---------------------------------------------------------------------------
# ConquestRegion
# ---------------------------------------------------------------------------
## A continent/region that grants a bonus when fully controlled.
class ConquestRegion:
	var region_id: String = ""
	var display_name: String = ""
	var territory_ids: Array[String] = []
	var bonus_armies: int = 0

	func _init(
		p_id: String,
		p_name: String,
		p_territories: Array[String],
		p_bonus: int
	) -> void:
		region_id = p_id
		display_name = p_name
		territory_ids = p_territories
		bonus_armies = p_bonus


# ---------------------------------------------------------------------------
# ConquestPlayer
# ---------------------------------------------------------------------------
class ConquestPlayer:
	var player_id: int = -1
	var display_name: String = ""
	var color: Color = Color.WHITE
	var is_alive: bool = true
	var is_ai: bool = false

	func _init(p_id: int, p_name: String, p_color: Color, p_ai: bool = false) -> void:
		player_id = p_id
		display_name = p_name
		color = p_color
		is_ai = p_ai


# ---------------------------------------------------------------------------
# ConquestGameState
# ---------------------------------------------------------------------------
## Top-level game state. Passed around and mutated by subsystems.
class ConquestGameState:
	var current_phase: int = ConquestPhase.MATCH_SETUP
	var turn_number: int = 0
	var current_player_id: int = -1
	var turn_order: Array[int] = []        # player_ids in turn order
	var players: Dictionary = {}           # player_id -> ConquestPlayer
	var territories: Dictionary = {}       # territory_id -> ConquestTerritory
	var regions: Dictionary = {}           # region_id -> ConquestRegion
	var winner_player_id: int = -1
	## Armies remaining to place during REINFORCE phase.
	var reinforcements_remaining: int = 0
	## Set to true when the current player has finished attacking (ended attack phase).
	var attack_phase_ended: bool = false
	## Set to true when the current player has used their fortify action.
	var fortify_used: bool = false

	# ── Setup phase state ─────────────────────────────────────────────────
	## Roll-for-order results: player_id -> die value.
	var roll_for_order_results: Dictionary = {}
	## True when roll-for-order is fully resolved (no ties remaining).
	var roll_for_order_resolved: bool = false
	## Draft phase: index into turn_order for whose turn to pick.
	var draft_turn_index: int = 0
	## Army placement pools: player_id -> armies remaining to place.
	var army_placement_pools: Dictionary = {}
	## Army placement: index into turn_order for whose turn to place.
	var placement_turn_index: int = 0
