extends "res://tests/framework/test_case.gd"
## CablePuzzleView terminal etkileşimi: seçim, aynı taraf, bağlama, sökme, yanlış bağlantılar ve oturumun tek kaynak
## olması (K-033). Girdi gerçek fare olaylarıyla verilir.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CableBoardScript := preload("res://scripts/ui/cable_board.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

var _viewport: SubViewport
var _session: CablePuzzleSessionScript
var _view: CablePuzzleViewScript


func test_first_click_selects_free_terminal() -> void:
	await _start()
	_click(&"terminal_a")
	assert_eq(_view.get_selected_terminal(), &"terminal_a")
	assert_eq(_button(&"terminal_a").text, "[ terminal_a ]")
	assert_eq(_session.get_connections(), [])
	await _finish()


func test_clicking_selected_terminal_clears_selection() -> void:
	await _start()
	_click(&"terminal_a")
	_click(&"terminal_a")
	assert_eq(_view.get_selected_terminal(), &"")
	assert_eq(_button(&"terminal_a").text, "terminal_a")
	assert_eq(_session.get_connections(), [])
	await _finish()


func test_same_side_click_moves_selection_without_connecting() -> void:
	await _start()
	_click(&"terminal_a")
	_click(&"terminal_c")
	assert_eq(_view.get_selected_terminal(), &"terminal_c", "Seçim aynı taraftaki yeni terminale geçmeli.")
	assert_eq(_button(&"terminal_a").text, "terminal_a")
	assert_eq(_session.get_connections(), [])
	_click(&"terminal_d")
	assert_eq(_session.get_connections(), [[&"terminal_c", &"terminal_d"]])
	await _finish()


func test_opposite_side_click_connects_and_clears_selection() -> void:
	await _start()
	_click(&"terminal_b")
	_click(&"terminal_a")
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_b"]])
	assert_eq(_view.get_selected_terminal(), &"")
	assert_eq(_board().get_segments().size(), 1)
	await _finish()


func test_clicking_connected_terminal_disconnects_immediately() -> void:
	await _start()
	_click(&"terminal_a")
	_click(&"terminal_b")
	_click(&"terminal_b")
	assert_eq(_session.get_connections(), [], "Bağlı terminale tıklama bağlantıyı sökmeli.")
	assert_eq(_view.get_selected_terminal(), &"", "Sökme seçim oluşturmamalı.")
	assert_eq(_board().get_segments().size(), 0)
	await _finish()


func test_disconnect_keeps_other_selection() -> void:
	await _start()
	_click(&"terminal_a")
	_click(&"terminal_b")
	_click(&"terminal_c")
	_click(&"terminal_b")
	assert_eq(_session.get_connections(), [])
	assert_eq(_view.get_selected_terminal(), &"terminal_c", "Başka terminalin seçimi korunmalı.")
	await _finish()


func test_occupied_terminal_is_never_auto_connected() -> void:
	await _start()
	_click(&"terminal_a")
	_click(&"terminal_b")
	_click(&"terminal_c")
	# Seçim varken dolu terminale tıklama yalnızca söker; seçili terminale bağlamaz.
	_click(&"terminal_a")
	assert_eq(_session.get_connections(), [])
	assert_eq(_session.get_partner(&"terminal_c"), &"")
	await _finish()


func test_wrong_connection_is_shown_without_revealing_correctness() -> void:
	await _start()
	_click(&"terminal_a")
	_click(&"terminal_d")
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_d"]])
	var wrong: Array[PackedVector2Array] = _board().get_segments()
	assert_eq(wrong.size(), 1, "Yanlış bağlantı da çizilmeli.")
	assert_eq(UiFixtures.feedback_text(_view), "", "Bağlantı kurmak doğruluk hakkında geri bildirim vermemeli.")
	var wrong_texts: Array[String] = _texts()
	_click(&"terminal_a")
	_click(&"terminal_a")
	_click(&"terminal_b")
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_b"]])
	assert_eq(_board().get_segments().size(), 1)
	assert_eq(UiFixtures.feedback_text(_view), "")
	# Doğru ve yanlış bağlantıda düğme metinleri ve stilleri aynı kalır.
	assert_eq(_texts(), wrong_texts)
	assert_false(_button(&"terminal_a").has_theme_stylebox_override(&"normal"))
	await _finish()


func test_wrong_connection_can_be_removed() -> void:
	await _start()
	_click(&"terminal_c")
	_click(&"terminal_b")
	_click(&"terminal_c")
	assert_eq(_session.get_connections(), [])
	assert_eq(_board().get_segments().size(), 0)
	await _finish()


func test_external_session_change_is_read_on_next_interaction() -> void:
	await _start()
	_click(&"terminal_a")
	assert_eq(_session.connect_terminals(&"terminal_a", &"terminal_b"), CablePuzzleSessionScript.MOVE_CONNECTED)
	_click(&"terminal_c")
	assert_eq(_view.get_selected_terminal(), &"terminal_c", "Bağlanmış eski seçim tutulmamalı.")
	assert_eq(_board().get_segments().size(), 1, "Dışarıda kurulan bağlantı oturumdan okunmalı.")
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_b"]])
	await _finish()


func test_board_matches_session_after_every_move() -> void:
	await _start()
	# a–d, c–b, a–d sökülür, a seçilir, c–b sökülür (seçim korunur), a–b, c–d.
	var moves: Array[StringName] = [&"terminal_a", &"terminal_d", &"terminal_c", &"terminal_b", &"terminal_d",
			&"terminal_a", &"terminal_b", &"terminal_b", &"terminal_c", &"terminal_d"]
	for terminal: StringName in moves:
		_click(terminal)
		assert_eq(_board().get_segments().size(), _session.get_connections().size(), "Hamle sonrası: %s" % terminal)
		assert_eq(UiFixtures.remaining_text(_view), str(_session.get_remaining_submissions()))
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_b"], [&"terminal_c", &"terminal_d"]])
	await _finish()


func test_view_shows_exactly_session_terminals() -> void:
	await _start()
	var expected: Array[StringName] = _session.get_terminal_ids(&"left")
	expected.append_array(_session.get_terminal_ids(&"right"))
	var shown: Array[StringName] = []
	for button: Button in UiFixtures.all_buttons(_view):
		shown.append(UiFixtures.terminal_of(button))
		assert_true(_session.has_terminal(UiFixtures.terminal_of(button)))
	assert_eq(shown, expected)
	var ports: Array[StringName] = []
	for port: Dictionary in _board().get_port_points():
		ports.append(port["terminal"])
	assert_eq(ports, expected, "Board yalnızca oturum terminallerini göstermeli.")
	await _finish()


func _start() -> void:
	_viewport = UiFixtures.make_viewport()
	_session = UiFixtures.standard_session()
	_view = UiFixtures.mount(_viewport, _session)
	await UiFixtures.settle()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _click(terminal: StringName) -> void:
	UiFixtures.click(_viewport, _view.get_terminal_button(terminal))


func _button(terminal: StringName) -> Button:
	return _view.get_terminal_button(terminal)


func _board() -> CableBoardScript:
	return UiFixtures.board(_view) as CableBoardScript


func _texts() -> Array[String]:
	var result: Array[String] = []
	for button: Button in UiFixtures.all_buttons(_view):
		result.append(button.text)
	return result
