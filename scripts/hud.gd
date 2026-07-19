class_name Hud
extends CanvasLayer

## Score + mana counters, tutorial hint, "no mana" flash, pause, game-over
## panel. Everything except the pause button ignores the mouse so taps fall
## through to gameplay. The HUD runs in ALWAYS mode: it owns pausing, so it
## must keep receiving input while the tree is paused.

var score_label: Label
var coin_label: Label
var hint_label: Label
var no_mana_label: Label
var pause_button: Button
var pause_root: Control
var over_root: Control
var final_label: Label
var best_label: Label
var restart_label: Label
var menu_root: Control
var level_list: VBoxContainer
var banner_label: Label

var _no_mana_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	score_label = _label(64, Color.WHITE)
	score_label.position = Vector2(48, 28)
	root.add_child(score_label)

	coin_label = _label(64, Color("52e5ff"))
	root.add_child(coin_label)
	coin_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	coin_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coin_label.offset_left = -560.0
	coin_label.offset_right = -48.0
	coin_label.offset_top = 28.0
	coin_label.offset_bottom = 120.0
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	hint_label = _label(40, Color(1, 1, 1, 0.9))
	hint_label.text = "Tap LEFT of your wizard to JUMP  •  Tap RIGHT to BUILD (1 mana)"
	root.add_child(hint_label)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_left = -800.0
	hint_label.offset_right = 800.0
	hint_label.offset_top = -150.0
	hint_label.offset_bottom = -80.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint_tw := create_tween()
	hint_tw.tween_interval(7.0)
	hint_tw.tween_property(hint_label, "modulate:a", 0.0, 1.0)

	no_mana_label = _label(52, Color("ff6688"))
	no_mana_label.text = "Not enough mana!"
	no_mana_label.modulate.a = 0.0
	root.add_child(no_mana_label)
	no_mana_label.set_anchors_preset(Control.PRESET_CENTER)
	no_mana_label.offset_left = -400.0
	no_mana_label.offset_right = 400.0
	no_mana_label.offset_top = -300.0
	no_mana_label.offset_bottom = -220.0
	no_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	pause_button = Button.new()
	pause_button.text = "II"
	pause_button.add_theme_font_size_override("font_size", 44)
	pause_button.focus_mode = Control.FOCUS_NONE
	root.add_child(pause_button)
	pause_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_button.offset_left = -70.0
	pause_button.offset_right = 70.0
	pause_button.offset_top = 20.0
	pause_button.offset_bottom = 110.0
	pause_button.pressed.connect(_toggle_pause)

	_build_game_over(root)
	_build_menu(root)

	# level banner: announces each level as you cross into it
	banner_label = _label(88, Color("ffd75e"))
	banner_label.modulate.a = 0.0
	root.add_child(banner_label)
	banner_label.set_anchors_preset(Control.PRESET_CENTER)
	banner_label.offset_left = -800.0
	banner_label.offset_right = 800.0
	banner_label.offset_top = -330.0
	banner_label.offset_bottom = -210.0
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	pause_root = Control.new()
	pause_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_root.visible = false
	root.add_child(pause_root)

	var pdim := ColorRect.new()
	pdim.color = Color(0.05, 0.03, 0.1, 0.55)
	pdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pdim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_root.add_child(pdim)

	var ptitle := _label(120, Color.WHITE)
	ptitle.text = "PAUSED"
	_center_row(pause_root, ptitle, -140.0, 0.0)

	var psub := _label(44, Color(1, 1, 1, 0.85))
	psub.text = "Tap anywhere or press P to resume"
	_center_row(pause_root, psub, 40.0, 100.0)


func _unhandled_input(event: InputEvent) -> void:
	if menu_root.visible:
		return  # the menu owns the screen; only its buttons act
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_P:
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif get_tree().paused and event is InputEventScreenTouch and event.pressed:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	var main = get_tree().get_first_node_in_group("main")
	if main == null or main.game_over or menu_root.visible:
		return
	var now := not get_tree().paused
	get_tree().paused = now
	pause_root.visible = now
	pause_button.visible = not now


func _build_menu(root: Control) -> void:
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.visible = false
	root.add_child(menu_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.1, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(dim)

	# top-anchored layout: title, subtitle, then the list growing downward,
	# so the first (playable) button can never end up off-screen
	var title := _label(120, Color("8b6cff"))
	title.text = "SPELLBROS"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	menu_root.add_child(title)
	title.offset_left = -700.0
	title.offset_right = 700.0
	title.offset_top = 30.0
	title.offset_bottom = 170.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var sub := _label(40, Color(1, 1, 1, 0.85))
	sub.text = "Choose your level"
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	menu_root.add_child(sub)
	sub.offset_left = -700.0
	sub.offset_right = 700.0
	sub.offset_top = 180.0
	sub.offset_bottom = 240.0
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	level_list = VBoxContainer.new()
	level_list.add_theme_constant_override("separation", 16)
	menu_root.add_child(level_list)
	level_list.set_anchors_preset(Control.PRESET_CENTER_TOP)
	level_list.grow_horizontal = Control.GROW_DIRECTION_BOTH
	level_list.grow_vertical = Control.GROW_DIRECTION_END
	level_list.offset_left = -430.0
	level_list.offset_right = 430.0
	level_list.offset_top = 270.0


## (Re)build the level buttons for the current unlock state and show the menu.
func show_menu(unlocked: int) -> void:
	for c in level_list.get_children():
		c.queue_free()
	for i in range(Levels.count()):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(860.0, 92.0)
		b.add_theme_font_size_override("font_size", 40)
		if i <= unlocked:
			var best := Levels.best_for(i)
			var best_txt := "   best %d m" % best if best > 0 else ""
			b.text = "%s  —  %d m%s" % [Levels.level_name(i), int(Levels.start_m(i)), best_txt]
			var idx := i
			b.pressed.connect(func() -> void:
				var main = get_tree().get_first_node_in_group("main")
				if main:
					main.begin_run(idx))
		else:
			b.text = "%s  —  reach %d m to unlock" % [Levels.level_name(i), int(Levels.start_m(i))]
			b.disabled = true
		level_list.add_child(b)
	menu_root.visible = true
	pause_button.visible = false


func hide_menu() -> void:
	menu_root.visible = false
	pause_button.visible = true


## Big center-screen announcement when a level starts or is unlocked.
func show_level_banner(text: String) -> void:
	banner_label.text = text
	banner_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner_label, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.6)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.8)


func _build_game_over(root: Control) -> void:
	over_root = Control.new()
	over_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	over_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_root.visible = false
	root.add_child(over_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.1, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_root.add_child(dim)

	var title := _label(120, Color.WHITE)
	title.text = "GAME OVER"
	_center_row(over_root, title, -260.0, -120.0)

	final_label = _label(64, Color.WHITE)
	_center_row(over_root, final_label, -90.0, -10.0)

	best_label = _label(48, Color("52e5ff"))
	_center_row(over_root, best_label, 0.0, 60.0)

	restart_label = _label(44, Color(1, 1, 1, 0.85))
	restart_label.text = "Tap to try again"
	_center_row(over_root, restart_label, 120.0, 180.0)

	var levels_button := Button.new()
	levels_button.text = "LEVELS"
	levels_button.focus_mode = Control.FOCUS_NONE
	levels_button.add_theme_font_size_override("font_size", 40)
	over_root.add_child(levels_button)
	levels_button.set_anchors_preset(Control.PRESET_CENTER)
	levels_button.offset_left = -160.0
	levels_button.offset_right = 160.0
	levels_button.offset_top = 220.0
	levels_button.offset_bottom = 300.0
	levels_button.pressed.connect(func() -> void:
		var main = get_tree().get_first_node_in_group("main")
		if main:
			main.to_menu())


func _center_row(parent: Control, l: Label, top: float, bottom: float) -> void:
	parent.add_child(l)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = -700.0
	l.offset_right = 700.0
	l.offset_top = top
	l.offset_bottom = bottom
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.12, 0.85))
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func update_score(m: int) -> void:
	score_label.text = str(m) + " m"


func update_coins(n: int) -> void:
	coin_label.text = "MANA " + str(n)


func flash_no_mana() -> void:
	if _no_mana_tween and _no_mana_tween.is_valid():
		_no_mana_tween.kill()
	no_mana_label.modulate.a = 1.0
	_no_mana_tween = create_tween()
	_no_mana_tween.tween_interval(0.35)
	_no_mana_tween.tween_property(no_mana_label, "modulate:a", 0.0, 0.6)


func show_game_over(score: int, best: int, from_name: String) -> void:
	final_label.text = "Distance: " + str(score) + " m"
	best_label.text = "Best from %s: %d m" % [from_name, best]
	pause_button.visible = false
	over_root.visible = true
	var tw := create_tween().set_loops()
	tw.tween_property(restart_label, "modulate:a", 0.25, 0.6)
	tw.tween_property(restart_label, "modulate:a", 0.85, 0.6)
