extends Node3D

@onready var _camera:     Camera3D       = $Camera3D
@onready var _globe_root: Node3D         = $GlobeRoot
@onready var _globe_mesh: MeshInstance3D = $GlobeRoot/Globe
@onready var _atmo_mesh:  MeshInstance3D = $GlobeRoot/Atmosphere

# ── Camera zoom ─────────────────────────────────────────────────────────────
const CAM_DIST_MIN:     float = 1.2
const CAM_DIST_MAX:     float = 6.0
const ZOOM_STEP:        float = 0.25
const ZOOM_SMOOTH:      float = 8.0
const DEFAULT_CAM_DIST: float = 3.0
var _cam_dist:          float = DEFAULT_CAM_DIST
var _cam_dist_target:   float = DEFAULT_CAM_DIST

# ── Camera pan ───────────────────────────────────────────────────────────────
const PAN_LIMIT:        float = 2.0
const PAN_SMOOTH:       float = 8.0
var _cam_offset:        Vector2 = Vector2.ZERO
var _cam_offset_target: Vector2 = Vector2.ZERO

# ── Axial tilt ───────────────────────────────────────────────────────────────
const AXIAL_TILT_DEG: float = 23.5
var   _default_quat:  Quaternion   # tilt-only orientation, set in _ready

# ── Time-driven rotation ──────────────────────────────────────────────────────
# 1 real minute = 1 full rotation  →  6 °/s at time_scale 1.0
const BASE_DEG_PER_SEC:  float = 6.0    # 360 / 60
const TIME_SCALE_MIN:    float = 0.0
const TIME_SCALE_MAX:    float = 120.0  # up to 2 days/sec for fast-forward
const SPEED_DRAG_SENS:   float = 0.05   # time_scale change per pixel of drag
var   _sim_angle:        float = 0.0    # cumulative rotation in degrees
var   _time_scale:       float = 1.0    # 1.0 = real-time (1 day/min)

# ── Drag state ───────────────────────────────────────────────────────────────
var _left_dragging: bool = false
var _pan_dragging:  bool = false   # middle OR right button

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Quaternion(Vector3.RIGHT, 23.5°) tilts the north pole toward +Z.
	# All rotation is post-multiplied in local space so the axis never drifts.
	_default_quat = Quaternion(Vector3.RIGHT, deg_to_rad(AXIAL_TILT_DEG))

	_apply_globe_texture()
	_apply_atmosphere_material()
	_add_reset_button()
	_update_globe()
	_update_camera()

func _process(delta: float) -> void:
	# Advance simulation time — always running (drag only changes the rate)
	_sim_angle += BASE_DEG_PER_SEC * _time_scale * delta

	# Smooth zoom & pan
	_cam_dist   = lerpf(_cam_dist, _cam_dist_target, ZOOM_SMOOTH * delta)
	_cam_offset = _cam_offset.lerp(_cam_offset_target, PAN_SMOOTH * delta)

	_update_globe()
	_update_camera()

# ── Reset view ────────────────────────────────────────────────────────────────
func _reset_view() -> void:
	_cam_dist_target   = DEFAULT_CAM_DIST
	_cam_offset_target = Vector2.ZERO
	_sim_angle         = 0.0
	_time_scale        = 1.0

# ── Input ─────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mbe := event as InputEventMouseButton
		match mbe.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_cam_dist_target = clampf(_cam_dist_target - ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cam_dist_target = clampf(_cam_dist_target + ZOOM_STEP, CAM_DIST_MIN, CAM_DIST_MAX)
			MOUSE_BUTTON_LEFT:
				_left_dragging = mbe.pressed
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_pan_dragging = mbe.pressed

	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _left_dragging:
			# Drag right = faster day, drag left = slower/pause
			_time_scale = clampf(
				_time_scale + motion.relative.x * SPEED_DRAG_SENS,
				TIME_SCALE_MIN, TIME_SCALE_MAX
			)
		elif _pan_dragging:
			var pan_scale := 0.0015 * _cam_dist
			_cam_offset_target.y += motion.relative.y * pan_scale
			_cam_offset_target.y  = clampf(_cam_offset_target.y, -PAN_LIMIT, PAN_LIMIT)

	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_R:
			_reset_view()

# ── Globe orientation ─────────────────────────────────────────────────────────
func _update_globe() -> void:
	# Deterministic: tilt first, then spin around the globe's own (local) Y axis.
	var spin_q := Quaternion(Vector3.UP, deg_to_rad(_sim_angle))
	_globe_root.quaternion = (_default_quat * spin_q).normalized()

# ── Camera ─────────────────────────────────────────────────────────────────────
func _update_camera() -> void:
	_camera.position = Vector3(_cam_offset.x, _cam_offset.y, _cam_dist)
	_camera.look_at(Vector3.ZERO, Vector3.UP)

# ── Texture loading ────────────────────────────────────────────────────────────
func _apply_globe_texture() -> void:
	var img := Image.load_from_file("res://assets/maps/globe.png")
	if img == null:
		push_error("globe_arena: cannot load res://assets/maps/globe.png")
		return
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.roughness      = 0.85
	mat.metallic       = 0.0
	mat.specular_mode  = BaseMaterial3D.SPECULAR_DISABLED
	_globe_mesh.material_override = mat

# ── Atmosphere halo ────────────────────────────────────────────────────────────
func _apply_atmosphere_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode      = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode       = BaseMaterial3D.CULL_FRONT
	mat.albedo_color    = Color(0.35, 0.65, 1.0, 0.10)
	mat.emission_enabled = true
	mat.emission        = Color(0.20, 0.50, 0.95)
	mat.emission_energy_multiplier = 0.15
	_atmo_mesh.material_override = mat

# ── Reset button (bottom-right HUD overlay) ───────────────────────────────────
func _add_reset_button() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var btn := Button.new()
	btn.text          = "Reset View  [R]"
	btn.anchor_left   = 1.0
	btn.anchor_right  = 1.0
	btn.anchor_top    = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left   = -160.0
	btn.offset_top    = -52.0
	btn.offset_right  = -12.0
	btn.offset_bottom = -12.0
	canvas.add_child(btn)
	btn.pressed.connect(_reset_view)
