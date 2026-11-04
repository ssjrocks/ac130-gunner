extends CanvasLayer
## Full-screen sensor processing on top of the 3D view: TV desaturation,
## night-vision gain and green phosphor, thermal contrast, noise, scanlines.

const CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;
uniform float gain = 1.0;
uniform float noise_amt = 0.03;
uniform float t = 0.0;
uniform float flash = 0.0;

float rnd(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen_tex, uv, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec2 px = FRAGCOORD.xy;
	float n = rnd(floor(px) + vec2(fract(t * 7.13) * 1013.0, fract(t * 3.71) * 727.0)) - 0.5;
	vec3 o;
	if (mode == 0) {
		o = mix(vec3(l), c, 0.6);
		o = (o - 0.45) * 1.22 + 0.45;
		o += n * noise_amt;
	} else if (mode == 1) {
		vec3 blur = textureLod(screen_tex, uv, 2.0).rgb;
		float lb = dot(blur, vec3(0.299, 0.587, 0.114));
		float v = mix(l, lb, 0.25) * gain;
		v = v / (1.0 + v * 0.55);
		v += n * (noise_amt * 2.0 + 0.05 / (0.35 + v));
		o = vec3(0.3, 1.0, 0.42) * v * 1.08;
		o = mix(o, vec3(0.85, 1.0, 0.85), smoothstep(0.9, 1.3, v));
	} else {
		vec3 blur2 = textureLod(screen_tex, uv, 1.0).rgb;
		float v2 = mix(l, dot(blur2, vec3(0.333)), 0.3);
		v2 = (v2 - 0.5) * 1.18 + 0.5;
		v2 += n * noise_amt * 1.5;
		o = vec3(v2);
	}
	o *= 0.97 + 0.03 * sin(px.y * 3.14159);
	vec2 d = uv - 0.5;
	o *= 1.0 - dot(d, d) * 0.85;
	o = mix(o, vec3(1.0, 0.95, 0.9), flash);
	COLOR = vec4(o, 1.0);
}
"""

var rect: ColorRect
var mat: ShaderMaterial
var flash := 0.0
var time := 0.0


func _ready() -> void:
	layer = 1
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CODE
	mat.shader = sh
	rect.material = mat
	add_child(rect)


func set_mode(m: int, night: float) -> void:
	mat.set_shader_parameter("mode", m)
	mat.set_shader_parameter("gain", lerpf(1.7, 12.0, night))
	mat.set_shader_parameter("noise_amt", 0.025 if m == 0 else (0.05 if m == 1 else 0.03))


func _process(dt: float) -> void:
	time += dt
	flash = maxf(0.0, flash - dt * 2.0)
	mat.set_shader_parameter("t", time)
	mat.set_shader_parameter("flash", flash)
