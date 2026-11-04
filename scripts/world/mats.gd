extends RefCounted
## Shaders shared by everything visible. Each reads the global view_mode
## (0 TV, 1 NV, 2 white-hot, 3 black-hot) so thermal imaging works on every
## surface: in thermal modes a surface shows its heat instead of its colour.
## Heat for meshes comes from the instance "heat" times vertex alpha * 2.

static var _cache := {}

const HASH := """
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int k = 0; k < 4; k++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return s;
}
"""

const SOLID := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
global uniform int view_mode;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float heat = 0.3;
instance uniform vec4 glow = vec4(0.0);
uniform float roughness_v = 0.85;

void fragment() {
	if (view_mode >= 2) {
		float h = clamp(heat * COLOR.a * 2.0, 0.0, 1.0);
		if (view_mode == 3) { h = 1.0 - h; }
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(h);
	} else {
		ALBEDO = tint.rgb * COLOR.rgb;
		ROUGHNESS = roughness_v;
		SPECULAR = 0.25;
		EMISSION = glow.rgb * glow.a;
	}
}
"""

# Buildings are one unit cube (y 0..1) per instance in a MultiMesh.
# INSTANCE_CUSTOM: rgb = colour, a = windows*1000 + seed + heat (fraction).
const BUILDING := """
shader_type spatial;
render_mode cull_back, diffuse_burley;
global uniform int view_mode;
global uniform float night;
varying vec3 lpos;
varying vec3 lnorm;
varying vec3 scl;
varying vec4 custom;
%HASH%
void vertex() {
	scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = (VERTEX + vec3(0.5, 0.0, 0.5)) * scl;
	lnorm = NORMAL;
	custom = INSTANCE_CUSTOM;
}
void fragment() {
	float packed = custom.a;
	float heat = fract(packed);
	float s = floor(packed);
	float windows = step(999.5, s);
	float seed = mod(s, 1000.0);
	vec3 c = custom.rgb;
	float wmask = 0.0;
	float lit = 0.0;
	if (abs(lnorm.y) < 0.5) {
		float u = abs(lnorm.x) > 0.5 ? lpos.z : lpos.x;
		float fl = floor(lpos.y / 3.2);
		float col = floor(u / 3.0);
		vec2 f = vec2(fract(u / 3.0), fract(lpos.y / 3.2));
		float inwin = step(0.28, f.x) * step(f.x, 0.72) * step(0.32, f.y) * step(f.y, 0.78);
		wmask = inwin * step(1.0, lpos.y) * step(lpos.y, scl.y - 1.0) * windows;
		wmask *= step(1.5, u) * step(u, (abs(lnorm.x) > 0.5 ? scl.z : scl.x) - 1.5);
		float hs = hash12(vec2(col + seed * 13.0 + lnorm.x * 5.0, fl + seed * 7.0 + lnorm.z * 3.0));
		lit = step(0.72, hs) * night * wmask;
		c = mix(c, vec3(0.07, 0.08, 0.09), wmask * 0.85);
		c *= mix(0.72, 1.0, clamp(lpos.y / 2.5, 0.0, 1.0));
		float streak = vnoise(vec2(u * 0.7, lpos.y * 0.15) + seed);
		c *= 0.9 + 0.12 * streak;
	} else if (lnorm.y > 0.5) {
		c *= 0.82 + 0.1 * vnoise(lpos.xz * 0.4 + seed);
	}
	if (view_mode >= 2) {
		float h = heat + lit * 0.3 + wmask * 0.04;
		if (lnorm.y > 0.5) { h += 0.05 * (1.0 - night); }
		h = clamp(h, 0.0, 1.0);
		if (view_mode == 3) { h = 1.0 - h; }
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(h);
	} else {
		ALBEDO = c;
		ROUGHNESS = 0.92;
		SPECULAR = 0.15;
		EMISSION = vec3(1.0, 0.78, 0.45) * lit * 1.6;
	}
}
"""

# Trees: MultiMesh, INSTANCE_CUSTOM rgb = tint, a = heat.
const TREE := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
global uniform int view_mode;
varying vec4 custom;
void vertex() {
	custom = INSTANCE_CUSTOM;
}
void fragment() {
	if (view_mode >= 2) {
		float h = clamp(custom.a * COLOR.a * 2.0, 0.0, 1.0);
		if (view_mode == 3) { h = 1.0 - h; }
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(h);
	} else {
		ALBEDO = COLOR.rgb * custom.rgb;
		ROUGHNESS = 0.95;
		SPECULAR = 0.1;
	}
}
"""

const TERRAIN := """
shader_type spatial;
render_mode cull_back, diffuse_burley;
global uniform int view_mode;
global uniform float night;
uniform sampler2D road_tex : filter_linear, repeat_disable;
uniform float core_size = 8000.0;
uniform int biome = 0;
uniform vec3 c_ground : source_color = vec3(0.6, 0.52, 0.4);
uniform vec3 c_ground2 : source_color = vec3(0.55, 0.47, 0.36);
uniform vec3 c_rock : source_color = vec3(0.45, 0.4, 0.35);
uniform vec3 c_road : source_color = vec3(0.4, 0.37, 0.33);
uniform vec3 c_town : source_color = vec3(0.6, 0.53, 0.42);
uniform vec3 c_veg : source_color = vec3(0.3, 0.38, 0.2);
uniform vec3 c_snow : source_color = vec3(0.9, 0.92, 0.95);
uniform float snow_line = 100000.0;
uniform float water_level = -10000.0;
uniform float base_heat = 0.22;
uniform vec4 towns[8];
uniform int town_count = 0;
varying vec3 wpos;
varying vec3 wnrm;
%HASH%
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
}
void fragment() {
	vec2 xz = wpos.xz;
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float n1 = fbm(xz * 0.0012);
	float n2 = fbm(xz * 0.025);
	float n3 = vnoise(xz * 0.8);
	float n4 = vnoise(xz * 3.7);
	float n5 = vnoise(xz * 0.45 + 31.0) * 0.7 + vnoise(xz * 1.3 + 3.0) * 0.3;
	float n6 = vnoise(xz * 1.9 + 7.0);
	vec3 c = mix(c_ground, c_ground2, smoothstep(0.3, 0.7, n1));
	c *= 0.74 + 0.5 * n2;
	c *= 0.86 + 0.18 * n3 + 0.08 * n4 + 0.1 * (n6 - 0.5);
	// dry stream beds
	float wadi = 1.0 - abs(fbm(xz * 0.0035 + 5.0) * 2.0 - 1.0);
	wadi = smoothstep(0.9, 0.985, wadi);
	c = mix(c, c_ground2 * 0.62, wadi * 0.6);
	// scrub, bushes and rocks
	float scrub = smoothstep(0.7, 0.82, n5 + (n2 - 0.5) * 0.3) * (1.0 - smoothstep(0.85, 1.0, n1));
	c = mix(c, c_veg * 0.7, scrub * 0.45);
	c *= 1.0 - smoothstep(0.86, 0.95, n6) * 0.25;
	float veg = 0.0;
	float town = 0.0;
	for (int i = 0; i < town_count; i++) {
		vec4 t = towns[i];
		float d = distance(xz, t.xy);
		town = max(town, 1.0 - smoothstep(t.z * 0.7, t.z * 1.1, d + (n2 - 0.5) * 80.0));
	}
	if (biome == 2 || biome == 3) {
		// Patchwork of fields with hedge lines between them.
		vec2 q = mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * xz;
		vec2 fsz = vec2(110.0, 160.0);
		vec2 cell = floor(q / fsz);
		vec2 fq = fract(q / fsz);
		float h = hash12(cell + 3.0);
		vec3 fc = h < 0.35 ? c_veg * (0.8 + 0.4 * h) : (h < 0.7 ? c_ground2 * 1.05 : mix(c_veg, c_ground, 0.5));
		float rows = 0.92 + 0.08 * sin(q.x * (h < 0.7 ? 2.2 : 0.0));
		fc *= rows;
		float edge = 1.0 - smoothstep(0.0, 0.035, min(min(fq.x, 1.0 - fq.x), min(fq.y, 1.0 - fq.y)));
		fc = mix(fc, c_veg * 0.6, edge * 0.7);
		veg = (1.0 - town) * smoothstep(0.25, 0.4, n1 + 0.2) * (biome == 3 ? 0.6 : 1.0);
		c = mix(c, fc * (0.9 + 0.2 * n3), veg * 0.9);
	} else if (biome == 4) {
		c = mix(c, c_veg * (0.8 + 0.4 * n2), (1.0 - town) * 0.6);
	} else if (biome == 1) {
		c = mix(c, c_veg * (0.7 + 0.5 * n2), smoothstep(0.55, 0.75, n2) * (1.0 - slope) * 0.6);
	}
	c = mix(c, c_rock * (0.8 + 0.35 * n3), smoothstep(0.22, 0.45, slope + (n2 - 0.5) * 0.2));
	float sn = smoothstep(snow_line - 80.0, snow_line + 80.0, wpos.y + (n1 - 0.5) * 400.0) * (1.0 - smoothstep(0.5, 0.75, slope));
	c = mix(c, c_snow, sn);
	c = mix(c, c_town * (0.85 + 0.25 * n3) * (0.9 + 0.1 * n4), town * 0.85);
	if (wpos.y < water_level + 3.0) {
		c = mix(c, c_ground2 * 0.72, 1.0 - smoothstep(water_level, water_level + 3.0, wpos.y));
	}
	vec2 ruv = xz / core_size + 0.5;
	float road = texture(road_tex, ruv).r;
	if (ruv.x < 0.0 || ruv.x > 1.0 || ruv.y < 0.0 || ruv.y > 1.0) { road = 0.0; }
	road = smoothstep(0.15, 0.6, road);
	c = mix(c, c_road * (0.88 + 0.16 * n4), road);
	if (view_mode >= 2) {
		float h = base_heat + (n2 - 0.5) * 0.09 + (n4 - 0.5) * 0.03 + slope * 0.06;
		h += road * mix(0.1, 0.05, night) + town * 0.05 - sn * 0.15 - veg * 0.05;
		h += (1.0 - night) * 0.05;
		if (wpos.y < water_level + 0.2) { h = 0.07; }
		h = clamp(h, 0.0, 1.0);
		if (view_mode == 3) { h = 1.0 - h; }
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(h);
	} else {
		ALBEDO = c;
		ROUGHNESS = 0.96;
		SPECULAR = 0.08;
	}
}
"""

const WATER := """
shader_type spatial;
render_mode cull_back, diffuse_burley;
global uniform int view_mode;
uniform vec3 c_water : source_color = vec3(0.04, 0.1, 0.12);
%HASH%
void fragment() {
	vec3 w = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (view_mode >= 2) {
		float h = 0.08;
		if (view_mode == 3) { h = 0.92; }
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = vec3(h);
	} else {
		float n = vnoise(w.xz * 0.08 + TIME * 0.05) * 0.6 + vnoise(w.xz * 0.5 - TIME * 0.1) * 0.4;
		ALBEDO = c_water * (0.85 + 0.3 * n);
		ROUGHNESS = 0.12 + 0.1 * n;
		SPECULAR = 0.6;
	}
}
"""

# Particles and lines. Billboard quads or camera-facing beams; unshaded.
const FX := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
global uniform int view_mode;
global uniform float scene_light;
instance uniform vec4 fx_color : source_color = vec4(1.0);
instance uniform float fx_alpha = 1.0;
instance uniform float fx_heat = 0.5;
void vertex() {
%VERTEX%
}
void fragment() {
	if (((%MODES%) & (1 << view_mode)) == 0) { discard; }
	float a = fx_alpha;
%ROUND%
	vec3 c = fx_color.rgb%LIT%;
	if (view_mode >= 2) {
		float h = fx_heat;
		if (view_mode == 3) { h = 1.0 - h; }
		c = vec3(h);
	}
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const BILLBOARD := """
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
"""

# A unit quad turned into a beam along the node's Y axis (length = |Y|,
# width = |X|) that always faces the camera.
const BEAM := """
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 ax = MODEL_MATRIX[1].xyz;
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 tc = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = normalize(cross(ax, tc)) * wid;
	vec3 wp = center + ax * VERTEX.y + side * VERTEX.x;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
"""

const ROUND := """
	vec2 dd = UV * 2.0 - 1.0;
	float r2 = dot(dd, dd);
	a *= 1.0 - smoothstep(0.15, 1.0, r2);
"""

const BEAM_SOFT := """
	float e = abs(UV.x * 2.0 - 1.0);
	a *= 1.0 - smoothstep(0.3, 1.0, e);
"""


static func _shader(key: String, code: String) -> Shader:
	if _cache.has("sh_" + key):
		return _cache["sh_" + key]
	var s := Shader.new()
	s.code = code.replace("%HASH%", HASH)
	_cache["sh_" + key] = s
	return s


static func _mat(key: String, code: String) -> ShaderMaterial:
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(key, code)
	_cache[key] = m
	return m


static func solid() -> ShaderMaterial:
	return _mat("solid", SOLID)


static func building() -> ShaderMaterial:
	return _mat("building", BUILDING)


static func tree() -> ShaderMaterial:
	return _mat("tree", TREE)


static func water() -> ShaderMaterial:
	return _mat("water", WATER)


static func terrain() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("terrain", TERRAIN)
	return m


## kind: "puff" (smoke/dust, lit by scene light), "glow" (flashes, fire),
## "beam" (tracers), "ir" (IR strobe, NV only), "irbeam" (laser, NV/thermal).
static func fx(kind: String) -> ShaderMaterial:
	if _cache.has("fx_" + kind):
		return _cache["fx_" + kind]
	var vert := BILLBOARD
	var modes := "15"
	var rnd := ROUND
	var lit := ""
	match kind:
		"puff":
			lit = " * scene_light"
		"glow":
			pass
		"beam":
			vert = BEAM
			rnd = BEAM_SOFT
		"ir":
			modes = "2"
		"irbeam":
			vert = BEAM
			rnd = BEAM_SOFT
			modes = "14"
	var code := FX.replace("%VERTEX%", vert).replace("%MODES%", modes).replace("%ROUND%", rnd).replace("%LIT%", lit)
	return _mat("fx_" + kind, code)
