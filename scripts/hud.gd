class_name Hud
extends CanvasLayer

## Score + mana counters, tutorial hint, "no mana" flash, pause, game-over
## panel. Everything except the pause button ignores the mouse so taps fall
## through to gameplay. The HUD runs in ALWAYS mode: it owns pausing, so it
## must keep receiving input while the tree is paused.

var score_label: Label
var death_label: Label
var coin_label: Label
var shield_chip: Label
var star_chip: Label
var hint: TutorialHint
var no_mana_label: Label
var pause_button: Button
var pause_root: Control
var over_root: Control
var final_label: Label
var best_label: Label
var restart_label: Label
var next_label: Label
var next_track: ColorRect
var next_fill: ColorRect
var menu_root: Control
var menu_sub: Label
var spawn_row: Label
var level_list: VBoxContainer
var banner_label: Label

const NEXT_BAR_W := 620.0

var _no_mana_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2  # above the build ghost's layer, which sits on 1
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	score_label = _label(64, Color.WHITE)
	score_label.position = Vector2(48, 28)
	root.add_child(score_label)

	coin_label = _label(64, Color("f4c15d"))
	root.add_child(coin_label)
	coin_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	coin_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coin_label.offset_left = -560.0
	coin_label.offset_right = -48.0
	coin_label.offset_top = 28.0
	coin_label.offset_bottom = 120.0
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# held-powerup readout under the mana counter. The HUD layer provably
	# renders on every machine (score/mana/float-texts do), so a held
	# shield or double jump is always announced here, whatever happens to
	# the world-space aura.
	shield_chip = _label(40, Color("7bd5d6"))
	shield_chip.text = "FOCUS MODE"
	root.add_child(shield_chip)
	shield_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	shield_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	shield_chip.offset_left = -560.0
	shield_chip.offset_right = -48.0
	shield_chip.offset_top = 122.0
	shield_chip.offset_bottom = 172.0
	shield_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shield_chip.visible = false

	star_chip = _label(40, Color("ffd75e"))
	star_chip.text = "DOUBLE JUMP"
	root.add_child(star_chip)
	star_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	star_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	star_chip.offset_left = -560.0
	star_chip.offset_right = -48.0
	star_chip.offset_top = 172.0
	star_chip.offset_bottom = 222.0
	star_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	star_chip.visible = false

	# The opening instructions are played, not read — see TutorialHint. It frees
	# itself once it has run its loops, so nothing here has to tidy it up.
	# Anyone who has reached COMMUTE has demonstrably learned both verbs, and
	# replaying the lesson at the top of every run is just something in the way.
	if Levels.load_unlocked() < Levels.SPRINGS:
		hint = TutorialHint.new()
		add_child(hint)

	no_mana_label = _label(52, Color("ff6688"))
	no_mana_label.text = "Out of energy!"
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

	# Runs lost since the app opened — the day's tally, not this run's. Only
	# on the menu and the game-over panel: mid-run it is a number you can do
	# nothing about, and the top of the screen is where the next gap appears.
	# Added AFTER both panels so it sits on top of their dimming layers rather
	# than being greyed out by the only two screens that show it.
	death_label = _label(44, Color("ff8a9b"))
	death_label.visible = false
	root.add_child(death_label)
	death_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	death_label.offset_left = -240.0
	death_label.offset_right = 240.0
	death_label.offset_top = 26.0
	death_label.offset_bottom = 86.0
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
	var key := event as InputEventKey
	if key and key.pressed and not key.echo \
			and key.keycode == KEY_L and key.shift_pressed:
		# SHIFT+L: back to a fresh install — every unlock and best cleared, and
		# the death tally with them, so the opening plays as a first-timer sees
		# it. Shifted and out of the way of anything used mid-run.
		Levels.reset_progress()
		Main.deaths = 0
		Main.auto_start_level = -1
		update_deaths(0)
		show_level_banner("PROGRESS RESET")
		if menu_root.visible:
			show_menu(Levels.load_unlocked())
		get_viewport().set_input_as_handled()
		return
	if key and key.pressed and not key.echo \
			and key.keycode == KEY_U and key.shift_pressed:
		# SHIFT+U (dev cheat): every level unlocks as a starting point
		Levels.unlock(Levels.count() - 1)
		show_level_banner("ALL LEVELS UNLOCKED")
		if menu_root.visible:
			show_menu(Levels.load_unlocked())
		get_viewport().set_input_as_handled()
		return
	if key and key.pressed and not key.echo and menu_root.visible \
			and key.shift_pressed \
			and (key.keycode == KEY_UP or key.keycode == KEY_DOWN):
		# dev aid: while SHIFT reveals the row, the arrows step it by 100 m.
		# SHIFT is the reveal now rather than a multiplier, so the fine 25 m
		# step moved to the wheel — see _spawn_row_input.
		var step := 100.0
		if key.keycode == KEY_DOWN:
			step = -step
		Levels.debug_spawn_m = clampf(Levels.debug_spawn_m + step, 0.0, 2000.0)
		_update_spawn_row()
		get_viewport().set_input_as_handled()
		return
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
	dim.color = Color(0.035, 0.075, 0.10, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(dim)

	# Top-anchored layout: title, subtitle, then the list growing downward, so
	# the first (playable) button can never end up off-screen. Everything sits
	# 70 px lower than it used to, leaving the top strip to the death tally —
	# the title was running straight through it.
	var title := _label(120, Color("f4c15d"))
	title.text = "EVERYDAY LIFE"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	menu_root.add_child(title)
	title.offset_left = -700.0
	title.offset_right = 700.0
	title.offset_top = 100.0
	title.offset_bottom = 240.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	menu_sub = _label(40, Color(1, 1, 1, 0.85))
	menu_sub.text = "Choose a part of the day"
	menu_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	menu_root.add_child(menu_sub)
	menu_sub.offset_left = -700.0
	menu_sub.offset_right = 700.0
	menu_sub.offset_top = 250.0
	menu_sub.offset_bottom = 310.0
	menu_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Dev row, hidden unless SHIFT is held (see _process): it is a debugging
	# aid, and a menu that opens with a "LATE SPAWN" line on it reads like a
	# half-built game to anyone who is not me. A phone has no shift key, which
	# is exactly the point — there is no way to summon it there.
	# ↑/↓ step 100 m, the wheel over the row steps 25; mouse_filter STOP so
	# this one label hears the wheel itself.
	spawn_row = _label(34, Color("7bd5d6"))
	spawn_row.mouse_filter = Control.MOUSE_FILTER_STOP
	spawn_row.gui_input.connect(_spawn_row_input)
	spawn_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	spawn_row.visible = false
	menu_root.add_child(spawn_row)
	spawn_row.offset_left = -700.0
	spawn_row.offset_right = 700.0
	spawn_row.offset_top = 314.0
	spawn_row.offset_bottom = 366.0
	spawn_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_update_spawn_row()

	level_list = VBoxContainer.new()
	level_list.add_theme_constant_override("separation", 10)
	menu_root.add_child(level_list)
	level_list.set_anchors_preset(Control.PRESET_CENTER_TOP)
	level_list.grow_horizontal = Control.GROW_DIRECTION_BOTH
	level_list.grow_vertical = Control.GROW_DIRECTION_END
	level_list.offset_left = -430.0
	level_list.offset_right = 430.0
	# 7 rows of 76 + 10 separation = 602, so this still lands ~100 px clear of
	# the bottom on the 1080-tall canvas
	level_list.offset_top = 380.0


## (Re)build the level buttons for the current unlock state and show the menu.
func show_menu(unlocked: int) -> void:
	for c in level_list.get_children():
		c.queue_free()
	for i in range(Levels.count()):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(860.0, 76.0)
		b.add_theme_font_size_override("font_size", 34)
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
	death_label.visible = true
	_show_hint(false)  # the demo belongs to the run, not to the menu over it
	_update_spawn_row()


## Wheel over the LATE SPAWN row nudges the offset by 25 m — the fine step,
## since SHIFT is now what reveals the row rather than a multiplier.
func _spawn_row_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	var step := 25.0
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = -step
	elif mb.button_index != MOUSE_BUTTON_WHEEL_UP:
		return
	Levels.debug_spawn_m = clampf(Levels.debug_spawn_m + step, 0.0, 2000.0)
	_update_spawn_row()


## The dev row only exists while SHIFT is down. Polled rather than driven off
## key events because it has to disappear the instant the key is released, and
## the HUD runs in ALWAYS mode so this keeps ticking while the menu holds the
## tree paused.
func _process(_delta: float) -> void:
	if spawn_row != null:
		spawn_row.visible = menu_root.visible and Input.is_key_pressed(KEY_SHIFT)


func _update_spawn_row() -> void:
	spawn_row.text = "LATE SPAWN  +%d m     ↑ ↓ ±100  ·  scroll here ±25" \
			% int(Levels.debug_spawn_m)


## The instruction demo frees itself once it has run, so every caller has to
## cope with it already being gone.
func _show_hint(on: bool) -> void:
	if is_instance_valid(hint):
		hint.visible = on


func hide_menu() -> void:
	menu_root.visible = false
	pause_button.visible = true
	death_label.visible = false
	_show_hint(true)


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
	title.text = "MISSED A STEP"
	_center_row(over_root, title, -260.0, -120.0)

	final_label = _label(64, Color.WHITE)
	_center_row(over_root, final_label, -90.0, -10.0)

	best_label = _label(48, Color("7bd5d6"))
	_center_row(over_root, best_label, 0.0, 60.0)

	# HOW CLOSE YOU CAME. "You died at 238 m" is a fact nobody restarts for;
	# "62 m short of COMMUTE" is. The bar fills across the band this run ended
	# in, so the near-misses look near.
	next_label = _label(42, Color("f4c15d"))
	_center_row(over_root, next_label, 78.0, 128.0)

	next_track = ColorRect.new()
	next_track.color = Color(1.0, 1.0, 1.0, 0.16)
	next_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_root.add_child(next_track)
	next_track.set_anchors_preset(Control.PRESET_CENTER)
	next_track.offset_left = -NEXT_BAR_W * 0.5
	next_track.offset_right = NEXT_BAR_W * 0.5
	next_track.offset_top = 134.0
	next_track.offset_bottom = 152.0

	next_fill = ColorRect.new()
	next_fill.color = Color("f4c15d")
	next_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_track.add_child(next_fill)
	next_fill.position = Vector2.ZERO
	next_fill.size = Vector2(0.0, 18.0)

	restart_label = _label(44, Color(1, 1, 1, 0.85))
	restart_label.text = "Tap to try again"
	_center_row(over_root, restart_label, 176.0, 236.0)

	var levels_button := Button.new()
	levels_button.text = "LEVELS"
	levels_button.focus_mode = Control.FOCUS_NONE
	levels_button.add_theme_font_size_override("font_size", 40)
	over_root.add_child(levels_button)
	levels_button.set_anchors_preset(Control.PRESET_CENTER)
	levels_button.offset_left = -160.0
	levels_button.offset_right = 160.0
	levels_button.offset_top = 264.0
	levels_button.offset_bottom = 344.0
	levels_button.pressed.connect(func() -> void:
		var main = get_tree().get_first_node_in_group("main")
		if main:
			main.to_menu())


## "How far short you fell", measured against the level AFTER wherever this
## run ended — so it is always true of the run just played, however deep it
## got. Hidden in the last band, where there is no next thing to chase.
func _show_next_milestone(score: int) -> void:
	var lv := Levels.level_for(float(score))
	var nxt := lv + 1
	var show: bool = nxt < Levels.count()
	next_label.visible = show
	next_track.visible = show
	if not show:
		return
	var from := Levels.start_m(lv)
	var to := Levels.start_m(nxt)
	next_label.text = "NEXT: %s at %d m  —  %d m to go" % [
		Levels.level_name(nxt), int(to), maxi(0, int(to) - score)]
	var frac := clampf((float(score) - from) / maxf(to - from, 1.0), 0.0, 1.0)
	next_fill.size = Vector2(NEXT_BAR_W * frac, 18.0)


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


func update_deaths(n: int) -> void:
	death_label.text = "DEATHS " + str(n)


func update_coins(n: int) -> void:
	coin_label.text = "ENERGY " + str(n)


func update_powerups(sh: bool, dj: bool) -> void:
	shield_chip.visible = sh
	star_chip.visible = dj


func flash_no_mana() -> void:
	if _no_mana_tween and _no_mana_tween.is_valid():
		_no_mana_tween.kill()
	no_mana_label.modulate.a = 1.0
	_no_mana_tween = create_tween()
	_no_mana_tween.tween_interval(0.35)
	_no_mana_tween.tween_property(no_mana_label, "modulate:a", 0.0, 0.6)


func show_game_over(score: int, best: int, from_name: String, retry_name: String) -> void:
	final_label.text = "Distance: " + str(score) + " m"
	best_label.text = "Best from %s: %d m" % [from_name, best]
	# retry resumes at the furthest level unlocked, which is not always the one
	# this run began at — say so, so the jump is never a surprise
	restart_label.text = "Tap to try again  —  " + retry_name
	_show_next_milestone(score)
	pause_button.visible = false
	death_label.visible = true
	_show_hint(false)
	over_root.visible = true
	var tw := create_tween().set_loops()
	tw.tween_property(restart_label, "modulate:a", 0.25, 0.6)
	tw.tween_property(restart_label, "modulate:a", 0.85, 0.6)
