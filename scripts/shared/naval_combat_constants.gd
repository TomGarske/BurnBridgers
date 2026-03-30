## Tunables for req-naval-combat-prototype-v1 (Blacksite naval mode).
## World coordinates use UNITS_PER_LOGIC_TILE world units per terrain grid cell.
## 1 world unit = 1 meter.
extends Object

const UNITS_PER_LOGIC_TILE: float = 10.0

const MAP_TILES_WIDE: int = 800
const MAP_TILES_HIGH: int = 800

## Movement tuning (higher top-end speed with same accel/decel feel).
## Residual speed when sails furled: current + wind on bare hull/rigging (~1.5 kn).
## Below MIN_SPEED_DRIFT so rudder loses authority — historically accurate.
const SAILS_DOWN_DRIFT_SPEED: float = 0.8
const MIN_SPEED_DRIFT: float = 1.5
const QUARTER_SPEED: float = 4.0
const CRUISE_SPEED: float = 7.0
const MAX_SPEED: float = 11.5

## Preserve previous linear acceleration/deceleration rates.
const ACCEL_TIME_ZERO_TO_MAX: float = 29.76
const DECEL_TIME_SAILS_DOWN: float = 27.06

## Derived linear accel (u/s²)
static func accel_rate() -> float:
	return MAX_SPEED / maxf(0.001, ACCEL_TIME_ZERO_TO_MAX)


static func decel_rate_sails() -> float:
	return MAX_SPEED / maxf(0.001, DECEL_TIME_SAILS_DOWN)


## Turning: heavy at all speeds.
## Radius ≈ speed / deg_to_rad(rate). Quarter≈82u, Half≈335u, Full≈1465u.
static func turn_rate_deg_for_speed(speed: float) -> float:
	var s: float = clampf(speed, 0.0, MAX_SPEED * 1.1)
	if s <= MIN_SPEED_DRIFT:
		return 5.0
	if s <= QUARTER_SPEED:
		var t: float = (s - MIN_SPEED_DRIFT) / maxf(0.001, QUARTER_SPEED - MIN_SPEED_DRIFT)
		return lerpf(5.0, 2.8, t)
	if s <= CRUISE_SPEED:
		var t: float = (s - QUARTER_SPEED) / maxf(0.001, CRUISE_SPEED - QUARTER_SPEED)
		return lerpf(2.8, 1.2, t)
	var t2: float = (s - CRUISE_SPEED) / maxf(0.001, MAX_SPEED - CRUISE_SPEED)
	return lerpf(1.2, 0.45, clampf(t2, 0.0, 1.0))


## Rudder / heading inertia.
const HELM_TURN_LAG_SEC: float = 2.5

## §4 Firing — half-angle from broadside normal (total arc per side ≈ 90°).
## Cannons can only traverse ±6° at the gunport; the arc represents the combined
## coverage of all guns along the hull.  Peak accuracy at 90° (beam), degraded
## toward the 45° and 135° edges where only extreme guns bear.
const BROADSIDE_HALF_ARC_DEG: float = 45.0
const BROADSIDE_QUALITY_PEAK_DEG: float = 90.0
const BROADSIDE_QUALITY_FALLOFF_START_DEG: float = 25.0
const BROADSIDE_QUALITY_FALLOFF_END_DEG: float = 45.0
const CANNON_FINE_AIM_DEG: float = 6.0

## Broadside quality: 1.0 at beam (90° from bow), dropping to 0.3 at arc edges.
## angle_from_bow: absolute angle between ship forward and target direction.
static func broadside_quality(angle_from_bow_deg: float) -> float:
	var off_beam: float = absf(angle_from_bow_deg - BROADSIDE_QUALITY_PEAK_DEG)
	if off_beam <= BROADSIDE_QUALITY_FALLOFF_START_DEG:
		return 1.0
	if off_beam >= BROADSIDE_QUALITY_FALLOFF_END_DEG:
		return 0.3
	var t: float = (off_beam - BROADSIDE_QUALITY_FALLOFF_START_DEG) / (BROADSIDE_QUALITY_FALLOFF_END_DEG - BROADSIDE_QUALITY_FALLOFF_START_DEG)
	return lerpf(1.0, 0.3, t)

## Chase batteries: narrower arc, longer reload, fewer guns.
const CHASE_HALF_ARC_DEG: float = 20.0
const CHASE_CANNON_COUNT: int = 2
const CHASE_RELOAD_TIME_SEC: float = 22.0
const CHASE_BATTERY_DAMAGE: float = 40.0

const RELOAD_TIME_SEC: float = 18.0

## §4.1 Max engagement (same unit space as wx, wy)
const OPTIMAL_RANGE: float = 250.0
const MAX_CANNON_RANGE: float = 450.0
const CLOSE_RANGE: float = 120.0

## Projectile horizontal speed scale (req-weapons-layer-v1 suggests ~55 u/s; raised here so
## arc + lifetime still reach MAX_CANNON_RANGE on this map).
const PROJECTILE_SPEED: float = 110.0
const PROJECTILE_LIFETIME: float = 6.0
const PROJECTILE_GRAVITY_SCALE: float = 0.32

## Historical accuracy model (age of sail, manned broadsides).
## Bands now aligned to the actual cannon engagement envelope:
##   depressed quoin  → ~125u   (point-blank)
##   flat quoin       → ~250u   (optimal combat)
##   max quoin        → ~450u   (extreme range)
##   pistol shot  (0–40u):   ~90%
##   point blank  (40–125u): ~75%
##   effective    (125–250u): ~50%
##   long         (250–370u): ~25%
##   extreme      (370–450u): ~10%
const ACC_PISTOL_RANGE: float = 40.0
const ACC_CLOSE_RANGE: float = 125.0
const ACC_MUSKET_RANGE: float = 250.0
const ACC_MEDIUM_RANGE: float = 370.0
const ACC_LONG_RANGE: float = 450.0

static func hit_probability(distance: float) -> float:
	if distance <= ACC_PISTOL_RANGE:
		return lerpf(0.92, 0.85, clampf(distance / ACC_PISTOL_RANGE, 0.0, 1.0))
	if distance <= ACC_CLOSE_RANGE:
		var t: float = (distance - ACC_PISTOL_RANGE) / (ACC_CLOSE_RANGE - ACC_PISTOL_RANGE)
		return lerpf(0.85, 0.65, t)
	if distance <= ACC_MUSKET_RANGE:
		var t: float = (distance - ACC_CLOSE_RANGE) / (ACC_MUSKET_RANGE - ACC_CLOSE_RANGE)
		return lerpf(0.65, 0.40, t)
	if distance <= ACC_MEDIUM_RANGE:
		var t: float = (distance - ACC_MUSKET_RANGE) / (ACC_MEDIUM_RANGE - ACC_MUSKET_RANGE)
		return lerpf(0.40, 0.15, t)
	if distance <= ACC_LONG_RANGE:
		var t: float = (distance - ACC_MEDIUM_RANGE) / (ACC_LONG_RANGE - ACC_MEDIUM_RANGE)
		return lerpf(0.15, 0.02, t)
	return 0.02

## Base half-spread (degrees) before pattern offsets — req-weapons-layer-v1 §Accuracy Model.
static func spread_deg_for_range(distance: float) -> float:
	var d: float = maxf(0.0, distance)
	if d < 100.0:
		return lerpf(2.0, 4.0, clampf(d / 100.0, 0.0, 1.0))
	if d < 200.0:
		return lerpf(5.0, 8.0, (d - 100.0) / 100.0)
	var t_far: float = clampf((d - 200.0) / maxf(1.0, ACC_LONG_RANGE - 200.0), 0.0, 1.0)
	return lerpf(10.0, 15.0, t_far)

const TURNING_SPREAD_MULT: float = 1.4
const HIGH_SPEED_SPREAD_MULT: float = 1.25
const HIGH_SPEED_THRESHOLD: float = 16.0


## Ship footprint for collision / hits (world units).
const SHIP_LENGTH_UNITS: float = 60.0
const SHIP_WIDTH_UNITS: float = 20.0
## Slightly expanded fallback radius for legacy/catch-all checks.
const SHIP_HIT_RADIUS: float = 22.0

## Ballistics scale vs legacy iso tuning (line speed)
const CANNON_LINE_SPEED_SCALE: float = 2.6

## Camera: zoom baseline so ~20–40 tiles visible (tune with iso TILE_W)
const NAVAL_DEFAULT_ZOOM: float = 0.14
