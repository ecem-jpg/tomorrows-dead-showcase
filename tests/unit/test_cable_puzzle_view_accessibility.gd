extends "res://tests/framework/test_case.gd"
## CablePuzzleView erişilebilirliği: odak alabilirlik, deterministik ilk odak, Tab / Shift+Tab ve ok tuşları, yalnızca
## klavyeyle oynama, kilitte odağın bırakılması, renkten bağımsız seçili işareti, asgari boyut (K-033).

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

var _viewport: SubViewport
var _session: CablePuzzleSessionScript
var _view: CablePuzzleViewScript


func test_interactive_nodes_take_focus_and_others_do_not() -> void:
	await _start()
	for button: Button in UiFixtures.all_buttons(_view):
		assert_eq(button.focus_mode, Control.FOCUS_ALL, "%s odak alabilmeli." % button.name)
	assert_eq(UiFixtures.check_button(_view).focus_mode, Control.FOCUS_ALL)
	assert_eq(UiFixtures.board(_view).focus_mode, Control.FOCUS_NONE)
	assert_eq(UiFixtures.board(_view).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for label_path: String in ["%Title", "%RemainingValue", "%Feedback"]:
		assert_eq((_view.get_node(label_path) as Control).focus_mode, Control.FOCUS_NONE)
	await _finish()


func test_initial_focus_is_first_left_terminal_only_for_active_session() -> void:
	await _start()
	assert_true(_focused() == _view.get_terminal_button(&"terminal_a"), "Aktif oturumda ilk sol terminal odaklanmalı.")
	_view.setup(null)
	assert_eq(take_engine_errors().size(), 1)
	await UiFixtures.settle()
	assert_false(UiFixtures.owns_focus(_view, _viewport), "null kurulumda odak verilmemeli.")
	var finished: CablePuzzleSessionScript = UiFixtures.standard_session(1)
	finished.connect_terminals(&"terminal_a", &"terminal_d")
	finished.connect_terminals(&"terminal_c", &"terminal_b")
	finished.submit()
	_view.setup(finished)
	await UiFixtures.settle()
	assert_false(UiFixtures.owns_focus(_view, _viewport), "Bitmiş kurulumda odak verilmemeli.")
	_view.setup(UiFixtures.standard_session())
	await UiFixtures.settle()
	assert_true(_focused() == _view.get_terminal_button(&"terminal_a"))
	await _finish()


func test_tab_order_is_left_then_right_then_check_and_wraps() -> void:
	await _start()
	var expected: Array[Control] = _chain()
	for i in expected.size():
		_key(KEY_TAB)
		var target: Control = expected[(i + 1) % expected.size()]
		assert_true(_focused() == target, "Tab %d: %s bekleniyordu, gelen %s" % [i + 1, target.name, _focus_name()])
	await _finish()


func test_shift_tab_reverses_order() -> void:
	await _start()
	var expected: Array[Control] = _chain()
	for i in expected.size():
		_key(KEY_TAB, true)
		var target: Control = expected[(expected.size() - 1 - i) % expected.size()]
		assert_true(_focused() == target, "Shift+Tab %d: %s bekleniyordu, gelen %s" % [i + 1, target.name, _focus_name()])
	await _finish()


func test_arrow_keys_follow_explicit_neighbors() -> void:
	await _start()
	var check: Button = UiFixtures.check_button(_view)
	var steps: Array = [
		[KEY_UP, &"terminal_a"], [KEY_DOWN, &"terminal_c"], [KEY_RIGHT, &"terminal_d"], [KEY_UP, &"terminal_b"],
		[KEY_LEFT, &"terminal_a"], [KEY_LEFT, &"terminal_a"], [KEY_RIGHT, &"terminal_b"], [KEY_RIGHT, &"terminal_b"],
		[KEY_DOWN, &"terminal_d"], [KEY_DOWN, &""], [KEY_DOWN, &""], [KEY_UP, &"terminal_c"],
	]
	for step: Array in steps:
		_key(step[0])
		var target: Control = check if step[1] == &"" else _view.get_terminal_button(step[1])
		assert_true(_focused() == target, "%s: %s bekleniyordu, gelen %s"
				% [OS.get_keycode_string(step[0]), target.name, _focus_name()])
	await _finish()


func test_keyboard_only_connect_disconnect_and_check() -> void:
	await _start()
	var emitted: Array = []
	_view.puzzle_finished.connect(func(finished: CablePuzzleSessionScript) -> void: emitted.append(finished))
	# Odak terminal_a'da: seç, sağa geç, terminal_b'ye bağla.
	_key(KEY_ENTER)
	assert_eq(_view.get_selected_terminal(), &"terminal_a")
	_key(KEY_RIGHT)
	_key(KEY_SPACE)
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_b"]])
	# Bağlı terminal Space ile sökülür ve yeniden bağlanır.
	_key(KEY_SPACE)
	assert_eq(_session.get_connections(), [])
	_key(KEY_LEFT)
	_key(KEY_ENTER)
	_key(KEY_RIGHT)
	_key(KEY_ENTER)
	# terminal_c → terminal_d.
	_key(KEY_LEFT)
	_key(KEY_DOWN)
	_key(KEY_ENTER)
	_key(KEY_RIGHT)
	_key(KEY_ENTER)
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_b"], [&"terminal_c", &"terminal_d"]])
	_key(KEY_DOWN)
	assert_true(_focused() == UiFixtures.check_button(_view))
	_key(KEY_ENTER)
	assert_eq(_session.get_status(), CablePuzzleSessionScript.STATUS_SOLVED)
	assert_eq(emitted.size(), 1)
	await _finish()


func test_lock_moves_focus_to_close_and_keys_do_nothing_afterwards() -> void:
	await _start(1)
	var emitted: Array = []
	_view.puzzle_finished.connect(func(finished: CablePuzzleSessionScript) -> void: emitted.append(finished))
	_session.connect_terminals(&"terminal_a", &"terminal_d")
	_session.connect_terminals(&"terminal_c", &"terminal_b")
	UiFixtures.check_button(_view).grab_focus()
	_key(KEY_ENTER)
	assert_eq(_session.get_status(), CablePuzzleSessionScript.STATUS_FAILED)
	assert_eq(emitted.size(), 1)
	var close: Button = _view.get_node("%Close") as Button
	assert_true(_focused() == close, "Kilitte odak Kapat'a geçmeli; gelen %s" % _focus_name())
	var before: Array = UiFixtures.snapshot(_session)
	for keycode: Key in [KEY_ENTER, KEY_SPACE, KEY_TAB, KEY_DOWN, KEY_ENTER]:
		_key(keycode)
		assert_true(_focused() == close, "Kilitli görünümde yalnızca Kapat odak alır; gelen %s" % _focus_name())
	await UiFixtures.settle()
	for button: Button in UiFixtures.all_buttons(_view) + [UiFixtures.check_button(_view)]:
		assert_eq(button.focus_mode, Control.FOCUS_NONE, "%s kilitte odak almamalı." % button.name)
	assert_eq(UiFixtures.snapshot(_session), before)
	assert_eq(emitted.size(), 1, "Kilitten sonra Enter/Space ikinci sinyal üretmemeli.")
	await _finish()


func test_selected_state_has_non_color_markers_and_minimum_sizes() -> void:
	await _start()
	var button: Button = _view.get_terminal_button(&"terminal_a")
	var normal_width: int = (button.get_theme_stylebox(&"normal") as StyleBoxFlat).border_width_left
	_key(KEY_ENTER)
	var selected_style: StyleBoxFlat = button.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_eq(button.text, CablePuzzleViewScript.SELECTED_TEXT_FORMAT % "terminal_a", "Seçili metin işareti olmalı.")
	assert_true(selected_style != null and selected_style.border_width_left == CablePuzzleViewScript.SELECTED_BORDER_WIDTH)
	assert_true(selected_style != null and selected_style.border_width_left > normal_width, "Çerçeve kalınlaşmalı.")
	assert_true(button.get_theme_stylebox(&"focus") != null, "Odak ayrı bir stil kutusuyla çizilmeli.")
	for control: Control in _chain():
		assert_true(control.size.x >= CablePuzzleViewScript.TERMINAL_MIN_SIZE.x
				and control.size.y >= CablePuzzleViewScript.TERMINAL_MIN_SIZE.y, "%s çok küçük." % control.name)
	assert_true(button.get_theme_font_size(&"font_size") >= 28, "Yazı en az 28 px olmalı.")
	_key(KEY_ENTER)
	assert_eq(button.text, "terminal_a")
	assert_eq((button.get_theme_stylebox(&"normal") as StyleBoxFlat).border_width_left, normal_width)
	await _finish()


func _start(max_submissions: int = 2) -> void:
	_viewport = UiFixtures.make_viewport()
	_session = UiFixtures.standard_session(max_submissions)
	_view = UiFixtures.mount(_viewport, _session)
	await UiFixtures.settle()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _key(keycode: Key, shift: bool = false) -> void:
	UiFixtures.key(_viewport, keycode, shift)


func _focused() -> Control:
	return UiFixtures.focus_owner(_viewport)


func _focus_name() -> String:
	var focused: Control = _focused()
	return "yok" if focused == null else String(focused.name)


## Beklenen Tab zinciri: sol terminaller, sağ terminaller, Kontrol, Kapat.
func _chain() -> Array[Control]:
	var result: Array[Control] = []
	result.append_array(UiFixtures.all_buttons(_view))
	result.append(UiFixtures.check_button(_view))
	result.append(_view.get_node("%Close") as Control)
	return result
