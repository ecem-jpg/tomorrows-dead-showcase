extends "res://tests/framework/test_case.gd"
## CablePuzzleView Kapat eylemi: close_requested yalnızca düğmeyle ve bir kez, oturuma dokunmaz; Kapat kilitte etkin
## kalır ve kilit anında (puzzle_finished'den önce) odağı alır; ileri/geri zincirde Kapat bulunur; kilitli zincir
## yalnızca Kapat'tır; null kurulum otomatik odak almaz; Esc'yi görünüm ele almaz.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

var _viewport: SubViewport
var _session: CablePuzzleSessionScript
var _view: CablePuzzleViewScript
var _close_count: int = 0


func test_close_button_is_accessible_by_default() -> void:
	await _start()
	var close: Button = _close()
	assert_eq(close.text, "UI_HUD_CLOSE")
	assert_false(close.disabled)
	assert_eq(close.focus_mode, Control.FOCUS_ALL)
	assert_true(close.size.x >= CablePuzzleViewScript.TERMINAL_MIN_SIZE.x and close.size.y >= CablePuzzleViewScript.TERMINAL_MIN_SIZE.y)
	await _finish()


func test_close_emits_once_and_leaves_session_untouched() -> void:
	await _start()
	_click(&"terminal_a")
	_click(&"terminal_d")
	var before: Array = UiFixtures.snapshot(_session)
	var finished: Array = []
	_view.puzzle_finished.connect(func(session: CablePuzzleSessionScript) -> void: finished.append(session))
	UiFixtures.click(_viewport, _close())
	assert_eq(_close_count, 1, "Kapat tıklaması tam bir close_requested yaymalı.")
	assert_eq(UiFixtures.snapshot(_session), before, "Kapatma oturumu değiştirmemeli.")
	assert_false(_view.is_locked())
	assert_eq(finished.size(), 0)
	_close().grab_focus()
	UiFixtures.key(_viewport, KEY_ENTER)
	assert_eq(_close_count, 2, "Klavyeyle de tam bir kez yayılmalı.")
	assert_eq(UiFixtures.snapshot(_session), before)
	await _finish()


func test_close_stays_enabled_when_locked_and_null() -> void:
	var finished_session: CablePuzzleSessionScript = UiFixtures.standard_session(1)
	finished_session.connect_terminals(&"terminal_a", &"terminal_d")
	finished_session.connect_terminals(&"terminal_c", &"terminal_b")
	finished_session.submit()
	await _start(finished_session)
	assert_true(_view.is_locked())
	assert_false(_close().disabled, "Bitmiş kurulumda Kapat etkin kalmalı.")
	assert_false(UiFixtures.owns_focus(_view, _viewport), "Bitmiş kurulum otomatik odak almamalı.")
	await _finish()
	# Oturumsuz (null) görünüm: setup(null) akış hatası ürettiği için burada kurulmamış görünüm kullanılır; ikisinin
	# durumu aynıdır (oturum yok, kilitli). setup(null) hatası kurulum testlerinde doğrulanır.
	_viewport = UiFixtures.make_viewport()
	_view = UiFixtures.mount(_viewport)
	_close_count = 0
	_view.close_requested.connect(func() -> void: _close_count += 1)
	await UiFixtures.settle()
	assert_true(_view.get_session() == null and _view.is_locked())
	assert_false(_close().disabled, "Oturumsuz görünümde Kapat etkin kalmalı.")
	assert_false(UiFixtures.owns_focus(_view, _viewport), "Oturumsuz görünüm otomatik odak almamalı.")
	UiFixtures.click(_viewport, _close())
	assert_eq(_close_count, 1, "Kapat fareyle kullanılabilir kalmalı.")
	await _finish()


func test_lock_moves_focus_to_close_before_finished_signal() -> void:
	await _start(UiFixtures.standard_session(1))
	var focus_at_signal: Array = []
	_view.puzzle_finished.connect(func(_session_value: CablePuzzleSessionScript) -> void:
		focus_at_signal.append(_viewport.gui_get_focus_owner()))
	_click(&"terminal_a")
	_click(&"terminal_b")
	_click(&"terminal_c")
	_click(&"terminal_d")
	UiFixtures.click(_viewport, UiFixtures.check_button(_view))
	assert_eq(focus_at_signal.size(), 1)
	assert_true(focus_at_signal.size() == 1 and focus_at_signal[0] == _close(), "Sinyal anında odak Kapat'ta olmalı.")
	assert_true(_viewport.gui_get_focus_owner() == _close())
	assert_false(_close().disabled)
	await _finish()


func test_forward_and_backward_chain_include_close() -> void:
	await _start()
	var expected: Array[Control] = [_button(&"terminal_a"), _button(&"terminal_c"), _button(&"terminal_b"),
			_button(&"terminal_d"), UiFixtures.check_button(_view), _close()]
	for i in expected.size():
		UiFixtures.key(_viewport, KEY_TAB)
		assert_true(_focused() == expected[(i + 1) % expected.size()], "Tab %d: gelen %s" % [i + 1, _focus_name()])
	for i in expected.size():
		UiFixtures.key(_viewport, KEY_TAB, true)
		assert_true(_focused() == expected[(expected.size() - 1 - i) % expected.size()], "Shift+Tab %d: gelen %s" % [i + 1, _focus_name()])
	assert_true(UiFixtures.check_button(_view).get_node(UiFixtures.check_button(_view).focus_neighbor_right) == _close())
	assert_true(_close().get_node(_close().focus_neighbor_left) == UiFixtures.check_button(_view))
	await _finish()


func test_locked_chain_is_only_close() -> void:
	await _start(UiFixtures.standard_session(1))
	_click(&"terminal_a")
	_click(&"terminal_d")
	_click(&"terminal_c")
	_click(&"terminal_b")
	UiFixtures.click(_viewport, UiFixtures.check_button(_view))
	assert_true(_view.is_locked())
	var close: Button = _close()
	assert_true(close.get_node(close.focus_next) == close and close.get_node(close.focus_previous) == close)
	for side: Side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		assert_true(close.get_node(close.get_focus_neighbor(side)) == close)
	for button: Button in UiFixtures.all_buttons(_view) + [UiFixtures.check_button(_view)]:
		assert_eq(button.focus_mode, Control.FOCUS_NONE)
		assert_eq(button.focus_next, NodePath(), "%s kilitte zincirde olmamalı." % button.name)
	for keycode: Key in [KEY_TAB, KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		UiFixtures.key(_viewport, keycode, false)
		assert_true(_focused() == close, "Kilitte yalnızca Kapat odak alır; gelen %s" % _focus_name())
	UiFixtures.key(_viewport, KEY_TAB, true)
	assert_true(_focused() == close)
	await _finish()


func test_focus_first_available_control() -> void:
	await _start()
	_viewport.gui_release_focus()
	assert_true(_view.focus_first_available_control())
	assert_true(_focused() == _button(&"terminal_a"))
	var locked: CablePuzzleSessionScript = UiFixtures.standard_session(1)
	locked.connect_terminals(&"terminal_a", &"terminal_b")
	locked.connect_terminals(&"terminal_c", &"terminal_d")
	locked.submit()
	_view.setup(locked)
	await UiFixtures.settle()
	assert_true(_view.focus_first_available_control())
	assert_true(_focused() == _close(), "Kilitli görünümde ilk uygun denetim Kapat'tır.")
	var detached: CablePuzzleViewScript = (load(UiFixtures.SCENE_PATH) as PackedScene).instantiate() as CablePuzzleViewScript
	assert_false(detached.focus_first_available_control(), "Ağaç dışında false.")
	detached.free()
	await _finish()


func test_escape_is_not_handled_by_the_view() -> void:
	await _start()
	_click(&"terminal_a")
	var before: Array = UiFixtures.snapshot(_session)
	var selected: StringName = _view.get_selected_terminal()
	UiFixtures.key(_viewport, KEY_ESCAPE)
	_close().grab_focus()
	UiFixtures.key(_viewport, KEY_ESCAPE)
	await UiFixtures.settle()
	assert_eq(_close_count, 0, "Esc görünümde close_requested yaymamalı.")
	assert_eq(UiFixtures.snapshot(_session), before)
	assert_eq(_view.get_selected_terminal(), selected)
	assert_false(_view.is_locked())
	var code: String = FileAccess.get_file_as_string("res://scripts/ui/cable_puzzle_view.gd")
	assert_false(code.contains("ui_cancel"), "Esc sorumluluğu görünümde değil, host'tadır.")
	await _finish()


# --- Yardımcılar ---

func _start(session: CablePuzzleSessionScript = null) -> void:
	_viewport = UiFixtures.make_viewport()
	_session = session if session != null else UiFixtures.standard_session()
	_view = UiFixtures.mount(_viewport, _session)
	_close_count = 0
	_view.close_requested.connect(func() -> void: _close_count += 1)
	await UiFixtures.settle()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _close() -> Button:
	return _view.get_node("%Close") as Button


func _button(terminal: StringName) -> Button:
	return _view.get_terminal_button(terminal)


func _click(terminal: StringName) -> void:
	UiFixtures.click(_viewport, _view.get_terminal_button(terminal))


func _focused() -> Control:
	return _viewport.gui_get_focus_owner()


func _focus_name() -> String:
	var focused: Control = _focused()
	return "yok" if focused == null else String(focused.name)
