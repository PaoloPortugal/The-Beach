class_name Clouds
extends Node3D
## Clouds (W09): low-poly clumps drifting with the wind, high over the
## sea around the camera. The weather's cover says how many there are
## (each grows in or shrinks away rather than popping) and a storm darkens
## them. They wrap around the camera, so there are always clouds about.

const COUNT := 30
## The square around the camera they drift in, metres, and their height.
const AREA := 800.0
const MIN_Y := 90.0
const MAX_Y := 130.0
## Drift speed, m/s: calm and at full wind.
const CALM_DRIFT := 2.0
const WINDY_DRIFT := 12.0

const WHITE := Color(0.96, 0.97, 0.98)
const STORMY := Color(0.42, 0.44, 0.48)

var weather: Weather
## The wind's direction, the same for the whole run.
var wind_direction := Vector2.RIGHT

var _clouds: Array[MeshInstance3D] = []
var _homes := PackedVector2Array()
var _drift := Vector2.ZERO
var _material := StandardMaterial3D.new()


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	wind_direction = Vector2.from_angle(rng.randf() * TAU)
	_material.albedo_color = WHITE
	_material.roughness = 1.0
	for i in COUNT:
		var cloud := MeshInstance3D.new()
		cloud.name = "Cloud%d" % i
		cloud.mesh = make_cloud(rng)
		cloud.material_override = _material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.position.y = rng.randf_range(MIN_Y, MAX_Y)
		cloud.rotation.y = rng.randf() * TAU
		cloud.scale = Vector3.ZERO
		add_child(cloud)
		_clouds.append(cloud)
		_homes.append(Vector2(rng.randf() * AREA, rng.randf() * AREA))


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or weather == null:
		return
	_drift += wind_direction * lerpf(CALM_DRIFT, WINDY_DRIFT, weather.wind) * delta
	var at := Vector2(camera.global_position.x, camera.global_position.z)
	# Cloud i shows once the cover reaches i / COUNT, growing in over it.
	var shown := weather.cover * COUNT
	for i in COUNT:
		var cloud := _clouds[i]
		var size := clampf(shown - i, 0.0, 1.0)
		cloud.visible = size > 0.0
		if not cloud.visible:
			continue
		cloud.scale = Vector3.ONE * size
		var p := _homes[i] + _drift - at
		p = Vector2(fposmod(p.x, AREA) - AREA / 2.0, fposmod(p.y, AREA) - AREA / 2.0) + at
		cloud.position.x = p.x
		cloud.position.z = p.y
	_material.albedo_color = WHITE.lerp(STORMY, clampf(weather.storm * 0.9 + maxf(weather.cover - 0.6, 0.0), 0.0, 1.0))


## How many clouds show now.
func shown_count() -> int:
	return _clouds.filter(func(c: MeshInstance3D) -> bool: return c.visible).size()


## A cloud: a few flattened low-poly blobs side by side, flat shaded.
static func make_cloud(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blobs := rng.randi_range(3, 6)
	var length := rng.randf_range(30.0, 60.0)
	for b in blobs:
		var along := (b / float(blobs - 1) - 0.5) * length
		var r := rng.randf_range(8.0, 15.0) * (1.0 - absf(along) / length)
		var centre := Vector3(along, rng.randf_range(-1.0, 3.0), rng.randf_range(-5.0, 5.0))
		_blob(st, centre, Vector3(r * 1.3, r * 0.45, r))
	st.generate_normals() # per face: the vertices aren't shared
	return st.commit()


# A squashed low-poly ball: 6 sides, 3 bands, flat faces.
static func _blob(st: SurfaceTool, centre: Vector3, radii: Vector3) -> void:
	var sides := 6
	var bands := 3
	var rings: Array[PackedVector3Array] = []
	for j in bands + 1:
		var phi := PI * j / bands
		var ring := PackedVector3Array()
		for i in sides:
			var theta := TAU * i / sides + j * 0.5
			ring.append(centre + Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * radii)
		rings.append(ring)
	for j in bands:
		for i in sides:
			var a := rings[j][i]
			var b := rings[j][(i + 1) % sides]
			var c := rings[j + 1][(i + 1) % sides]
			var d := rings[j + 1][i]
			if j > 0:
				st.add_vertex(a)
				st.add_vertex(b)
				st.add_vertex(d)
			if j < bands - 1:
				st.add_vertex(b)
				st.add_vertex(c)
				st.add_vertex(d)
