extends "res://tests/framework/test_case.gd"
## MainHudView odağı: ilk etkin eylem, tam ileri ve geri sıra (tamir → seçenekler → atamalar → Bekle → Sonraki gece),
## devre dışı eylemlerin atlanması, tek düğümlü döngü, eylemsiz durum, yenilemede odağın korunması ve kaldırılan
## odak sahibinin güvenli yeni odağı. Girdi gerçek klavye olaylarıyla verilir.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")
const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")

const SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"

var _viewport: SubViewport
var _view: MainHudViewScript


func test_first_available_action_gets_focus() -> void:
	await _mount(_model())
	assert_false(_owns_focus(), "show_model odak çalmamalı.")
	assert_true(_view.focus_first_available_action())
	assert_true(_focused() == _child("RepairList", 0))
	await _finish()


func test_full_forward_order() -> void:
	await _mount(_model())
	var expected: Array[Control] = _expected_chain()
	assert_eq(expected.size(), 6)
	_view.focus_first_available_action()
	for i in expected.size():
		var target: Control = expected[(i + 1) % expected.size()]
		_key(KEY_TAB)
		assert_true(_focused() == target, "Tab %d: %s bekleniyordu, gelen %s" % [i + 1, target.name, _focus_name()])
	await _finish()


func test_full_backward_order() -> void:
	await _mount(_model())
	var expected: Array[Control] = _expected_chain()
	_view.focus_first_available_action()
	for i in expected.size():
		var target: Control = expected[(expected.size() - 1 - i) % expected.size()]
		_key(KEY_TAB, true)
		assert_true(_focused() == target, "Shift+Tab %d: %s bekleniyordu, gelen %s" % [i + 1, target.name, _focus_name()])
	await _finish()


func test_disabled_actions_are_skipped() -> void:
	var model: MainHudModelScript = _model()
	model.choices[0].available = false
	model.repairs[0].available = false
	model.can_start_night = false
	await _mount(model)
	var expected: Array[Control] = [_child("ChoiceList", 1), _child("AssignmentList", 0), _button("WaitButton")]
	for button: Button in [_child("ChoiceList", 0), _child("RepairList", 0), _button("NextNightButton")]:
		assert_eq(button.focus_mode, Control.FOCUS_NONE, "%s odak almamalı." % button.name)
		assert_eq(button.focus_next, NodePath(), "%s zincirde olmamalı." % button.name)
	_view.focus_first_available_action()
	assert_true(_focused() == expected[0])
	for i in expected.size():
		_key(KEY_TAB)
		assert_true(_focused() == expected[(i + 1) % expected.size()], "Tab %d: gelen %s" % [i + 1, _focus_name()])
	await _finish()


func test_single_action_loops_to_itself() -> void:
	var model: MainHudModelScript = _model()
	model.repairs.clear()
	model.choices.clear()
	model.assignable.clear()
	model.can_start_night = false
	await _mount(model)
	var wait: Button = _button("WaitButton")
	assert_true(wait.get_node(wait.focus_next) == wait and wait.get_node(wait.focus_previous) == wait)
	_view.focus_first_available_action()
	_key(KEY_TAB)
	assert_true(_focused() == wait)
	_key(KEY_TAB, true)
	assert_true(_focused() == wait)
	await _finish()


func test_no_actions_means_no_focus() -> void:
	await _mount(_model())
	_view.focus_first_available_action()
	assert_true(_owns_focus())
	_view.show_model(null)
	assert_false(_owns_focus(), "Etkin eylem kalmayınca görünüme ait odak bırakılmalı.")
	assert_false(_view.focus_first_available_action())
	assert_false(_owns_focus())
	_key(KEY_TAB)
	assert_false(_owns_focus(), "Devre dışı eylemlere Tab ile odak gelmemeli.")
	await _finish()


func test_refresh_keeps_valid_focus() -> void:
	await _mount(_model())
	_button("WaitButton").grab_focus()
	_view.show_model(_model())
	assert_true(_focused() == _button("WaitButton"), "Statik odak korunmalı.")
	var old_choice: Button = _child("ChoiceList", 1)
	old_choice.grab_focus()
	_view.show_model(_model())
	var new_choice: Button = _child("ChoiceList", 1)
	assert_true(new_choice != old_choice, "Dinamik düğmeler yeniden kurulur.")
	assert_true(_focused() == new_choice, "Aynı kimlikli yeni düğme odağı almalı.")
	await _finish()


func test_removed_focus_owner_moves_to_first_action() -> void:
	await _mount(_model())
	_child("ChoiceList", 1).grab_focus()
	var model: MainHudModelScript = _model()
	model.choices.remove_at(1)
	_view.show_model(model)
	assert_true(_focused() == _child("RepairList", 0), "Kaldırılan odak ilk etkin eyleme geçmeli; gelen %s" % _focus_name())
	_button("NextNightButton").grab_focus()
	var closed: MainHudModelScript = _model()
	closed.can_start_night = false
	_view.show_model(closed)
	assert_true(_focused() == _child("RepairList", 0), "Kapanan statik eylemin odağı ilk etkin eyleme geçmeli.")
	await _finish()


# --- Yardımcılar ---

func _mount(model: MainHudModelScript) -> void:
	_viewport = UiFixtures.make_viewport(Vector2i(1920, 1080))
	_view = (load(SCENE_PATH) as PackedScene).instantiate() as MainHudViewScript
	_viewport.add_child(_view)
	_view.show_model(model)
	await UiFixtures.settle()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _key(keycode: Key, shift: bool = false) -> void:
	UiFixtures.key(_viewport, keycode, shift)


func _focused() -> Control:
	return _viewport.gui_get_focus_owner()


func _owns_focus() -> bool:
	return UiFixtures.owns_focus(_view, _viewport)


func _focus_name() -> String:
	var focused: Control = _focused()
	return "yok" if focused == null else String(focused.name)


func _button(node_name: String) -> Button:
	return _view.get_node("%" + node_name) as Button


func _child(list_name: String, index: int) -> Button:
	return _view.get_node("%" + list_name).get_child(index) as Button


## Varsayılan modelde beklenen zincir: tamir, iki seçenek, atama, Bekle, Sonraki gece.
func _expected_chain() -> Array[Control]:
	return [_child("RepairList", 0), _child("ChoiceList", 0), _child("ChoiceList", 1), _child("AssignmentList", 0),
			_button("WaitButton"), _button("NextNightButton")]


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
	var assignable: MainHudModelScript.AssignableRow = MainHudModelScript.AssignableRow.new()
	assignable.task_id = &"task_a"
	assignable.active_actor_id = &"actor_a"
	assignable.assigned_actor_id = &"actor_b"
	assignable.available = true
	model.assignable.append(assignable)
	model.can_wait = true
	model.can_start_night = true
	return model
