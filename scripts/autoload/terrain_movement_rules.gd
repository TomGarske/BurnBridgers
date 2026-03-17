extends Node

## Terrain movement rules — wraps TerrainDefinitions for per-creature entry checks.


func get_terrain_requirements(terrain_type: String) -> Array[String]:
	return TerrainDefinitions.get_required_movement_types(terrain_type)


func can_enter(movement_types: Array[String], terrain_type: String) -> bool:
	var req := get_terrain_requirements(terrain_type)
	for mt: String in movement_types:
		if mt in req:
			return true
	return false


func apply_entry_consequences(creature_id: String, terrain_type: String) -> void:
	var creature_data: Dictionary = GameState.placed_creatures.get(creature_id, {})
	if creature_data.is_empty():
		return
	var movement_types: Array[String] = []
	movement_types.assign(creature_data.get("data", {}).get("movement_types", []))
	if not can_enter(movement_types, terrain_type):
		var hex: Vector2i = creature_data.get("hex", Vector2i(-1, -1))
		HexOccupancyValidator.remove_creature(creature_id, hex)
		GameState.dead_creatures.append(creature_id)
		GameState.placed_creatures.erase(creature_id)
