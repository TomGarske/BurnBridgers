## conquest_spawn_resolver.gd
## Manages the classic Risk setup phases:
##   1. ROLL_FOR_ORDER — all players roll, highest goes first, re-roll ties
##   2. TERRITORY_DRAFT — players claim territories one at a time in turn order
##   3. ARMY_PLACEMENT — players place remaining armies one at a time
##
## After all armies are placed, the game transitions to the first REINFORCE turn.

const ConquestData := preload("res://scripts/game_modes/conquest/conquest_data.gd")
const ConquestCombat := preload("res://scripts/game_modes/conquest/conquest_combat_resolver.gd")


# ---------------------------------------------------------------------------
# Phase 1: Roll for Order
# ---------------------------------------------------------------------------

## Roll dice for all players, resolve ties, populate state.turn_order.
## Returns the roll results dict for UI display: { player_id: roll_value }.
static func roll_for_order(
	state: ConquestData.ConquestGameState,
	combat: ConquestCombat
) -> Dictionary:
	state.current_phase = ConquestData.ConquestPhase.ROLL_FOR_ORDER
	state.roll_for_order_results.clear()
	state.roll_for_order_resolved = false

	# Roll for every player.
	var rolls: Dictionary = {}
	for player in state.players.values():
		rolls[player.player_id] = combat.roll_spawn_die()
	state.roll_for_order_results = rolls.duplicate()

	# Sort by roll value (descending), breaking ties with re-rolls.
	var order: Array[int] = []
	var remaining: Array[int] = []
	for pid in state.players.keys():
		remaining.append(int(pid))

	while not remaining.is_empty():
		# Find max roll among remaining.
		var max_roll: int = 0
		for pid in remaining:
			if int(rolls.get(pid, 0)) > max_roll:
				max_roll = int(rolls[pid])

		# Collect all players with max roll.
		var tied: Array[int] = []
		for pid in remaining:
			if int(rolls.get(pid, 0)) == max_roll:
				tied.append(pid)

		if tied.size() == 1:
			order.append(tied[0])
			remaining.erase(tied[0])
		else:
			# Re-roll only the tied players until one wins.
			var winner: int = _break_tie(tied, combat, rolls)
			order.append(winner)
			remaining.erase(winner)

	state.turn_order = order
	state.roll_for_order_resolved = true
	return state.roll_for_order_results


## Break a tie among `tied` player_ids. Mutates `rolls` with re-roll values.
## Returns the single winner.
static func _break_tie(
	tied: Array[int],
	combat: ConquestCombat,
	rolls: Dictionary
) -> int:
	var pool: Array[int] = tied.duplicate()
	while pool.size() > 1:
		var rerolls: Dictionary = {}
		var max_r: int = 0
		for pid in pool:
			var r: int = combat.roll_spawn_die()
			rerolls[pid] = r
			rolls[pid] = r  # update for display
			if r > max_r:
				max_r = r
		var winners: Array[int] = []
		for pid in pool:
			if int(rerolls[pid]) == max_r:
				winners.append(pid)
		pool = winners
	return pool[0]


# ---------------------------------------------------------------------------
# Phase 2: Territory Draft
# ---------------------------------------------------------------------------

## Begin the territory draft phase. Sets current_player_id to first in turn order.
static func begin_draft(state: ConquestData.ConquestGameState) -> void:
	state.current_phase = ConquestData.ConquestPhase.TERRITORY_DRAFT
	state.draft_turn_index = 0
	state.current_player_id = state.turn_order[0]


## Claim a territory for the current player during the draft.
## Returns true if successful, false if territory already claimed.
static func draft_territory(
	state: ConquestData.ConquestGameState,
	territory_id: String
) -> bool:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		return false
	if t.owner_player_id >= 0:
		return false  # Already claimed.

	t.owner_player_id = state.current_player_id
	t.army_count = 1  # Each claimed territory starts with 1 army.

	# Advance to next player.
	state.draft_turn_index = (state.draft_turn_index + 1) % state.turn_order.size()
	state.current_player_id = state.turn_order[state.draft_turn_index]
	return true


## Returns true when all territories have been claimed.
static func is_draft_complete(state: ConquestData.ConquestGameState) -> bool:
	for t in state.territories.values():
		if t.owner_player_id < 0:
			return false
	return true


## Returns an Array[String] of unclaimed territory_ids.
static func unclaimed_territories(state: ConquestData.ConquestGameState) -> Array[String]:
	var result: Array[String] = []
	for t in state.territories.values():
		if t.owner_player_id < 0:
			result.append(t.territory_id)
	return result


# ---------------------------------------------------------------------------
# Phase 3: Army Placement
# ---------------------------------------------------------------------------

## Begin the army placement phase. Calculates pools based on player count.
static func begin_placement(state: ConquestData.ConquestGameState) -> void:
	state.current_phase = ConquestData.ConquestPhase.ARMY_PLACEMENT
	state.placement_turn_index = 0
	state.current_player_id = state.turn_order[0]

	var player_count: int = state.players.size()
	var total_pool: int = ConquestData.STARTING_ARMIES_BY_PLAYER_COUNT.get(player_count, 30)

	# Each player already has 1 army on each of their territories.
	state.army_placement_pools.clear()
	for player in state.players.values():
		var territories_owned: int = 0
		for t in state.territories.values():
			if t.owner_player_id == player.player_id:
				territories_owned += 1
		var remaining: int = maxi(0, total_pool - territories_owned)
		state.army_placement_pools[player.player_id] = remaining


## Place one army on a territory the current player owns.
## Returns true if successful.
static func place_army(
	state: ConquestData.ConquestGameState,
	territory_id: String
) -> bool:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		return false
	if t.owner_player_id != state.current_player_id:
		return false
	var pool: int = int(state.army_placement_pools.get(state.current_player_id, 0))
	if pool <= 0:
		return false

	t.army_count += 1
	state.army_placement_pools[state.current_player_id] = pool - 1

	# Advance to next player who still has armies to place.
	_advance_placement_turn(state)
	return true


## Returns true when all players have placed all armies.
static func is_placement_complete(state: ConquestData.ConquestGameState) -> bool:
	for pid in state.army_placement_pools.keys():
		if int(state.army_placement_pools[pid]) > 0:
			return false
	return true


## Returns the number of armies the current player has left to place.
static func current_player_pool(state: ConquestData.ConquestGameState) -> int:
	return int(state.army_placement_pools.get(state.current_player_id, 0))


## Advance to the next player who still has armies to place.
static func _advance_placement_turn(state: ConquestData.ConquestGameState) -> void:
	var n: int = state.turn_order.size()
	for _i in range(n):
		state.placement_turn_index = (state.placement_turn_index + 1) % n
		var next_pid: int = state.turn_order[state.placement_turn_index]
		if int(state.army_placement_pools.get(next_pid, 0)) > 0:
			state.current_player_id = next_pid
			return
	# All pools empty — stay on current (will be caught by is_placement_complete).
