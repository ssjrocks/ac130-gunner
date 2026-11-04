extends RefCounted
## Static game data: weapons, support calls, optics, view modes and ranks.

# Gun and onboard weapon definitions.
# rate: rounds per second, disp: dispersion in milliradians, pen: armour
# penetration class (armour 0 soft, 1 light, 2 medium, 3 heavy).
const WEAPONS := {
	"w_762": {
		"name": "GAU-2/A 7.62mm MINIGUN", "short": "7.62", "rate": 40.0, "mag": 1000, "reload": 5.0,
		"speed": 850.0, "disp": 0.55, "dmg": 40.0, "radius": 2.2, "pen": 0, "tracer": 4,
		"fx": "small", "shake": 0.03, "sound": "mg", "reticle": "cross",
	},
	"w_30": {
		"name": "GAU-23/A 30mm CANNON", "short": "30mm", "rate": 3.3, "mag": 60, "reload": 5.0,
		"speed": 1000.0, "disp": 0.45, "dmg": 120.0, "radius": 4.0, "pen": 2, "tracer": 1,
		"fx": "medium", "shake": 0.12, "sound": "c30", "reticle": "bracket",
	},
	"w_40": {
		"name": "L/60 BOFORS 40mm", "short": "40mm", "rate": 2.0, "mag": 32, "reload": 6.0,
		"speed": 880.0, "disp": 0.5, "dmg": 190.0, "radius": 7.0, "pen": 2, "tracer": 1,
		"fx": "medium", "shake": 0.25, "sound": "c40", "reticle": "bracket",
	},
	"w_105": {
		"name": "M102 105mm HOWITZER", "short": "105mm", "rate": 10.0, "mag": 1, "reload": 4.5,
		"speed": 520.0, "disp": 0.35, "dmg": 1300.0, "radius": 20.0, "pen": 4, "tracer": 1,
		"fx": "large", "shake": 1.0, "sound": "c105", "reticle": "circle",
	},
	"w_griffin": {
		"name": "AGM-176 GRIFFIN (LASER)", "short": "GRIFFIN", "mag": 1, "reload": 7.0, "total": 8,
		"guided": "missile", "guide": "laser", "flight_speed": 330.0, "dmg": 900.0, "radius": 9.0,
		"pen": 4, "fx": "large", "shake": 0.2, "sound": "launch", "reticle": "diamond", "rate": 10.0,
	},
	"w_lgb": {
		"name": "GBU-39 SDB (LASER)", "short": "SDB", "mag": 1, "reload": 12.0, "total": 4,
		"guided": "bomb", "guide": "laser", "tot": 22.0, "dmg": 2600.0, "radius": 32.0,
		"pen": 5, "fx": "bomb", "shake": 0.1, "sound": "reload", "reticle": "diamond", "rate": 10.0,
	},
}
const WEAPON_ORDER := ["w_762", "w_30", "w_40", "w_105", "w_griffin", "w_lgb"]

# Off-board support ("call-ins"). guide gps = fixed point, laser = follows the spot.
const SUPPORT := {
	"s_hellfire": {
		"name": "MQ-9 HELLFIRE", "short": "HELLFIRE", "guide": "laser", "kind": "missile", "tot": 9.0,
		"dmg": 950.0, "radius": 8.0, "pen": 4, "fx": "large", "count": 1, "charges": 3,
		"radio": "Reaper copies, Hellfire off the rail, time of flight %d seconds. Keep your sparkle on it.",
	},
	"s_jdam": {
		"name": "F/A-18 JDAM (GPS)", "short": "JDAM", "guide": "gps", "kind": "bomb", "tot": 26.0,
		"dmg": 3200.0, "radius": 45.0, "pen": 5, "fx": "bomb", "count": 2, "spread": 22.0, "charges": 2,
		"radio": "Hornet 2-1, two JDAMs on the coordinates, impact in %d seconds.",
	},
	"s_lgb18": {
		"name": "F/A-18 GBU-12 (LASER)", "short": "GBU-12", "guide": "laser", "kind": "bomb", "tot": 24.0,
		"dmg": 2800.0, "radius": 38.0, "pen": 5, "fx": "bomb", "count": 1, "charges": 2,
		"radio": "Hornet 2-2, GBU-12 away, %d seconds. Laser on in ten.",
	},
	"s_tomahawk": {
		"name": "TLAM CRUISE MISSILE", "short": "TOMAHAWK", "guide": "gps", "kind": "cruise", "tot": 55.0,
		"dmg": 6000.0, "radius": 65.0, "pen": 5, "fx": "huge", "count": 1, "charges": 1,
		"radio": "Destroyer Halsey confirms launch. Tomahawk inbound, time on target %d seconds.",
	},
	"s_illum": {
		"name": "ILLUMINATION ROUND", "short": "ILLUM", "guide": "gps", "kind": "illum", "tot": 6.0,
		"dmg": 0.0, "radius": 0.0, "pen": 0, "fx": "", "count": 1, "charges": 4,
		"radio": "Illumination round out, %d seconds.",
	},
}
const SUPPORT_ORDER := ["s_hellfire", "s_jdam", "s_lgb18", "s_tomahawk", "s_illum"]

# Sensor view modes: 0 TV, 1 NV, 2 white-hot thermal, 3 black-hot thermal.
const MODE_NAMES := ["TV", "NV", "WHT", "BHT"]

const OPTICS := {"o_base": 25.0, "o_60": 60.0, "o_150": 150.0}

# Everything that can be unlocked, with a readable name for the career page.
const UNLOCK_NAMES := {
	"w_762": "GAU-2/A 7.62mm minigun",
	"w_30": "GAU-23/A 30mm cannon",
	"w_40": "L/60 Bofors 40mm cannon",
	"w_105": "M102 105mm howitzer",
	"w_griffin": "AGM-176 Griffin laser missiles",
	"w_lgb": "GBU-39 laser-guided bombs",
	"v_nv": "Night vision sensor",
	"v_ir": "Thermal imager (white/black hot)",
	"o_60": "Improved optics (60x)",
	"o_150": "Hi-mag turret (150x)",
	"laser": "Laser target designator",
	"s_hellfire": "MQ-9 Reaper Hellfire strike",
	"s_jdam": "F/A-18 JDAM strike (GPS)",
	"s_lgb18": "F/A-18 GBU-12 strike (laser)",
	"s_tomahawk": "Tomahawk cruise missile",
	"s_illum": "Illumination rounds",
}

const RANKS := [
	{"name": "Airman", "abbr": "AMN", "xp": 0, "unlocks": ["w_762"]},
	{"name": "Airman First Class", "abbr": "A1C", "xp": 1200, "unlocks": ["v_nv", "w_30"]},
	{"name": "Senior Airman", "abbr": "SRA", "xp": 3500, "unlocks": ["o_60", "laser", "s_hellfire"]},
	{"name": "Staff Sergeant", "abbr": "SSGT", "xp": 7000, "unlocks": ["w_40", "v_ir"]},
	{"name": "Technical Sergeant", "abbr": "TSGT", "xp": 12000, "unlocks": ["w_105", "s_jdam"]},
	{"name": "Master Sergeant", "abbr": "MSGT", "xp": 19000, "unlocks": ["w_lgb", "s_lgb18", "s_illum"]},
	{"name": "Senior Master Sergeant", "abbr": "SMSGT", "xp": 28000, "unlocks": ["o_150", "w_griffin"]},
	{"name": "Chief Master Sergeant", "abbr": "CMSGT", "xp": 40000, "unlocks": ["s_tomahawk"]},
]

const DIFFICULTY := [
	{"name": "RECRUIT", "enemy": 0.7, "acc": 0.7, "aa": 0.6, "plane_dmg": 0.6, "xp": 0.8, "auto_flares": true},
	{"name": "REGULAR", "enemy": 1.0, "acc": 1.0, "aa": 1.0, "plane_dmg": 1.0, "xp": 1.0, "auto_flares": false},
	{"name": "VETERAN", "enemy": 1.35, "acc": 1.25, "aa": 1.4, "plane_dmg": 1.3, "xp": 1.4, "auto_flares": false},
]


static func all_unlocks() -> Array:
	return UNLOCK_NAMES.keys()
