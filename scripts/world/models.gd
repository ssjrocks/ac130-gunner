extends RefCounted
## Imported models in assets/models, built by tools/models/convert.py from
## CC-BY downloads (authors in CREDITS.md). Each is one mesh with a baked
## colour texture, the heat multiplier in vertex alpha and limb tags in UV2,
## so the game's own shaders draw them like the procedural meshes.

const Mats := preload("res://scripts/world/mats.gd")
const DIR := "res://assets/models/"

static var _info := {}
static var _meshes := {}
static var _textures := {}
static var _mats := {}

const SURVIVORS := ["inf_enemy_1", "inf_civ_0_armed", "inf_civ_2_armed", "inf_civ_3_armed"]
const ENEMY_TINTS := [Color(1, 1, 1), Color(0.85, 0.8, 0.7), Color(0.72, 0.74, 0.76)]
const CIV_TINTS := [Color(1, 1, 1), Color(0.86, 0.9, 1.0)]
const ZOMBIE_TINTS := [Color(1, 1, 1), Color(0.85, 0.92, 0.8), Color(0.8, 0.74, 0.7), Color(0.95, 0.95, 0.9)]


static func info() -> Dictionary:
	if _info.is_empty():
		var f := FileAccess.open(DIR + "models.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_info = d.get("models", {})
	return _info


## [model, texture tint] for a procedural mesh id, or ["", ...] to build it in code.
static func lookup(id: String) -> Array:
	var p := id.split("_")
	var n := int(p[2]) if p.size() > 2 and p[2].is_valid_int() else 0
	var model := ""
	var tint := Color.WHITE
	match p[0]:
		"inf":
			match p[1]:
				"friendly":
					model = "inf_friendly"
				"sf":
					model = "inf_friendly"
					tint = Color(0.6, 0.6, 0.56)
				"enemy":
					model = "inf_enemy_%d" % (n % 2)
					tint = ENEMY_TINTS[(n / 2) % ENEMY_TINTS.size()]
				"civ":
					model = "inf_civ_%d" % (n % 4)
					tint = CIV_TINTS[(n / 4) % CIV_TINTS.size()]
				"surv":
					model = SURVIVORS[n % SURVIVORS.size()]
				"zombie":
					model = "inf_zombie"
					tint = ZOMBIE_TINTS[n % ZOMBIE_TINTS.size()]
				"pilot":
					model = "inf_pilot"
				"vip":
					model = "inf_civ_1"
					tint = Color(0.45, 0.45, 0.5)
		"technical", "pickup", "truck", "humvee", "btr", "tank":
			model = p[0]
			if p.size() > 1 and p[1] == "dark":
				tint = Color(0.6, 0.6, 0.6)
		"heli":
			model = "heli_" + (p[1] if p.size() > 1 else "uh60")
		"jet":
			if p[1] == "a10":
				model = "a10"
		"gunship":
			model = "ac130"
	if model != "" and not info().has(model):
		model = ""
	return [model, tint]


static func mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var ps: PackedScene = load(DIR + model + ".glb")
	var root := ps.instantiate()
	var mi := _find_mesh(root)
	var m: Mesh = mi.mesh
	var sm := m.surface_get_material(0)
	if sm is BaseMaterial3D:
		_textures[model] = (sm as BaseMaterial3D).albedo_texture
	root.free()
	_meshes[model] = m
	return m


## The game's solid or unit shader with this model's texture and a tint.
static func material(model: String, person: bool, tint: Color) -> Material:
	var key := "%s|%s" % [model, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	mesh(model)
	var m := Mats.textured("unit" if person else "solid", _textures.get(model), tint)
	_mats[key] = m
	return m


static func parts(model: String) -> Dictionary:
	return info().get(model, {}).get("parts", {})


static func hands(model: String) -> Array:
	return info().get(model, {}).get("hands", [])


static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null
