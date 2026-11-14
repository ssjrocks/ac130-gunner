extends RefCounted
## Battlefield layouts. Coordinates are metres on the ground (x east, z south).
## The detailed terrain covers +-4000 m; fighting stays inside +-3000 m.
##
## routes: [road index, reversed, start fraction, end fraction]
## sites: named points used by missions; outposts get HESCO walls.

const MAPS := {
	"kharim": {
		"name": "KHARIM VALLEY", "biome": "desert", "seed": 1103, "tree_count": 2200,
		"desc": "A mud-brick town in a dry valley. Walled compounds, open ground and long sight lines.",
		"towns": [
			{"name": "Kharim", "pos": Vector2(0, 0), "r": 430.0, "style": "compound"},
			{"name": "Dashti", "pos": Vector2(-1500, 950), "r": 210.0, "style": "compound"},
			{"name": "Qasr", "pos": Vector2(1300, 1300), "r": 170.0, "style": "village"},
		],
		"roads": [
			[Vector2(-3800, 1150), Vector2(-2600, 1100), Vector2(-1500, 950), Vector2(-700, 420), Vector2(0, 0), Vector2(650, -380), Vector2(1150, -900), Vector2(1700, -1300), Vector2(2600, -1600), Vector2(3800, -1900)],
			[Vector2(0, 0), Vector2(400, 650), Vector2(1300, 1300), Vector2(1900, 2400), Vector2(2300, 3800)],
			[Vector2(0, 0), Vector2(-500, -700), Vector2(-900, -1500), Vector2(-1100, -2600), Vector2(-1200, -3800)],
			[Vector2(1150, -900), Vector2(1250, -1110)],
		],
		"sites": {
			"qrf": Vector2(-2250, 1150),
			"crash2": Vector2(1650, 850), "lz_crash2": Vector2(1850, 650), "hvt2": Vector2(1300, 1330), "op2": Vector2(950, 1560), "lz_sf2": Vector2(700, 2000),
			"fob": Vector2(1250, -1180), "checkpoint": Vector2(-700, 470), "crash": Vector2(-1750, -380),
			"lz_crash": Vector2(-1560, -600), "op": Vector2(-1120, 620), "hvt_target": Vector2(-1480, 960),
			"lz_sf": Vector2(-420, 1480), "hq": Vector2(60, 40),
		},
		"site_names": {"qrf": "COP LION", "fob": "FOB ANVIL", "checkpoint": "CHECKPOINT 7"},
		"outposts": {"qrf": 60.0, "fob": 80.0, "checkpoint": 34.0},
		"defend": ["fob", "checkpoint"],
		"escort": [[0, true, 0.18, 0.78]],
		"interdict": [[1, true, 0.0, 0.85], [2, true, 0.0, 0.85]],
		"hvt": [[0, false, 0.08, 0.5]],
		"strike": [{"target": "hvt_target", "op": "op", "lz": "lz_sf"}, {"target": "hvt2", "op": "op2", "lz": "lz_sf2"}],
		"csar": [{"crash": "crash", "lz": "lz_crash"}, {"crash": "crash2", "lz": "lz_crash2"}],
		"sam": [Vector2(-1600, -1300), Vector2(1700, 450), Vector2(-400, 1900), Vector2(2100, -250)],
		"spawns": [Vector2(-2400, 0), Vector2(-1000, 2300), Vector2(2300, 700), Vector2(200, -2400), Vector2(-2600, -1500), Vector2(2500, 2000)],
	},
	"ridge": {
		"name": "RIDGE 471", "biome": "mountain", "seed": 4471, "tree_count": 3500,
		"desc": "A narrow valley ringed by steep mountains. The enemy comes down the slopes.",
		"towns": [
			{"name": "Sarband", "pos": Vector2(0, 150), "r": 260.0, "style": "compound"},
			{"name": "Kalay", "pos": Vector2(-850, -650), "r": 150.0, "style": "village"},
		],
		"roads": [
			[Vector2(-3800, -2400), Vector2(-2400, -1600), Vector2(-1500, -1100), Vector2(-850, -650), Vector2(0, 150), Vector2(850, 700), Vector2(1600, 1500), Vector2(2500, 2500), Vector2(3800, 3600)],
			[Vector2(0, 150), Vector2(500, -200), Vector2(850, -520)],
		],
		"sites": {
			"qrf": Vector2(-1250, -1000),
			"crash2": Vector2(950, 300), "lz_crash2": Vector2(760, 420), "hvt2": Vector2(40, 190), "op2": Vector2(460, 470), "lz_sf2": Vector2(-620, 620),
			"cop": Vector2(860, -560), "north_post": Vector2(40, 520), "crash": Vector2(-300, 1000),
			"lz_crash": Vector2(-500, 860), "op": Vector2(-560, -340), "hvt_target": Vector2(-850, -640),
			"lz_sf": Vector2(320, -900), "hq": Vector2(20, 160),
		},
		"site_names": {"qrf": "COP BEAR", "cop": "COP HAWK", "north_post": "OP NORTH"},
		"outposts": {"qrf": 60.0, "cop": 75.0, "north_post": 32.0},
		"defend": ["cop", "north_post"],
		"escort": [[0, false, 0.2, 0.78]],
		"interdict": [[0, true, 0.12, 0.55]],
		"hvt": [[0, false, 0.15, 0.48]],
		"strike": [{"target": "hvt_target", "op": "op", "lz": "lz_sf"}, {"target": "hvt2", "op": "op2", "lz": "lz_sf2"}],
		"csar": [{"crash": "crash", "lz": "lz_crash"}, {"crash": "crash2", "lz": "lz_crash2"}],
		"sam": [Vector2(1500, 1100), Vector2(-1500, -250), Vector2(300, -1700), Vector2(-900, 1500)],
		"spawns": [Vector2(1800, -500), Vector2(-1800, 350), Vector2(0, 1900), Vector2(-700, -1900), Vector2(1500, 1700), Vector2(-1600, -1400)],
	},
	"port": {
		"name": "QALA BANDAR", "biome": "coastal", "field_top": 12.0, "seed": 2207, "tree_count": 1800, "water": 0.0, "coast_x": 1950.0,
		"desc": "A crowded river port on the border river, with its docks and wharves. Civilians everywhere, tight streets, the river to the east.",
		"towns": [
			{"name": "Qala Bandar", "pos": Vector2(350, 0), "r": 700.0, "style": "city"},
			{"name": "Docks", "pos": Vector2(1500, 380), "r": 260.0, "style": "industrial"},
			{"name": "Haddah", "pos": Vector2(-1500, -900), "r": 200.0, "style": "village"},
			{"name": "Marj", "pos": Vector2(-900, 1300), "r": 180.0, "style": "compound"},
		],
		"roads": [
			[Vector2(1200, -3800), Vector2(1000, -2000), Vector2(700, -900), Vector2(500, 0), Vector2(800, 1100), Vector2(1000, 2200), Vector2(1100, 3800)],
			[Vector2(-3800, -700), Vector2(-2400, -800), Vector2(-1500, -900), Vector2(-600, -400), Vector2(500, 0), Vector2(1500, 380)],
			[Vector2(500, 0), Vector2(-300, 700), Vector2(-900, 1300), Vector2(-1600, 2500), Vector2(-2200, 3800)],
		],
		"sites": {
			"qrf": Vector2(-2000, -700),
			"crash2": Vector2(-300, 1500), "lz_crash2": Vector2(-520, 1660), "hvt2": Vector2(-1480, -870), "op2": Vector2(-1100, -640), "lz_sf2": Vector2(-800, -1700),
			"base": Vector2(-300, -1500), "embassy": Vector2(150, -350), "crash": Vector2(-700, -1050),
			"lz_crash": Vector2(-900, -1200), "op": Vector2(-680, 1040), "hvt_target": Vector2(-900, 1310),
			"lz_sf": Vector2(-1500, 1750), "hq": Vector2(1550, 300),
		},
		"site_names": {"qrf": "CAMP TIGER", "base": "CAMP SENTINEL", "embassy": "THE EMBASSY"},
		"outposts": {"qrf": 60.0, "base": 80.0, "embassy": 46.0},
		"defend": ["base", "embassy"],
		"escort": [[1, false, 0.25, 1.0], [0, false, 0.15, 0.6]],
		"interdict": [[2, true, 0.0, 0.75]],
		"hvt": [[0, true, 0.1, 0.55]],
		"strike": [{"target": "hvt_target", "op": "op", "lz": "lz_sf"}, {"target": "hvt2", "op": "op2", "lz": "lz_sf2"}],
		"csar": [{"crash": "crash", "lz": "lz_crash"}, {"crash": "crash2", "lz": "lz_crash2"}],
		"sam": [Vector2(-1700, 500), Vector2(-200, -2100), Vector2(900, 1800), Vector2(-2200, -1700)],
		"spawns": [Vector2(-2300, 0), Vector2(-1200, -2100), Vector2(-1800, 1900), Vector2(300, 2300), Vector2(300, -2300)],
	},
	"greenbelt": {
		"name": "GREENBELT", "biome": "green", "field_top": 46.0, "seed": 7319, "tree_count": 9000, "water": 24.0,
		"desc": "The green zone: fields, orchards and tree lines along a river, with open desert on the plateau above. Lots of cover for the enemy.",
		"river": [Vector2(-700, -4200), Vector2(-350, -2000), Vector2(-300, -1000), Vector2(-500, 0), Vector2(-250, 1300), Vector2(-450, 2600), Vector2(-300, 4200)],
		"towns": [
			{"name": "Merin", "pos": Vector2(700, 500), "r": 230.0, "style": "village"},
			{"name": "Tarak", "pos": Vector2(-1500, -500), "r": 200.0, "style": "compound"},
			{"name": "Hollin", "pos": Vector2(1200, -1400), "r": 160.0, "style": "village"},
		],
		"roads": [
			[Vector2(-3800, -450), Vector2(-2500, -500), Vector2(-1500, -500), Vector2(-450, -150), Vector2(700, 500), Vector2(1800, 800), Vector2(3800, 1200)],
			[Vector2(700, 500), Vector2(900, -500), Vector2(1200, -1400), Vector2(1400, -3800)],
			[Vector2(700, 500), Vector2(500, 1500), Vector2(300, 3800)],
		],
		"bridges": [Vector2(-470, -140)],
		"sites": {
			"qrf": Vector2(2100, 980),
			"crash2": Vector2(1300, -900), "lz_crash2": Vector2(1500, -700), "hvt2": Vector2(720, 520), "op2": Vector2(1100, 900), "lz_sf2": Vector2(1600, 1300),
			"fob": Vector2(1500, 60), "bridge": Vector2(-300, -80), "crash": Vector2(300, -900),
			"lz_crash": Vector2(450, -1100), "op": Vector2(-1150, -250), "hvt_target": Vector2(-1500, -480),
			"lz_sf": Vector2(-850, 700), "hq": Vector2(-1480, -520),
		},
		"site_names": {"qrf": "PB OAK", "fob": "PATROL BASE LINDEN", "bridge": "THE BRIDGE"},
		"outposts": {"qrf": 60.0, "fob": 76.0, "bridge": 36.0},
		"defend": ["fob", "bridge"],
		"escort": [[0, false, 0.15, 0.85]],
		"interdict": [[0, false, 0.05, 0.55], [2, true, 0.0, 0.8]],
		"hvt": [[1, true, 0.1, 0.8]],
		"strike": [{"target": "hvt_target", "op": "op", "lz": "lz_sf"}, {"target": "hvt2", "op": "op2", "lz": "lz_sf2"}],
		"csar": [{"crash": "crash", "lz": "lz_crash"}, {"crash": "crash2", "lz": "lz_crash2"}],
		"sam": [Vector2(-1900, 900), Vector2(1900, -700), Vector2(-1000, -1900), Vector2(600, 2000)],
		"spawns": [Vector2(-2300, -1200), Vector2(-2200, 800), Vector2(2200, 1800), Vector2(1800, -2000), Vector2(0, 2300)],
	},
	"flats": {
		"name": "DUST FLATS", "biome": "desert", "seed": 905, "tree_count": 500, "flat": true,
		"desc": "Open desert with a training range. Nowhere to hide.",
		"towns": [
			{"name": "Camp Dune", "pos": Vector2(-1300, 800), "r": 120.0, "style": "village"},
			{"name": "Old Fort", "pos": Vector2(1400, -1100), "r": 95.0, "style": "compound"},
		],
		"roads": [
			[Vector2(-3800, 800), Vector2(-1300, 800), Vector2(0, 0), Vector2(1400, -1100), Vector2(3800, -1500)],
			"loop:300,200,210",
		],
		"sites": {
			"qrf": Vector2(-2300, 900),
			"range": Vector2(300, 200), "camp": Vector2(-1200, 650), "crash": Vector2(900, 900),
			"lz_crash": Vector2(1100, 780), "op": Vector2(1000, -700), "hvt_target": Vector2(1400, -1080),
			"lz_sf": Vector2(600, -1500), "hq": Vector2(1380, -1100),
		},
		"site_names": {"qrf": "CAMP SCORPION", "camp": "CAMP DUNE", "range": "RANGE 4"},
		"outposts": {"qrf": 60.0, "camp": 64.0},
		"defend": ["camp"],
		"escort": [[0, true, 0.1, 0.7]],
		"interdict": [[0, false, 0.15, 0.6]],
		"hvt": [[0, false, 0.1, 0.62]],
		"strike": [{"target": "hvt_target", "op": "op", "lz": "lz_sf"}],
		"csar": [{"crash": "crash", "lz": "lz_crash"}],
		"sam": [Vector2(-1500, -900), Vector2(1600, 600), Vector2(0, 1700), Vector2(-200, -1800)],
		"spawns": [Vector2(-2300, -500), Vector2(2300, 400), Vector2(500, 2300), Vector2(-500, -2300), Vector2(2200, -2000)],
	},
	"lowtown": {
		"name": "MIRZABAD", "biome": "urban", "seed": 6660, "tree_count": 2500,
		"desc": "A city laid out in a grid in a mountain basin. Long straight streets, rooftops and a lot of places for things to come from.",
		"towns": [
			{"name": "Mirzabad", "pos": Vector2(0, 0), "r": 1150.0, "style": "mixed", "ang": 0.0},
		],
		"roads": [
			"grid:0,0,1350,160",
			[Vector2(-3800, 0), Vector2(3800, 0)],
			[Vector2(0, -3800), Vector2(0, 3800)],
		],
		"sites": {
			"qrf": Vector2(-1600, 120),
			"hospital": Vector2(80, 80), "school": Vector2(720, -560), "mall": Vector2(-720, 720),
			"crash": Vector2(900, 800), "lz_crash": Vector2(1050, 650), "op": Vector2(-450, -450),
			"hvt_target": Vector2(-800, -720), "lz_sf": Vector2(500, 900), "hq": Vector2(-800, -720),
		},
		"site_names": {"qrf": "FORT ASH", "hospital": "MERCY GENERAL", "school": "WESTFIELD HIGH", "mall": "THE MALL"},
		"outposts": {"qrf": 60.0, "hospital": 70.0, "school": 56.0, "mall": 60.0},
		"defend": ["hospital", "school", "mall"],
		"escort": [[1, false, 0.28, 0.74]],
		"interdict": [[2, true, 0.22, 0.55]],
		"hvt": [[1, false, 0.25, 0.6]],
		"strike": [{"target": "hvt_target", "op": "op", "lz": "lz_sf"}],
		"csar": [{"crash": "crash", "lz": "lz_crash"}],
		"sam": [Vector2(-1500, -1500), Vector2(1500, 1500), Vector2(1600, -1300)],
		"spawns": [Vector2(-1800, 0), Vector2(1800, 0), Vector2(0, 1800), Vector2(0, -1800), Vector2(1300, 1300), Vector2(-1300, -1300)],
	},
}

const ORDER := ["kharim", "ridge", "port", "greenbelt", "flats", "lowtown"]


static func get_map(id: String) -> Dictionary:
	var key := id if MAPS.has(id) else "kharim"
	var m: Dictionary = MAPS[key].duplicate()
	m["id"] = key
	return m


static func site_name(m: Dictionary, site: String) -> String:
	return m.get("site_names", {}).get(site, site.to_upper().replace("_", " "))
