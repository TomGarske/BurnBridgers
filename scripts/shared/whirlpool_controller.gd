## Centered whirlpool arena mechanic — Rankine vortex model.
##
## Two-zone velocity profile:
##   Forced vortex  (r <= R_core):  v_tan = v_max * (r / R_core)   — solid body rotation
##   Free vortex    (r >  R_core):  v_tan = v_max * (R_core / r)   — 1/r decay
##
## Radial inflow proportional to tangential:  v_radial = inflow_ratio * v_tangential
## Drag force on ship ∝ |v_water − v_ship|²  (quadratic fluid drag)
## Turning torque ∝ |v_lateral|² (cross-flow component squared)
##
## (req-whirlpool-arena-v1)
extends RefCounted
class_name WhirlpoolController

# ═══════════════════════════════════════════════════════════════════════
#  Ring classification (visual / gameplay zones only — physics is continuous)
# ═══════════════════════════════════════════════════════════════════════

enum Ring { NONE, OUTER, CONTROL, DANGER, CORE }

# ═══════════════════════════════════════════════════════════════════════
#  Geometry (world-unit radii)
# ═══════════════════════════════════════════════════════════════════════

var center: Vector2 = Vector2.ZERO

## Ring boundaries — used for classification and visuals.
## Core is where the forced vortex peaks; beyond it, free vortex decays.
var influence_radius: float = 600.0
var control_ring_radius: float = 280.0
var danger_ring_radius: float = 120.0
var core_radius: float = 40.0

# ═══════════════════════════════════════════════════════════════════════
#  Rankine vortex parameters
# ═══════════════════════════════════════════════════════════════════════

## Water speed at each ring boundary as a fraction of max_speed.
## Tuned for gameplay — not pure Rankine (which decays too fast for wide rings).
## OUTER edge (influence_radius): noticeable current to signal you're entering.
var water_frac_outer_edge: float = 0.096
## OUTER→CONTROL boundary (control_ring_radius):
var water_frac_control: float = 0.20
## CONTROL→DANGER boundary (danger_ring_radius):
var water_frac_danger: float = 0.32
## DANGER→CORE boundary (core_radius): peak speed.
var water_frac_core: float = 0.80

## Inflow ratio: radial_speed = inflow_ratio * tangential_speed.
## 0.08 = gentle pull, objects orbit many times before spiraling in.
var inflow_ratio: float = 0.08

# ═══════════════════════════════════════════════════════════════════════
#  Drag / force tuning  (collapsed constants: 0.5 * Cd * rho * A → drag_k)
# ═══════════════════════════════════════════════════════════════════════

## Quadratic drag coefficient for translational force.
## F = drag_k * |v_rel|² * normalize(v_rel)
## This accelerates the ship; units are 1/speed (so F has units of acceleration).
## Keep LOW — the whirlpool should nudge, not dominate. Ships should still steer.
var drag_k: float = 0.0018

## Torque coefficient for cross-flow turning.
## torque = torque_k * |v_lateral|² * sign(cross(forward, v_lateral))
## Units: rad/s per (speed²) — feeds into angular_velocity.
var torque_k: float = 0.0012

## Maximum angular velocity the whirlpool torque can contribute (rad/s).
## Prevents absurd spin rates even in extreme cross-flow.
var max_torque_av: float = 0.5

## Turn authority penalty inside the whirlpool.
## Interpolated: 1.0 at edge → this value at core.
## 0.7 means even at the core you still have 70% steering. Outer ring barely affected.
var min_turn_authority: float = 0.7

## Gravity well: base inward acceleration (world units/s²).
## Actual pull = gravity_pull × depth² × escape_factor.
## escape_factor: 1.0 when dead in water, 0.15 at full speed.
## A stationary ship in the danger ring feels ~3 units/s² pull inward.
## A full-speed ship feels only ~0.45 units/s² — easily escaped.
var gravity_pull: float = 6.0

# ═══════════════════════════════════════════════════════════════════════
#  Disruption — whirlpool escalates over time
# ═══════════════════════════════════════════════════════════════════════

## Elapsed time since whirlpool started (seconds). Call advance_time() each tick.
var elapsed_time: float = 0.0

## Time (seconds) for disruption to go from 0% → 100%.
var disruption_ramp_sec: float = 180.0  # 3 minutes to full disruption.

## At full disruption, water speed is multiplied by this.
var disruption_speed_mult_max: float = 1.6

## At full disruption, gravity pull is multiplied by this.
var disruption_gravity_mult_max: float = 2.0

## At full disruption, turbulence jitter amplitude (world units/s² on drag force).
var disruption_turbulence_max: float = 3.0

## At full disruption, influence radius grows by this fraction (whirlpool expands).
var disruption_radius_growth: float = 0.25

## Base influence radius (set once at init, before disruption expands it).
var _base_influence_radius: float = 600.0

## Current disruption level (0.0–1.0). Read-only outside; use advance_time().
var disruption: float = 0.0


## Call once per tick with delta to advance disruption.
func advance_time(delta: float) -> void:
	elapsed_time += delta
	disruption = clampf(elapsed_time / maxf(0.01, disruption_ramp_sec), 0.0, 1.0)
	# Expand the whirlpool radius as disruption grows.
	influence_radius = _base_influence_radius * (1.0 + disruption * disruption_radius_growth)


## Current speed multiplier from disruption (1.0 at start, up to disruption_speed_mult_max).
func _disruption_speed_mult() -> float:
	return lerpf(1.0, disruption_speed_mult_max, disruption)


## Current gravity multiplier from disruption.
func _disruption_gravity_mult() -> float:
	return lerpf(1.0, disruption_gravity_mult_max, disruption)


## Pseudorandom turbulence vector for a given position + time (deterministic noise).
func _turbulence_at(pos: Vector2, time: float) -> Vector2:
	# Use sin-based hash for cheap deterministic noise.
	var seed_x: float = pos.x * 0.013 + pos.y * 0.0079 + time * 1.7
	var seed_y: float = pos.x * 0.0091 + pos.y * 0.017 + time * 2.3
	return Vector2(sin(seed_x * 6.28) * cos(seed_y * 3.14), cos(seed_x * 3.14) * sin(seed_y * 6.28))


# ═══════════════════════════════════════════════════════════════════════
#  Per-ship state
# ═══════════════════════════════════════════════════════════════════════

var _ship_states: Dictionary = {}


class WhirlpoolShipState:
	var is_in_whirlpool: bool = false
	var distance_to_center: float = 0.0
	var ring_type: int = Ring.NONE
	## Computed water velocity at ship position (world units/sec).
	var water_velocity: Vector2 = Vector2.ZERO
	## Water speed magnitude at ship position.
	var water_speed: float = 0.0
	## Tangential water speed component (positive = CCW flow direction).
	var water_speed_tangential: float = 0.0
	## Radial water speed component (positive = inward).
	var water_speed_radial: float = 0.0
	## Relative velocity: water - ship (world units/sec).
	var v_relative: Vector2 = Vector2.ZERO
	## Lateral (cross-flow) component of v_relative w.r.t ship heading.
	var v_lateral: float = 0.0
	## Longitudinal (along-ship) component of v_relative.
	var v_longitudinal: float = 0.0
	## Drag force vector this tick (acceleration, world units/s²).
	var drag_force: Vector2 = Vector2.ZERO
	## Direct water carry: velocity applied to position each tick (world units/s).
	## Slow ships get carried by the current; fast ships resist it.
	var water_carry: Vector2 = Vector2.ZERO
	## Torque this tick (angular acceleration, rad/s²). Positive = CCW.
	var torque: float = 0.0
	## Flow direction (unit vector, tangential CCW).
	var flow_direction: Vector2 = Vector2.ZERO
	## Dot product of ship heading with flow direction (-1 to 1).
	var flow_alignment: float = 0.0
	## Turn authority scalar (1.0 = full, lower = sluggish from current).
	var turn_modifier: float = 1.0
	## Acceleration modifier based on flow alignment.
	var acceleration_modifier: float = 1.0
	var prev_ring: int = Ring.NONE
	var _frame_id: int = -1


# ═══════════════════════════════════════════════════════════════════════
#  Public API
# ═══════════════════════════════════════════════════════════════════════

var frame_id: int = 0


func get_ship_state(ship_id: int) -> WhirlpoolShipState:
	if not _ship_states.has(ship_id):
		_ship_states[ship_id] = WhirlpoolShipState.new()
	return _ship_states[ship_id]


func classify_ring(distance: float) -> int:
	if distance > influence_radius:
		return Ring.NONE
	if distance > control_ring_radius:
		return Ring.OUTER
	if distance > danger_ring_radius:
		return Ring.CONTROL
	if distance > core_radius:
		return Ring.DANGER
	return Ring.CORE


static func ring_name(ring: int) -> String:
	match ring:
		Ring.NONE: return "NONE"
		Ring.OUTER: return "OUTER"
		Ring.CONTROL: return "CONTROL"
		Ring.DANGER: return "DANGER"
		Ring.CORE: return "CORE"
	return "?"


## Compute water speed at a given distance from center.
## Uses smooth interpolation between ring boundary speeds for gameplay tuning.
## Returns the tangential speed (scalar). Radial = inflow_ratio * tangential.
func water_speed_at_radius(r: float, max_speed: float) -> float:
	if r > influence_radius:
		return 0.0

	# Smoothstep helper: 0 at outer, 1 at inner.
	var v_tan: float
	if r > control_ring_radius:
		# OUTER ring: 0 at edge → water_frac_control at inner boundary.
		var t: float = _smooth_t(r, influence_radius, control_ring_radius)
		v_tan = lerpf(water_frac_outer_edge, water_frac_control, t) * max_speed
	elif r > danger_ring_radius:
		# CONTROL ring: water_frac_control → water_frac_danger.
		var t: float = _smooth_t(r, control_ring_radius, danger_ring_radius)
		v_tan = lerpf(water_frac_control, water_frac_danger, t) * max_speed
	elif r > core_radius:
		# DANGER ring: water_frac_danger → water_frac_core.
		var t: float = _smooth_t(r, danger_ring_radius, core_radius)
		v_tan = lerpf(water_frac_danger, water_frac_core, t) * max_speed
	else:
		# CORE: peak speed (forced vortex — solid body, slight decrease toward center).
		v_tan = water_frac_core * max_speed * clampf(r / maxf(0.01, core_radius), 0.3, 1.0)

	return v_tan * _disruption_speed_mult()


## Returns 0.0 at outer_r, 1.0 at inner_r, with smoothstep.
func _smooth_t(dist: float, outer_r: float, inner_r: float) -> float:
	var raw: float = 1.0 - clampf((dist - inner_r) / maxf(0.01, outer_r - inner_r), 0.0, 1.0)
	return raw * raw * (3.0 - 2.0 * raw)


## Process whirlpool effects for a single ship. Call EXACTLY ONCE per tick.
func process_ship(ship_id: int, ship_pos: Vector2, ship_dir: Vector2, ship_speed: float, max_speed: float, delta: float) -> WhirlpoolShipState:
	var state: WhirlpoolShipState = get_ship_state(ship_id)

	# Guard: only process once per frame.
	if state._frame_id == frame_id:
		return state
	state._frame_id = frame_id

	var to_center: Vector2 = center - ship_pos
	var dist: float = to_center.length()

	state.distance_to_center = dist
	state.prev_ring = state.ring_type
	state.ring_type = classify_ring(dist)
	state.is_in_whirlpool = state.ring_type != Ring.NONE

	# Reset per-tick outputs.
	state.drag_force = Vector2.ZERO
	state.water_carry = Vector2.ZERO
	state.torque = 0.0

	# ── Outside influence ──
	if not state.is_in_whirlpool:
		state.water_velocity = Vector2.ZERO
		state.water_speed = 0.0
		state.water_speed_tangential = 0.0
		state.water_speed_radial = 0.0
		state.v_relative = Vector2.ZERO
		state.v_lateral = 0.0
		state.v_longitudinal = 0.0
		state.flow_direction = Vector2.ZERO
		state.flow_alignment = 0.0
		state.turn_modifier = 1.0
		state.acceleration_modifier = 1.0
		return state

	# ── Directional basis ──
	var radial_inward: Vector2 = to_center.normalized() if dist > 0.01 else Vector2.UP
	var tangential: Vector2 = radial_inward.rotated(-PI * 0.5)
	state.flow_direction = tangential

	# ── Compute Rankine water velocity at ship position ──
	var v_tan: float = water_speed_at_radius(dist, max_speed)
	var v_rad: float = v_tan * inflow_ratio
	var water_vel: Vector2 = tangential * v_tan + radial_inward * v_rad

	state.water_velocity = water_vel
	state.water_speed = water_vel.length()
	state.water_speed_tangential = v_tan
	state.water_speed_radial = v_rad

	# ── Ship velocity vector ──
	var ship_dir_n: Vector2 = ship_dir.normalized() if ship_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var ship_vel: Vector2 = ship_dir_n * ship_speed

	# ── Relative velocity: water w.r.t. ship ──
	var v_rel: Vector2 = water_vel - ship_vel
	state.v_relative = v_rel

	# ── Decompose v_rel into longitudinal (along ship) and lateral (across ship) ──
	var v_long: float = v_rel.dot(ship_dir_n)
	var v_lat_vec: Vector2 = v_rel - ship_dir_n * v_long
	var v_lat_mag: float = v_lat_vec.length()
	state.v_longitudinal = v_long
	state.v_lateral = v_lat_mag

	# ── Flow alignment ──
	state.flow_alignment = ship_dir_n.dot(tangential)

	# ── Quadratic drag force: F = drag_k * |v_rel|² * normalize(v_rel) ──
	var v_rel_sq: float = v_rel.length_squared()
	if v_rel_sq > 0.01:
		state.drag_force = v_rel.normalized() * drag_k * v_rel_sq
	else:
		state.drag_force = Vector2.ZERO

	# ── Gravity well with escape velocity ──
	# Exponential pull: gentle at edge, ramps hard near center.
	# Formula: gravity_pull × (e^(k×depth) - 1) / (e^k - 1) × escape_factor
	# k=4 gives ~2% pull at 25% depth, ~18% at 50%, ~55% at 75%, 100% at core.
	# Fast ships easily escape; dead-in-the-water ships get sucked in.
	var speed_ratio: float = clampf(ship_speed / maxf(0.01, max_speed), 0.0, 1.0)
	var escape_factor: float = lerpf(1.0, 0.15, speed_ratio)
	var depth_norm: float = 1.0 - clampf(dist / influence_radius, 0.0, 1.0)  # 0 at edge, 1 at center
	var grav_exp_k: float = 4.0
	var grav_frac: float = (exp(grav_exp_k * depth_norm) - 1.0) / (exp(grav_exp_k) - 1.0)
	var grav_accel: float = gravity_pull * grav_frac * escape_factor * _disruption_gravity_mult()
	state.drag_force += radial_inward * grav_accel

	# ── Turbulence: chaotic jitter that grows with disruption and depth ──
	if disruption > 0.01:
		var turb_amp: float = disruption_turbulence_max * disruption * depth_norm
		var turb_vec: Vector2 = _turbulence_at(ship_pos, elapsed_time) * turb_amp
		state.drag_force += turb_vec

	# ── Water carry: current drags the ship's position directly ──
	# Slow ships get carried almost fully; fast ships resist the current.
	# carry_factor: 1.0 when stationary → 0.1 at max speed.
	var carry_factor: float = lerpf(1.0, 0.1, speed_ratio)
	state.water_carry = water_vel * carry_factor

	# ── Torque from cross-flow: LINEAR in v_lateral (not quadratic) ──
	# Gentle nudge that aligns heading with the flow over time.
	# Fast ships with high v_lat barely feel it; slow ships turn with the current.
	if v_lat_mag > 0.1:
		var cross_sign: float = signf(ship_dir_n.x * v_lat_vec.y - ship_dir_n.y * v_lat_vec.x)
		# Scale torque by water speed fraction, not ship-relative velocity.
		# This prevents fast ships from generating enormous self-torque.
		var water_frac: float = clampf(water_vel.length() / maxf(0.01, max_speed), 0.0, 1.0)
		state.torque = clampf(torque_k * v_lat_mag * water_frac * cross_sign, -max_torque_av, max_torque_av)
	else:
		state.torque = 0.0

	# ── Turn authority: penalized by how strong the current is relative to ship speed ──
	# Stronger current = harder to steer. Lerp from 1.0 at edge to min_turn_authority at core.
	var depth_frac: float = 1.0 - clampf((dist - core_radius) / maxf(0.01, influence_radius - core_radius), 0.0, 1.0)
	state.turn_modifier = lerpf(1.0, min_turn_authority, depth_frac)

	# ── Acceleration modifier: boost with flow, penalize against ──
	# Scaled by depth — outer ring barely affects accel, inner rings more so.
	var alignment: float = state.flow_alignment
	var accel_depth: float = depth_frac * depth_frac  # Quadratic — very mild in outer ring.
	if alignment > 0.0:
		state.acceleration_modifier = lerpf(1.0, 1.3, alignment * accel_depth)
	else:
		state.acceleration_modifier = lerpf(1.0, 0.7, -alignment * accel_depth)

	return state


# ═══════════════════════════════════════════════════════════════════════
#  AI data hooks
# ═══════════════════════════════════════════════════════════════════════

func get_ai_data(ship_id: int, ship_pos: Vector2, ship_dir: Vector2) -> Dictionary:
	var state: WhirlpoolShipState = get_ship_state(ship_id)
	var to_center: Vector2 = center - ship_pos
	var dist: float = to_center.length()
	var tangential: Vector2 = Vector2.ZERO
	if dist > 0.01:
		tangential = to_center.normalized().rotated(-PI * 0.5)
	var ship_dir_n: Vector2 = ship_dir.normalized() if ship_dir.length_squared() > 0.0001 else Vector2.RIGHT
	var slingshot_score: float = 0.0
	if state.ring_type == Ring.CONTROL:
		slingshot_score = maxf(0.0, ship_dir_n.dot(tangential))
	return {
		"distance_to_whirlpool_center": dist,
		"whirlpool_ring": state.ring_type,
		"whirlpool_ring_name": ring_name(state.ring_type),
		"whirlpool_flow_direction": tangential,
		"whirlpool_water_speed": state.water_speed,
		"is_in_danger_ring": state.ring_type == Ring.DANGER,
		"is_in_core": state.ring_type == Ring.CORE or state.is_captured,
		"slingshot_alignment_score": slingshot_score,
	}
