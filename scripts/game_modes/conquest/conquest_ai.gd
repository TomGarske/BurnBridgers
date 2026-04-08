## conquest_ai.gd
## Simple AI opponent for Conquest mode.
## Priorities (in order):
##   1. Reinforce threatened borders.
##   2. Prefer completing a region if close.
##   3. Attack weaker adjacent territories with favorable odds.
##   4. Fortify toward the active front.
##
## No lookahead, no tree search — greedy heuristics only.

const ConquestData := preload("res://scripts/game_modes/conquest/conquest_data.gd")
const ConquestTM := preload("res://scripts/game_modes/conquest/conquest_territory_manager.gd")
const ConquestPath := preload("res://scripts/game_modes/conquest/conquest_path_service.gd")


# ---------------------------------------------------------------------------
# Spawn selection
# ---------------------------------------------------------------------------

## Choose a territory to draft during the territory draft phase.
## Prefers Australia (easiest to defend), then South America, then any unclaimed.
static func choose_start_territory(
	state: ConquestData.ConquestGameState,
	_player_id: int
) -> String:
	var preferred_regions: Array[String] = ["australia", "south_america", "north_america", "africa", "europe", "asia"]
	for region_id in preferred_regions:
		var region: ConquestData.ConquestRegion = state.regions.get(region_id)
		if region == null:
			continue
		for tid in region.territory_ids:
			var t: ConquestData.ConquestTerritory = state.territories.get(tid)
			if t != null and t.owner_player_id < 0:
				return tid

	# Fallback: any unclaimed territory.
	for t in state.territories.values():
		if t.owner_player_id < 0:
			return t.territory_id

	return ""


# ---------------------------------------------------------------------------
# Reinforce
# ---------------------------------------------------------------------------

## Returns a Dictionary: territory_id -> armies to place.
## Distributes all `reinforcements` armies across owned territories.
## Strategy: reinforce borders (territories adjacent to enemies) first,
## bias toward regions we're close to completing.
static func plan_reinforce(
	state: ConquestData.ConquestGameState,
	player_id: int,
	reinforcements: int
) -> Dictionary:
	var result: Dictionary = {}
	var remaining: int = reinforcements

	if remaining <= 0:
		return result

	# Gather border territories (own territories adjacent to enemies).
	var borders: Array[String] = []
	for tid in ConquestTM.territories_owned_by(state, player_id):
		if not ConquestTM.adjacent_enemy_territories(state, tid).is_empty():
			borders.append(tid)

	if borders.is_empty():
		# No borders — place on any territory with most armies (turtling).
		var all_owned: Array[String] = ConquestTM.territories_owned_by(state, player_id)
		if all_owned.is_empty():
			return result
		result[all_owned[0]] = remaining
		return result

	# Score borders: prefer those that are close to completing a region.
	var scored: Array[Dictionary] = []
	for tid in borders:
		var t: ConquestData.ConquestTerritory = state.territories.get(tid)
		if t == null:
			continue
		var region_progress: int = _region_near_completion(state, player_id, t.region_id)
		scored.append({"tid": tid, "score": region_progress, "armies": t.army_count})

	# Sort descending by score (then ascending by current armies — reinforce weaker first).
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["armies"]) < int(b["armies"])
	)

	# Distribute: round-robin across top borders.
	var idx: int = 0
	while remaining > 0:
		var entry: Dictionary = scored[idx % scored.size()]
		var tid: String = str(entry["tid"])
		result[tid] = int(result.get(tid, 0)) + 1
		remaining -= 1
		idx += 1

	return result


# ---------------------------------------------------------------------------
# Attack
# ---------------------------------------------------------------------------

## Returns an Array[Dictionary] of attacks to make this turn.
## Each attack: { "from": territory_id, "to": territory_id }
## AI stops attacking when odds are unfavorable or a capture improved position.
static func plan_attacks(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> Array[Dictionary]:
	var attacks: Array[Dictionary] = []
	var max_attacks: int = 8  # safety cap

	for _attempt in range(max_attacks):
		var best: Dictionary = _find_best_attack(state, player_id)
		if best.is_empty():
			break
		attacks.append(best)
		# Simulate the effect to avoid planning multiple attacks from the same territory
		# after it runs low on armies. Use a simple check: if attacker has < 3 armies
		# after this planned attack, stop planning for that territory.
		# (The arena will call apply_attack; we just produce the plan.)
		break  # MVP: plan one attack per call, arena iterates

	return attacks


## Find the best single attack opportunity.
static func _find_best_attack(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> Dictionary:
	var best: Dictionary = {}
	var best_score: float = -INF

	for from_id in ConquestTM.territories_owned_by(state, player_id):
		var from_t: ConquestData.ConquestTerritory = state.territories.get(from_id)
		if from_t == null or from_t.army_count < 2:
			continue
		for to_id in ConquestTM.adjacent_enemy_territories(state, from_id):
			var to_t: ConquestData.ConquestTerritory = state.territories.get(to_id)
			if to_t == null:
				continue
			var score: float = _score_attack(state, player_id, from_t, to_t)
			if score > best_score:
				best_score = score
				best = {"from": from_id, "to": to_id}

	# Only attack if score is positive (i.e., favorable odds or strategic value).
	if best_score <= 0.0:
		return {}
	return best


static func _score_attack(
	state: ConquestData.ConquestGameState,
	player_id: int,
	from_t: ConquestData.ConquestTerritory,
	to_t: ConquestData.ConquestTerritory
) -> float:
	# Base: ratio of attacker dice to defender dice.
	var atk_dice: float = float(mini(3, from_t.army_count - 1))
	var def_dice: float = float(mini(2, to_t.army_count))
	var odds_score: float = atk_dice - def_dice   # positive = favorable

	if odds_score < 0.0:
		return -1.0  # unfavorable — don't attack

	# Bonus if capturing this territory helps complete a region.
	var region_bonus: float = float(_region_near_completion(state, player_id, to_t.region_id)) * 0.5

	return odds_score + region_bonus


# ---------------------------------------------------------------------------
# Fortify
# ---------------------------------------------------------------------------

## Returns { "from": territory_id, "to": territory_id, "armies": int } or {}.
static func plan_fortify(
	state: ConquestData.ConquestGameState,
	player_id: int
) -> Dictionary:
	# Find the interior territory with the most excess armies.
	var best_source: String = ""
	var best_excess: int = 0

	for tid in ConquestTM.territories_owned_by(state, player_id):
		var t: ConquestData.ConquestTerritory = state.territories.get(tid)
		if t == null or t.army_count < 3:
			continue
		var enemies: Array[String] = ConquestTM.adjacent_enemy_territories(state, tid)
		if not enemies.is_empty():
			continue  # It's a border — don't strip it
		var excess: int = t.army_count - 1
		if excess > best_excess:
			best_excess = excess
			best_source = tid

	if best_source.is_empty() or best_excess < 1:
		return {}

	# Find the most-threatened border reachable from source.
	var reachable: Array[String] = ConquestPath.reachable_from(state, player_id, best_source)
	var best_dest: String = ""
	var best_threat: int = 0

	for dest_id in reachable:
		var dest: ConquestData.ConquestTerritory = state.territories.get(dest_id)
		if dest == null:
			continue
		var enemy_adj: Array[String] = ConquestTM.adjacent_enemy_territories(state, dest_id)
		if enemy_adj.is_empty():
			continue
		# Threat = enemy armies adjacent.
		var threat: int = 0
		for eid in enemy_adj:
			var e: ConquestData.ConquestTerritory = state.territories.get(eid)
			if e != null:
				threat += e.army_count
		if threat > best_threat:
			best_threat = threat
			best_dest = dest_id

	if best_dest.is_empty():
		return {}

	return {"from": best_source, "to": best_dest, "armies": best_excess}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## How close is the player to completing the region that `territory_id` belongs to?
## Returns (owned_count / total_territories) * 10 as an integer score.
static func _region_near_completion(
	state: ConquestData.ConquestGameState,
	player_id: int,
	region_id: String
) -> int:
	var region: ConquestData.ConquestRegion = state.regions.get(region_id)
	if region == null or region.territory_ids.is_empty():
		return 0
	var owned: int = 0
	for tid in region.territory_ids:
		var t: ConquestData.ConquestTerritory = state.territories.get(tid)
		if t != null and t.owner_player_id == player_id:
			owned += 1
	return int(float(owned) / float(region.territory_ids.size()) * 10.0)
