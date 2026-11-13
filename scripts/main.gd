extends Node
## Root node: swaps between the menus and a running sortie.

const Menus := preload("res://scripts/ui/menus.gd")
const Battle := preload("res://scripts/battle/battle.gd")
const Replay := preload("res://scripts/replay/replay.gd")
const Autotest := preload("res://scripts/test/autotest.gd")

var current: Node


func _ready() -> void:
	Game.main = self
	if Game.autotest != "":
		var at := Autotest.new()
		add_child(at)
		at.begin(Game.autotest)
		return
	show_menu("title")


func _clear() -> void:
	get_tree().paused = false
	if current:
		current.queue_free()
		current = null


func show_menu(screen: String, arg = null) -> void:
	_clear()
	var m := Menus.new()
	add_child(m)
	current = m
	m.show_screen(screen, arg)


func start_battle(cfg: Dictionary) -> void:
	_clear()
	var b := Battle.new(cfg)
	add_child(b)
	current = b


func start_replay(path: String) -> void:
	_clear()
	var r := Replay.new(path)
	add_child(r)
	current = r
