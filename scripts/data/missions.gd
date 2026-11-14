extends RefCounted
## Campaign missions and the generator for skirmish, survival and last stand.

const CAMPAIGN_NAME := "AFGHANISTAN"
const Maps := preload("res://scripts/data/maps.gd")

const CHAPTERS := ["QUALIFICATION", "NIGHT SHIFT", "HEAVY METAL", "BLACK OPS", "OUTBREAK", "LAST ORBIT",
	"DUST AND IRON", "HIGH GROUND", "HARBOR LIGHTS", "RIVER WAR", "OUTBREAK II", "ENDGAME"]

const TYPE_NAMES := {
	"cas": "Close Air Support", "escort": "Convoy Escort", "interdict": "Convoy Interdiction",
	"strike": "Coordinated Strike", "csar": "Combat Rescue", "sam": "SAM Hunt", "hvt": "HVT Hunt",
	"zombie": "Outbreak", "laststand": "Last Stand", "survival": "Survival", "range": "Range",
}
const SKIRMISH_TYPES := ["cas", "escort", "interdict", "strike", "csar", "sam", "hvt", "zombie"]
const TIMES := ["day", "dusk", "night"]

const CAMPAIGN := [
	{"id": "c01", "chapter": 0, "name": "Range Day", "map": "flats", "time": "day", "type": "range", "xp": 400, "only": ["w_762"],
		"brief": "Your first sortie as sensor operator aboard Spectre 21. Qualify on the GAU-2/A minigun against target hulks on Range 4. Learn to find targets from 10,000 feet, zoom in, and lead moving vehicles: your rounds take seconds to land."},
	{"id": "c02", "chapter": 0, "name": "First Light", "map": "kharim", "time": "day", "type": "cas", "site": "checkpoint", "level": 1.0,
		"duration": 300.0, "interval": 80.0, "friendlies": 8, "friendly_vehicles": 1, "armor": 0, "civ": 0.5, "xp": 700, "grants": ["v_nv"],
		"brief": "Dawn over Kharim Valley. A squad at Checkpoint 7 is taking fire from the town. Find the enemy among the compounds and keep the checkpoint alive until the QRF arrives. Civilians are in the streets: positive ID before you shoot."},
	{"id": "c03", "chapter": 0, "name": "Highway Watch", "map": "kharim", "time": "day", "type": "interdict", "route": [1, true, 0.0, 0.85], "level": 2.0,
		"max_escape": 2, "civ": 0.5, "armor": 0, "xp": 800, "grants": ["w_30"],
		"brief": "An insurgent convoy is driving south toward Kharim, mixed in with civilian traffic. Stop it before it reaches the town. Technicals carry gunners; trucks carry fighters who scatter when hit."},
	{"id": "c04", "chapter": 1, "name": "Dark Orbit", "map": "ridge", "time": "night", "type": "cas", "site": "cop", "level": 2.0,
		"duration": 360.0, "interval": 70.0, "friendlies": 12, "armor": 0, "civ": 0.3, "xp": 1000, "grants": ["laser", "s_hellfire"], "loadout_add": ["v_nv"],
		"brief": "Night over Ridge 471. COP Hawk is about to be hit from the mountains. Switch to night vision with V. Friendly troops wear IR strobes that blink in night vision."},
	{"id": "c05", "chapter": 1, "name": "Shepherd", "map": "port", "time": "dusk", "type": "escort", "route": [1, false, 0.25, 1.0], "level": 2.0,
		"civ": 0.6, "supports": {"s_hellfire": 2}, "xp": 1200, "grants": ["o_60"],
		"brief": "Roadrunner 2-6 is moving a VIP through Qala Bandar to the docks. Scout the route ahead, break up ambushes and keep the MRAP alive. The orbit follows the convoy; press O to move it yourself. Use your laser (right mouse) to guide the Reaper's Hellfire."},
	{"id": "c06", "chapter": 1, "name": "Hornet's Nest", "map": "kharim", "time": "night", "type": "laststand", "site": "fob", "waves": 5, "level": 2.0,
		"aa": 1, "friendlies": 14, "civ": 0.2, "armor": 0, "supports": {"s_hellfire": 2}, "xp": 1300, "grants": ["w_40"],
		"brief": "FOB Anvil will be attacked tonight in waves. Hold for five. Expect shoulder-fired missiles: on a launch warning press F for flares. Climbing (PgUp) keeps you above most of them but spreads your rounds."},
	{"id": "c07", "chapter": 2, "name": "Thermal Crossing", "map": "greenbelt", "time": "night", "type": "interdict", "route": [0, false, 0.05, 0.55], "level": 3.0,
		"max_escape": 2, "civ": 0.3, "aa": 1, "xp": 1500, "loadout_add": ["v_ir"], "grants": ["v_ir"],
		"brief": "Enemy vehicles are crossing the river bridge under cover of the tree lines. You've been fitted with a thermal imager: white-hot and black-hot show hot engines and bodies through the dark. Stop them before they reach Merin."},
	{"id": "c08", "chapter": 2, "name": "Iron Rain", "map": "ridge", "time": "day", "type": "cas", "site": "cop", "level": 4.0, "armor": 2,
		"duration": 420.0, "interval": 65.0, "friendlies": 14, "friendly_vehicles": 2, "civ": 0.2, "supports": {"s_hellfire": 3},
		"xp": 1800, "loadout_add": ["w_105"], "grants": ["w_105", "s_jdam"],
		"brief": "An armored column with BTRs and tanks is pushing down the valley toward COP Hawk. You have the 105 tonight. It takes several seconds to land, so pick your shots and lead the vehicles."},
	{"id": "c09", "chapter": 2, "name": "Broken Arrow", "map": "kharim", "time": "night", "type": "csar", "csar": {"crash": "crash", "lz": "lz_crash"}, "level": 2.0, "duration": 240.0, "aa": 1,
		"civ": 0.2, "supports": {"s_hellfire": 2, "s_jdam": 1}, "xp": 1800, "grants": ["w_lgb"],
		"brief": "A helicopter went down west of Kharim. Two crew survived, and every fighter in the valley is heading for the wreck. Keep them alive until Pedro 6-6 can land, and make sure the LZ is clear when it does."},
	{"id": "c10", "chapter": 3, "name": "Painted Target", "map": "kharim", "time": "night", "type": "strike", "strike": {"target": "hvt_target", "op": "op", "lz": "lz_sf"}, "window": 150.0, "level": 3.0,
		"civ": 0.3, "supports": {"s_hellfire": 2, "s_jdam": 1, "s_lgb18": 1}, "xp": 2200, "loadout_add": ["s_lgb18"], "grants": ["s_lgb18"],
		"brief": "Viking 3-1, a special forces team, is hidden 400 meters from a compound in Dashti, lasing an HVT's vehicle. Destroy it with guns or ride their laser with guided weapons. Then cover their run to the LZ."},
	{"id": "c11", "chapter": 3, "name": "SAM Alley", "map": "ridge", "time": "night", "type": "sam", "sites": 3, "level": 3.0, "flares": 40,
		"supports": {"s_jdam": 2, "s_hellfire": 2}, "xp": 2400, "grants": ["s_illum"],
		"brief": "Three SAM sites have closed the valley to air traffic. Find and kill the launchers; intel only has rough locations. SAMs reach any altitude: watch for launches and use flares."},
	{"id": "c12", "chapter": 3, "name": "Needle", "map": "port", "time": "day", "type": "hvt", "route": [0, true, 0.1, 0.55], "level": 2.0,
		"civ": 0.9, "max_civ": 3, "supports": {"s_hellfire": 2}, "xp": 2400, "grants": ["o_150", "w_griffin"],
		"brief": "A bomb-maker is leaving Qala Bandar in a white pickup with two technicals as escort. There are a lot of white pickups out there. Find the right one and kill it: three civilian casualties ends the mission."},
	{"id": "c13", "chapter": 4, "name": "Patient Zero", "map": "lowtown", "time": "dusk", "type": "zombie", "site": "hospital", "duration": 360.0,
		"survivors": 12, "min_survivors": 4, "civ": 0.0, "supports": {"s_hellfire": 2, "s_jdam": 1}, "xp": 2500, "grants": [],
		"brief": "Something has gone very wrong in Mirzabad. Twelve survivors are holed up in Mercy General and the dead are walking. Keep the hordes off the hospital until the evac helicopter arrives. Whatever this is runs them hot: on thermal they burn brighter than the living, and they sprint."},
	{"id": "c14", "chapter": 4, "name": "Dead City", "map": "lowtown", "time": "night", "type": "zombie", "site": "school", "duration": 480.0,
		"survivors": 14, "min_survivors": 5, "civ": 0.0, "supports": {"s_jdam": 2, "s_hellfire": 3, "s_illum": 3}, "xp": 3000, "grants": ["s_tomahawk"],
		"brief": "Night. A second group is trapped at Westfield High. The horde is bigger and some of them are much bigger. Use illumination rounds, use everything."},
	{"id": "c15", "chapter": 5, "name": "Long Reach", "map": "greenbelt", "time": "night", "type": "strike", "strike": {"target": "hvt_target", "op": "op", "lz": "lz_sf"}, "window": 120.0, "level": 4.0, "aa": 1,
		"civ": 0.3, "supports": {"s_tomahawk": 1, "s_jdam": 2, "s_lgb18": 1}, "xp": 3200, "loadout_add": ["s_tomahawk"], "grants": [],
		"brief": "Viking 3-1 has found the enemy commander at Tarak. A Tomahawk is available from the destroyer offshore, nearly a minute out. Time it right, then get Viking out through heavy pursuit."},
	{"id": "c16", "chapter": 5, "name": "Final Orbit", "map": "port", "time": "night", "type": "laststand", "site": "base", "waves": 8, "level": 3.0,
		"aa": 2, "armor": 2, "friendlies": 16, "flares": 45, "civ": 0.1,
		"supports": {"s_tomahawk": 1, "s_jdam": 3, "s_hellfire": 3, "s_lgb18": 2, "s_illum": 3}, "xp": 5000, "grants": [],
		"brief": "Everything the enemy has left is coming for Camp Sentinel. Eight waves, armor and missile teams. Hold the camp."},
	# --- Chapter 7: desert -------------------------------------------------------
	{"id": "c17", "chapter": 6, "name": "Sandstorm", "map": "kharim", "time": "day", "weather": "dust", "type": "cas", "site": "checkpoint",
		"level": 3.0, "duration": 360.0, "interval": 70.0, "friendlies": 10, "armor": 1, "civ": 0.3, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3200,
		"brief": "A dust storm has rolled into Kharim Valley and the enemy is using it. Checkpoint 7 is under attack again and you can barely see the ground. Thermal cuts through dust better than TV."},
	{"id": "c18", "chapter": 6, "name": "Wadi Run", "map": "flats", "time": "dusk", "type": "escort", "route": [0, true, 0.1, 0.7],
		"level": 3.0, "aa": 1, "civ": 0.2, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3200,
		"brief": "A supply convoy has to cross the Dust Flats at last light. There's no cover out there, for them or for the ambushers. Find the ambush teams before Roadrunner drives into them."},
	{"id": "c19", "chapter": 6, "name": "Old Fort", "map": "flats", "time": "night", "type": "strike", "strike": {"target": "hvt_target", "op": "op", "lz": "lz_sf"},
		"window": 120.0, "level": 3.0, "aa": 1, "civ": 0.0, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3400,
		"brief": "An arms dealer is meeting buyers inside the Old Fort. Viking 3-1 is lasing his vehicle from the dunes. Kill it inside two minutes, then get Viking across open desert to the pickup."},
	{"id": "c20", "chapter": 6, "name": "Camel Road", "map": "flats", "time": "day", "weather": "haze", "type": "interdict", "route": [0, false, 0.15, 0.6],
		"level": 3.0, "max_escape": 2, "civ": 0.4, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3200,
		"brief": "A weapons convoy is crossing the flats toward the Old Fort, hiding among trade traffic in the haze. Stop it before it reaches the fort."},
	{"id": "c21", "chapter": 6, "name": "Anvil Falls", "map": "kharim", "time": "dusk", "type": "laststand", "site": "fob", "waves": 6,
		"level": 2.5, "aa": 1, "armor": 2, "friendlies": 14, "civ": 0.1, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4200,
		"brief": "They're coming for FOB Anvil again, this time with armor. Six waves. Hold the base."},
	# --- Chapter 8: mountains ------------------------------------------------------
	{"id": "c22", "chapter": 7, "name": "Switchback", "map": "ridge", "time": "day", "type": "escort", "route": [0, false, 0.2, 0.78],
		"level": 3.0, "aa": 1, "civ": 0.3, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3400,
		"brief": "Roadrunner is taking a VIP up the valley road. Every switchback is a perfect ambush spot, and the slopes above hide fighters. Clear the road ahead of them."},
	{"id": "c23", "chapter": 7, "name": "Kalay Night", "map": "ridge", "time": "night", "type": "strike", "strike": {"target": "hvt_target", "op": "op", "lz": "lz_sf"},
		"window": 150.0, "level": 3.0, "aa": 1, "civ": 0.3, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3600,
		"brief": "A commander is sleeping in Kalay tonight. Viking 3-1 has crept to within 400 meters and is lasing his vehicle. Hit it, then cover their climb out of the valley."},
	{"id": "c24", "chapter": 7, "name": "Goat Path", "map": "ridge", "time": "night", "type": "interdict", "route": [0, false, 0.1, 0.5],
		"level": 3.5, "max_escape": 2, "civ": 0.2, "aa": 1, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3600,
		"brief": "A night convoy is bringing rockets up the valley toward Sarband, lights off. Thermal will show the engines. Stop it."},
	{"id": "c25", "chapter": 7, "name": "Cold Landing", "map": "ridge", "time": "dusk", "type": "csar", "csar": {"crash": "crash2", "lz": "lz_crash2"},
		"level": 3.0, "duration": 240.0, "aa": 1, "civ": 0.2, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3600,
		"brief": "A supply helicopter went down on the valley floor east of Sarband. Two crew are hiding near the wreck. Keep the searchers away from them until Pedro gets in."},
	{"id": "c26", "chapter": 7, "name": "Eyrie", "map": "ridge", "time": "night", "type": "cas", "site": "north_post",
		"level": 3.5, "duration": 360.0, "interval": 70.0, "friendlies": 10, "armor": 1, "aa": 1, "civ": 0.2, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3800,
		"brief": "OP North is a handful of men on a spur above Sarband, and the enemy wants it back. Hold until the QRF climbs up to them."},
	# --- Chapter 9: the river port ----------------------------------------------------------
	{"id": "c27", "chapter": 8, "name": "Embassy Row", "map": "port", "time": "night", "type": "cas", "site": "embassy",
		"level": 3.0, "duration": 360.0, "interval": 70.0, "friendlies": 12, "armor": 1, "civ": 0.8, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3800,
		"brief": "A mob has turned into an assault on the Embassy in the middle of Qala Bandar. The streets are full of civilians. Pick your targets carefully."},
	{"id": "c28", "chapter": 8, "name": "Dockside", "map": "port", "time": "night", "type": "interdict",
		"level": 3.5, "max_escape": 2, "civ": 0.6, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3800,
		"brief": "A truck convoy is running weapons from the hills down to the docks for a barge waiting to cross the river. Don't let it reach the city."},
	{"id": "c29", "chapter": 8, "name": "Salt Wind", "map": "port", "time": "day", "type": "csar", "csar": {"crash": "crash2", "lz": "lz_crash2"},
		"level": 3.0, "duration": 240.0, "aa": 1, "civ": 0.4, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 3800,
		"brief": "A Navy helicopter on a border patrol went down north of the city near Marj. The crew are alive, but the town is waking up. Keep them alive until Pedro arrives."},
	{"id": "c30", "chapter": 8, "name": "Haddah", "map": "port", "time": "dusk", "type": "strike", "strike": {"target": "hvt2", "op": "op2", "lz": "lz_sf2"},
		"window": 150.0, "level": 3.0, "aa": 1, "civ": 0.4, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4000,
		"brief": "The bomb-maker's teacher is in Haddah. Viking 3-1 has eyes on his car. Kill it, then cover the team's run south to the pickup."},
	{"id": "c31", "chapter": 8, "name": "Sentinel", "map": "port", "time": "night", "type": "sam", "sites": 3, "level": 3.0, "flares": 40,
		"supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4200,
		"brief": "Three SAM batteries now cover Qala Bandar. Nothing else can fly until they're gone. Find and kill the launchers."},
	# --- Chapter 10: river ----------------------------------------------------------
	{"id": "c32", "chapter": 9, "name": "Linden", "map": "greenbelt", "time": "day", "weather": "haze", "type": "cas", "site": "fob",
		"level": 3.0, "duration": 360.0, "interval": 70.0, "friendlies": 12, "armor": 1, "civ": 0.3, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4000,
		"brief": "Patrol Base Linden is being probed from the tree lines. The orchards give the enemy plenty of cover. Hold until the QRF arrives."},
	{"id": "c33", "chapter": 9, "name": "Hold the Bridge", "map": "greenbelt", "time": "night", "type": "laststand", "site": "bridge", "waves": 6,
		"level": 2.5, "aa": 1, "armor": 2, "friendlies": 12, "civ": 0.1, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4600,
		"brief": "The bridge is the only crossing for twenty kilometers and they want it. A platoon is dug in on the east bank. Six waves."},
	{"id": "c34", "chapter": 9, "name": "Orchard", "map": "greenbelt", "time": "day", "type": "hvt", "level": 3.0, "civ": 0.9, "max_civ": 3,
		"supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4000,
		"brief": "A militia leader is driving out of Hollin in a white pickup with two technicals. Farm traffic everywhere. Positive ID, then kill it."},
	{"id": "c35", "chapter": 9, "name": "Hollin Crash", "map": "greenbelt", "time": "dusk", "type": "csar", "csar": {"crash": "crash2", "lz": "lz_crash2"},
		"level": 3.0, "duration": 240.0, "aa": 1, "civ": 0.3, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4000,
		"brief": "A drone crew's helicopter came down in the fields outside Hollin. They're hiding in a ditch and the village militia is out looking. Keep them alive."},
	{"id": "c36", "chapter": 9, "name": "Merin Road", "map": "greenbelt", "time": "night", "type": "escort",
		"level": 3.5, "aa": 1, "civ": 0.2, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4200,
		"brief": "Roadrunner is moving a VIP across the river at night. The bridge and the tree lines are both perfect for an ambush. Watch the road."},
	# --- Chapter 11: outbreak --------------------------------------------------------
	{"id": "c37", "chapter": 10, "name": "Mall Rats", "map": "lowtown", "time": "night", "type": "zombie", "site": "mall", "duration": 420.0,
		"survivors": 12, "min_survivors": 4, "civ": 0.0, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4200,
		"brief": "Another group made it to the Mall. The parking lots are wide open and the dead are coming down every street. Keep them alive until evac."},
	{"id": "c38", "chapter": 10, "name": "Quarantine", "map": "kharim", "time": "dusk", "type": "zombie", "site": "fob", "duration": 420.0,
		"survivors": 12, "min_survivors": 4, "civ": 0.0, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4200,
		"brief": "It has spread to Kharim. The town emptied, then started walking toward FOB Anvil. Hold the gates until the last helicopter out."},
	{"id": "c39", "chapter": 10, "name": "Dead Harbor", "map": "port", "time": "night", "type": "zombie", "site": "base", "duration": 450.0,
		"survivors": 14, "min_survivors": 5, "civ": 0.0, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4400,
		"brief": "Qala Bandar has fallen. Camp Sentinel is the last lit window in the city. Fourteen people are waiting for a helicopter. Keep them alive."},
	{"id": "c40", "chapter": 10, "name": "Valley of the Dead", "map": "ridge", "time": "night", "type": "zombie", "site": "cop", "duration": 450.0,
		"survivors": 12, "min_survivors": 4, "civ": 0.0, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 4400,
		"brief": "Even the mountains aren't safe. COP Hawk took in the villagers from Sarband, and the rest of Sarband is coming up the road after them."},
	{"id": "c41", "chapter": 10, "name": "Last Light", "map": "lowtown", "time": "night", "type": "laststand", "site": "hospital", "waves": 6, "enemy": "zombies", "max_ff": 6,
		"level": 2.0, "friendlies": 14, "civ": 0.0, "supports": {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_illum": 2}, "xp": 5000,
		"brief": "Mercy General again, six waves, no helicopter. Hold until dawn."},
	# --- Chapter 12: endgame ---------------------------------------------------------
	{"id": "c42", "chapter": 11, "name": "Hammer and Anvil", "map": "kharim", "time": "night", "type": "cas", "site": "fob",
		"level": 4.0, "duration": 420.0, "interval": 65.0, "friendlies": 14, "friendly_vehicles": 2, "armor": 2, "aa": 2, "civ": 0.2, "supports": {"s_hellfire": 3, "s_jdam": 3, "s_lgb18": 2, "s_tomahawk": 1, "s_illum": 3}, "xp": 5000,
		"brief": "The enemy's last armored brigade is driving on FOB Anvil, with missile teams covering it. Break it before it reaches the wire."},
	{"id": "c43", "chapter": 11, "name": "Iron Valley", "map": "ridge", "time": "day", "type": "laststand", "site": "cop", "waves": 6,
		"level": 3.0, "aa": 2, "armor": 2, "friendlies": 16, "flares": 45, "civ": 0.1, "supports": {"s_hellfire": 3, "s_jdam": 3, "s_lgb18": 2, "s_tomahawk": 1, "s_illum": 3}, "xp": 5400,
		"brief": "Everything in the mountains is coming down on COP Hawk at once. Six waves, armor and SAM teams on the slopes."},
	{"id": "c44", "chapter": 11, "name": "Cutting the Head", "map": "port", "time": "night", "type": "hvt", "level": 4.0, "civ": 0.7, "max_civ": 3,
		"supports": {"s_hellfire": 3, "s_jdam": 3, "s_lgb18": 2, "s_tomahawk": 1, "s_illum": 3}, "xp": 5000,
		"brief": "The enemy's leader is trying to slip out of Qala Bandar by road tonight in a white pickup with two technicals. This is the one we've been waiting for. Don't lose him."},
	{"id": "c45", "chapter": 11, "name": "Dragon's Teeth", "map": "greenbelt", "time": "night", "type": "sam", "sites": 4, "level": 4.0, "flares": 50,
		"supports": {"s_hellfire": 3, "s_jdam": 3, "s_lgb18": 2, "s_tomahawk": 1, "s_illum": 3}, "xp": 5400,
		"brief": "Four SAM batteries guard the river valley. Take them down and the air campaign can start."},
	{"id": "c46", "chapter": 11, "name": "Dawn Patrol", "map": "kharim", "time": "dusk", "type": "escort",
		"level": 4.5, "aa": 2, "civ": 0.3, "flares": 45, "supports": {"s_hellfire": 3, "s_jdam": 3, "s_lgb18": 2, "s_tomahawk": 1, "s_illum": 3}, "xp": 6000,
		"brief": "The last convoy of the war: the peace delegation drives from FOB Anvil to Dashti. Everyone who wants the war to go on will be waiting along the road. Get them there."},
]

const DEFAULT_SUPPORTS := {"s_hellfire": 3, "s_jdam": 2, "s_lgb18": 1, "s_tomahawk": 1, "s_illum": 3,
	"s_a10": 1, "s_sof": 2, "s_qrf": 1, "s_heli": 1, "s_arty": -1, "s_gmlrs": 2, "s_cbu": 1, "s_smoke": 3, "s_switchblade": 3}


# The newer call-ins each mission type gets on top of its own list.
const TYPE_SUPPORTS := {
	"cas": {"s_qrf": 1, "s_heli": 1, "s_sof": 1},
	"laststand": {"s_qrf": 1, "s_a10": 1, "s_heli": 1},
	"escort": {"s_a10": 1, "s_sof": 2},
	"csar": {"s_sof": 2, "s_heli": 1},
	"strike": {"s_sof": 1, "s_a10": 1},
	"zombie": {"s_a10": 2, "s_heli": 1},
	"interdict": {"s_a10": 1},
	"hvt": {"s_sof": 1},
	"sam": {"s_a10": 1},
}


static func campaign_cfg(i: int) -> Dictionary:
	var c: Dictionary = CAMPAIGN[i].duplicate(true)
	c["mode"] = "campaign"
	c["index"] = i
	if not c.has("supports"):
		c["supports"] = {}
	for sid in TYPE_SUPPORTS.get(c.type, {}):
		if not c.supports.has(sid):
			c.supports[sid] = TYPE_SUPPORTS[c.type][sid]
	# whatever else is in the player's loadout comes along with one charge
	# (the artillery runs on its reload timer instead)
	if c.type != "range":
		for sid in DEFAULT_SUPPORTS:
			if not c.supports.has(sid):
				c.supports[sid] = -1 if int(DEFAULT_SUPPORTS[sid]) < 0 else 1
	return c


static func skirmish_cfg(map_id: String, type: String, tod: String, difficulty: int) -> Dictionary:
	var m: Dictionary = Maps.get_map(map_id)
	var c := {
		"id": "sk_%s_%s" % [map_id, type], "mode": "skirmish", "map": map_id, "time": tod, "type": type,
		"name": "%s: %s" % [TYPE_NAMES.get(type, type), String(m.name).capitalize()], "difficulty": difficulty,
		"level": 2.0 + difficulty * 0.6, "civ": 0.45, "aa": 1 if tod != "day" else 0, "xp": 900, "armor": 1,
		"supports": DEFAULT_SUPPORTS.duplicate(), "flares": 30,
	}
	match type:
		"cas":
			c["duration"] = 360.0
			c["interval"] = 70.0
			c["friendlies"] = 12
		"zombie":
			c["civ"] = 0.0
			c["aa"] = 0
			c["survivors"] = 12
			c["min_survivors"] = 4
			c["duration"] = 420.0
		"escort":
			c["civ"] = 0.5
		"interdict":
			c["max_escape"] = 2
		"strike":
			c["window"] = 150.0
		"csar":
			c["duration"] = 240.0
		"sam":
			c["sites"] = 3
			c["flares"] = 40
			c["aa"] = 2
		"hvt":
			c["civ"] = 0.9
			c["max_civ"] = 3
	return c


static func survival_cfg(map_id: String, tod: String, difficulty: int) -> Dictionary:
	var m: Dictionary = Maps.get_map(map_id)
	return {
		"id": "survival_" + map_id, "mode": "survival", "map": map_id, "time": tod, "type": "survival",
		"name": "Survival: %s" % String(m.name).capitalize(), "difficulty": difficulty, "level": 1.0,
		"civ": 0.35, "aa": 0, "armor": 1, "xp": 0, "flares": 60, "max_civ": 10,
		"supports": {"s_hellfire": 5, "s_jdam": 3, "s_lgb18": 2, "s_tomahawk": 1, "s_illum": 5, "s_a10": 2, "s_sof": 3, "s_qrf": 2, "s_heli": 2},
	}


static func laststand_cfg(map_id: String, tod: String, difficulty: int, zombies: bool) -> Dictionary:
	var m: Dictionary = Maps.get_map(map_id)
	return {
		"id": "laststand_%s_%s" % [map_id, "z" if zombies else "i"], "mode": "laststand", "map": map_id, "time": tod,
		"type": "laststand", "waves": 0, "enemy": "zombies" if zombies else "insurgents",
		"name": "Last Stand: %s%s" % [String(m.name).capitalize(), " (Outbreak)" if zombies else ""],
		"difficulty": difficulty, "level": 1.5, "civ": 0.0 if zombies else 0.15, "aa": 0 if zombies else 1, "armor": 2,
		"friendlies": 14, "xp": 0, "flares": 50,
		"supports": {"s_hellfire": 4, "s_jdam": 3, "s_lgb18": 2, "s_tomahawk": 1, "s_illum": 4, "s_a10": 2, "s_sof": 2, "s_qrf": 1, "s_heli": 2},
	}
