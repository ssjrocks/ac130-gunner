# AC-130 Gunner

You are the sensor operator and gunner on an AC-130 gunship orbiting 10,000 ft
above a battlefield. At 1x you see the whole valley and none of the people in
it. Zoom in and they appear, tiny, a few kilometres away. Your rounds take
seconds to land.

Built with Godot 4.7. Everything (terrain, towns, models, sound) is generated in
code, with no asset files.

## Features

- **Stabilised sensor turret:** continuous zoom from 1x (55°) to 150x (0.4°).
  It stays locked on a ground point while the aircraft orbits, has gimbal
  limits, point track, and a moving map that shows the sensor footprint.
- **Sensor modes:** daylight TV, night vision (image intensifier with gain,
  noise and bloom), and white-hot / black-hot thermal. In thermal everything
  shows its heat: engines, people, warm roads, cooling wrecks. Infected show
  up cold. Friendly troops wear IR strobes you can see in night vision.
- **Guns:** 7.62 mm minigun, 30 mm, 40 mm Bofors and 105 mm howitzer, each with
  its own time of flight, dispersion, blast and armour penetration.
- **Onboard guided weapons:** Griffin laser missiles and SDB laser-guided bombs.
- **Support calls:** MQ-9 Hellfire (laser), F/A-18 JDAM (GPS) and GBU-12
  (laser), Tomahawk cruise missile with a time-on-target countdown, and
  illumination rounds at night. Laser-guided weapons can also ride the special
  forces team's laser.
- **Threats to the aircraft:** MANPADS, SAM sites and triple-A. Flares, with
  timing that matters. Altitude choice: higher is safer but less accurate.
- **Battlefields:** six procedural maps (desert valley, mountains, coastal
  city, farmland with a river, open desert range, abandoned city), with
  compounds, towns, roads, trees, water, destructible buildings, civilians and
  traffic.
- **Mission types:** close air support, convoy escort, convoy interdiction,
  coordinated strike plus SF exfil, combat search and rescue, SAM hunt, HVT
  hunt among civilian traffic, outbreak (survivors against zombie hordes),
  last stand, survival.
- **Modes:** a 46-mission campaign across 12 chapters, skirmish (any map and
  mission type), survival (endless calls for fire) and last stand (endless
  waves, against insurgents or zombies).
- **Career:** 8 ranks from Airman to Chief Master Sergeant. Weapons, sensors,
  optics and support calls unlock with XP; campaign missions qualify you on
  equipment early.
- **Rules of engagement:** fratricide and civilian casualties cost score, and
  too many end the mission.
- **Supercomputer target prediction** (P, off by default): marks where the
  enemies near your aim point will be when the selected weapon's rounds land.
  It heats up while predicting, giving 30 seconds of use in every 2 minutes;
  at 100% it shuts down for a minute to cool.
- **Contact markers:** enemy positions called over the radio or spotted by
  friendly troops are marked on the map.
- Mouse and keyboard, plus gamepad.
- In-game updates from GitHub releases.

## Controls

| Action | Keyboard / mouse | Gamepad |
|---|---|---|
| Slew sensor | Mouse, arrow keys | Right stick |
| Zoom | Wheel, W / S | Left stick |
| Wide / narrow FOV | Z | L3 |
| Fire | Left mouse | RT |
| Laser designator | Right mouse (hold), L to latch | LT |
| Weapon | Q / E, 1-6 | LB / RB |
| Sensor mode | V | Y |
| Support calls (fire calls one) | G | X |
| Flares | F | B |
| Track target | C | A |
| Move orbit to sensor point | O | R3 |
| Climb / descend | PgUp / PgDn | D-pad |
| Map (click to move the orbit) | Tab | Back |
| Friendly markers | I | |
| Target prediction | P | D-pad left |
| Help overlay | H | |
| Pause | Esc | Start |

## Install

Linux: download `ac130-gunner-linux-x86_64.zip` from the releases, or build it
yourself (below) and run `scripts/install-linux.sh`, which installs to
`~/.local/share/ac130-gunner` and adds a launcher entry.

Windows: unzip `ac130-gunner-windows-x86_64.zip` into a folder you can write to
and run `ac130-gunner.exe`. Windows may warn that the file is unsigned.

The game checks this repository's latest release at the title screen and can
install a newer version and restart itself.

## Development

```bash
godot --path .                                   # run from source
godot --headless --path . --export-release "Linux" build/linux/ac130-gunner.x86_64
scripts/install-linux.sh                          # install the build with a launcher
scripts/release.sh 0.1.1                          # needs release/notes-v0.1.1.md
```

Headless test harness (runs a sortie with a bot gunner, at simulated time):

```bash
godot --headless --path . --fixed-fps 30 -- --autotest=skirmish:kharim:cas:day --secs=300
godot --headless --path . --fixed-fps 30 -- --autotest=input:skirmish:kharim:cas:day   # controls
godot --headless --path . --fixed-fps 30 -- --autotest=flow:1                          # debrief/career
```

`--shots=DIR` with a normal (non-headless) run saves screenshots at several zoom
levels and sensor modes.

Code layout: `scripts/world` (terrain, towns, shaders, models),
`scripts/battle` (gunship, units and AI, ordnance, effects, mission logic),
`scripts/ui` (HUD, post-processing, menus), `scripts/data` (weapons, ranks,
maps, campaign).
