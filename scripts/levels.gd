class_name Levels
extends RefCounted

## The level ladder: each level owns a band of meters with one twist.
## Crossing into a level unlocks it as a starting point on the title menu
## (persisted to user://, which also works in the web build via browser
## storage). Score stays absolute meters wherever you start; bests are
## tracked per starting level so late starts never beat the "from 0" run.

const DEFS := [
	{"name": "MORNING RUSH", "start": 0.0},
	{"name": "COMMUTE", "start": 300.0},
	{"name": "NOTIFICATIONS", "start": 600.0},
	{"name": "CHANGE OF PLANS", "start": 900.0},
	{"name": "NIGHT WALK", "start": 1200.0},
	{"name": "FRIENDS", "start": 1500.0},
	{"name": "OFF THE CLOCK", "start": 1800.0},
]

# indices, for readable level checks across the codebase
const SPRINGS := 1
const BRIDGES := 2
const FLIPSIDE := 3
const UMBRA := 4
const BROS := 5
const VOID := 6

## var (not const) so tests can point saves at a scratch file
static var save_path := "user://progress.cfg"

## Dev aid (menu wheel or ↑/↓, SHIFT ×100): extra meters credited past the
## chosen level's start — even past its band's end — so any absolute meter
## mark is testable without surviving the run up to it.
static var debug_spawn_m := 0.0


static func count() -> int:
	return DEFS.size()


static func level_name(i: int) -> String:
	return DEFS[i]["name"]


static func start_m(i: int) -> float:
	return DEFS[i]["start"]


static func level_for(d: float) -> int:
	var lv := 0
	for i in range(DEFS.size()):
		if d >= DEFS[i]["start"]:
			lv = i
	return lv


static func load_unlocked() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return 0
	return clampi(cfg.get_value("progress", "unlocked", 0), 0, DEFS.size() - 1)


static func unlock(i: int) -> void:
	if i <= load_unlocked():
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)  # keep existing keys; missing file is fine
	cfg.set_value("progress", "unlocked", clampi(i, 0, DEFS.size() - 1))
	cfg.save(save_path)


static func best_for(i: int) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return 0
	return cfg.get_value("progress", "best_%d" % i, 0)


static func save_best(i: int, meters: int) -> void:
	if meters <= best_for(i):
		return
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value("progress", "best_%d" % i, meters)
	cfg.save(save_path)
