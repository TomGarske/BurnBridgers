## conquest_debug_tools.gd
## Debug helpers for Conquest mode.
## Integrates with the existing DebugOverlay autoload.
## All methods are static — call them from the arena or tests.

const ConquestData := preload("res://scripts/game_modes/conquest/conquest_data.gd")
const ConquestTM := preload("res://scripts/game_modes/conquest/conquest_territory_manager.gd")
const ConquestCombat := preload("res://scripts/game_modes/conquest/conquest_combat_resolver.gd")


# ---------------------------------------------------------------------------
# Board report
# ---------------------------------------------------------------------------

## Print a full territory ownership report to DebugOverlay.
static func print_board_report(state: ConquestData.ConquestGameState) -> void:
	DebugOverlay.log_message("[ConquestDebug] ── Board Report ──")
	for region in state.regions.values():
		var owned_by: Dictionary = {}
		for tid in region.territory_ids:
			var t: ConquestData.ConquestTerritory = state.territories.get(tid)
			if t == null:
				continue
			var pid: int = t.owner_player_id
			if not owned_by.has(pid):
				owned_by[pid] = []
			owned_by[pid].append("%s(%d)" % [t.display_name, t.army_count])
		DebugOverlay.log_message("  Region: %s (+%d)" % [region.display_name, region.bonus_armies])
		for pid in owned_by.keys():
			var player: ConquestData.ConquestPlayer = state.players.get(pid)
			var pname: String = player.display_name if player != null else "Neutral"
			DebugOverlay.log_message("    P%d %s: %s" % [pid, pname, ", ".join(owned_by[pid])])


## Print reinforcement summary for all alive players.
static func print_reinforcement_summary(state: ConquestData.ConquestGameState) -> void:
	DebugOverlay.log_message("[ConquestDebug] ── Reinforcement Summary ──")
	for player in state.players.values():
		if not player.is_alive:
			continue
		var reinf: int = ConquestTM.calculate_reinforcements(state, player.player_id)
		var regions_owned: Array[String] = ConquestTM.owned_regions(state, player.player_id)
		DebugOverlay.log_message(
			"  P%d %s: %d reinforcements (regions: %s)"
			% [player.player_id, player.display_name, reinf, ", ".join(regions_owned)]
		)


## Print adjacency for a single territory.
static func print_adjacency(state: ConquestData.ConquestGameState, territory_id: String) -> void:
	var t: ConquestData.ConquestTerritory = state.territories.get(territory_id)
	if t == null:
		DebugOverlay.log_message("[ConquestDebug] Unknown territory: %s" % territory_id, true)
		return
	DebugOverlay.log_message("[ConquestDebug] %s adjacency: %s" % [t.display_name, str(t.adjacent_territory_ids)])


## Run board validation and print results.
static func validate_board(state: ConquestData.ConquestGameState) -> bool:
	var errors: PackedStringArray = []

	if state.territories.size() != 42:
		errors.append("Expected 42 territories, got %d" % state.territories.size())
	if state.regions.size() != 6:
		errors.append("Expected 6 regions, got %d" % state.regions.size())

	for t in state.territories.values():
		if not state.regions.has(t.region_id):
			errors.append("Territory '%s' has invalid region_id '%s'" % [t.territory_id, t.region_id])
		for adj_id in t.adjacent_territory_ids:
			if not state.territories.has(adj_id):
				errors.append("Territory '%s' references missing adj '%s'" % [t.territory_id, adj_id])
			else:
				var adj_t: ConquestData.ConquestTerritory = state.territories[adj_id]
				if not adj_t.adjacent_territory_ids.has(t.territory_id):
					errors.append("Non-symmetric adj: '%s' <-> '%s'" % [t.territory_id, adj_id])

	if errors.is_empty():
		DebugOverlay.log_message("[ConquestDebug] Board validation: PASS (42 territories, 6 regions)")
		return true
	else:
		for e in errors:
			DebugOverlay.log_message("[ConquestDebug] VALIDATION ERROR: %s" % e, true)
		return false


# ---------------------------------------------------------------------------
# Combat simulation
# ---------------------------------------------------------------------------

## Simulate `n` attack rounds and print win statistics.
static func simulate_combat(attacker_armies: int, defender_armies: int, n: int = 100) -> void:
	var combat := ConquestCombat.new()
	var atk_wins: int = 0
	for _i in range(n):
		var result: Dictionary = combat.resolve_attack(attacker_armies, defender_armies)
		if result.get("captured", false):
			atk_wins += 1
	DebugOverlay.log_message(
		"[ConquestDebug] Combat sim: atk=%d vs def=%d, %d/%d attacker wins (%.0f%%)"
		% [attacker_armies, defender_armies, atk_wins, n, float(atk_wins) / float(n) * 100.0]
	)


# ---------------------------------------------------------------------------
# Roll-for-order simulation
# ---------------------------------------------------------------------------

## Simulate a roll-for-order with N players and print the result.
static func simulate_roll_for_order(player_count: int) -> void:
	var combat := ConquestCombat.new()
	var ConquestSpawn := load("res://scripts/game_modes/conquest/conquest_spawn_resolver.gd")
	var state := ConquestData.ConquestGameState.new()
	for i in range(player_count):
		state.players[i] = ConquestData.ConquestPlayer.new(i, "P%d" % i, Color.WHITE)
	var rolls: Dictionary = ConquestSpawn.roll_for_order(state, combat)
	DebugOverlay.log_message(
		"[ConquestDebug] Roll for order (%d players): order=%s, rolls=%s"
		% [player_count, str(state.turn_order), str(rolls)]
	)


# ---------------------------------------------------------------------------
# Phase state dump
# ---------------------------------------------------------------------------

static func dump_state(state: ConquestData.ConquestGameState) -> void:
	var phase_name: String = ConquestData.ConquestPhase.keys()[state.current_phase]
	DebugOverlay.log_message(
		"[ConquestDebug] Phase=%s Turn=%d CurrentPlayer=%d Reinf=%d"
		% [phase_name, state.turn_number, state.current_player_id, state.reinforcements_remaining]
	)
	for player in state.players.values():
		var tc: int = ConquestTM.territory_count(state, player.player_id)
		DebugOverlay.log_message(
			"  P%d %s alive=%s territories=%d"
			% [player.player_id, player.display_name, str(player.is_alive), tc]
		)
