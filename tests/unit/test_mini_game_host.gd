extends "res://tests/framework/test_case.gd"
## MiniGameHost: doğrulanmış açılış ve kısmi kilit olmaması, layer 10 ve iç içe CanvasLayer yokluğu, kilit ve önceki
## gerçek değerlerin geri yüklenmesi, tamamlanmanın tam bir kez iletilmesi, otomatik kapanmama, Esc / Kapat / close ile
## sinyalsiz kapanış, odak dönüşü, aç/kapat/aç, sinyal yarışları, set_locked_root kuralları ve ağaçtan çıkış.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const MiniGameHostScript := preload("res://scripts/ui/mini_game_host.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

const DISABLED_FOCUS: Control.FocusBehaviorRecursive = Control.FOCUS_BEHAVIOR_DISABLED
const DISABLED_MOUSE: Control.MouseBehaviorRecursive = Control.MOUSE_BEHAVIOR_DISABLED


## Host'tan önce ağaca eklenir: host Esc'yi işlediyse bu düğüm onu görmez.
class EscProbe extends Node:
	var cancel_count: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"ui_cancel"):
			cancel_count += 1


var _viewport: SubViewport
var _root: Control
var _first: Button
var _second: Button
var _probe: EscProbe
var _host: MiniGameHostScript
var _finished: Array = []
var _closed: int = 0


func test_null_or_invalid_open_does_not_lock() -> void:
	await _mount()
	var before: Array = _behaviors()
	assert_false(_host.open(null))
	assert_false(_host.open(RefCounted.new()), "Oturum olmayan değer reddedilmeli.")
	assert_false(_host.open(3))
	assert_eq(_behaviors(), before, "Başarısız açılış kilit bırakmamalı.")
	assert_false(_host.is_open())
	assert_eq(_host.get_child_count(), 0)
	var unrooted: MiniGameHostScript = MiniGameHostScript.new()
	_viewport.add_child(unrooted)
	assert_false(unrooted.open(UiFixtures.standard_session()), "Root verilmeden açılmamalı.")
	assert_eq(unrooted.get_child_count(), 0)
	unrooted.queue_free()
	await _finish()


func test_valid_open_uses_separate_layer_10() -> void:
	await _mount()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	assert_true(_host.open(session))
	assert_true(_host.is_open())
	var view: CablePuzzleViewScript = _view()
	assert_true(view != null and view.get_parent() == _host)
	assert_eq(view.layer, MiniGameHostScript.MINI_GAME_LAYER)
	assert_eq(view.layer, 10)
	assert_true(view.get_session() == session)
	var ancestor: Node = view.get_parent()
	while ancestor != null:
		assert_false(ancestor is CanvasLayer, "Kablo görünümü başka bir CanvasLayer altında olmamalı.")
		ancestor = ancestor.get_parent()
	await _finish()


func test_second_open_is_ignored() -> void:
	await _mount()
	assert_true(_host.open(UiFixtures.standard_session()))
	var view: CanvasLayer = _host.get_view()
	assert_false(_host.open(UiFixtures.standard_session()))
	assert_true(_host.get_view() == view)
	assert_eq(_host.get_child_count(), 1)
	await _finish()


func test_open_locks_root_and_moves_focus_into_view() -> void:
	await _mount()
	_first.grab_focus()
	assert_true(_host.open(UiFixtures.standard_session()))
	assert_eq(_behaviors(), [DISABLED_FOCUS, DISABLED_MOUSE])
	for button: Button in [_first, _second]:
		assert_eq(button.get_focus_mode_with_override(), Control.FOCUS_NONE)
		assert_eq(button.get_mouse_filter_with_override(), Control.MOUSE_FILTER_IGNORE)
	assert_false(_first.has_focus(), "HUD odağı bırakılmalı.")
	await UiFixtures.settle()
	assert_true(_focused() == _view().get_terminal_button(&"terminal_a"), "İlk uygun kablo denetimi odaklanmalı.")
	for i in 8:
		UiFixtures.key(_viewport, KEY_TAB)
		assert_true(_view().is_ancestor_of(_focused()), "Odak mini oyundan çıkmamalı.")
	await _finish()


func test_finished_is_forwarded_once_and_view_stays_open() -> void:
	await _mount()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_host.open(session)
	await UiFixtures.settle()
	_solve()
	assert_eq(_finished, [session], "Tamamlanma aynı oturumla tam bir kez iletilmeli.")
	assert_true(_host.is_open(), "Tamamlanınca otomatik kapanmamalı.")
	assert_true(_focused() == _close_button(), "Kilitte odak Kapat'ta olmalı.")
	await UiFixtures.settle(3)
	assert_true(_host.is_open())
	UiFixtures.click(_viewport, UiFixtures.check_button(_view()))
	assert_eq(_finished.size(), 1)
	await _finish()


func test_escape_closes_unfinished_without_result() -> void:
	await _mount()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_host.open(session)
	await UiFixtures.settle()
	UiFixtures.click(_viewport, _view().get_terminal_button(&"terminal_a"))
	UiFixtures.click(_viewport, _view().get_terminal_button(&"terminal_b"))
	var before: Array = UiFixtures.snapshot(session)
	UiFixtures.key(_viewport, KEY_ESCAPE)
	assert_false(_host.is_open())
	assert_eq(_closed, 1)
	assert_eq(_finished, [])
	assert_eq(UiFixtures.snapshot(session), before, "Kapatma oturumu değiştirmemeli.")
	assert_eq(_probe.cancel_count, 0, "Host Esc'yi işlenmiş olarak işaretlemeli.")
	assert_eq(_host.get_child_count(), 0, "Görünüm ağaçtan hemen çıkarılmalı.")
	await _finish()


func test_close_button_closes_unfinished_without_result() -> void:
	await _mount()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_host.open(session)
	await UiFixtures.settle()
	var before: Array = UiFixtures.snapshot(session)
	UiFixtures.click(_viewport, _close_button())
	assert_false(_host.is_open())
	assert_eq([_closed, _finished.size()], [1, 0])
	assert_eq(UiFixtures.snapshot(session), before)
	await _finish()


func test_finished_view_can_be_closed() -> void:
	await _mount()
	_host.open(UiFixtures.standard_session())
	await UiFixtures.settle()
	_solve()
	assert_true(_host.close())
	assert_false(_host.close(), "Kapalıyken close false döner.")
	assert_eq([_closed, _finished.size()], [1, 1])
	assert_true(_host.get_view() == null)
	await _finish()


func test_previous_behavior_values_are_restored_exactly() -> void:
	await _mount()
	_root.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	_root.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	_host.open(UiFixtures.standard_session())
	assert_eq(_behaviors(), [DISABLED_FOCUS, DISABLED_MOUSE])
	_host.close()
	assert_eq(_behaviors(), [Control.FOCUS_BEHAVIOR_ENABLED, Control.MOUSE_BEHAVIOR_INHERITED])
	_root.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	_root.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	_host.open(UiFixtures.standard_session())
	_host.close()
	assert_eq(_behaviors(), [Control.FOCUS_BEHAVIOR_INHERITED, Control.MOUSE_BEHAVIOR_ENABLED])
	assert_eq(_first.get_focus_mode_with_override(), Control.FOCUS_ALL)
	await _finish()


func test_valid_previous_focus_is_restored() -> void:
	await _mount()
	_second.grab_focus()
	_host.open(UiFixtures.standard_session())
	await UiFixtures.settle()
	_host.close()
	assert_true(_focused() == _second, "Geçerli eski odak geri gelmeli.")
	await _finish()


func test_invalid_previous_focus_is_not_restored() -> void:
	await _mount()
	_second.grab_focus()
	_host.open(UiFixtures.standard_session())
	_second.disabled = true
	_host.close()
	assert_true(_focused() == null, "Devre dışı eski odağa dönülmemeli.")
	_second.disabled = false
	_first.grab_focus()
	_host.open(UiFixtures.standard_session())
	_first.get_parent().remove_child(_first)
	_first.free()
	_host.close()
	assert_true(_focused() == null, "Silinmiş eski odak güvenle atlanmalı.")
	await _finish()


func test_open_close_open_uses_fresh_view_and_connections() -> void:
	await _mount()
	_host.open(UiFixtures.standard_session())
	var first_view: CablePuzzleViewScript = _view()
	_host.close()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_host.open(session)
	var second_view: CablePuzzleViewScript = _view()
	assert_true(second_view != first_view, "İkinci açılış yeni görünüm kullanmalı.")
	assert_eq(second_view.puzzle_finished.get_connections().size(), 1)
	assert_eq(second_view.close_requested.get_connections().size(), 1)
	await UiFixtures.settle()
	_solve()
	assert_eq(_finished, [session], "Çift bağlantı olmamalı.")
	await _finish()


func test_escape_when_closed_does_nothing() -> void:
	await _mount()
	_first.grab_focus()
	UiFixtures.key(_viewport, KEY_ESCAPE)
	assert_eq(_closed, 0)
	assert_eq(_probe.cancel_count, 1, "Kapalıyken host Esc'yi tüketmemeli.")
	assert_true(_focused() == _first)
	await _finish()


func test_finished_then_close_in_same_frame_forwards_once() -> void:
	await _mount()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_host.open(session)
	var view: CablePuzzleViewScript = _view()
	view.puzzle_finished.emit(session)
	view.puzzle_finished.emit(session)
	view.close_requested.emit()
	assert_eq(_finished, [session], "Sonuç en fazla bir kez iletilmeli.")
	assert_eq(_closed, 1)
	assert_false(_host.is_open())
	await _finish()


func test_late_signal_from_closed_view_is_ignored() -> void:
	await _mount()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_host.open(session)
	var old_view: CablePuzzleViewScript = _view()
	old_view.close_requested.emit()
	assert_false(_host.is_open())
	assert_eq(old_view.puzzle_finished.get_connections().size(), 0, "Kapanışta bağlantılar koparılmalı.")
	assert_eq(old_view.close_requested.get_connections().size(), 0)
	old_view.puzzle_finished.emit(session)
	old_view.close_requested.emit()
	assert_eq(_finished, [], "Kapatılan görünümün sonucu iletilmemeli.")
	assert_eq(_closed, 1)
	assert_true(_host.get_view() == null, "Host eski görünümü tutmamalı.")
	assert_true(_host.open(UiFixtures.standard_session()))
	assert_true(_view() != old_view)
	await _finish()


func test_locked_root_cannot_change_while_open() -> void:
	await _mount()
	var other: Control = Control.new()
	_viewport.add_child(other)
	_host.open(UiFixtures.standard_session())
	assert_false(_host.set_locked_root(other), "Açıkken Root değiştirilemez.")
	assert_false(_host.set_locked_root(null))
	assert_eq(other.focus_behavior_recursive, Control.FOCUS_BEHAVIOR_INHERITED)
	_host.close()
	assert_eq(_behaviors(), [Control.FOCUS_BEHAVIOR_INHERITED, Control.MOUSE_BEHAVIOR_INHERITED], "Asıl Root geri yüklenmeli.")
	assert_true(_host.set_locked_root(null), "Kapalıyken null kabul edilir.")
	assert_false(_host.open(UiFixtures.standard_session()), "Root yokken açılmaz.")
	assert_true(_host.set_locked_root(other))
	assert_true(_host.open(UiFixtures.standard_session()))
	assert_eq(other.focus_behavior_recursive, DISABLED_FOCUS)
	assert_eq(_behaviors(), [Control.FOCUS_BEHAVIOR_INHERITED, Control.MOUSE_BEHAVIOR_INHERITED])
	_host.close()
	await _finish()


func test_leaving_tree_while_open_restores_root() -> void:
	await _mount()
	_host.open(UiFixtures.standard_session())
	_host.queue_free()
	await UiFixtures.settle()
	assert_false(is_instance_valid(_host))
	assert_eq(_behaviors(), [Control.FOCUS_BEHAVIOR_INHERITED, Control.MOUSE_BEHAVIOR_INHERITED])
	assert_eq(_closed, 0, "Ağaçtan çıkışta closed yayılmaz.")
	await _finish()


# --- Yardımcılar ---

func _mount() -> void:
	_viewport = UiFixtures.make_viewport()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box: VBoxContainer = VBoxContainer.new()
	_first = Button.new()
	_first.text = "first"
	_second = Button.new()
	_second.text = "second"
	box.add_child(_first)
	box.add_child(_second)
	_root.add_child(box)
	_viewport.add_child(_root)
	_probe = EscProbe.new()
	_viewport.add_child(_probe)
	_host = MiniGameHostScript.new()
	_viewport.add_child(_host)
	assert_true(_host.set_locked_root(_root))
	_finished = []
	_closed = 0
	_host.finished.connect(func(session: RefCounted) -> void: _finished.append(session))
	_host.closed.connect(func() -> void: _closed += 1)
	await UiFixtures.settle()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _view() -> CablePuzzleViewScript:
	return _host.get_view() as CablePuzzleViewScript


func _close_button() -> Button:
	return _view().get_node("%Close") as Button


func _behaviors() -> Array:
	return [_root.focus_behavior_recursive, _root.mouse_behavior_recursive]


func _focused() -> Control:
	return _viewport.gui_get_focus_owner()


## Standart düzeni doğru bağlayıp Kontrol'e basar (gerçek tıklamalar).
func _solve() -> void:
	for terminal: StringName in [&"terminal_a", &"terminal_b", &"terminal_c", &"terminal_d"]:
		UiFixtures.click(_viewport, _view().get_terminal_button(terminal))
	UiFixtures.click(_viewport, UiFixtures.check_button(_view()))
