extends "res://tests/framework/test_case.gd"
## CablePuzzleView kontrolü: hak tüketimi oturumdan, kilit, bitiş sinyalinin aynı oturumla tam bir kez yayılması,
## doğru düzenin gizli kalması (K-033).

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CableBoardScript := preload("res://scripts/ui/cable_board.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

var _viewport: SubViewport
var _session: CablePuzzleSessionScript
var _view: CablePuzzleViewScript
var _emitted: Array = []


func test_incomplete_check_does_not_consume_and_reports() -> void:
	await _start(2)
	_connect(&"terminal_a", &"terminal_b")
	_check()
	assert_eq(_session.get_remaining_submissions(), 2)
	assert_eq(UiFixtures.remaining_text(_view), "2")
	assert_eq(UiFixtures.feedback_text(_view), "UI_CABLE_INCOMPLETE")
	assert_false(_view.is_locked())
	assert_eq(_emitted.size(), 0)
	await _finish()


func test_incorrect_full_check_consumes_one_and_keeps_connections() -> void:
	await _start(3)
	_connect(&"terminal_a", &"terminal_d")
	_connect(&"terminal_c", &"terminal_b")
	_check()
	assert_eq(_session.get_remaining_submissions(), 2)
	assert_eq(UiFixtures.remaining_text(_view), "2", "Kalan hak oturumdan okunmalı.")
	assert_eq(UiFixtures.feedback_text(_view), "UI_CABLE_INCORRECT")
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_d"], [&"terminal_b", &"terminal_c"]])
	assert_eq(_board().get_segments().size(), 2, "Yanlış kontrolden sonra bağlantılar yerinde kalmalı.")
	assert_false(_view.is_locked())
	assert_eq(_emitted.size(), 0)
	await _finish()


func test_remaining_label_tracks_session_on_every_check() -> void:
	await _start(3)
	_check()
	assert_eq(UiFixtures.remaining_text(_view), str(_session.get_remaining_submissions()))
	_connect(&"terminal_a", &"terminal_d")
	_connect(&"terminal_c", &"terminal_b")
	for i in 2:
		_check()
		assert_eq(UiFixtures.remaining_text(_view), str(_session.get_remaining_submissions()))
	assert_eq(_session.get_remaining_submissions(), 1)
	await _finish()


func test_fix_after_incorrect_then_solve() -> void:
	await _start(2)
	_connect(&"terminal_a", &"terminal_d")
	_connect(&"terminal_c", &"terminal_b")
	_check()
	assert_eq(UiFixtures.feedback_text(_view), "UI_CABLE_INCORRECT")
	_click(&"terminal_a")
	_click(&"terminal_c")
	assert_eq(UiFixtures.feedback_text(_view), "", "Yeni hamle eski geri bildirimi temizler.")
	_connect(&"terminal_a", &"terminal_b")
	_connect(&"terminal_c", &"terminal_d")
	_check()
	assert_eq(_session.get_status(), CablePuzzleSessionScript.STATUS_SOLVED)
	assert_true(_view.is_locked())
	assert_eq(_emitted.size(), 1)
	await _finish()


func test_solve_locks_and_emits_same_session_once() -> void:
	await _start(2)
	_connect(&"terminal_a", &"terminal_b")
	_connect(&"terminal_c", &"terminal_d")
	_check()
	assert_true(_view.is_locked())
	assert_eq(UiFixtures.feedback_text(_view), "UI_CABLE_SOLVED")
	assert_eq(_emitted.size(), 1)
	assert_true(_emitted.size() == 1 and _emitted[0] == _session, "Sinyal aynı oturum nesnesini taşımalı.")
	_assert_all_disabled()
	await _finish()


func test_last_incorrect_check_fails_locks_and_emits_once() -> void:
	await _start(1)
	_connect(&"terminal_a", &"terminal_d")
	_connect(&"terminal_c", &"terminal_b")
	_check()
	assert_eq(_session.get_status(), CablePuzzleSessionScript.STATUS_FAILED)
	assert_true(_view.is_locked())
	assert_eq(UiFixtures.feedback_text(_view), "UI_CABLE_FAILED")
	assert_eq(UiFixtures.remaining_text(_view), "0")
	assert_true(_emitted.size() == 1 and _emitted[0] == _session)
	_assert_all_disabled()
	await _finish()


func test_clicks_after_finish_do_nothing() -> void:
	await _start(2)
	_connect(&"terminal_a", &"terminal_b")
	_connect(&"terminal_c", &"terminal_d")
	_check()
	var before: Array = UiFixtures.snapshot(_session)
	_check()
	_check()
	_click(&"terminal_a")
	_click(&"terminal_d")
	await UiFixtures.settle()
	assert_eq(UiFixtures.snapshot(_session), before)
	assert_eq(_emitted.size(), 1, "Tekrar tıklamalar ikinci sinyal üretmemeli.")
	assert_eq(_view.get_selected_terminal(), &"")
	await _finish()


func test_externally_finished_session_locks_without_signal() -> void:
	await _start(2)
	_connect(&"terminal_a", &"terminal_b")
	_connect(&"terminal_c", &"terminal_d")
	assert_eq(_session.submit(), CablePuzzleSessionScript.SUBMIT_SOLVED)
	assert_false(_view.is_locked(), "Görünüm oturumu yoklamaz; değişiklik sonraki etkileşimde okunur.")
	_check()
	assert_true(_view.is_locked())
	assert_eq(UiFixtures.feedback_text(_view), "UI_CABLE_SOLVED")
	assert_eq(_emitted.size(), 0, "Bu görünümde yapılmayan kontrol için sinyal yayılmamalı.")
	await _finish()


func test_listener_may_setup_again_during_signal() -> void:
	await _start(2)
	var replacement: CablePuzzleSessionScript = UiFixtures.standard_session()
	_view.puzzle_finished.connect(func(_finished: CablePuzzleSessionScript) -> void: _view.setup(replacement))
	_connect(&"terminal_a", &"terminal_b")
	_connect(&"terminal_c", &"terminal_d")
	_check()
	await UiFixtures.settle()
	assert_eq(_emitted.size(), 1)
	assert_true(_view.get_session() == replacement, "Dinleyicinin kurduğu oturum geçerli kalmalı.")
	assert_false(_view.is_locked())
	assert_eq(UiFixtures.feedback_text(_view), "")
	assert_eq(_session.get_status(), CablePuzzleSessionScript.STATUS_SOLVED)
	await _finish()


func test_failure_never_reveals_correct_layout() -> void:
	await _start(1)
	_connect(&"terminal_a", &"terminal_d")
	_connect(&"terminal_c", &"terminal_b")
	var texts_before: Array[String] = _texts()
	_check()
	await UiFixtures.settle()
	assert_eq(_session.get_connections(), [[&"terminal_a", &"terminal_d"], [&"terminal_b", &"terminal_c"]])
	var segments: Array[PackedVector2Array] = _board().get_segments()
	assert_eq(segments.size(), 2, "Yalnızca oyuncunun kurduğu bağlantılar çizilir.")
	assert_eq(_texts(), texts_before, "Başarısızlık düğme metinlerinde doğru eşleşmeyi göstermemeli.")
	await _finish()


func _start(max_submissions: int) -> void:
	_viewport = UiFixtures.make_viewport()
	_session = UiFixtures.standard_session(max_submissions)
	_view = UiFixtures.mount(_viewport, _session)
	_emitted = []
	_view.puzzle_finished.connect(func(finished: CablePuzzleSessionScript) -> void: _emitted.append(finished))
	await UiFixtures.settle()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _click(terminal: StringName) -> void:
	UiFixtures.click(_viewport, _view.get_terminal_button(terminal))


func _connect(left: StringName, right: StringName) -> void:
	_click(left)
	_click(right)


func _check() -> void:
	UiFixtures.click(_viewport, UiFixtures.check_button(_view))


func _board() -> CableBoardScript:
	return UiFixtures.board(_view) as CableBoardScript


func _texts() -> Array[String]:
	var result: Array[String] = []
	for button: Button in UiFixtures.all_buttons(_view):
		result.append(button.text)
	return result


func _assert_all_disabled() -> void:
	for button: Button in UiFixtures.all_buttons(_view):
		assert_true(button.disabled and button.focus_mode == Control.FOCUS_NONE, "%s kilitli olmalı." % button.name)
	assert_true(UiFixtures.check_button(_view).disabled)
	# Kapat kilitten muaftır ve kilit anında odağı alır.
	var close: Button = _view.get_node("%Close") as Button
	assert_true(not close.disabled and close.focus_mode == Control.FOCUS_ALL, "Kapat etkin kalmalı.")
	assert_true(UiFixtures.focus_owner(_viewport) == close, "Kilitten sonra odak Kapat'ta olmalı.")
