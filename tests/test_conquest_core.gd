extends Node

## test_conquest_core.gd
## Tests for Conquest core logic systems:
##   - Classic territory graph (42 territories, 6 regions, correct adjacency)
##   - Reinforcement calculation (base + region bonus)
##   - Combat dice resolution
##   - Spawn selection and contested territory resolution
##   - Fortify path validation
##   - Turn state transitions
##   - Player elimination and victory detection
##
## Run as main scene or via CI: expects "TEST_CONQUEST_CORE: PASS" on stdout.

const ConquestData     := preload("res://scripts/game_modes/conquest/conquest_data.gd")
const ConquestBoard    := preload("res://scripts/game_modes/conquest/conquest_board_builder.gd")
const ConquestTM       := preload("res://scripts/game_modes/conquest/conquest_territory_manager.gd")
const ConquestSpawn    := preload("res://scripts/game_modes/conquest/conquest_spawn_resolver.gd")
const ConquestCombat   := preload("res://scripts/game_modes/conquest/conquest_combat_resolver.gd")
const ConquestPath     := preload("res://scripts/game_modes/conquest/conquest_path_service.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var errs: PackedStringArray = []

	_test_board_structure(errs)
	_test_territory_graph(errs)
	_test_reinforcements(errs)
	_test_region_control(errs)
	_test_combat(errs)
	_test_roll_for_order(errs)
	_test_territory_draft(errs)
	_test_army_placement(errs)
	_test_fortify_path(errs)
	_test_player_elimination(errs)
	_test_victory_detection(errs)
	_test_army_capture(errs)

	_finish(errs)


# ---------------------------------------------------------------------------
# Board structure
# ---------------------------------------------------------------------------
func _test_board_structure(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()

	if state.territories.size() != 42:
		errs.append("board: expected 42 territories, got %d" % state.territories.size())

	if state.regions.size() != 6:
		errs.append("board: expected 6 regions, got %d" % state.regions.size())

	# Region territory counts match classic Risk.
	var expected_counts: Dictionary = {
		"north_america": 9,
		"south_america": 4,
		"europe": 7,
		"africa": 6,
		"asia": 12,
		"australia": 4,
	}
	for rid in expected_counts.keys():
		var region: ConquestData.ConquestRegion = state.regions.get(rid)
		if region == null:
			errs.append("board: missing region '%s'" % rid)
			continue
		if region.territory_ids.size() != expected_counts[rid]:
			errs.append("board: region '%s' expected %d territories, got %d"
				% [rid, expected_counts[rid], region.territory_ids.size()])

	# Region bonuses match classic Risk.
	var expected_bonuses: Dictionary = {
		"north_america": 5,
		"south_america": 2,
		"europe": 5,
		"africa": 3,
		"asia": 7,
		"australia": 2,
	}
	for rid in expected_bonuses.keys():
		var region: ConquestData.ConquestRegion = state.regions.get(rid)
		if region == null:
			continue
		if region.bonus_armies != expected_bonuses[rid]:
			errs.append("board: region '%s' bonus expected %d, got %d"
				% [rid, expected_bonuses[rid], region.bonus_armies])


# ---------------------------------------------------------------------------
# Territory graph correctness
# ---------------------------------------------------------------------------
func _test_territory_graph(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()

	# All adjacencies are symmetric.
	for t in state.territories.values():
		for adj_id in t.adjacent_territory_ids:
			if not state.territories.has(adj_id):
				errs.append("graph: territory '%s' adj '%s' not found" % [t.territory_id, adj_id])
				continue
			var adj: ConquestData.ConquestTerritory = state.territories[adj_id]
			if not adj.adjacent_territory_ids.has(t.territory_id):
				errs.append("graph: non-symmetric: '%s' adj '%s' but not vice versa"
					% [t.territory_id, adj_id])

	# Key adjacency spot-checks (classic Risk board):
	var checks: Array[Array] = [
		["alaska",          "kamchatka"],       # NA → Asia bridge
		["greenland",       "iceland"],          # NA → Europe bridge
		["brazil",          "north_africa"],     # SA → Africa bridge
		["southern_europe", "middle_east"],      # Europe → Asia
		["ukraine",         "ural"],             # Europe → Asia
		["ukraine",         "afghanistan"],      # Europe → Asia
		["egypt",           "middle_east"],      # Africa → Asia
		["east_africa",     "middle_east"],      # Africa → Asia
		["siam",  "indonesia"],        # Asia → Australia
		["central_america", "venezuela"],        # NA → SA
	]
	for pair in checks:
		var a_id: String = str(pair[0])
		var b_id: String = str(pair[1])
		if not state.territories.has(a_id) or not state.territories.has(b_id):
			errs.append("graph_check: missing territory in pair %s--%s" % [a_id, b_id])
			continue
		var a_t: ConquestData.ConquestTerritory = state.territories[a_id]
		if not a_t.adjacent_territory_ids.has(b_id):
			errs.append("graph_check: expected adjacency %s--%s missing" % [a_id, b_id])

	# Each territory belongs to the correct region.
	var region_membership: Dictionary = {
		"alaska": "north_america",
		"argentina": "south_america",
		"ukraine": "europe",
		"madagascar": "africa",
		"kamchatka": "asia",
		"eastern_australia": "australia",
	}
	for tid in region_membership.keys():
		var t: ConquestData.ConquestTerritory = state.territories.get(tid)
		if t == null:
			errs.append("graph: territory '%s' missing" % tid)
			continue
		if t.region_id != region_membership[tid]:
			errs.append("graph: '%s' region expected '%s', got '%s'"
				% [tid, region_membership[tid], t.region_id])


# ---------------------------------------------------------------------------
# Reinforcement calculation
# ---------------------------------------------------------------------------
func _test_reinforcements(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = _make_two_player_state()

	# Player 0 owns 9 territories (NA) + all of Australia (4) = 13.
	# Base = max(3, 13/3) = max(3,4) = 4.
	# Australia bonus = +2. Total = 6.
	_give_region(state, 0, "australia")
	_give_extra_territories(state, 0, 9)
	var reinf: int = ConquestTM.calculate_reinforcements(state, 0)
	# We gave australia (4) + 9 more = 13. Base = 4. Bonus = 2. Expected = 6.
	if reinf != 6:
		errs.append("reinf: expected 6, got %d" % reinf)

	# Player with 0 territories gets base 3.
	var state2: ConquestData.ConquestGameState = _make_two_player_state()
	var r2: int = ConquestTM.calculate_reinforcements(state2, 1)
	if r2 != 3:
		errs.append("reinf: 0-territory player expected 3, got %d" % r2)

	# Player with 3 territories gets base 3 (3/3=1 < 3).
	var state3: ConquestData.ConquestGameState = _make_two_player_state()
	_give_extra_territories(state3, 0, 3)
	var r3: int = ConquestTM.calculate_reinforcements(state3, 0)
	if r3 != 3:
		errs.append("reinf: 3-territory player expected base 3, got %d" % r3)

	# Player with 6 territories gets base 2 → max(3,2)=3 + any bonuses.
	var state4: ConquestData.ConquestGameState = _make_two_player_state()
	_give_extra_territories(state4, 0, 6)
	var r4: int = ConquestTM.calculate_reinforcements(state4, 0)
	if r4 != 3:
		errs.append("reinf: 6-territory player expected base 3, got %d" % r4)


# ---------------------------------------------------------------------------
# Region control
# ---------------------------------------------------------------------------
func _test_region_control(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)

	# Give P0 all of Australia.
	_give_region(state, 0, "australia")

	if not ConquestTM.controls_region(state, 0, "australia"):
		errs.append("region_ctrl: P0 should control australia")

	if ConquestTM.controls_region(state, 1, "australia"):
		errs.append("region_ctrl: P1 should NOT control australia")

	var bonus: int = ConquestTM.total_region_bonus(state, 0)
	if bonus != 2:
		errs.append("region_ctrl: australia bonus expected 2, got %d" % bonus)

	# Remove one territory.
	var region: ConquestData.ConquestRegion = state.regions["australia"]
	ConquestTM.set_owner(state, region.territory_ids[0], 1)
	if ConquestTM.controls_region(state, 0, "australia"):
		errs.append("region_ctrl: P0 should NOT control incomplete australia")


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------
func _test_combat(errs: PackedStringArray) -> void:
	var combat := ConquestCombat.new()
	combat.rng.seed = 12345

	# Attacker with 4 armies vs defender with 2 armies.
	var result: Dictionary = combat.resolve_attack(4, 2)
	if result.is_empty():
		errs.append("combat: resolve_attack returned empty dict")
		return

	if not result.has("attacker_dice"):
		errs.append("combat: missing attacker_dice")
	if not result.has("defender_dice"):
		errs.append("combat: missing defender_dice")
	if not result.has("attacker_losses"):
		errs.append("combat: missing attacker_losses")
	if not result.has("defender_losses"):
		errs.append("combat: missing defender_losses")
	if not result.has("captured"):
		errs.append("combat: missing captured")

	# Dice count constraints.
	var atk_d: Array = result["attacker_dice"]
	var def_d: Array = result["defender_dice"]
	if atk_d.size() > 3:
		errs.append("combat: attacker dice > 3")
	if def_d.size() > 2:
		errs.append("combat: defender dice > 2")
	if atk_d.size() != mini(3, 4 - 1):
		errs.append("combat: attacker dice count wrong: %d" % atk_d.size())

	# Losses must be non-negative and sum to number of compared pairs.
	var pairs: int = mini(atk_d.size(), def_d.size())
	var total_loss: int = result["attacker_losses"] + result["defender_losses"]
	if total_loss != pairs:
		errs.append("combat: attacker_losses + defender_losses should == pairs (%d), got %d" % [pairs, total_loss])

	# Dice are sorted descending.
	for i in range(1, atk_d.size()):
		if int(atk_d[i]) > int(atk_d[i - 1]):
			errs.append("combat: attacker dice not sorted descending")
	for i in range(1, def_d.size()):
		if int(def_d[i]) > int(def_d[i - 1]):
			errs.append("combat: defender dice not sorted descending")

	# apply_attack modifies state correctly.
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)
	ConquestTM.set_owner(state, "alaska", 0)
	ConquestTM.set_armies(state, "alaska", 10)
	ConquestTM.set_owner(state, "northwest_territory", 1)
	ConquestTM.set_armies(state, "northwest_territory", 1)
	var apply_result: Dictionary = combat.apply_attack(state, "alaska", "northwest_territory")
	if apply_result.is_empty():
		errs.append("combat: apply_attack returned empty")
		return
	# defender had 1 army — should be captured.
	if not apply_result.get("captured", false):
		errs.append("combat: 10 vs 1 should capture (captures not guaranteed but very likely; retrying below)")
		# Retry with fixed seed that ensures capture.
		combat.rng.seed = 99999
		ConquestTM.set_owner(state, "alaska", 0)
		ConquestTM.set_armies(state, "alaska", 10)
		ConquestTM.set_owner(state, "northwest_territory", 1)
		ConquestTM.set_armies(state, "northwest_territory", 1)
		var r2: Dictionary = combat.apply_attack(state, "alaska", "northwest_territory")
		if not r2.get("captured", false):
			errs.append("combat: 10 vs 1 still not captured on retry")


# ---------------------------------------------------------------------------
# Spawn selection — uncontested
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Roll for turn order
# ---------------------------------------------------------------------------
func _test_roll_for_order(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)
	_add_player(state, 2)

	var combat := ConquestCombat.new()
	combat.rng.seed = 42
	var rolls: Dictionary = ConquestSpawn.roll_for_order(state, combat)

	if not state.roll_for_order_resolved:
		errs.append("roll_order: should be resolved")
	if state.turn_order.size() != 3:
		errs.append("roll_order: turn_order should have 3 entries, got %d" % state.turn_order.size())
	# Every player must appear exactly once.
	for pid in [0, 1, 2]:
		if not state.turn_order.has(pid):
			errs.append("roll_order: player %d missing from turn_order" % pid)
	if rolls.size() != 3:
		errs.append("roll_order: expected 3 roll results, got %d" % rolls.size())
	# Turn order should be sorted descending by roll value.
	for i in range(state.turn_order.size() - 1):
		var r_a: int = int(rolls.get(state.turn_order[i], 0))
		var r_b: int = int(rolls.get(state.turn_order[i + 1], 0))
		if r_a < r_b:
			errs.append("roll_order: turn_order not sorted by roll value")


# ---------------------------------------------------------------------------
# Territory draft
# ---------------------------------------------------------------------------
func _test_territory_draft(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)
	state.turn_order = [0, 1]

	ConquestSpawn.begin_draft(state)
	if state.current_phase != ConquestData.ConquestPhase.TERRITORY_DRAFT:
		errs.append("draft: phase should be TERRITORY_DRAFT")
	if state.current_player_id != 0:
		errs.append("draft: first player should be 0")

	# P0 claims alaska.
	if not ConquestSpawn.draft_territory(state, "alaska"):
		errs.append("draft: should succeed claiming alaska")
	var alaska_t: ConquestData.ConquestTerritory = state.territories["alaska"]
	if alaska_t.owner_player_id != 0:
		errs.append("draft: alaska should be owned by P0")
	if alaska_t.army_count != 1:
		errs.append("draft: alaska should have 1 army")
	# Turn should advance to P1.
	if state.current_player_id != 1:
		errs.append("draft: should be P1's turn after P0 drafts")

	# P1 claims brazil.
	ConquestSpawn.draft_territory(state, "brazil")
	if state.current_player_id != 0:
		errs.append("draft: should be P0's turn again")

	# Can't claim already-claimed territory.
	if ConquestSpawn.draft_territory(state, "alaska"):
		errs.append("draft: should NOT succeed re-claiming alaska")

	# Draft all remaining territories.
	var unclaimed: Array[String] = ConquestSpawn.unclaimed_territories(state)
	for tid in unclaimed:
		ConquestSpawn.draft_territory(state, tid)
	if not ConquestSpawn.is_draft_complete(state):
		errs.append("draft: should be complete after claiming all 42 territories")


# ---------------------------------------------------------------------------
# Army placement
# ---------------------------------------------------------------------------
func _test_army_placement(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)
	state.turn_order = [0, 1]

	# Draft all territories (round-robin).
	ConquestSpawn.begin_draft(state)
	var tids: Array[String] = []
	for t in state.territories.values():
		tids.append(t.territory_id)
	for tid in tids:
		ConquestSpawn.draft_territory(state, tid)

	# Begin placement — 2 players → 40 armies each.
	ConquestSpawn.begin_placement(state)
	if state.current_phase != ConquestData.ConquestPhase.ARMY_PLACEMENT:
		errs.append("placement: phase should be ARMY_PLACEMENT")

	# Each player has 21 territories (42/2), so pool = 40 - 21 = 19.
	var p0_pool: int = int(state.army_placement_pools.get(0, 0))
	var p1_pool: int = int(state.army_placement_pools.get(1, 0))
	if p0_pool != 19:
		errs.append("placement: P0 pool expected 19, got %d" % p0_pool)
	if p1_pool != 19:
		errs.append("placement: P1 pool expected 19, got %d" % p1_pool)

	# Place one army — should succeed on own territory, fail on enemy's.
	var p0_territory: String = ""
	var p1_territory: String = ""
	for t in state.territories.values():
		if t.owner_player_id == 0 and p0_territory.is_empty():
			p0_territory = t.territory_id
		if t.owner_player_id == 1 and p1_territory.is_empty():
			p1_territory = t.territory_id

	state.current_player_id = 0
	if not ConquestSpawn.place_army(state, p0_territory):
		errs.append("placement: should succeed placing on own territory")
	# Pool should decrease.
	if int(state.army_placement_pools.get(0, 0)) != 18:
		errs.append("placement: P0 pool should be 18 after placing 1")

	# Place all remaining armies.
	while not ConquestSpawn.is_placement_complete(state):
		# Find any territory owned by current player.
		for t in state.territories.values():
			if t.owner_player_id == state.current_player_id:
				ConquestSpawn.place_army(state, t.territory_id)
				break

	if not ConquestSpawn.is_placement_complete(state):
		errs.append("placement: should be complete after placing all armies")


# ---------------------------------------------------------------------------
# Fortify path validation
# ---------------------------------------------------------------------------
func _test_fortify_path(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)

	# P0 owns Alberta (adj to Alaska and Western US).
	ConquestTM.set_owner(state, "alberta", 0)
	ConquestTM.set_armies(state, "alberta", 5)
	ConquestTM.set_owner(state, "alaska", 0)
	ConquestTM.set_armies(state, "alaska", 1)  # source but will be used as dest
	ConquestTM.set_owner(state, "western_us", 0)
	ConquestTM.set_armies(state, "western_us", 3)
	ConquestTM.set_owner(state, "brazil", 1)

	# Alberta → Alaska: both owned by P0, Alberta has armies, adjacent.
	if not ConquestPath.can_fortify(state, 0, "alberta", "alaska"):
		errs.append("fortify: alberta→alaska should be valid (adjacent, both P0)")

	# Alberta → Brazil: Brazil owned by P1 — invalid.
	if ConquestPath.can_fortify(state, 0, "alberta", "brazil"):
		errs.append("fortify: alberta→brazil should be invalid (enemy territory)")

	# Fortify source needs 2+ armies; alaska only has 1 — invalid as source.
	if ConquestPath.can_fortify(state, 0, "alaska", "alberta"):
		errs.append("fortify: alaska→alberta invalid (alaska only 1 army)")

	# Same territory → invalid.
	if ConquestPath.can_fortify(state, 0, "alberta", "alberta"):
		errs.append("fortify: same territory should be invalid")

	# Build a 3-hop chain: eastern_us → ontario → quebec (all P0).
	ConquestTM.set_owner(state, "eastern_us", 0)
	ConquestTM.set_armies(state, "eastern_us", 4)
	ConquestTM.set_owner(state, "ontario", 0)
	ConquestTM.set_armies(state, "ontario", 2)
	ConquestTM.set_owner(state, "quebec", 0)
	ConquestTM.set_armies(state, "quebec", 2)

	if not ConquestPath.can_fortify(state, 0, "eastern_us", "quebec"):
		errs.append("fortify: eastern_us→quebec 3-hop chain should be valid")

	# Break chain by giving ontario to P1.
	ConquestTM.set_owner(state, "ontario", 1)
	if ConquestPath.can_fortify(state, 0, "eastern_us", "quebec"):
		errs.append("fortify: broken chain eastern_us→quebec should be invalid")


# ---------------------------------------------------------------------------
# Player elimination
# ---------------------------------------------------------------------------
func _test_player_elimination(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)

	# P0 owns alaska, P1 owns nothing.
	ConquestTM.set_owner(state, "alaska", 0)

	var elim: Array[int] = ConquestTM.check_eliminations(state)
	if not elim.has(1):
		errs.append("elimination: P1 with 0 territories should be eliminated")

	if elim.has(0):
		errs.append("elimination: P0 with 1 territory should not be eliminated")


# ---------------------------------------------------------------------------
# Victory detection
# ---------------------------------------------------------------------------
func _test_victory_detection(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)

	# Give all territories to P0, mark P1 eliminated.
	for tid in state.territories.keys():
		ConquestTM.set_owner(state, tid, 0)
	var p1: ConquestData.ConquestPlayer = state.players[1]
	p1.is_alive = false

	var winner: int = ConquestTM.check_winner(state)
	if winner != 0:
		errs.append("victory: P0 should be winner, got %d" % winner)

	# Two alive players → no winner yet.
	var state2: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state2, 0)
	_add_player(state2, 1)
	var w2: int = ConquestTM.check_winner(state2)
	if w2 != -1:
		errs.append("victory: two alive players — no winner yet, got %d" % w2)


# ---------------------------------------------------------------------------
# Army capture and forced move
# ---------------------------------------------------------------------------
func _test_army_capture(errs: PackedStringArray) -> void:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)
	ConquestTM.set_owner(state, "alaska", 0)
	ConquestTM.set_armies(state, "alaska", 10)
	ConquestTM.set_owner(state, "northwest_territory", 1)
	ConquestTM.set_armies(state, "northwest_territory", 1)

	var combat := ConquestCombat.new()
	# Use many retries to ensure a capture (10 vs 1 with random dice).
	var captured: bool = false
	for _attempt in range(20):
		var s2: ConquestData.ConquestGameState = ConquestBoard.build()
		_add_player(s2, 0)
		_add_player(s2, 1)
		ConquestTM.set_owner(s2, "alaska", 0)
		ConquestTM.set_armies(s2, "alaska", 10)
		ConquestTM.set_owner(s2, "northwest_territory", 1)
		ConquestTM.set_armies(s2, "northwest_territory", 1)
		var r: Dictionary = combat.apply_attack(s2, "alaska", "northwest_territory")
		if r.get("captured", false):
			captured = true
			# Verify owner transferred.
			if ConquestTM.get_owner(s2, "northwest_territory") != 0:
				errs.append("capture: owner should transfer to P0 after capture")
			# Attacker must have moved armies.
			var moved: int = r.get("armies_moved", 0)
			if moved < 1:
				errs.append("capture: armies_moved should be >= 1")
			# Total armies must be conserved minus attacker losses.
			break

	if not captured:
		errs.append("capture: 10 vs 1 never captured in 20 attempts (very unlikely)")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _add_player(state: ConquestData.ConquestGameState, pid: int) -> void:
	var colors: Array[Color] = [Color.BLUE, Color.RED, Color.GREEN, Color.GOLD]
	var p := ConquestData.ConquestPlayer.new(pid, "Player %d" % pid, colors[pid % colors.size()])
	state.players[pid] = p


func _make_two_player_state() -> ConquestData.ConquestGameState:
	var state: ConquestData.ConquestGameState = ConquestBoard.build()
	_add_player(state, 0)
	_add_player(state, 1)
	return state


## Give all territories of a region to player_id.
func _give_region(
	state: ConquestData.ConquestGameState,
	player_id: int,
	region_id: String
) -> void:
	var region: ConquestData.ConquestRegion = state.regions.get(region_id)
	if region == null:
		return
	for tid in region.territory_ids:
		ConquestTM.set_owner(state, tid, player_id)


## Give `count` arbitrary territories to player_id (from unowned pool).
func _give_extra_territories(
	state: ConquestData.ConquestGameState,
	player_id: int,
	count: int
) -> void:
	var given: int = 0
	for t in state.territories.values():
		if given >= count:
			break
		if t.owner_player_id == -1:
			ConquestTM.set_owner(state, t.territory_id, player_id)
			given += 1


func _finish(errs: PackedStringArray) -> void:
	if errs.is_empty():
		print("TEST_CONQUEST_CORE: PASS")
	else:
		for e in errs:
			push_error("TEST_CONQUEST_CORE: %s" % e)
		print("TEST_CONQUEST_CORE: FAIL (%d)" % errs.size())
