"""Converts the downloaded Sketchfab models into the game's format.

Run with Blender 4.x:
    blender -b --python tools/models/convert.py -- [ids...]

Reads build/models-src/raw/<source>/scene.gltf, writes assets/models/<id>.glb,
assets/models/models.json and preview renders in build/models-preview/.

Each output is one mesh with one baked colour texture (UV0), a limb tag for
the walk animation in UV1 (people only: x = limb, y = joint height) and the
thermal heat multiplier in the vertex colour alpha (0.5 = 1x), the same
conventions as the procedural meshes in scripts/world/meshes.gd.
Blender axes: +Y is the model's front (-Z in Godot), +Z is up.
"""
import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Vector, Matrix, Quaternion

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "build", "models-src", "raw")
OUT = os.path.join(ROOT, "assets", "models")
PREVIEW = os.path.join(ROOT, "build", "models-preview")

# Heat boxes are in fractions of the finished model's bounds: (x0, y0, z0, x1, y1, z1, alpha).
WHEELS = (0, 0, 0, 1, 1, 0.22, 0.62)
FRONT_ENGINE = (0.15, 0.78, 0.2, 0.85, 1.0, 0.65, 0.92)
HEAD = (0, 0, 0.86, 1, 1, 1, 0.62)

# id -> how to build it. src: folder under RAW; objs: object names to use
# (default all); drop: names to delete; rot: degrees about Z to face +Y;
# length/height: target size in metres (or scale: a fixed factor);
# parts: extra outputs split off by object name, with their spin axis.
MODELS = {
	"heli_uh60": dict(src="heli_uh60", kind="heli", rot=180, scale=1.0, tex=1024, tris=14000,
		parts={"rotor": (["Object_10"], "y"), "tail": (["Object_4"], "x")},
		hot=[(0.3, 0.42, 0.62, 0.7, 0.62, 0.9, 0.97), (0.25, 0.3, 0.0, 0.75, 0.7, 0.62, 0.6)]),
	"heli_ch47": dict(src="heli_ch47", kind="heli", rot=180, scale=0.0738, tex=1024, tris=14000,
		parts={"rotor_f": (["Object_6", "Object_9"], "y"), "rotor_r": (["Object_7", "Object_8"], "y")},
		hot=[(0.25, 0.0, 0.62, 0.75, 0.35, 1.0, 0.97), (0.25, 0.3, 0.0, 0.75, 0.9, 0.6, 0.6)]),
	"a10": dict(src="a10", kind="jet", rot=0, scale=0.98, tex=512, tris=12000, drop_low=0.44,
		hot=[(0.38, 0.12, 0.4, 0.62, 0.42, 1.0, 0.97)]),
	"ac130": dict(src="ac130", kind="jet", rot=0, scale=2.05, tex=1024, drop_low=0.1,
		hot=[(0.08, 0.4, 0.2, 0.92, 0.75, 0.55, 0.92)]),
	"btr": dict(src="btr", kind="veh", rot=-90, length=7.65, tex=1024,
		hot=[WHEELS, (0.1, 0.0, 0.25, 0.9, 0.3, 0.8, 0.92)]),
	"truck": dict(src="truck", kind="veh", rot=180, length=7.37, tex=1024, hot=[WHEELS, FRONT_ENGINE]),
	"tank": dict(src="tank", kind="veh", rot=0, length=9.5, tex=1024, skin="raw",
		hot=[(0, 0, 0, 1, 1, 0.3, 0.65), (0.15, 0.0, 0.25, 0.85, 0.28, 0.75, 0.95)]),
	"humvee": dict(src="humvee", kind="veh", rot=180, length=4.57, tex=512, hot=[WHEELS, FRONT_ENGINE]),
	"pickup": dict(src="pickup", kind="veh", rot=0, length=5.3, tex=1024, hot=[WHEELS, FRONT_ENGINE]),
	"technical": dict(src="technical", kind="veh", rot=180, scale=0.92, tex=1024, tris=9000, drop=["Object_2"],
		hot=[WHEELS, FRONT_ENGINE]),
	"inf_friendly": dict(src="friendly", kind="person", rot=180, height=1.8, tex=512, tris=5000, arms="rifle"),
	"inf_pilot": dict(src="pilot", kind="person", rot=180, height=1.78, tex=512),
	"inf_zombie": dict(src="zombie", kind="person", rot=180, height=1.78, tex=512, tris=5000, arms="forward"),
	"inf_enemy_0": dict(src="enemy", objs=["Cube_Material.001_0"], kind="person", rot=180, height=1.75, tex=512, arms="rifle"),
	"inf_enemy_1": dict(src="enemy", objs=["Cube.001_Material.002_0"], kind="person", rot=180, height=1.76, tex=512, arms="rifle"),
	"inf_civ_0": dict(src="people", objs=["Object_4"], kind="person", rot=180, height=1.74, tex=512),
	"inf_civ_0_armed": dict(src="people", objs=["Object_4"], kind="person", rot=180, height=1.74, tex=512, arms="rifle"),
	"inf_civ_1": dict(src="people", objs=["Object_6"], kind="person", rot=180, height=1.86, tex=512),
	"inf_civ_1_armed": dict(src="people", objs=["Object_6"], kind="person", rot=180, height=1.86, tex=512, arms="rifle"),
	"inf_civ_2": dict(src="people", objs=["Object_8"], kind="person", rot=180, height=1.76, tex=512),
	"inf_civ_2_armed": dict(src="people", objs=["Object_8"], kind="person", rot=180, height=1.76, tex=512, arms="rifle"),
	"inf_civ_3": dict(src="people", objs=["Object_10"], kind="person", rot=180, height=1.72, tex=512),
	"inf_civ_3_armed": dict(src="people", objs=["Object_10"], kind="person", rot=180, height=1.72, tex=512, arms="rifle"),
}


def log(*a):
	print("[convert]", *a, flush=True)


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def import_src(src: str, skin: str) -> list:
	bpy.ops.import_scene.gltf(filepath=os.path.join(RAW, src, "scene.gltf"))
	meshes = []
	for o in list(bpy.data.objects):
		if o.type == "MESH" and not o.name.startswith("Icosphere"):
			meshes.append(o)
	# Freeze every mesh to world space, with its skin applied ("pose") or
	# ignored ("raw": the mesh as stored, for rigs whose bones are posed oddly).
	dg = bpy.context.evaluated_depsgraph_get()
	made = []
	for o in meshes:
		if skin == "raw":
			# The mesh as stored in the file, without the bone transforms.
			for m in list(o.modifiers):
				o.modifiers.remove(m)
			dg = bpy.context.evaluated_depsgraph_get()
			mw = Matrix.Identity(4)
		else:
			mw = o.matrix_world.copy()
		ev = o.evaluated_get(dg)
		me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
		me.transform(mw)
		made.append((o.name, me))
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o)
	out = []
	for name, me in made:
		n = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(n)
		out.append(n)
	return out


def join(objs: list):
	if len(objs) == 1:
		return objs[0]
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	return bpy.context.view_layer.objects.active


def bounds(objs: list):
	mn = Vector((1e9, 1e9, 1e9))
	mx = Vector((-1e9, -1e9, -1e9))
	for o in objs:
		for v in o.data.vertices:
			p = o.matrix_world @ v.co
			mn = Vector(map(min, mn, p))
			mx = Vector(map(max, mx, p))
	return mn, mx


def transform_all(objs: list, m: Matrix):
	for o in objs:
		o.data.transform(m)
		o.data.update()


# --- People --------------------------------------------------------------

def smooth(a, b, x):
	t = min(max((x - a) / (b - a), 0.0), 1.0)
	return t * t * (3.0 - 2.0 * t)


def pose_person(o, h: float, arms: str):
	"""Swings T/A-pose arms down to the sides (or forward for the infected)
	and returns per-vertex limb tags (limb, joint height)."""
	me = o.data
	sz = 0.815 * h
	sx = 0.1 * h
	rad = 0.1 * h
	tags = [(0.0, 0.0)] * len(me.vertices)
	weights = [0.0] * len(me.vertices)
	hands = []
	for side in (-1.0, 1.0):
		pivot = Vector((side * sx, 0.0, sz))
		cand = [v for v in me.vertices if v.co.x * side > sx and v.co.z > 0.3 * h]
		if not cand:
			continue
		# The hand is the outermost point; arms already hanging need no swing.
		hand = max(cand, key=lambda v: v.co.x * side).co.copy()
		d = (hand - pivot)
		ln = d.length
		d.normalize()
		if arms != "forward" and d.angle(Vector((0, 0, -1))) < math.radians(22):
			continue
		if arms == "forward":
			target = Vector((side * 0.12, 1.0, -0.12)).normalized()
		elif arms == "rifle":
			# right hand on the grip by the chest, left hand out on the handguard
			target = Vector((-0.13, 0.43, -0.9) if side > 0 else (0.33, 0.83, -0.45)).normalized()
		else:
			target = Vector((side * 0.16, 0.05, -1.0)).normalized()
		q = d.rotation_difference(target)
		for v in me.vertices:
			rel = v.co - pivot
			t = rel.dot(d) / ln
			if t < -0.05 or t > 1.15:
				continue
			dist = (rel - d * (t * ln)).length
			if dist > rad * (1.0 if t > 0.3 else 1.25):
				continue
			if v.co.x * side < sx * 0.7:
				continue
			w = smooth(0.0, 0.16, t)
			if w <= 0.0:
				continue
			qq = Quaternion().slerp(q, w)
			v.co = pivot + qq @ rel
			weights[v.index] = w
			if w > 0.5 and arms == "down":
				tags[v.index] = (3.0 if side < 0 else 4.0, sz)
		hands.append(pivot + q @ (hand - pivot))
	hip = 0.5 * h
	for v in me.vertices:
		if weights[v.index] > 0.5:
			continue
		if v.co.z < 0.47 * h:
			tags[v.index] = (1.0 if v.co.x < 0 else 2.0, hip)
	me.update()
	return tags, hands


# --- Texture bake --------------------------------------------------------

def emit_colour(nt):
	"""Rewires a material to emit its base colour, so an emission bake
	captures the albedo whatever shader the model used (lit or unlit)."""
	out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
	if out is None:
		out = nt.nodes.new("ShaderNodeOutputMaterial")
	src = None
	value = (0.5, 0.5, 0.5, 1.0)
	for n in nt.nodes:
		key = {"BSDF_PRINCIPLED": "Base Color", "EMISSION": "Color", "BSDF_DIFFUSE": "Color"}.get(n.type)
		if key is None:
			continue
		sock = n.inputs[key]
		if sock.is_linked:
			src = sock.links[0].from_socket
		else:
			value = tuple(sock.default_value)
		break
	em = nt.nodes.new("ShaderNodeEmission")
	if src is not None:
		nt.links.new(src, em.inputs["Color"])
	else:
		em.inputs["Color"].default_value = value
	nt.links.new(em.outputs["Emission"], out.inputs["Surface"])


def bake(o, size: int, name: str) -> str:
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = 1
	me = o.data
	old_uv = [u.name for u in me.uv_layers]
	atlas = me.uv_layers.new(name="atlas")
	me.uv_layers.active = atlas
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0, scale_to_bounds=True)
	bpy.ops.object.mode_set(mode="OBJECT")
	img = bpy.data.images.new(name + "_bake", size, size, alpha=False)
	img.generated_color = (0.3, 0.3, 0.3, 1.0)
	# The bake reads the old UVs through each material's own nodes, so point
	# every image node at the original map explicitly.
	src_uv = old_uv[0] if old_uv else None
	for slot in o.material_slots:
		mat = slot.material
		if mat is None:
			continue
		mat.use_nodes = True
		nt = mat.node_tree
		if src_uv:
			for n in list(nt.nodes):
				if n.type == "TEX_IMAGE" and not n.inputs["Vector"].is_linked:
					uvn = nt.nodes.new("ShaderNodeUVMap")
					uvn.uv_map = src_uv
					nt.links.new(uvn.outputs["UV"], n.inputs["Vector"])
				elif n.type == "UVMAP" and n.uv_map == "":
					n.uv_map = src_uv
		emit_colour(nt)
		tn = nt.nodes.new("ShaderNodeTexImage")
		tn.image = img
		uvt = nt.nodes.new("ShaderNodeUVMap")
		uvt.uv_map = "atlas"
		nt.links.new(uvt.outputs["UV"], tn.inputs["Vector"])
		for n in nt.nodes:
			n.select = False
		tn.select = True
		nt.nodes.active = tn
	if not o.material_slots:
		mat = bpy.data.materials.new("plain")
		mat.use_nodes = True
		o.data.materials.append(mat)
		tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
		tn.image = img
		mat.node_tree.nodes.active = tn
	bpy.ops.object.bake(type="EMIT", margin=4, use_clear=True)
	path = os.path.join(PREVIEW, "tex", name + ".png")
	os.makedirs(os.path.dirname(path), exist_ok=True)
	img.filepath_raw = path
	img.file_format = "PNG"
	img.save()
	for n in old_uv:
		me.uv_layers.remove(me.uv_layers[n])
	return path


def finish_material(o, tex_path: str, name: str):
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	bsdf = nt.nodes.get("Principled BSDF")
	bsdf.inputs["Roughness"].default_value = 0.85
	tn = nt.nodes.new("ShaderNodeTexImage")
	tn.image = bpy.data.images.load(tex_path)
	nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
	o.data.materials.clear()
	o.data.materials.append(mat)
	for p in o.data.polygons:
		p.material_index = 0


def set_tags_and_heat(o, tags, hot, mn: Vector, mx: Vector):
	me = o.data
	if tags is not None:
		uv2 = me.uv_layers.new(name="tags")
		for loop in me.loops:
			t = tags[loop.vertex_index]
			uv2.data[loop.index].uv = (t[0], t[1])
	col = me.color_attributes.new(name="heat", type="BYTE_COLOR", domain="POINT")
	size = mx - mn
	for v in me.vertices:
		p = v.co
		a = 0.5
		f = [(p[i] - mn[i]) / max(size[i], 1e-6) for i in range(3)]
		for b in hot:
			if b[0] <= f[0] <= b[3] and b[1] <= f[1] <= b[4] and b[2] <= f[2] <= b[5]:
				a = max(a, b[6]) if b[6] >= 0.5 else min(a, b[6])
		col.data[v.index].color = (1.0, 1.0, 1.0, a)
	me.color_attributes.active_color = col
	me.color_attributes.render_color_index = me.color_attributes.find("heat")


def decimate(o, tris: int):
	n = sum(len(p.vertices) - 2 for p in o.data.polygons)
	if n <= tris:
		return n
	m = o.modifiers.new("dec", "DECIMATE")
	m.ratio = tris / n
	m.use_collapse_triangulate = True
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.modifier_apply(modifier="dec")
	return sum(len(p.vertices) - 2 for p in o.data.polygons)


def export(o, path: str):
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
		export_texcoords=True, export_normals=True, export_vertex_color="ACTIVE", export_all_vertex_colors=False,
		export_image_format="JPEG", export_jpeg_quality=88, export_materials="EXPORT", export_animations=False,
		export_skins=False, export_morph=False, export_yup=True)


def render_preview(objs: list, name: str):
	sc = bpy.context.scene
	mn, mx = bounds(objs)
	c = (mn + mx) / 2
	r = max((mx - mn).length / 2, 0.5)
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
	sc.collection.objects.link(cam)
	sc.camera = cam
	cam.data.type = "ORTHO"
	cam.data.ortho_scale = r * 2.1
	cam.data.clip_end = r * 20
	sc.render.engine = "BLENDER_WORKBENCH"
	sc.display.shading.color_type = "TEXTURE"
	sc.display.shading.light = "STUDIO"
	sc.render.resolution_x = 400
	sc.render.resolution_y = 300
	for tag, dv in (("a", Vector((0.7, 1.0, 0.5))), ("b", Vector((-0.8, -0.5, 0.35)))):
		dv.normalize()
		cam.location = c + dv * r * 4
		cam.rotation_euler = (-dv).to_track_quat("-Z", "Y").to_euler()
		sc.render.filepath = os.path.join(PREVIEW, f"{name}_{tag}.png")
		bpy.ops.render.render(write_still=True)
	bpy.data.objects.remove(cam)


def g(v: Vector) -> list:
	"""Blender coordinates to Godot (x, z, -y)."""
	return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]


def convert(mid: str, cfg: dict, manifest: dict):
	reset()
	objs = import_src(cfg["src"], cfg.get("skin", "pose"))
	if "objs" in cfg:
		for o in list(objs):
			if o.name not in cfg["objs"]:
				bpy.data.objects.remove(o)
		objs = [o for o in bpy.data.objects if o.type == "MESH"]
	for name in cfg.get("drop", []):
		for o in list(objs):
			if o.name == name:
				objs.remove(o)
				bpy.data.objects.remove(o)
	if "drop_low" in cfg:
		for o in list(objs):
			if min((o.matrix_world @ v.co).z for v in o.data.vertices) < cfg["drop_low"]:
				objs.remove(o)
				bpy.data.objects.remove(o)
	transform_all(objs, Matrix.Rotation(math.radians(cfg.get("rot", 0)), 4, "Z"))
	mn, mx = bounds(objs)
	if "scale" in cfg:
		s = cfg["scale"]
	elif "length" in cfg:
		s = cfg["length"] / (mx.y - mn.y)
	else:
		s = cfg["height"] / (mx.z - mn.z)
	transform_all(objs, Matrix.Scale(s, 4))
	# Split off the spinning parts before centring on the body.
	part_objs = {}
	for pname, (names, axis) in cfg.get("parts", {}).items():
		part_objs[pname] = [o for o in objs if o.name in names]
		objs = [o for o in objs if o.name not in names]
	mn, mx = bounds(objs)
	if cfg["kind"] == "jet":
		off = -(mn + mx) / 2
	else:
		off = Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
	transform_all(objs, Matrix.Translation(off))
	for po in part_objs.values():
		transform_all(po, Matrix.Translation(off))
	body = join(objs)
	body.name = mid
	decimate(body, cfg.get("tris", 10000))
	tags = None
	hands = []
	if cfg["kind"] == "person":
		h = bounds([body])[1].z
		tags, hands = pose_person(body, h, cfg.get("arms", "down"))
		mn, mx = bounds([body])
		shift = Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, 0.0))
		body.data.transform(Matrix.Translation(shift))
		hands = [hp + shift for hp in hands]
	mn, mx = bounds([body])
	tex = bake(body, cfg.get("tex", 512), mid)
	finish_material(body, tex, mid)
	hot = cfg.get("hot", [])
	if cfg["kind"] == "person":
		hot = hot + [HEAD]
	set_tags_and_heat(body, tags, hot, mn, mx)
	os.makedirs(OUT, exist_ok=True)
	export(body, os.path.join(OUT, mid + ".glb"))
	entry = {"src": cfg["src"], "size": [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)],
		"tris": sum(len(p.vertices) - 2 for p in body.data.polygons), "parts": {}}
	if hands:
		entry["hands"] = [g(hp) for hp in hands]
	for pname, po in part_objs.items():
		(names, axis) = cfg["parts"][pname]
		part = join(po)
		pmn, pmx = bounds([part])
		hub = (pmn + pmx) / 2
		if axis == "x":
			hub = Vector((hub.x, hub.y, hub.z))
		part.data.transform(Matrix.Translation(-hub))
		ptex = bake(part, 256, mid + "_" + pname)
		finish_material(part, ptex, mid + "_" + pname)
		set_tags_and_heat(part, None, [(0, 0, 0, 1, 1, 1, 0.35)], *bounds([part]))
		part.name = mid + "_" + pname
		export(part, os.path.join(OUT, f"{mid}_{pname}.glb"))
		entry["parts"][pname] = {"file": f"{mid}_{pname}.glb", "pos": g(hub), "axis": axis}
		part.data.transform(Matrix.Translation(hub))
	render_preview([o for o in bpy.data.objects if o.type == "MESH"], mid)
	manifest[mid] = entry
	log(mid, "tris", entry["tris"], "size", entry["size"])


def main():
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	ids = args or list(MODELS.keys())
	mpath = os.path.join(OUT, "models.json")
	manifest = {}
	if os.path.exists(mpath):
		manifest = json.load(open(mpath)).get("models", {})
	os.makedirs(PREVIEW, exist_ok=True)
	for mid in ids:
		convert(mid, MODELS[mid], manifest)
	json.dump({"models": manifest}, open(mpath, "w"), indent=1, sort_keys=True)


main()
