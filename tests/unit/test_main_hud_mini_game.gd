extends "res://tests/framework/test_case.gd"
## MainHudView mini oyun bağlantısı: API iletimi, repair_finished'in tam bir kez yayılması, açıkken show_model'in HUD'a
## odak vermemesi ve kilidi bozmaması, açıkken HUD'un fare/klavye almaması, kapanışta odak dönüşü (host'un geri verdiği
## odağın çalınmaması), eylemsiz durumda odak verilmemesi ve Esc ile sonuçsuz kapanış.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")
const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")
const MiniGameHostScript := preload("res://scripts/ui/mini_game_host.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

const SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"

var _viewport: SubViewport
var _view: MainHudViewScript
var _repairs: Array = []
var _intents: int = 0


func test_api_forwards_to_host() -> void:
	await _mount(_model())
	assert_false(_view.is_mini_game_open())
	assert_false(_view.open_mini_game(null), "null oturum açılmamalı.")
	assert_eq(_root().focus_behavior_recursive, Control.FOCUS_BEHAVIOR_INHERITED, "Başarısız açılış kilitlememeli.")
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	assert_true(_view.open_mini_game(session))
	assert_true(_view.is_mini_game_open() and _host().is_open())
	assert_true(_cable().get_session() == session)
	assert_false(_view.open_mini_game(UiFixtures.standard_session()), "İkinci açma yok sayılmalı.")
	assert_true(_view.close_mini_game())
	assert_false(_view.is_mini_game_open())
	assert_false(_view.close_mini_game())
	await _finish()


func test_repair_finished_emitted_once() -> void:
	await _mount(_model())
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_view.open_mini_game(session)
	await UiFixtures.settle()
	for terminal: StringName in [&"terminal_a", &"terminal_b", &"terminal_c", &"terminal_d"]:
		UiFixtures.click(_viewport, _cable().get_terminal_button(terminal))
	UiFixtures.click(_viewport, UiFixtures.check_button(_cable()))
	UiFixtures.click(_viewport, UiFixtures.check_button(_cable()))
	assert_eq(_repairs, [session], "repair_finished aynı oturumla tam bir kez yayılmalı.")
	assert_true(_view.is_mini_game_open(), "Tamamlanınca otomatik kapanmamalı.")
	_view.close_mini_game()
	assert_eq(_repairs.size(), 1)
	await _finish()


func test_show_model_while_open_keeps_lock_and_cable_focus() -> void:
	var warnings: UiFixtures.WarningCapture = UiFixtures.WarningCapture.new()
	OS.add_logger(warnings)
	await _mount(_model())
	_view.focus_first_available_action()
	_view.open_mini_game(UiFixtures.standard_session())
	await UiFixtures.settle()
	var cable_focus: Control = _focused()
	assert_true(_cable().is_ancestor_of(cable_focus))
	var changed: MainHudModelScript = _model()
	changed.choices.remove_at(0)
	_view.show_model(changed)
	_view.show_model(_model())
	assert_true(_focused() == cable_focus, "show_model mini oyun odağını korumalı.")
	assert_eq([_root().focus_behavior_recursive, _root().mouse_behavior_recursive],
			[Control.FOCUS_BEHAVIOR_DISABLED, Control.MOUSE_BEHAVIOR_DISABLED], "Kilit değişmemeli.")
	for button: Button in _hud_buttons():
		assert_eq(button.get_focus_mode_with_override(), Control.FOCUS_NONE, "%s odak almamalı." % button.name)
		assert_eq(button.get_mouse_filter_with_override(), Control.MOUSE_FILTER_IGNORE, "%s fare almamalı." % button.name)
	assert_false(_view.focus_first_available_action(), "Açıkken HUD'a odak verilmez.")
	assert_true(_view.is_mini_game_open(), "Yenileme mini oyunu kapatmamalı.")
	OS.remove_logger(warnings)
	assert_eq(warnings.take_warnings(), PackedStringArray(), "Kilitli düğmeye odak denenmemeli (uyarı yok).")
	await _finish()


func test_hud_actions_receive_no_input_while_open() -> void:
	await _mount(_model())
	_view.open_mini_game(UiFixtures.standard_session())
	await UiFixtures.settle()
	for i in 10:
		UiFixtures.key(_viewport, KEY_TAB)
		assert_false(_root().is_ancestor_of(_focused()), "Tab HUD'a geçmemeli.")
	for button: Button in [_hud_button("WaitButton"), _hud_list_button("ChoiceList", 0)]:
		UiFixtures.click(_viewport, button)
	UiFixtures.key(_viewport, KEY_ENTER)
	assert_eq(_intents, 0, "Açıkken HUD niyet sinyali yaymamalı.")
	await _finish()


func test_close_keeps_focus_restored_by_host() -> void:
	await _mount(_model())
	_hud_button("WaitButton").grab_focus()
	_view.open_mini_game(UiFixtures.standard_session())
	await UiFixtures.settle()
	_view.close_mini_game()
	assert_true(_focused() == _hud_button("WaitButton"), "Host'un geri verdiği odak ilk eylemle değiştirilmemeli.")
	await _finish()


func test_close_without_valid_previous_focus_moves_to_first_action() -> void:
	await _mount(_model())
	_hud_list_button("ChoiceList", 1).grab_focus()
	_view.open_mini_game(UiFixtures.standard_session())
	await UiFixtures.settle()
	var changed: MainHudModelScript = _model()
	changed.choices.remove_at(1)
	_view.show_model(changed)
	_view.close_mini_game()
	assert_true(_focused() == _hud_list_button("RepairList", 0), "Geçerli eski odak yoksa ilk etkin eylem; gelen %s" % _focus_name())
	await _finish()


func test_close_with_no_actions_gives_no_focus() -> void:
	await _mount(null)
	_view.open_mini_game(UiFixtures.standard_session())
	await UiFixtures.settle()
	_view.close_mini_game()
	assert_true(_focused() == null or not _root().is_ancestor_of(_focused()), "Eylem yoksa HUD'a odak verilmemeli.")
	assert_true(_focused() == null, "Kapanan mini oyunun odağı kalmamalı.")
	await _finish()


func test_escape_closes_without_repair_result() -> void:
	await _mount(_model())
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	_view.open_mini_game(session)
	await UiFixtures.settle()
	var before: Array = UiFixtures.snapshot(session)
	UiFixtures.key(_viewport, KEY_ESCAPE)
	assert_false(_view.is_mini_game_open())
	assert_eq(_repairs, [])
	assert_eq(UiFixtures.snapshot(session), before)
	assert_eq([_root().focus_behavior_recursive, _root().mouse_behavior_recursive],
			[Control.FOCUS_BEHAVIOR_INHERITED, Control.MOUSE_BEHAVIOR_INHERITED], "Önceki değerler geri yüklenmeli.")
	UiFixtures.key(_viewport, KEY_ESCAPE)
	assert_false(_view.is_mini_game_open(), "Kapalıyken Esc hiçbir şey yapmaz.")
	await _finish()


# --- Yardımcılar ---

func _mount(model: MainHudModelScript) -> void:
	_viewport = UiFixtures.make_viewport(Vector2i(1920, 1080))
	_view = (load(SCENE_PATH) as PackedScene).instantiate() as MainHudViewScript
	_viewport.add_child(_view)
	_view.show_model(model)
	_repairs = []
	_intents = 0
	_view.repair_finished.connect(func(session: RefCounted) -> void: _repairs.append(session))
	for signal_name: String in ["assign_requested", "choice_requested", "repair_requested"]:
		_view.connect(signal_name, func(_id: StringName) -> void: _intents += 1)
	for signal_name: String in ["wait_requested", "next_night_requested"]:
		_view.connect(signal_name, func() -> void: _intents += 1)
	await UiFixtures.settle()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _root() -> Control:
	return _view.get_node("%Root") as Control


func _host() -> MiniGameHostScript:
	return _view.get_node("%MiniGameHost") as MiniGameHostScript


func _cable() -> CablePuzzleViewScript:
	return _host().get_view() as CablePuzzleViewScript


func _focused() -> Control:
	return _viewport.gui_get_focus_owner()


func _focus_name() -> String:
	var focused: Control = _focused()
	return "yok" if focused == null else String(focused.name)


func _hud_button(node_name: String) -> Button:
	return _view.get_node("%" + node_name) as Button


func _hud_list_button(list_name: String, index: int) -> Button:
	return _view.get_node("%" + list_name).get_child(index) as Button


func _hud_buttons() -> Array[Button]:
	var result: Array[Button] = [_hud_button("WaitButton"), _hud_button("NextNightButton")]
	for list_name: String in ["RepairList", "ChoiceList", "AssignmentList"]:
		for child: Node in _view.get_node("%" + list_name).get_children():
			if child is Button:
				result.append(child)
	return result


static func _model() -> MainHudModelScript:
	var model: MainHudModelScript = MainHudModelScript.new()
	model.has_session = true
	model.night = 1
	model.night_count = 2
	model.decision_id = &"decision_a"
	var repair: MainHudModelScript.RepairRow = MainHudModelScript.RepairRow.new()
	repair.puzzle_id = &"puzzle_a"
	repair.available = true
	model.repairs.append(repair)
	for choice_id: StringName in [&"choice_a", &"choice_b"]:
		var choice: MainHudModelScript.ChoiceRow = MainHudModelScript.ChoiceRow.new()
		choice.choice_id = choice_id
		choice.available = true
		model.choices.append(choice)
	model.can_wait = true
	model.can_start_night = true
	return model
