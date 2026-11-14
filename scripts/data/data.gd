extends RefCounted
## Static game data: weapons, support calls, optics, view modes and ranks.

# Gun and onboard weapon definitions.
# rate: rounds per second, disp: dispersion in milliradians, pen: armour
# penetration class (armour 0 soft, 1 light, 2 medium, 3 heavy).
const WEAPONS := {
	"w_762": {
		"name": "GAU-2/A 7.62mm MINIGUN", "short": "7.62", "rate": 40.0, "mag": 1000, "reload": 5.0,
		"speed": 850.0, "disp": 0.55, "dmg": 40.0, "radius": 2.2, "pen": 0, "tracer": 4,
		"fx": "small", "shake": 0.0, "sound": "mg", "reticle": "cross",
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
	"w_20": {
		"name": "M61A1 VULCAN 20mm", "short": "20mm", "rate": 50.0, "mag": 300, "reload": 6.0,
		"speed": 1030.0, "disp": 0.65, "dmg": 65.0, "radius": 2.8, "pen": 1, "tracer": 5,
		"fx": "small", "shake": 0.0, "sound": "mg", "loop": true, "reticle": "cross",
	},
	"w_25": {
		"name": "GAU-12/U EQUALIZER 25mm", "short": "25mm", "rate": 15.0, "mag": 150, "reload": 6.0,
		"speed": 1050.0, "disp": 0.4, "dmg": 95.0, "radius": 3.2, "pen": 2, "tracer": 3,
		"fx": "small", "shake": 0.05, "sound": "c30", "reticle": "bracket",
	},
	"w_127": {
		"name": "M2 .50 CAL DOOR GUN", "short": ".50 CAL", "rate": 10.0, "mag": 400, "reload": 6.0,
		"speed": 890.0, "disp": 0.22, "dmg": 60.0, "radius": 1.2, "pen": 1, "tracer": 5,
		"fx": "small", "shake": 0.0, "sound": "mg", "loop": true, "reticle": "cross",
	},
	# airburst: the fuze sets the round off this many metres above the ground,
	# so it reaches men in ditches and behind low walls, but barely scratches armour
	"w_40ab": {
		"name": "40mm PROXIMITY AIRBURST", "short": "40mm AB", "rate": 2.0, "mag": 24, "reload": 6.0,
		"speed": 880.0, "disp": 0.5, "dmg": 150.0, "radius": 12.0, "pen": 0, "tracer": 1, "airburst": 3.0,
		"fx": "flak", "shake": 0.25, "sound": "c40", "reticle": "bracket",
	},
	"w_105ab": {
		"name": "105mm AIRBURST (M732 FUZE)", "short": "105 AB", "rate": 10.0, "mag": 1, "reload": 5.0,
		"speed": 520.0, "disp": 0.35, "dmg": 650.0, "radius": 32.0, "pen": 1, "tracer": 1, "airburst": 9.0,
		"fx": "flak", "shake": 1.0, "sound": "c105", "reticle": "circle",
	},
	"w_hellfire": {
		"name": "AGM-114 HELLFIRE (LASER)", "short": "HELLFIRE", "mag": 1, "reload": 6.0, "total": 6,
		"guided": "missile", "guide": "laser", "flight_speed": 420.0, "dmg": 3000.0, "radius": 6.0,
		"pen": 5, "fx": "large", "shake": 0.2, "sound": "launch", "reticle": "diamond", "rate": 10.0,
	},
	"w_viper": {
		"name": "GBU-44 VIPER STRIKE (LASER)", "short": "VIPER", "mag": 1, "reload": 9.0, "total": 6,
		"guided": "bomb", "guide": "laser", "tot": 14.0, "dmg": 1100.0, "radius": 11.0,
		"pen": 4, "fx": "large", "shake": 0.1, "sound": "reload", "reticle": "diamond", "rate": 10.0,
	},
	# a high-energy laser: hits the instant you fire, silently, and burns what
	# it's held on. "mag" is the charge, ten pulses a second, then it recharges
	"w_atl": {
		"name": "ADVANCED TACTICAL LASER", "short": "ATL LASER", "beam": true, "rate": 10.0, "mag": 100, "reload": 25.0,
		"speed": 1.0e9, "disp": 0.0, "dmg": 45.0, "radius": 1.6, "pen": 3, "tracer": 0,
		"fx": "", "shake": 0.0, "sound": "", "reticle": "cross",
	},
}
const WEAPON_ORDER := ["w_762", "w_127", "w_20", "w_25", "w_30", "w_40", "w_40ab", "w_105", "w_105ab",
	"w_griffin", "w_hellfire", "w_viper", "w_lgb", "w_atl"]

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
	# placement "line": a strafe line on the ground, rotated with the wheel
	"s_a10": {
		"name": "A-10 GUN RUN", "short": "A-10 GUN RUN", "kind": "gunrun", "placement": "line", "len": 300.0, "tot": 16.0,
		"dmg": 200.0, "radius": 5.5, "pen": 3, "speed": 1000.0, "fx": "medium", "tracer": 3, "charges": 2,
		"radio": "Hawg 1-1, one A-10, guns, inbound along your line. Rounds on the ground in %d seconds.",
	},
	"s_sof": {
		"name": "SHOW OF FORCE", "short": "SHOW OF FORCE", "kind": "sof", "placement": "line", "len": 1400.0, "tot": 12.0,
		"charges": 3, "radio": "Viper 2-1 copies show of force, low pass along your line in %d seconds.",
	},
	"s_qrf": {
		"name": "GROUND QRF (PLATOON)", "short": "QRF PLATOON", "kind": "qrf", "placement": "point", "tot": 0.0, "charges": 1,
		"radio": "",
	},
	"s_heli": {
		"name": "BLACK HAWK INSERTION (SQUAD)", "short": "HELO SQUAD", "kind": "heli", "placement": "point", "tot": 0.0, "charges": 2,
		"radio": "",
	},
	# never runs out: "cooldown" seconds between calls instead of charges
	"s_arty": {
		"name": "85mm ARTILLERY BARRAGE", "short": "85mm ARTY", "guide": "gps", "kind": "shell", "tot": 26.0,
		"dmg": 520.0, "radius": 16.0, "pen": 3, "fx": "large", "count": 8, "scatter": 45.0, "stagger": 0.6,
		"cooldown": 60.0, "radio": "Gun line copies, battery eight rounds, splash in %d seconds.",
	},
	"s_gmlrs": {
		"name": "GMLRS ROCKET (GPS)", "short": "GMLRS", "guide": "gps", "kind": "rocket", "tot": 40.0,
		"dmg": 2400.0, "radius": 28.0, "pen": 5, "fx": "bomb", "count": 1, "charges": 2,
		"radio": "Steel Rain, one rocket on the grid, time of flight %d seconds.",
	},
	# sensor-fuzed: each of ten skeets finds a vehicle; men on foot are barely touched
	"s_cbu": {
		"name": "CBU-97 SENSOR FUZED (ANTI-ARMOUR)", "short": "CBU-97", "guide": "gps", "kind": "cbu", "tot": 24.0,
		"dmg": 1800.0, "radius": 160.0, "pen": 5, "fx": "medium", "count": 1, "charges": 1, "skeets": 10,
		"radio": "Viper 2-2, CBU-97 on the grid, %d seconds. Vehicles only.",
	},
	# smoke: blocks everyone's sight lines through the cloud for a minute and a half
	"s_smoke": {
		"name": "SMOKE SCREEN (MORTAR)", "short": "SMOKE", "guide": "gps", "kind": "smoke", "tot": 18.0,
		"dmg": 0.0, "radius": 0.0, "pen": 0, "fx": "", "count": 4, "scatter": 40.0, "stagger": 0.8, "charges": 3,
		"duration": 90.0, "radio": "Mortars copy, smoke on the grid, %d seconds.",
	},
	# a Black Hawk from the nearest outpost lifts out the wounded near the
	# point; on the way it drops off healed men going back to their unit
	"s_medevac": {
		"name": "MEDEVAC (DUSTOFF)", "short": "MEDEVAC", "kind": "medevac", "placement": "point", "tot": 0.0, "cooldown": 45.0,
		"radio": "",
	},
	"s_switchblade": {
		"name": "SWITCHBLADE 600 (LOITERING)", "short": "SWITCHBLADE", "guide": "laser", "kind": "missile", "tot": 12.0,
		"dmg": 3000.0, "radius": 7.0, "pen": 5, "fx": "large", "count": 1, "charges": 3,
		"radio": "Switchblade launched from the team, %d seconds. It'll ride your sparkle.",
	},
}
const SUPPORT_ORDER := ["s_hellfire", "s_jdam", "s_lgb18", "s_tomahawk", "s_illum", "s_a10", "s_sof", "s_qrf", "s_heli",
	"s_arty", "s_gmlrs", "s_cbu", "s_smoke", "s_switchblade", "s_medevac"]

# How many weapons and how many call-ins a loadout can carry (one per number key).
const LOADOUT_SLOTS := 9
# Before the player picks: the long-standing set on its usual keys, then
# anything newer that's unlocked fills the spare slots.
const DEFAULT_LOADOUT := {
	"w": ["w_762", "w_30", "w_40", "w_105", "w_griffin", "w_lgb"],
	"s": ["s_hellfire", "s_jdam", "s_lgb18", "s_medevac", "s_illum", "s_a10", "s_sof", "s_qrf", "s_heli"],
}

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
	"w_20": "M61A1 Vulcan 20mm cannon",
	"w_25": "GAU-12/U Equalizer 25mm cannon",
	"w_127": "M2 .50 cal door gun",
	"w_40ab": "40mm proximity airburst rounds",
	"w_105ab": "105mm airburst rounds",
	"w_hellfire": "AGM-114 Hellfire laser missiles",
	"w_viper": "GBU-44 Viper Strike glide bombs",
	"w_atl": "Advanced Tactical Laser",
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
	"s_sof": "Show of force (low jet pass)",
	"s_heli": "Black Hawk squad insertion",
	"s_a10": "A-10 gun run",
	"s_qrf": "Ground QRF platoon",
	"s_arty": "85mm artillery barrage",
	"s_gmlrs": "GMLRS rocket strike (GPS)",
	"s_cbu": "CBU-97 sensor-fuzed anti-armour bomb",
	"s_smoke": "Smoke screen",
	"s_switchblade": "Switchblade loitering munition",
	"s_medevac": "Medevac helicopter",
}

# One line on what each weapon and call-in is for, for the loadout screen.
const DESC := {
	"w_762": "Fast and precise. Infantry in the open; does nothing to armour.",
	"w_127": "Very accurate door gun. Picks off men without hitting the people next to them.",
	"w_20": "Huge rate of fire. Hoses down groups and soft vehicles.",
	"w_25": "Fast-firing cannon. Shreds technicals and trucks.",
	"w_30": "Accurate cannon with a punch. Light armour and men behind cover.",
	"w_40": "Heavy rounds. Vehicles, APCs and buildings.",
	"w_40ab": "Bursts above the ground. Men in ditches and behind walls; no use on armour.",
	"w_105": "The big gun. Tanks, buildings, anything.",
	"w_105ab": "Airburst 105. Clears a large area of infantry; barely touches armour.",
	"w_griffin": "Small laser missile. Precise kills with little collateral.",
	"w_hellfire": "Laser anti-tank missile. Kills any vehicle; keep the laser on it.",
	"w_viper": "Small laser glide bomb. Precise, a modest blast, 14 seconds to land.",
	"w_lgb": "Laser-guided bomb. Flattens a compound.",
	"w_atl": "High-energy laser. Hits the instant you fire, silent, burns through vehicles. Recharges.",
	"s_hellfire": "A Reaper's Hellfire on your laser spot.",
	"s_jdam": "Two 2,000 lb bombs on the coordinates. Danger close is a long way.",
	"s_lgb18": "A laser-guided 500 lb bomb from a Hornet.",
	"s_tomahawk": "A cruise missile. Takes a minute, flattens a block.",
	"s_illum": "A flare on a parachute that lights the ground at night.",
	"s_a10": "An A-10 strafes along a line you set with the wheel.",
	"s_sof": "A jet roars low along your line. Enemies and civilians scatter.",
	"s_qrf": "A platoon drives out from the outpost to your point.",
	"s_heli": "A Black Hawk drops a squad at your point.",
	"s_arty": "Eight 85mm rounds over the area, as slow as a JDAM. Never runs out: one minute to reload.",
	"s_gmlrs": "A GPS rocket from a launcher far away. Big blast, 40 seconds.",
	"s_cbu": "Each skeet hunts a vehicle in a wide area. Any vehicle, so check for friendlies.",
	"s_smoke": "A smoke screen that blocks everyone's sight lines through it for a minute and a half.",
	"s_switchblade": "A loitering munition from the ground team that rides your laser. Quick to arrive.",
	"s_medevac": "Lifts the wounded near the point back to an outpost to be patched up. Healed men ride the next one back out. 45 s between calls.",
}

const RANKS := [
	{"name": "Airman", "abbr": "AMN", "xp": 0, "unlocks": ["w_762"]},
	{"name": "Airman First Class", "abbr": "A1C", "xp": 1200, "unlocks": ["v_nv", "w_30", "s_sof", "w_127", "s_medevac"]},
	{"name": "Senior Airman", "abbr": "SRA", "xp": 3500, "unlocks": ["o_60", "laser", "s_hellfire", "s_heli", "w_20", "s_smoke"]},
	{"name": "Staff Sergeant", "abbr": "SSGT", "xp": 7000, "unlocks": ["w_40", "v_ir", "s_a10", "w_25", "s_arty"]},
	{"name": "Technical Sergeant", "abbr": "TSGT", "xp": 12000, "unlocks": ["w_105", "s_jdam", "s_qrf", "w_40ab"]},
	{"name": "Master Sergeant", "abbr": "MSGT", "xp": 19000, "unlocks": ["w_lgb", "s_lgb18", "s_illum", "w_hellfire", "s_switchblade"]},
	{"name": "Senior Master Sergeant", "abbr": "SMSGT", "xp": 28000, "unlocks": ["o_150", "w_griffin", "w_105ab", "s_gmlrs"]},
	{"name": "Chief Master Sergeant", "abbr": "CMSGT", "xp": 40000, "unlocks": ["s_tomahawk", "w_viper", "s_cbu"]},
	{"name": "Command Chief Master Sergeant", "abbr": "CCM", "xp": 60000, "unlocks": ["w_atl"]},
]

const DIFFICULTY := [
	{"name": "RECRUIT", "enemy": 0.55, "acc": 0.5, "aa": 0.5, "plane_dmg": 0.5, "xp": 0.8, "auto_flares": true},
	{"name": "REGULAR", "enemy": 0.8, "acc": 0.75, "aa": 0.85, "plane_dmg": 0.85, "xp": 1.0, "auto_flares": false},
	{"name": "VETERAN", "enemy": 1.15, "acc": 1.05, "aa": 1.2, "plane_dmg": 1.15, "xp": 1.4, "auto_flares": false},
]


static func all_unlocks() -> Array:
	return UNLOCK_NAMES.keys()
