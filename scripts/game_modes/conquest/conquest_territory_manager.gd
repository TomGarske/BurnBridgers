## conquest_territory_manager.gd
## Manages territory ownership, army counts, region control checks,
## and adjacency queries.  Pure logic — no rendering.

const ConquestData := preload("res://scripts/game_modes/conquest/conquest_data.gd")


# ---------------------------------------------------------------------------
# Ownership
# ---------------------------------------------------------------------------

static func set_owner(
	state: ConquestData.ConquestGameState,
	territory_id: String,
	player_id: int
) -> void:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		push_error("[CTM] set_owner: unknown territory '%s'" % territory_id)
		return
	t.owner_player_id = player_id


static func get_owner(
	state: ConquestData.ConquestGameState,
	territory_id: String
) -> int:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		return -1
	return t.owner_player_id


# ---------------------------------------------------------------------------
# Armies
# ---------------------------------------------------------------------------

static func set_armies(
	state: ConquestData.ConquestGameState,
	territory_id: String,
	count: int
) -> void:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		push_error("[CTM] set_armies: unknown territory '%s'" % territory_id)
		return
	t.army_count = maxi(0, count)


static func add_armies(
	state: ConquestData.ConquestGameState,
	territory_id: String,
	delta: int
) -> void:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		return
	t.army_count = maxi(0, t.army_count + delta)


# ---------------------------------------------------------------------------
# Region control
# ---------------------------------------------------------------------------

## Returns true if `player_id` owns every territory in `region_id`.
static func controls_region(
	state: ConquestData.ConquestGameState,
	player_id: int,
	region_id: String
) -> bool:
	var region: ConquestData.ConquestRegion = state.regions.get(region_id)
	if region == null:
		return false
	for tid in region.territory_ids:
		var t: ConquestData.ConquestTerritory = state.territories.get(tid)
		if t == null or t.owner_player_id != player_id:
			return false
	return true


## Returns the total region bonus earned by `player_id`.
static func total_region_bonus(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> int:
	var bonus: int = 0
	for region in state.regions.values():
		if controls_region(state, player_id, region.region_id):
			bonus += region.bonus_armies
	return bonus


## Returns an Array[String] of region_ids fully controlled by `player_id`.
static func owned_regions(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> Array[String]:
	var result: Array[String] = []
	for region in state.regions.values():
		if controls_region(state, player_id, region.region_id):
			result.append(region.region_id)
	return result


# ---------------------------------------------------------------------------
# Territory queries
# ---------------------------------------------------------------------------

## All territory_ids owned by `player_id`.
static func territories_owned_by(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> Array[String]:
	var result: Array[String] = []
	for t in state.territories.values():
		if t.owner_player_id == player_id:
			result.append(t.territory_id)
	return result


## Count of territories owned by `player_id`.
static func territory_count(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> int:
	var count: int = 0
	for t in state.territories.values():
		if t.owner_player_id == player_id:
			count += 1
	return count


## Returns adjacent territory_ids that are owned by a different player.
static func adjacent_enemy_territories(
	state: ConquestData.ConquestGameState,
	territory_id: String
) -> Array[String]:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		return []
	var result: Array[String] = []
	for adj_id in t.adjacent_territory_ids:
		var adj: ConquestData.ConquestTerritory = state.territories.get(adj_id)
		if adj != null and adj.owner_player_id != t.owner_player_id:
			result.append(adj_id)
	return result


## Returns adjacent territory_ids owned by the same player.
static func adjacent_friendly_territories(
	state: ConquestData.ConquestGameState,
	territory_id: String
) -> Array[String]:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		return []
	var result: Array[String] = []
	for adj_id in t.adjacent_territory_ids:
		var adj: ConquestData.ConquestTerritory = state.territories.get(adj_id)
		if adj != null and adj.owner_player_id == t.owner_player_id:
			result.append(adj_id)
	return result


## True if `attacker_id` territory is adjacent to `defender_id` territory.
static func are_adjacent(
	state: ConquestData.ConquestGameState,
	attacker_id: String,
	defender_id: String
) -> bool:
	var t: ConquestData.ConquestTerritory = state.territories.get(attacker_id)
	if t == null:
		return false
	return t.adjacent_territory_ids.has(defender_id)


# ---------------------------------------------------------------------------
# Reinforcement calculation
# ---------------------------------------------------------------------------

## Standard Risk formula: max(3, floor(territory_count / 3)) + region_bonuses.
static func calculate_reinforcements(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> int:
	var count: int = territory_count(state, player_id)
	@warning_ignore("integer_division")
	var base: int = maxi(3, count / 3)
	var bonus: int = total_region_bonus(state, player_id)
	return base + bonus


# ---------------------------------------------------------------------------
# Elimination check
# ---------------------------------------------------------------------------

## Returns player_ids who have been eliminated (alive=true but 0 territories).
static func check_eliminations(state: ConquestData.ConquestGameState) -> Array[int]:
	var eliminated: Array[int] = []
	for player in state.players.values():
		if not player.is_alive:
			continue
		if territory_count(state, player.player_id) == 0:
			eliminated.append(player.player_id)
	return eliminated


## Returns the winning player_id, or -1 if no winner yet.
static func check_winner(state: ConquestData.ConquestGameState) -> int:
	var alive_players: Array[int] = []
	for player in state.players.values():
		if player.is_alive:
			alive_players.append(player.player_id)
	if alive_players.size() == 1:
		return alive_players[0]
	return -1
