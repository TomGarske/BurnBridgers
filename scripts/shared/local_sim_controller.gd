## Local simulation controller: spawns bot enemies for local testing.
## Isolated from multiplayer logic.  (req-local-sim-v1)
class_name LocalSimController
extends RefCounted

const NC := preload("res://scripts/shared/naval_combat_constants.gd")

## Master toggle — when false, arena skips bot spawning entirely.
var local_sim_enabled: bool = true
## Spawn distance range — outside preferred engagement, inside max cannon range (req-local-sim §2.2).
var spawn_distance_min: float = 220.0
var spawn_distance_max: float = 320.0
## Base bearing offset so the opening isn't a pure head-on line (req-local-sim §2.2: 15–45°).
var spawn_bearing_offset_deg: float = 30.0

## Distinct bot palettes — visually different from player blue.
const BOT_PALETTES: Array = [
	[Color(0.85, 0.20, 0.15), Color(1.00, 0.50, 0.35)],   # red
	[Color(0.80, 0.55, 0.10), Color(1.00, 0.80, 0.30)],   # gold
	[Color(0.60, 0.15, 0.70), Color(0.85, 0.45, 0.95)],   # purple
]

const BOT_LABELS: Array = ["Red", "Gold", "Prpl"]


## Build a bot ship dictionary entry matching the arena's player format.
## player_dict: the existing player's ship dictionary for position reference.
## bot_index: 0-based index used for unique peer_id, palette, and label.
## Each bot gets a unique negative peer_id: -10, -11, -12, etc.
func create_bot_entry(player_dict: Dictionary, bot_index: int = 0) -> Dictionary:
	var px: float = float(player_dict.get("wx", 400.0))
	var py: float = float(player_dict.get("wy", 400.0))
	var p_dir: Vector2 = Vector2(float(player_dict.dir.x), float(player_dict.dir.y))
	if p_dir.length_squared() < 0.0001:
		p_dir = Vector2.RIGHT
	p_dir = p_dir.normalized()

	# Random spawn distance within range.
	var dist: float = randf_range(spawn_distance_min, spawn_distance_max)

	# Spread multiple bots around the player; single-bot duels use random jitter within 15–45°.
	var sector_offset: float = float(bot_index) * 55.0
	var jitter_deg: float = randf_range(-12.0, 12.0)
	var offset_rad: float = deg_to_rad(spawn_bearing_offset_deg + sector_offset + jitter_deg)
	var spawn_dir: Vector2 = p_dir.rotated(offset_rad)

	var bot_x: float = px + spawn_dir.x * dist
	var bot_y: float = py + spawn_dir.y * dist

	# Clamp to map bounds.
	var map_max: float = float(NC.MAP_TILES_WIDE) * NC.UNITS_PER_LOGIC_TILE - 50.0
	bot_x = clampf(bot_x, 50.0, map_max)
	bot_y = clampf(bot_y, 50.0, map_max)

	# Bot faces back toward the player with a slight offset.
	var to_player: Vector2 = (Vector2(px, py) - Vector2(bot_x, bot_y))
	if to_player.length_squared() < 0.01:
		to_player = -spawn_dir
	var bot_heading: Vector2 = to_player.normalized().rotated(randf_range(-0.2, 0.2))

	# Unique negative peer_id so projectile ownership works correctly.
	var bot_peer_id: int = -(10 + bot_index)
	var palette: Array = BOT_PALETTES[bot_index % BOT_PALETTES.size()]
	var label: String = BOT_LABELS[bot_index % BOT_LABELS.size()]

	return {
		"peer_id": bot_peer_id,
		"wx": bot_x,
		"wy": bot_y,
		"dir": bot_heading,
		"health": 10.0,       # matches HULL_HITS_MAX in arena
		"alive": true,
		"atk_time": 0.0,
		"hit_landed": false,
		"palette": palette,
		"label": label,
		"walk_time": 0.0,
		"moving": false,
		"is_bot": true,
	}
