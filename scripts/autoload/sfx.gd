extends Node
## Sounds generated in code at startup (no audio files) and simple playback:
## one-shots from a pool of players, plus named loops.

const RATE := 22050

var streams := {}
var players: Array = []
var loops := {}
var delayed: Array = []
var _seed := 12345


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 20:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	_generate()


func play(id: String, vol_db := 0.0, pitch := 1.0, delay := 0.0) -> void:
	if not streams.has(id):
		return
	if delay > 0.01:
		delayed.append({"id": id, "vol": vol_db, "pitch": pitch, "t": delay})
		return
	var best: AudioStreamPlayer = null
	for p in players:
		if not p.playing:
			best = p
			break
	if best == null:
		best = players[0]
		players.push_back(players.pop_front())
	best.stream = streams[id]
	best.volume_db = vol_db
	best.pitch_scale = pitch
	best.play()


func loop(id: String, on: bool, vol_db := 0.0) -> void:
	if not streams.has(id):
		return
	var p: AudioStreamPlayer = loops.get(id)
	if p == null:
		p = AudioStreamPlayer.new()
		p.stream = streams[id]
		add_child(p)
		loops[id] = p
	p.volume_db = vol_db
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


func stop_all() -> void:
	for id in loops:
		loops[id].stop()
	for p in players:
		p.stop()
	delayed.clear()


func _process(dt: float) -> void:
	var i := delayed.size() - 1
	while i >= 0:
		var d: Dictionary = delayed[i]
		d.t -= dt
		if d.t <= 0.0:
			delayed.remove_at(i)
			play(d.id, d.vol, d.pitch)
		i -= 1


# --- Synthesis ------------------------------------------------------------

func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7fffffff
	return float(_seed) / float(0x7fffffff) * 2.0 - 1.0


func _wav(s: PackedFloat32Array, looped := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _buf(secs: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(secs * RATE))
	return b


static func _lp_k(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / RATE)


## A gun report: lowpassed noise crack plus a decaying low thump.
func _shot(b: PackedFloat32Array, at: int, len_s: float, fc: float, thump_hz: float, amp: float) -> void:
	var n := int(len_s * RATE)
	var k := _lp_k(fc)
	var y := 0.0
	for i in n:
		var idx := at + i
		if idx >= b.size():
			break
		var t := float(i) / RATE
		var env := exp(-t / (len_s * 0.25))
		y += k * (_rand() - y)
		var th := sin(TAU * thump_hz * t * (1.0 - t * 0.8)) * exp(-t / (len_s * 0.35))
		b[idx] += (y * 1.6 + th * 0.9) * env * amp


func _generate() -> void:
	# minigun: 40 rounds a second, looped
	var mg := _buf(1.0)
	for k in 40:
		_shot(mg, int(k * RATE / 40.0), 0.03, 3000.0, 140.0, 0.55)
	streams["mg"] = _wav(mg, true)
	var c30 := _buf(0.45)
	_shot(c30, 0, 0.4, 1800.0, 90.0, 0.9)
	streams["c30"] = _wav(c30)
	var c40 := _buf(0.6)
	_shot(c40, 0, 0.55, 1200.0, 62.0, 1.0)
	streams["c40"] = _wav(c40)
	var c105 := _buf(1.6)
	_shot(c105, 0, 1.5, 700.0, 42.0, 1.1)
	_shot(c105, 0, 0.08, 5000.0, 200.0, 0.5)
	streams["c105"] = _wav(c105)
	# distant explosion: heavy lowpass rumble
	var boom := _buf(2.2)
	var k1 := _lp_k(180.0)
	var y := 0.0
	for i in boom.size():
		var t := float(i) / RATE
		y += k1 * (_rand() - y)
		boom[i] = y * 4.5 * (exp(-t / 0.6) * minf(1.0, t / 0.01))
	streams["boom_far"] = _wav(boom)
	# engines: four turboprops, beating harmonics plus rumble, 4 s loop
	var eng := _buf(4.0)
	var k2 := _lp_k(220.0)
	y = 0.0
	for i in eng.size():
		var t := float(i) / RATE
		y += k2 * (_rand() - y)
		var s := sin(TAU * 68.0 * t) * 0.3 + sin(TAU * 68.5 * t) * 0.25 + sin(TAU * 136.0 * t) * 0.12 + sin(TAU * 204.25 * t) * 0.06
		s *= 0.8 + 0.2 * sin(TAU * 0.5 * t)
		eng[i] = s * 0.5 + y * 1.4
	streams["engine"] = _wav(eng, true)
	# missile warning tone, looped
	var warn := _buf(0.5)
	for i in warn.size():
		var t := float(i) / RATE
		var f := 1000.0 if fmod(t, 0.25) < 0.125 else 1350.0
		warn[i] = (1.0 if sin(TAU * f * t) > 0.0 else -1.0) * 0.18
	streams["warn"] = _wav(warn, true)
	# radio squelch
	var beep := _buf(0.16)
	for i in beep.size():
		var t := float(i) / RATE
		beep[i] = (sin(TAU * 1450.0 * t) * 0.25 * (1.0 if t < 0.06 else 0.0) + _rand() * 0.18 * exp(-(t - 0.06) / 0.04) * (1.0 if t >= 0.06 else 0.0))
	streams["beep"] = _wav(beep)
	var click := _buf(0.03)
	for i in click.size():
		click[i] = _rand() * exp(-float(i) / RATE / 0.004) * 0.5
	streams["click"] = _wav(click)
	var lock := _buf(0.3)
	for i in lock.size():
		var t := float(i) / RATE
		var f := 900.0 if t < 0.12 else 1400.0
		lock[i] = sin(TAU * f * t) * 0.3 * (1.0 if fmod(t, 0.15) < 0.11 else 0.0)
	streams["lock"] = _wav(lock)
	var flare := _buf(0.35)
	var k3 := _lp_k(2500.0)
	y = 0.0
	for i in flare.size():
		var t := float(i) / RATE
		y += k3 * (_rand() - y)
		flare[i] = y * 2.0 * exp(-t / 0.08)
	streams["flare"] = _wav(flare)
	var launch := _buf(1.6)
	var k4 := _lp_k(1500.0)
	y = 0.0
	for i in launch.size():
		var t := float(i) / RATE
		y += k4 * (_rand() - y)
		launch[i] = y * 2.2 * minf(1.0, t / 0.05) * exp(-t / 0.7)
	streams["launch"] = _wav(launch)
	var reload := _buf(0.5)
	for hit in [0.0, 0.18, 0.3]:
		_shot(reload, int(hit * RATE), 0.06, 4000.0, 300.0, 0.35)
	streams["reload"] = _wav(reload)
	var hitb := _buf(1.0)
	var k5 := _lp_k(900.0)
	y = 0.0
	for i in hitb.size():
		var t := float(i) / RATE
		y += k5 * (_rand() - y)
		hitb[i] = y * 3.5 * exp(-t / 0.3) + sin(TAU * 55.0 * t) * 0.5 * exp(-t / 0.2)
	streams["hit"] = _wav(hitb)
	# GAU-8: a 2 s burst at 65 rounds a second, so dense it's one low roar
	var gau := _buf(2.3)
	for k in 130:
		_shot(gau, int(k * RATE / 65.0), 0.05, 900.0, 70.0, 0.4)
	streams["gau8"] = _wav(gau)
	# sonic boom: a sharp double crack and a long rumble
	var sb := _buf(2.5)
	var k6 := _lp_k(400.0)
	y = 0.0
	for i in sb.size():
		var t := float(i) / RATE
		y += k6 * (_rand() - y)
		var crack := (exp(-t / 0.01) + exp(-maxf(t - 0.12, 0.0) / 0.01) * (1.0 if t > 0.12 else 0.0)) * _rand()
		sb[i] = crack * 0.9 + y * 3.0 * exp(-t / 0.8)
	streams["sonic"] = _wav(sb)
