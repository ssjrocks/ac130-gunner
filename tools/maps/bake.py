#!/usr/bin/env python3
"""Bakes each map's terrain and roads.

    python3 -I tools/maps/bake.py build/maps/layouts.json assets/maps [map ids...]

layouts.json comes from `godot -- --autotest=dumpmaps:PATH` (scripts/data/maps.gd).

The terrain is built around the map's layout: towns, mission sites and roads
sit on valley floors, and mountains rise away from them. The mountains are
shaped by stream-power erosion (rivers cutting valleys and leaving ridges and
spurs) and a talus limit, so slopes stay walkable instead of forming needles.
Roads are then routed across that ground with a grade limit, switching back
where a climb is too steep, smoothed, and cut and filled into the terrain.

Output per map: <id>.ter (heights) and <id>_roads.json (road polylines, in the
same order as the layout's roads so mission routes keep their meaning).
"""
import heapq
import json
import math
import os
import struct
import sys

import numpy as np
from scipy import ndimage

CORE = 8000.0
RES = 640
SP = CORE / RES
FAR_SPAN = 52000.0
FAR_RES = 520
FSP = FAR_SPAN / FAR_RES

# Per-map recipes. relief: mountain height above the floor; valley: half width
# of the flat ground around roads and towns; ramp: distance over which the
# mountains rise; style: range (eroded mountains), mesa (a plateau above a
# green river zone), hills (scattered rocky hills on a plain).
RECIPES = {
	"kharim": {"base": 40.0, "relief": 680.0, "valley": 420.0, "ramp": 2300.0, "style": "range", "wave": 2600.0, "floor": 9.0},
	"ridge": {"base": 600.0, "relief": 1300.0, "valley": 170.0, "ramp": 2700.0, "style": "range", "wave": 2000.0, "floor": 14.0},
	"port": {"base": 6.0, "relief": 90.0, "valley": 500.0, "ramp": 1800.0, "style": "hills", "wave": 1500.0, "floor": 4.0,
		"river_w": 1500.0},
	"greenbelt": {"base": 30.0, "relief": 55.0, "valley": 1100.0, "ramp": 260.0, "style": "mesa", "wave": 1800.0, "floor": 2.0},
	"flats": {"base": 40.0, "relief": 160.0, "valley": 380.0, "ramp": 1500.0, "style": "hills", "wave": 1300.0, "floor": 5.0},
	"lowtown": {"base": 20.0, "relief": 720.0, "valley": 380.0, "ramp": 2200.0, "style": "range", "wave": 2300.0, "floor": 6.0},
}
GRADE_MAIN = 0.09      # steepest sustained road grade
GRADE_TRACK = 0.13
TALUS = math.tan(math.radians(38.0))


# --- Noise -------------------------------------------------------------------

class Perlin:
	def __init__(self, seed):
		rng = np.random.default_rng(seed)
		p = rng.permutation(256)
		self.perm = np.concatenate([p, p])
		a = rng.random(256) * 2.0 * np.pi
		self.g = np.stack([np.cos(a), np.sin(a)], -1)

	def __call__(self, x, y):
		xi = np.floor(x).astype(np.int64)
		yi = np.floor(y).astype(np.int64)
		xf = x - xi
		yf = y - yi
		xi &= 255
		yi &= 255
		pm = self.perm

		def grad(ix, iy, dx, dy):
			h = pm[(pm[ix] + iy) & 255]
			gg = self.g[h]
			return gg[..., 0] * dx + gg[..., 1] * dy

		u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
		v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
		n00 = grad(xi, yi, xf, yf)
		n10 = grad((xi + 1) & 255, yi, xf - 1, yf)
		n01 = grad(xi, (yi + 1) & 255, xf, yf - 1)
		n11 = grad((xi + 1) & 255, (yi + 1) & 255, xf - 1, yf - 1)
		a = n00 + u * (n10 - n00)
		b = n01 + u * (n11 - n01)
		return (a + v * (b - a)) * 1.41


def fbm(noise, x, y, wave, octaves, gain=0.5):
	s = np.zeros_like(x)
	amp = 1.0
	f = 1.0 / wave
	norm = 0.0
	for o in range(octaves):
		s += amp * noise(x * f + o * 17.3, y * f - o * 9.1)
		norm += amp
		amp *= gain
		f *= 2.03
	return s / norm


def ridged(noise, x, y, wave, octaves):
	"""Ridged multifractal in 0..1: sharp crests, detail fading on the flanks."""
	s = np.zeros_like(x)
	f = 1.0 / wave
	w = np.ones_like(x)
	amp = 1.0
	norm = 0.0
	for o in range(octaves):
		n = 1.0 - np.abs(noise(x * f + o * 31.7, y * f + o * 7.7))
		n = n * n * w
		w = np.clip(n * 1.6, 0.0, 1.0)
		s += n * amp
		norm += amp
		amp *= 0.5
		f *= 2.1
	return s / norm


# --- Layout ------------------------------------------------------------------

def seg_dist(px, py, a, b):
	ax, ay = a
	bx, by = b
	dx, dy = bx - ax, by - ay
	l2 = max(dx * dx + dy * dy, 1e-6)
	t = np.clip(((px - ax) * dx + (py - ay) * dy) / l2, 0.0, 1.0)
	return np.hypot(px - (ax + t * dx), py - (ay + t * dy))


def road_polys(m):
	out = []
	for r in m.get("roads", []):
		if isinstance(r, str):
			kind, nums = r.split(":")
			v = [float(x) for x in nums.split(",")]
			if kind == "loop":
				out.append([[v[0] + math.cos(math.tau * k / 16) * v[2], v[1] + math.sin(math.tau * k / 16) * v[2]] for k in range(17)])
			else:
				out.append([[v[0] - v[2], v[1]], [v[0] + v[2], v[1]]])
		else:
			out.append(r)
	return out


def site_radius(m, name):
	op = m.get("outposts", {})
	return float(op[name]) * 0.9 + 40.0 if name in op else 70.0


def feature_distance(m, X, Z, warp):
	"""Distance (m) from each point to the nearest road, town or site, with a
	little noise so valley edges wander."""
	d = np.full(X.shape, 1e9)
	for i, pts in enumerate(road_polys(m)):
		wmul = 1.0 if i == 0 else 0.75
		for a, b in zip(pts[:-1], pts[1:]):
			d = np.minimum(d, seg_dist(X, Z, a, b) / wmul)
	for t in m.get("towns", []):
		d = np.minimum(d, np.maximum(np.hypot(X - t["pos"][0], Z - t["pos"][1]) - t["r"] * 1.1, 0.0))
	if m.get("river"):
		rv = m["river"]
		for a, b in zip(rv[:-1], rv[1:]):
			d = np.minimum(d, seg_dist(X, Z, a, b))
	return d * (1.0 + 0.45 * warp)


# --- Erosion -----------------------------------------------------------------

NB = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]


def thermal(h, sp, iters, talus=TALUS, rate=0.2):
	"""Slopes steeper than the talus angle shed material to all eight
	neighbours (no axis bias, so no streaks)."""
	ny, nx = h.shape
	for _ in range(iters):
		out = np.zeros_like(h)
		inn = np.zeros_like(h)
		for dx, dy in NB:
			lim = talus * sp * math.hypot(dx, dy)
			ys = slice(max(dy, 0), ny + min(dy, 0))
			xs = slice(max(dx, 0), nx + min(dx, 0))
			yd = slice(max(-dy, 0), ny + min(-dy, 0))
			xd = slice(max(-dx, 0), nx + min(-dx, 0))
			# cells at [yd, xd] give to their neighbour at [ys, xs]
			ex = np.maximum(h[yd, xd] - h[ys, xs] - lim, 0.0) * (rate / 8.0)
			out[yd, xd] += ex
			inn[ys, xs] += ex
		h = h - out + inn
	return h


def droplets(h, sp, count, seed, steps=56, batch=60000):
	"""Hydraulic erosion: many raindrops run downhill at once, picking up
	sediment where they speed up and dropping it where they slow, which cuts
	gullies and ravines and builds fans at the foot of the slopes."""
	rng = np.random.default_rng(seed)
	ny, nx = h.shape
	g = h / sp                      # heights in cell units, so slopes are unitless
	inertia, cap_k, min_slope = 0.08, 6.0, 0.02
	erode_k, dep_k, evap, grav = 0.35, 0.25, 0.03, 6.0
	off = [(-1, -1, 0.05), (0, -1, 0.1), (1, -1, 0.05), (-1, 0, 0.1), (0, 0, 0.4), (1, 0, 0.1), (-1, 1, 0.05), (0, 1, 0.1), (1, 1, 0.05)]
	done = 0
	while done < count:
		B = min(batch, count - done)
		done += B
		px = rng.uniform(2, nx - 3, B)
		pz = rng.uniform(2, ny - 3, B)
		dx = np.zeros(B)
		dz = np.zeros(B)
		speed = np.ones(B)
		water = np.ones(B)
		sed = np.zeros(B)
		alive = np.ones(B, bool)
		for _ in range(steps):
			ix = px.astype(np.int64)
			iz = pz.astype(np.int64)
			fx = px - ix
			fz = pz - iz
			h00 = g[iz, ix]
			h10 = g[iz, ix + 1]
			h01 = g[iz + 1, ix]
			h11 = g[iz + 1, ix + 1]
			gx = (h10 - h00) * (1 - fz) + (h11 - h01) * fz
			gz = (h01 - h00) * (1 - fx) + (h11 - h10) * fx
			hc = h00 * (1 - fx) * (1 - fz) + h10 * fx * (1 - fz) + h01 * (1 - fx) * fz + h11 * fx * fz
			dx = dx * inertia - gx * (1 - inertia)
			dz = dz * inertia - gz * (1 - inertia)
			ln = np.hypot(dx, dz)
			still = ln < 1e-9
			ln[still] = 1.0
			dx /= ln
			dz /= ln
			npx = px + dx
			npz = pz + dz
			alive &= ~still & (npx > 1) & (npx < nx - 2) & (npz > 1) & (npz < ny - 2)
			npx = np.clip(npx, 1, nx - 2.001)
			npz = np.clip(npz, 1, ny - 2.001)
			jx = npx.astype(np.int64)
			jz = npz.astype(np.int64)
			gx2 = npx - jx
			gz2 = npz - jz
			hn = (g[jz, jx] * (1 - gx2) * (1 - gz2) + g[jz, jx + 1] * gx2 * (1 - gz2)
				+ g[jz + 1, jx] * (1 - gx2) * gz2 + g[jz + 1, jx + 1] * gx2 * gz2)
			dh = hn - hc
			cap = np.maximum(-dh, min_slope) * speed * water * cap_k
			uphill = dh > 0
			dep = np.where(uphill, np.minimum(dh, sed), np.where(sed > cap, (sed - cap) * dep_k, 0.0))
			ero = np.where(~uphill & (sed <= cap), np.minimum((cap - sed) * erode_k, -dh), 0.0)
			# small steps keep the brush from digging runaway pits
			dep = np.minimum(dep, 0.08) * alive
			ero = np.minimum(ero, 0.04) * alive
			sed += ero - dep
			# drop sediment at the cell the drop is leaving, take it from a small brush
			np.add.at(g, (iz, ix), dep * (1 - fx) * (1 - fz))
			np.add.at(g, (iz, ix + 1), dep * fx * (1 - fz))
			np.add.at(g, (iz + 1, ix), dep * (1 - fx) * fz)
			np.add.at(g, (iz + 1, ix + 1), dep * fx * fz)
			ci = np.rint(px).astype(np.int64)
			cz = np.rint(pz).astype(np.int64)
			for ox, oz, w in off:
				np.add.at(g, (np.clip(cz + oz, 0, ny - 1), np.clip(ci + ox, 0, nx - 1)), -ero * w)
			speed = np.minimum(np.sqrt(np.maximum(speed * speed - dh * grav, 0.0)), 8.0)
			water *= 1.0 - evap
			px, pz = npx, npz
			if not alive.any():
				break
	return g * sp


# --- Terrain -----------------------------------------------------------------

def terrain(mid, m, X, Z, sp, erode):
	rc = RECIPES[mid]
	seed = int(m.get("seed", 1))
	pn = Perlin(seed)
	pn2 = Perlin(seed + 7)
	wave = rc["wave"]
	warp = fbm(pn2, X, Z, 1800.0, 3)
	d = feature_distance(m, X, Z, warp)
	valley = rc["valley"] * (1.0 + 0.4 * fbm(pn2, X + 911, Z - 377, 2400.0, 2))
	t = np.clip((d - valley) / rc["ramp"], 0.0, 1.0)
	floor = rc["base"] + rc["floor"] * fbm(pn, X, Z, 1600.0, 3) + rc["floor"] * 0.25 * fbm(pn, X, Z, 300.0, 2)
	# the floor tilts gently away from the middle, so water has somewhere to go
	floor += np.hypot(X, Z) * 0.0025
	wx = X + 600.0 * fbm(pn2, X, Z, 3000.0, 2)
	wz = Z + 600.0 * fbm(pn2, X + 5000, Z, 3000.0, 2)
	style = rc["style"]
	if style == "range":
		# a long gentle fan at the foot, steepening into the range
		env = (t * t * (3.0 - 2.0 * t)) ** 1.4
		r = ridged(pn, wx, wz, wave, 6)
		big = 0.5 + 0.5 * fbm(pn, X - 3000, Z + 2000, wave * 2.5, 2)
		mtn = rc["relief"] * env * (0.25 + 0.75 * r) * (0.55 + 0.6 * big)
		h = floor + mtn
		kmap = (5.0e-4 * np.clip(env * 1.5, 0.05, 1.0)) if erode else None
	elif style == "mesa":
		# the dasht: a desert plateau above the green zone, its edge cut by gullies
		edge = np.clip((d - valley) / rc["ramp"], 0.0, 1.0)
		edge = edge * edge * (3.0 - 2.0 * edge)
		h = floor + rc["relief"] * edge * (0.85 + 0.15 * fbm(pn, wx, wz, 900.0, 3))
		kmap = (1.2e-4 * np.clip(edge * 2.0, 0.05, 1.0)) if erode else None
	else:
		# a plain with scattered rocky hills and low ridges
		n = fbm(pn, wx, wz, wave, 4)
		hill = np.clip(n - 0.08, 0.0, None) ** 1.6 * 3.2
		env = np.clip(t * 1.4, 0.0, 1.0)
		h = floor + rc["relief"] * hill * env + rc["relief"] * 0.08 * env * fbm(pn, X, Z, 700.0, 3)
		kmap = (1.5e-4 * np.clip(env, 0.05, 1.0)) if erode else None
	h = thermal(h, sp, 40)
	if erode:
		h = droplets(h, sp, int(1.2 * X.size), seed)
		h = thermal(h, sp, 90)
	if "river_w" in rc and m.get("coast_x") is not None:
		# a wide river on the east side instead of the sea
		cx = float(m["coast_x"])
		wl = float(m.get("water", 0.0))
		shore = cx + 1100.0 * fbm(pn2, X * 0.3, Z, 2600.0, 3) + 90.0 * fbm(pn, X, Z, 450.0, 2)
		# the docks stand on the bank: draw the shore in to their edge
		for t in m.get("towns", []):
			if t.get("style") == "industrial":
				pull = np.exp(-((Z - t["pos"][1]) / 650.0) ** 2)
				shore = shore * (1.0 - pull) + (t["pos"][0] + t["r"] * 0.85) * pull
		inwater = np.clip((X - shore) / 220.0, 0.0, 1.0) * np.clip((shore + rc["river_w"] - X) / 220.0, 0.0, 1.0)
		h = h * (1.0 - inwater) + (wl - 9.0) * inwater
		# the land falls to a low bank near the water
		bank = np.clip(1.0 - np.minimum(np.abs(X - shore), np.abs(X - shore - rc["river_w"])) / 500.0, 0.0, 1.0) * (1.0 - inwater)
		h = h - bank * np.clip(h - (wl + 2.5), 0.0, None) * 0.8
	return h


def flatten(m, h, X, Z):
	"""Towns, outposts and mission sites sit on level ground."""
	spots = [(t["pos"], t["r"] * 0.95) for t in m.get("towns", [])]
	spots += [(p, site_radius(m, n) * 0.6) for n, p in m.get("sites", {}).items()]
	spots += [(p, 35.0) for p in m.get("sam", [])]
	for p, r in spots:
		dd = np.hypot(X - p[0], Z - p[1])
		inner = dd < r * 0.7
		if not inner.any():
			lvl = float(h[np.unravel_index(np.argmin(dd), dd.shape)])
		else:
			lvl = float(np.median(h[inner]))
		w = 1.0 - np.clip((dd - r * 0.7) / (r * 0.9), 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w)
		h = h * (1.0 - w) + lvl * w
	return h


def carve_river(m, h, X, Z):
	rv = m.get("river")
	if not rv:
		return h
	wl = float(m.get("water", 0.0))
	d = np.full(X.shape, 1e9)
	for a, b in zip(rv[:-1], rv[1:]):
		d = np.minimum(d, seg_dist(X, Z, a, b))
	bed = 1.0 - np.clip((d - 22.0) / 120.0, 0.0, 1.0)
	return h * (1.0 - bed) + (wl - 4.0) * bed


# --- Roads -------------------------------------------------------------------

def route(h, a, b, gmax, avoid):
	"""Cheapest path between grid cells a and b that keeps to the grade limit
	where it can (it zigzags up a slope rather than straight up it)."""
	ny, nx = h.shape
	ax, ay = a
	bx, by = b
	pad = 90
	x0, x1 = max(min(ax, bx) - pad, 0), min(max(ax, bx) + pad, nx - 1)
	y0, y1 = max(min(ay, by) - pad, 0), min(max(ay, by) + pad, ny - 1)
	W = x1 - x0 + 1
	sub = h[y0:y1 + 1, x0:x1 + 1]
	av = avoid[y0:y1 + 1, x0:x1 + 1]
	hs = sub.tolist()
	avl = av.tolist()
	start = (ay - y0) * W + (ax - x0)
	goal = (by - y0) * W + (bx - x0)
	gx, gy = bx - x0, by - y0
	best = {start: 0.0}
	prev = {}
	pq = [(0.0, 0.0, start)]
	steps = [(dx, dy, SP * math.hypot(dx, dy)) for dx, dy in NB] + \
		[(dx, dy, SP * math.hypot(dx, dy)) for dx, dy in ((2, 1), (1, 2), (-1, 2), (-2, 1), (-2, -1), (-1, -2), (1, -2), (2, -1))]
	H = y1 - y0 + 1
	while pq:
		_f, g0, cur = heapq.heappop(pq)
		if cur == goal:
			break
		if g0 > best.get(cur, 1e18) + 1e-6:
			continue
		cy, cx = divmod(cur, W)
		g = best[cur]
		hc = hs[cy][cx]
		for dx, dy, dd in steps:
			nx2, ny2 = cx + dx, cy + dy
			if nx2 < 0 or ny2 < 0 or nx2 >= W or ny2 >= H:
				continue
			grade = abs(hs[ny2][nx2] - hc) / dd
			cost = dd * (1.0 + 18.0 * grade * grade + avl[ny2][nx2])
			if grade > gmax:
				cost += dd * 60.0 * (grade - gmax) / gmax
			ng = g + cost
			nid = ny2 * W + nx2
			if ng < best.get(nid, 1e18):
				best[nid] = ng
				prev[nid] = cur
				heapq.heappush(pq, (ng + SP * math.hypot(nx2 - gx, ny2 - gy), ng, nid))
	path = [goal]
	while path[-1] != start:
		path.append(prev[path[-1]])
	path.reverse()
	return [((p % W + x0 + 0.5) * SP - CORE / 2, (p // W + y0 + 0.5) * SP - CORE / 2) for p in path]


def simplify(pts, tol):
	if len(pts) < 3:
		return pts
	a, b = np.array(pts[0]), np.array(pts[-1])
	ab = b - a
	l = np.linalg.norm(ab)
	best, bi = -1.0, 0
	for i in range(1, len(pts) - 1):
		p = np.array(pts[i])
		dd = abs(np.cross(ab, p - a)) / l if l > 1e-6 else np.linalg.norm(p - a)
		if dd > best:
			best, bi = dd, i
	if best <= tol:
		return [pts[0], pts[-1]]
	return simplify(pts[:bi + 1], tol)[:-1] + simplify(pts[bi:], tol)


def chaikin(pts, n):
	for _ in range(n):
		out = [pts[0]]
		for a, b in zip(pts[:-1], pts[1:]):
			out.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
			out.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
		out.append(pts[-1])
		pts = out
	return pts


def resample(pts, step):
	out = [pts[0]]
	carry = 0.0
	for a, b in zip(pts[:-1], pts[1:]):
		seg = math.dist(a, b)
		d = step - carry
		while d <= seg:
			f = d / seg
			out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
			d += step
		carry = seg - (d - step)
	if math.dist(out[-1], pts[-1]) > 1.0:
		out.append(pts[-1])
	return out


def sample(h, x, z):
	fx = (x + CORE / 2) / SP - 0.5
	fz = (z + CORE / 2) / SP - 0.5
	return float(ndimage.map_coordinates(h, [[fz], [fx]], order=1, mode="nearest")[0])


def grade_profile(zs, step, gmax, smooth=6):
	"""Road bed heights: the ground smoothed along the road, then limited to
	the grade both ways so no stretch is steeper than the road allows."""
	z = np.array(zs, dtype=float)
	k = np.ones(2 * smooth + 1) / (2 * smooth + 1)
	z = np.convolve(np.pad(z, smooth, mode="edge"), k, mode="valid")
	lim = gmax * step
	for _ in range(3):
		for i in range(1, len(z)):
			z[i] = min(max(z[i], z[i - 1] - lim), z[i - 1] + lim)
		for i in range(len(z) - 2, -1, -1):
			z[i] = min(max(z[i], z[i + 1] - lim), z[i + 1] + lim)
	return z


def carve_road(h, X, Z, pts, bed, half_w, shoulder):
	"""Cut and fill: the road bed is level across, with batter slopes to the ground."""
	P = np.array(pts)
	minx, maxx = P[:, 0].min() - shoulder * 3, P[:, 0].max() + shoulder * 3
	minz, maxz = P[:, 1].min() - shoulder * 3, P[:, 1].max() + shoulder * 3
	i0 = max(int((minx + CORE / 2) / SP), 0)
	i1 = min(int((maxx + CORE / 2) / SP) + 1, RES)
	j0 = max(int((minz + CORE / 2) / SP), 0)
	j1 = min(int((maxz + CORE / 2) / SP) + 1, RES)
	xs, zs = X[j0:j1, i0:i1], Z[j0:j1, i0:i1]
	best = np.full(xs.shape, 1e9)
	bz = np.zeros(xs.shape)
	for k in range(len(P) - 1):
		a, b = P[k], P[k + 1]
		dx, dz = b - a
		l2 = max(dx * dx + dz * dz, 1e-6)
		t = np.clip(((xs - a[0]) * dx + (zs - a[1]) * dz) / l2, 0.0, 1.0)
		dd = np.hypot(xs - (a[0] + t * dx), zs - (a[1] + t * dz))
		closer = dd < best
		best = np.where(closer, dd, best)
		bz = np.where(closer, bed[k] + (bed[k + 1] - bed[k]) * t, bz)
	region = h[j0:j1, i0:i1]
	# level bed across the road, then batter slopes no steeper than the
	# talus angle out to where they meet the ground (cuttings and embankments)
	off = np.maximum(best - half_w, 0.0)
	batter = np.clip(region, bz - TALUS * off, bz + TALUS * off)
	new = np.where(best <= half_w, bz, np.where(best < half_w + shoulder * 5.0, batter, region))
	# soften the edge of the bed into the batter
	w = 1.0 - np.clip((best - half_w) / shoulder, 0.0, 1.0)
	new = new * (1.0 - w * 0.5) + bz * (w * 0.5)
	h[j0:j1, i0:i1] = new
	return h


def build_roads(m, h, X, Z, water_mask):
	out = []
	avoid = water_mask * 40.0
	for ri, pts in enumerate(road_polys(m)):
		if len(pts) < 2:
			out.append(pts)
			continue
		loop = isinstance(m["roads"][ri], str)
		gmax = GRADE_MAIN if ri == 0 else GRADE_TRACK
		path = []
		for a, b in zip(pts[:-1], pts[1:]):
			ca = (int(np.clip((a[0] + CORE / 2) / SP, 0, RES - 1)), int(np.clip((a[1] + CORE / 2) / SP, 0, RES - 1)))
			cb = (int(np.clip((b[0] + CORE / 2) / SP, 0, RES - 1)), int(np.clip((b[1] + CORE / 2) / SP, 0, RES - 1)))
			if loop or math.dist(a, b) < 60.0:
				seg = [tuple(a), tuple(b)]
			else:
				seg = route(h, ca, cb, gmax, avoid)
				seg[0] = tuple(a)
				seg[-1] = tuple(b)
			path += seg if not path else seg[1:]
		path = simplify(path, SP * 0.45)
		path = chaikin(path, 3)
		path = resample(path, 10.0)
		zs = [sample(h, x, z) for x, z in path]
		bed = grade_profile(zs, 10.0, gmax * 0.95)
		# bridges and fords: a road never dips under the water
		wl = float(m.get("water", -1e9))
		bed = np.maximum(bed, wl + 1.2)
		h = carve_road(h, X, Z, path, bed, 5.0 if ri == 0 else 4.0, 16.0)
		out.append([[round(x, 1), round(z, 1)] for x, z in path])
	return h, out


# --- Output ------------------------------------------------------------------

def write_ter(path, core, far):
	"""ACT2: magic, core res, far res, core size, far span, then float32
	heights row by row (z then x), core first."""
	with open(path, "wb") as f:
		f.write(b"ACT2")
		f.write(struct.pack("<iiff", RES, FAR_RES, CORE, FAR_SPAN))
		f.write(core.astype("<f4").tobytes())
		f.write(far.astype("<f4").tobytes())


def hillshade(h, path, sp):
	from PIL import Image
	gy, gx = np.gradient(h, sp)
	sl = np.pi / 2 - np.arctan(np.hypot(gx, gy))
	asp = np.arctan2(-gx, gy)
	az, alt = math.radians(315), math.radians(45)
	shade = np.sin(alt) * np.sin(sl) + np.cos(alt) * np.cos(sl) * np.cos(az - asp)
	hn = (h - h.min()) / max(h.max() - h.min(), 1.0)
	rgb = np.stack([0.55 + 0.45 * hn, 0.5 + 0.35 * hn, 0.4 + 0.3 * hn], -1) * np.clip(shade, 0.15, 1.0)[..., None]
	Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).save(path)


def bake(mid, m, out_dir, preview_dir):
	print(f"[bake] {mid}", flush=True)
	c = (np.arange(RES) + 0.5) * SP - CORE / 2
	X, Z = np.meshgrid(c, c)
	fc = (np.arange(FAR_RES) + 0.5) * FSP - FAR_SPAN / 2
	FX, FZ = np.meshgrid(fc, fc)
	far = terrain(mid, m, FX, FZ, FSP, erode=True)
	core = terrain(mid, m, X, Z, SP, erode=True)
	# blend the core's edge into the coarser far field so there's no seam
	far_at_core = ndimage.map_coordinates(far, [(Z + FAR_SPAN / 2) / FSP - 0.5, (X + FAR_SPAN / 2) / FSP - 0.5], order=1, mode="nearest")
	edge = np.minimum(np.minimum(X + CORE / 2, CORE / 2 - X), np.minimum(Z + CORE / 2, CORE / 2 - Z))
	wb = np.clip((edge - 50.0) / 450.0, 0.0, 1.0)
	core = core * wb + far_at_core * (1.0 - wb)
	core = flatten(m, core, X, Z)
	core = thermal(core, SP, 12)
	core = carve_river(m, core, X, Z)
	wl = float(m.get("water", -1e9))
	water = (core < wl).astype(float)
	water = ndimage.binary_dilation(water > 0, iterations=2).astype(float)
	for b in m.get("bridges", []):
		water[np.hypot(X - b[0], Z - b[1]) < 120.0] = 0.0
	core, roads = build_roads(m, core, X, Z, water)
	write_ter(os.path.join(out_dir, mid + ".ter"), core, far)
	with open(os.path.join(out_dir, mid + "_roads.json"), "w") as f:
		json.dump(roads, f)
	if preview_dir:
		img = core.copy()
		hillshade(img, os.path.join(preview_dir, mid + "_hillshade.png"), SP)
		gy, gx = np.gradient(core, SP)
		slope = np.degrees(np.arctan(np.hypot(gx, gy)))
		print(f"[bake] {mid}: height {core.min():.0f}..{core.max():.0f} m, slope p50 {np.percentile(slope, 50):.1f} p99 {np.percentile(slope, 99):.1f} max {slope.max():.1f} deg", flush=True)
		for ri, r in enumerate(roads):
			zs = [sample(core, x, z) for x, z in r]
			g = np.abs(np.diff(zs)) / 10.0
			L = sum(math.dist(a, b) for a, b in zip(r[:-1], r[1:]))
			print(f"[bake]   road {ri}: {L / 1000:.1f} km, steepest grade {g.max() * 100:.1f}%, p95 {np.percentile(g, 95) * 100:.1f}%", flush=True)


def main():
	layouts = json.load(open(sys.argv[1]))
	out_dir = sys.argv[2]
	ids = sys.argv[3:] or list(RECIPES.keys())
	os.makedirs(out_dir, exist_ok=True)
	prev = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), "preview")
	os.makedirs(prev, exist_ok=True)
	for mid in ids:
		bake(mid, layouts[mid], out_dir, prev)


if __name__ == "__main__":
	main()
