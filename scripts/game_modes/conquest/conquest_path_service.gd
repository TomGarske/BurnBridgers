## conquest_path_service.gd
## Validates fortify connectivity and provides owned-territory path queries.
## A fortify move is legal only if there is a path through owned territories
## from source to destination.

const ConquestData := preload("res://scripts/game_modes/conquest/conquest_data.gd")


## Returns true if there is a path from `source_id` to `dest_id` through
## territories all owned by `player_id`.
## Both source and destination must be owned by the player.
static func can_fortify(
	state: ConquestData.ConquestGameState,
	player_id: int,
	source_id: String,
	dest_id: String
) -> bool:
	if source_id == dest_id:
		return false

	var src: ConquestData.ConquestTerritory = state.territories.get(source_id)
	var dst: ConquestData.ConquestTerritory = state.territories.get(dest_id)
	if src == null or dst == null:
		return false
	if src.owner_player_id != player_id or dst.owner_player_id != player_id:
		return false
	if src.army_count < 2:
		# Must leave at least 1 army behind.
		return false

	return _bfs_connected(state, player_id, source_id, dest_id)


## Returns all territories reachable from `source_id` through owned territory
## (excluding source itself).
static func reachable_from(
	state: ConquestData.ConquestGameState,
	player_id: int,
	source_id: String
) -> Array[String]:
	var visited: Dictionary = {}
	var queue: Array[String] = [source_id]
	visited[source_id] = true

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current: ConquestData.ConquestTerritory = state.territories.get(current_id)
		if current == null:
			continue
		for adj_id in current.adjacent_territory_ids:
			if visited.has(adj_id):
				continue
			var adj: ConquestData.ConquestTerritory = state.territories.get(adj_id)
			if adj != null and adj.owner_player_id == player_id:
				visited[adj_id] = true
				queue.append(adj_id)

	var result: Array[String] = []
	for tid in visited.keys():
		if tid != source_id:
			result.append(tid)
	return result


# ---------------------------------------------------------------------------
# BFS
# ---------------------------------------------------------------------------

static func _bfs_connected(
	state: ConquestData.ConquestGameState,
	player_id: int,
	start_id: String,
	goal_id: String
) -> bool:
	var visited: Dictionary = {}
	var queue: Array[String] = [start_id]
	visited[start_id] = true

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		if current_id == goal_id:
			return true
		var current: ConquestData.ConquestTerritory = state.territories.get(current_id)
		if current == null:
			continue
		for adj_id in current.adjacent_territory_ids:
			if visited.has(adj_id):
				continue
			var adj: ConquestData.ConquestTerritory = state.territories.get(adj_id)
			if adj != null and adj.owner_player_id == player_id:
				visited[adj_id] = true
				queue.append(adj_id)

	return false
