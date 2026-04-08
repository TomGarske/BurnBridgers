## conquest_combat_resolver.gd
## Deterministic dice-based combat resolution for Conquest mode.
## All randomness comes through a seeded or default RNG so tests can
## inject a fixed seed for deterministic results.

const ConquestData := preload("res://scripts/game_modes/conquest/conquest_data.gd")

## Shared RNG — callers may inject a seeded RandomNumberGenerator for tests.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


# ---------------------------------------------------------------------------
# Dice rolling
# ---------------------------------------------------------------------------

## Roll `count` dice, each 1-6. Returns an Array[int] sorted descending.
func roll_dice(count: int) -> Array[int]:
	var results: Array[int] = []
	for _i in range(count):
		results.append(rng.randi_range(1, 6))
	results.sort()
	results.reverse()
	return results


# ---------------------------------------------------------------------------
# Combat resolution
# ---------------------------------------------------------------------------

## Result dict returned by resolve_attack().
## {
##   "attacker_dice":  Array[int],
##   "defender_dice":  Array[int],
##   "attacker_losses": int,
##   "defender_losses": int,
##   "captured": bool,
##   "forced_move_min": int,   # minimum armies attacker must move into captured territory
## }

## Resolve one attack action.
##
## attacker_armies: total armies in the attacking territory.
## defender_armies: total armies in the defending territory.
## Returns a result dict (see above).
func resolve_attack(attacker_armies: int, defender_armies: int) -> Dictionary:
	# Determine dice counts.
	var atk_dice_count: int = mini(3, attacker_armies - 1)
	var def_dice_count: int = mini(2, defender_armies)

	if atk_dice_count < 1 or def_dice_count < 1:
		push_error("[ConquestCombat] Invalid dice counts — atk:%d def:%d" % [atk_dice_count, def_dice_count])
		return {}

	var atk_dice: Array[int] = []
	var def_dice: Array[int] = []
	for v in roll_dice(atk_dice_count):
		atk_dice.append(v)
	for v in roll_dice(def_dice_count):
		def_dice.append(v)

	var atk_losses: int = 0
	var def_losses: int = 0
	var pairs: int = mini(atk_dice.size(), def_dice.size())

	for i in range(pairs):
		if atk_dice[i] > def_dice[i]:
			def_losses += 1
		else:
			# Tie goes to defender.
			atk_losses += 1

	var captured: bool = (defender_armies - def_losses) <= 0
	var forced_min: int = atk_dice_count if captured else 0

	return {
		"attacker_dice":   atk_dice,
		"defender_dice":   def_dice,
		"attacker_losses": atk_losses,
		"defender_losses": def_losses,
		"captured":        captured,
		"forced_move_min": forced_min,
	}


## Apply attack result to state.
## Returns the result dict for UI display.
## `armies_to_move` is only used when the territory was captured;
## it must be >= result["forced_move_min"] and < attacker final armies.
func apply_attack(
	state: ConquestData.ConquestGameState,
	attacker_territory_id: String,
	defender_territory_id: String,
	armies_to_move: int = -1
) -> Dictionary:
	var atk_t: ConquestData.ConquestTerritory = state.territories.get(attacker_territory_id)
	var def_t: ConquestData.ConquestTerritory = state.territories.get(defender_territory_id)

	if atk_t == null or def_t == null:
		push_error("[ConquestCombat] apply_attack: invalid territory ids")
		return {}

	if atk_t.army_count < 2:
		push_error("[ConquestCombat] Attacker needs at least 2 armies")
		return {}

	if atk_t.owner_player_id == def_t.owner_player_id:
		push_error("[ConquestCombat] Cannot attack own territory")
		return {}

	if def_t.army_count < 1:
		# Defender has no armies — auto-capture without dice.
		def_t.owner_player_id = atk_t.owner_player_id
		var move_count: int = clampi(1, 1, atk_t.army_count - 1)
		atk_t.army_count -= move_count
		def_t.army_count = move_count
		return {
			"attacker_dice": [],
			"defender_dice": [],
			"attacker_losses": 0,
			"defender_losses": 0,
			"captured": true,
			"forced_move_min": 1,
			"armies_moved": move_count,
		}

	var result: Dictionary = resolve_attack(atk_t.army_count, def_t.army_count)
	if result.is_empty():
		return {}

	atk_t.army_count -= result["attacker_losses"]
	def_t.army_count -= result["defender_losses"]

	if result["captured"]:
		# Transfer ownership.
		def_t.owner_player_id = atk_t.owner_player_id
		# Forced army movement.
		var forced_min: int = result["forced_move_min"]
		var move_count: int = armies_to_move if armies_to_move >= forced_min else forced_min
		move_count = clampi(move_count, forced_min, atk_t.army_count - 1)
		atk_t.army_count -= move_count
		def_t.army_count = move_count
		result["armies_moved"] = move_count

	return result


# ---------------------------------------------------------------------------
# Spawn roll
# ---------------------------------------------------------------------------

## Roll a single die for spawn contest resolution. Returns 1-6.
func roll_spawn_die() -> int:
	return rng.randi_range(1, 6)
