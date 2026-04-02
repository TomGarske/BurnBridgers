class_name IronwakeWhirlpool
extends RefCounted
## Whirlpool arena-integration logic extracted from IronwakeArena.
## Owns init, per-frame advance, and per-ship physics injection.
## The WhirlpoolController (physics model) still lives on the arena as _whirlpool.

const NC := preload("res://scripts/shared/naval_combat_constants.gd")
const _WhirlpoolController := preload("res://scripts/shared/whirlpool_controller.gd")

var arena: Node = null


func init(arena_node: Node) -> void:
	arena = arena_node


func init_whirlpool() -> void:
	if not arena.whirlpool_enabled:
		return
	arena._whirlpool = _WhirlpoolController.new()
	var u: float = NC.UNITS_PER_LOGIC_TILE
	arena._whirlpool.center = Vector2(float(NC.MAP_TILES_WIDE) * 0.5 * u, float(NC.MAP_TILES_HIGH) * 0.5 * u)
	arena._whirlpool.influence_radius = arena.whirlpool_influence_radius
	arena._whirlpool._base_influence_radius = arena.whirlpool_influence_radius
	arena._whirlpool.control_ring_radius = arena.whirlpool_control_radius
	arena._whirlpool.danger_ring_radius = arena.whirlpool_danger_radius
	arena._whirlpool.core_radius = arena.whirlpool_core_radius


func begin_frame(delta: float = 0.0) -> void:
	if arena._whirlpool != null:
		arena._whirlpool.frame_id += 1
		arena._whirlpool.advance_time(delta)


func pre_physics(p: Dictionary, delta: float) -> void:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		return
	if not bool(p.get("alive", false)):
		return

	var ship_id: int = int(p.get("peer_id", 0))
	var ship_pos: Vector2 = Vector2(float(p.wx), float(p.wy))
	var ship_dir: Vector2 = Vector2(float(p.dir.x), float(p.dir.y))
	if ship_dir.length_squared() < 0.0001:
		ship_dir = Vector2.RIGHT
	else:
		ship_dir = ship_dir.normalized()
	var spd: float = float(p.get("move_speed", 0.0))

	var ws: _WhirlpoolController.WhirlpoolShipState = arena._whirlpool.process_ship(
		ship_id, ship_pos, ship_dir, spd, NC.MAX_SPEED, delta)

	p["_wp_ring"] = ws.ring_type
	p["_wp_captured"] = ws.is_captured
	p["_wp_just_ejected"] = ws.just_ejected
	p["_wp_turn_mod"] = ws.turn_modifier
	p["_wp_accel_mod"] = ws.acceleration_modifier
	p["_wp_flow_align"] = ws.flow_alignment
	p["_wp_flow_dir"] = ws.flow_direction
	p["_wp_vel_influence"] = ws.velocity_influence
	p["_wp_capture_av"] = ws.capture_angular_velocity
	p["_wp_eject_dir"] = ws.eject_direction
	p["_wp_eject_speed"] = ws.eject_speed
	p["_wp_recovery"] = ws.recovery_scalar
	p["_wp_drag_force"] = ws.drag_force
	p["_wp_torque"] = ws.torque
	p["_wp_water_vel"] = ws.water_velocity
	p["_wp_water_speed"] = ws.water_speed
	p["_wp_v_lateral"] = ws.v_lateral
	p["_wp_water_carry"] = ws.water_carry



func turn_scalar(p: Dictionary) -> float:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		return 1.0
	if bool(p.get("_wp_captured", false)):
		return 0.0
	var recovery: float = float(p.get("_wp_recovery", 1.0))
	var turn_mod: float = float(p.get("_wp_turn_mod", 1.0))
	if int(p.get("_wp_ring", 0)) == 0 and recovery < 1.0:
		return minf(1.0, recovery + 0.3)
	return turn_mod


func accel_scalar(p: Dictionary) -> float:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		return 1.0
	if bool(p.get("_wp_captured", false)):
		return 0.3
	return float(p.get("_wp_accel_mod", 1.0))


func inject_physics(p: Dictionary, delta: float) -> void:
	if arena._whirlpool == null or not arena.whirlpool_enabled:
		p["_wp_water_carry_vel"] = Vector2.ZERO
		return
	var ring: int = int(p.get("_wp_ring", 0))
	var captured: bool = bool(p.get("_wp_captured", false))
	var just_ejected: bool = bool(p.get("_wp_just_ejected", false))

	if just_ejected:
		p.alive = false
		p["move_speed"] = 0.0
		p["angular_velocity"] = 0.0
		p["respawn_timer"] = arena.RESPAWN_DELAY_SEC
		var def_pid: int = int(p.get("peer_id", 0))
		if arena._scoreboard.has(def_pid):
			arena._scoreboard[def_pid]["deaths"] += 1
		p["_wp_just_ejected"] = false
		p["_wp_captured"] = false
		p["_wp_ring"] = 0
		var ship_id: int = int(p.get("peer_id", 0))
		var ws: _WhirlpoolController.WhirlpoolShipState = arena._whirlpool.get_ship_state(ship_id)
		ws.eject_speed = 0.0
		ws.just_ejected = false
		ws.is_captured = false
		ws.capture_timer = 0.0
		ws.eject_immunity_timer = 0.0
		if not arena.multiplayer.has_multiplayer_peer() or arena.multiplayer.is_server():
			arena._check_win()
		return

	if captured:
		var capture_av: float = float(p.get("_wp_capture_av", -3.0))
		p["angular_velocity"] = capture_av
		var cap_hull: Vector2 = Vector2(p.dir.x, p.dir.y)
		if cap_hull.length_squared() < 0.0001:
			cap_hull = Vector2.RIGHT
		cap_hull = cap_hull.rotated(capture_av * delta).normalized()
		p.dir = cap_hull
		var vel_inf: Vector2 = p.get("_wp_vel_influence", Vector2.ZERO)
		p.wx = float(p.wx) + vel_inf.x
		p.wy = float(p.wy) + vel_inf.y
		p["move_speed"] = maxf(0.0, float(p.get("move_speed", 0.0)) * (1.0 - 0.8 * delta))
		return

	if ring == 0:
		p["_wp_water_carry_vel"] = Vector2.ZERO
		return

	var drag_force: Vector2 = p.get("_wp_drag_force", Vector2.ZERO)
	var wp_torque: float = float(p.get("_wp_torque", 0.0))
	var hull: Vector2 = Vector2(p.dir.x, p.dir.y)
	if hull.length_squared() < 0.0001:
		hull = Vector2.RIGHT
	hull = hull.normalized()

	var water_carry: Vector2 = p.get("_wp_water_carry", Vector2.ZERO)
	p["_wp_water_carry_vel"] = water_carry

	var spd: float = float(p.get("move_speed", 0.0))
	var grav_long: float = drag_force.dot(hull)
	spd = clampf(spd + grav_long * 0.5 * delta, 0.0, NC.MAX_SPEED)
	p["move_speed"] = spd

	var av: float = float(p.get("angular_velocity", 0.0))
	av += wp_torque * delta
	p["angular_velocity"] = av

	var drag_lat_vec: Vector2 = drag_force - hull * drag_force.dot(hull)
	if drag_lat_vec.length_squared() > 0.01:
		var lat_heading_push: float = hull.angle_to(hull + drag_lat_vec * 0.15 * delta)
		hull = hull.rotated(lat_heading_push).normalized()
		p.dir = hull
