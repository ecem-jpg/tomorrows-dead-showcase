extends "res://tests/framework/test_case.gd"
## MainHudView: gerekli düğümler, oturumsuz ve dolu model gösterimi, satırların tekrarlanmaması, show_model'in sinyal
## yaymaması, etkin düğmelerin doğru kimlikle tam bir sinyal yayması, devre dışı eylemler, özel karakterli kimlikler,
## son paneli ve bağımsız model kopyası. Girdi gerçek fare olaylarıyla verilir.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")
const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")

const SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"
const UNIQUE_NODES: Array[String] = ["NightLabel", "TimeLabel", "ResourceList", "BodyList", "EquipmentList",
		"RepairList", "DecisionLabel", "AdviceLabel", "ChoiceList", "TaskList", "AssignmentList", "WaitButton",
		"NextNightButton", "FeedbackLabel", "EndingPanel", "EndingLabel"]
const SIGNALS: Array[String] = ["assign_requested", "choice_requested", "wait_requested", "next_night_requested",
		"repair_requested"]

var _viewport: SubViewport
var _view: MainHudViewScript
var _emitted: Array = []


func test_required_nodes_exist() -> void:
	await _mount()
	for node_name: String in UNIQUE_NODES:
		assert_true(_view.get_node_or_null("%" + node_name) != null, "%s bulunmalı." % node_name)
	for path: String in ["HudLayer/Root/Margin/Layout/TopBar", "HudLayer/Root/Margin/Layout/Body/LeftColumn/BodiesPanel",
			"HudLayer/Root/Margin/Layout/Body/LeftColumn/EquipmentPanel", "HudLayer/Root/Margin/Layout/Body/CenterColumn/DecisionPanel",
			"HudLayer/Root/Margin/Layout/Body/RightColumn/TasksPanel", "HudLayer/Root/Margin/Layout/Body/RightColumn/ActionsPanel",
			"HudLayer/Root/Margin/Layout/StatusBar"]:
		assert_true(_view.get_node_or_null(path) != null, "%s bulunmalı." % path)
	await _finish()


func test_session_less_model_is_shown_safely() -> void:
	await _mount()
	assert_true(_view.get_last_model() == null, "Model verilmeden önce null.")
	_view.show_model(null)
	assert_false(_view.get_last_model().has_session)
	for list_name: String in ["ResourceList", "BodyList", "EquipmentList", "RepairList", "ChoiceList", "TaskList",
			"AssignmentList"]:
		assert_eq(_texts(list_name), ["UI_HUD_EMPTY"], "%s boş durum göstermeli." % list_name)
	assert_eq(_text("FeedbackLabel"), "UI_HUD_NO_SESSION")
	assert_eq(_text("AdviceLabel"), "UI_HUD_ADVICE_NONE")
	assert_true(_button("WaitButton").disabled and _button("NextNightButton").disabled)
	# Satırlar kullanılabilir olsa bile oturum yoksa bütün eylemler kapalıdır.
	var model: MainHudModelScript = _model()
	model.has_session = false
	_view.show_model(model)
	for button: Button in _all_buttons():
		assert_true(button.disabled and button.focus_mode == Control.FOCUS_NONE, "%s kapalı olmalı." % button.name)
	assert_false(_node("EndingPanel").visible)
	await _finish()


func test_filled_model_rows_and_texts() -> void:
	await _mount()
	_view.show_model(_model())
	assert_eq(_text("NightLabel"), "UI_HUD_NIGHT 1 / 2")
	assert_eq(_text("TimeLabel"), "UI_HUD_TIME 3 / 10")
	assert_eq(_texts("ResourceList"), ["resource_a: 3", "resource_b: 0"])
	assert_eq(_texts("BodyList"), ["occurrence_a · subject_a · 1 · UI_HUD_BODY_PRESENT",
			"occurrence_b · subject_b · 2 · UI_HUD_BODY_PERMANENT"])
	assert_eq(_texts("EquipmentList"), ["equipment_a · UI_HUD_STATUS_OPERATIONAL · 0",
			"equipment_b · UI_HUD_STATUS_DISABLED · 2"])
	assert_eq(_texts("TaskList"), ["task_a · actor_b · 3"])
	assert_eq(_texts("RepairList"), ["UI_HUD_REPAIR · puzzle_a"])
	assert_eq(_texts("ChoiceList"), ["choice_a", "choice_b"])
	assert_eq(_texts("AssignmentList"), ["task_b · actor_a → actor_b"])
	assert_eq(_text("DecisionLabel"), "UI_HUD_DECISION: decision_a")
	assert_eq(_text("AdviceLabel"), "UI_HUD_ADVICE: actor_b → choice_b")
	assert_eq(_text("FeedbackLabel"), "UI_HUD_DONE")
	assert_eq(_names("ChoiceList"), ["ChoiceButton0", "ChoiceButton1"])
	assert_eq(_names("ResourceList"), ["ResourceRow0", "ResourceRow1"])
	assert_eq([_button("WaitButton").disabled, _button("NextNightButton").disabled], [false, true])
	await _finish()


func test_same_model_again_does_not_duplicate_rows() -> void:
	await _mount()
	var model: MainHudModelScript = _model()
	_view.show_model(model)
	var first: Array = _snapshot()
	_view.show_model(model)
	_view.show_model(model)
	assert_eq(_snapshot(), first, "Aynı kare içinde bile satırlar kopyalanmamalı.")
	await UiFixtures.settle()
	assert_eq(_snapshot(), first)
	await _finish()


func test_show_model_emits_no_signals() -> void:
	await _mount()
	for model: Variant in [_model(), null, _model(), MainHudModelScript.empty(&"UI_HUD_ERROR"), _model()]:
		_view.show_model(model)
	await UiFixtures.settle()
	assert_eq(_emitted, [], "show_model hiçbir niyet sinyali yaymamalı.")
	await _finish()


func test_enabled_buttons_emit_once_with_their_id() -> void:
	await _mount()
	var model: MainHudModelScript = _model()
	model.can_start_night = true
	_view.show_model(model)
	await UiFixtures.settle()
	_click(_child("RepairList", 0))
	_click(_child("ChoiceList", 1))
	_click(_child("AssignmentList", 0))
	_click(_button("WaitButton"))
	_click(_button("NextNightButton"))
	assert_eq(_emitted, [["repair_requested", &"puzzle_a"], ["choice_requested", &"choice_b"],
			["assign_requested", &"task_b"], ["wait_requested"], ["next_night_requested"]])
	await _finish()


func test_disabled_actions_emit_nothing() -> void:
	await _mount()
	var model: MainHudModelScript = _model()
	model.choices[1].available = false
	model.repairs[0].available = false
	model.assignable[0].available = false
	model.can_wait = false
	_view.show_model(model)
	await UiFixtures.settle()
	for button: Button in [_child("RepairList", 0), _child("ChoiceList", 1), _child("AssignmentList", 0),
			_button("WaitButton"), _button("NextNightButton")]:
		assert_true(button.disabled)
		_click(button)
	assert_eq(_emitted, [], "Devre dışı düğmeler sinyal yaymamalı.")
	_click(_child("ChoiceList", 0))
	assert_eq(_emitted, [["choice_requested", &"choice_a"]])
	await _finish()


func test_repeated_show_does_not_double_callbacks() -> void:
	await _mount()
	var model: MainHudModelScript = _model()
	for i in 3:
		_view.show_model(model)
	await UiFixtures.settle()
	_click(_child("ChoiceList", 0))
	_click(_button("WaitButton"))
	assert_eq(_emitted, [["choice_requested", &"choice_a"], ["wait_requested"]])
	await _finish()


func test_special_character_ids_are_safe() -> void:
	await _mount()
	var odd_choice: StringName = &"seçenek/ç:ö ü"
	var odd_task: StringName = &"görev.a b/c"
	var odd_puzzle: StringName = &"bulmaca:1/ş"
	var model: MainHudModelScript = _model()
	model.choices[0].choice_id = odd_choice
	model.assignable[0].task_id = odd_task
	model.repairs[0].puzzle_id = odd_puzzle
	model.resources[0].resource_id = &"kaynak/ğ:1"
	_view.show_model(model)
	await UiFixtures.settle()
	assert_eq(take_engine_errors(), PackedStringArray(), "Özel karakterli kimlikler hata üretmemeli.")
	assert_eq(_names("ChoiceList"), ["ChoiceButton0", "ChoiceButton1"])
	assert_eq(_child("ChoiceList", 0).get_meta(MainHudViewScript.ID_META), odd_choice)
	assert_eq(_texts("ChoiceList")[0], String(odd_choice))
	assert_eq(_texts("ResourceList")[0], "kaynak/ğ:1: 3")
	_click(_child("ChoiceList", 0))
	_click(_child("AssignmentList", 0))
	_click(_child("RepairList", 0))
	assert_eq(_emitted, [["choice_requested", odd_choice], ["assign_requested", odd_task], ["repair_requested", odd_puzzle]])
	await _finish()


func test_ending_panel_visibility() -> void:
	await _mount()
	var model: MainHudModelScript = _model()
	_view.show_model(model)
	assert_false(_node("EndingPanel").visible)
	model.ending_id = &"ending_a"
	_view.show_model(model)
	assert_true(_node("EndingPanel").visible)
	assert_eq(_text("EndingLabel"), "UI_HUD_ENDING: ending_a")
	model.has_session = false
	_view.show_model(model)
	assert_false(_node("EndingPanel").visible, "Oturum yoksa son gösterilmez.")
	await _finish()


func test_last_model_is_an_independent_copy() -> void:
	await _mount()
	var model: MainHudModelScript = _model()
	_view.show_model(model)
	model.resources[0].value = 99
	model.choices.clear()
	var last: MainHudModelScript = _view.get_last_model()
	assert_eq(last.resources[0].value, 3, "Verilen modelin sonradan değişmesi görünümü etkilememeli.")
	assert_eq(last.choices.size(), 2)
	last.feedback_key = &"changed"
	last.repairs.clear()
	assert_eq(_view.get_last_model().feedback_key, &"UI_HUD_DONE")
	assert_eq(_view.get_last_model().repairs.size(), 1)
	assert_eq(_texts("ResourceList")[0], "resource_a: 3")
	await _finish()


func test_dynamic_nodes_carry_only_their_id() -> void:
	await _mount()
	_view.show_model(_model())
	for list_name: String in ["ResourceList", "BodyList", "EquipmentList", "RepairList", "ChoiceList", "TaskList",
			"AssignmentList"]:
		for child: Node in _view.get_node("%" + list_name).get_children():
			var metas: Array = Array(child.get_meta_list())
			assert_true(metas.is_empty() or metas == [MainHudViewScript.ID_META], "%s/%s yalnız kimlik taşımalı." % [list_name, child.name])
	await _finish()


# --- Yardımcılar ---

func _mount() -> void:
	_viewport = UiFixtures.make_viewport(Vector2i(1920, 1080))
	_view = (load(SCENE_PATH) as PackedScene).instantiate() as MainHudViewScript
	_viewport.add_child(_view)
	_emitted = []
	for signal_name: String in SIGNALS:
		_view.connect(signal_name, _on_view_signal.bind(signal_name))
	await UiFixtures.settle()


func _on_view_signal(a: Variant = null, b: Variant = null) -> void:
	# Bağlı argüman sona eklenir: kimlikli sinyallerde (kimlik, ad), kimliksizlerde (ad).
	if b == null:
		_emitted.append([a])
	else:
		_emitted.append([b, a])


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


func _click(control: Control) -> void:
	UiFixtures.click(_viewport, control)


func _node(node_name: String) -> Control:
	return _view.get_node("%" + node_name) as Control


func _button(node_name: String) -> Button:
	return _node(node_name) as Button


func _text(node_name: String) -> String:
	return (_node(node_name) as Label).text


func _child(list_name: String, index: int) -> Button:
	return _view.get_node("%" + list_name).get_child(index) as Button


func _texts(list_name: String) -> Array:
	return _view.get_node("%" + list_name).get_children().map(func(child: Node) -> String: return child.get("text"))


func _names(list_name: String) -> Array:
	return _view.get_node("%" + list_name).get_children().map(func(child: Node) -> String: return String(child.name))


func _all_buttons() -> Array[Button]:
	var result: Array[Button] = [_button("WaitButton"), _button("NextNightButton")]
	for list_name: String in ["RepairList", "ChoiceList", "AssignmentList"]:
		for child: Node in _view.get_node("%" + list_name).get_children():
			if child is Button:
				result.append(child)
	return result


func _snapshot() -> Array:
	var result: Array = []
	for list_name: String in ["ResourceList", "BodyList", "EquipmentList", "RepairList", "ChoiceList", "TaskList",
			"AssignmentList"]:
		result.append([list_name, _view.get_node("%" + list_name).get_child_count(), _names(list_name), _texts(list_name)])
	for node_name: String in ["NightLabel", "TimeLabel", "DecisionLabel", "AdviceLabel", "FeedbackLabel"]:
		result.append(_text(node_name))
	return result


## Dolu ve tarafsız bir model: iki seçenek, bir atama, bir tamir, iki ceset, iki ekipman, iki kaynak.
static func _model() -> MainHudModelScript:
	var model: MainHudModelScript = MainHudModelScript.new()
	model.has_session = true
	model.night = 1
	model.night_count = 2
	model.elapsed_units = 3
	model.night_length_units = 10
	for entry: Array in [[&"resource_a", 3], [&"resource_b", 0]]:
		var row: MainHudModelScript.ResourceRow = MainHudModelScript.ResourceRow.new()
		row.resource_id = entry[0]
		row.value = entry[1]
		model.resources.append(row)
	var task: MainHudModelScript.TaskRow = MainHudModelScript.TaskRow.new()
	task.task_id = &"task_a"
	task.assigned_actor_id = &"actor_b"
	task.remaining_units = 3
	model.tasks.append(task)
	var assignable: MainHudModelScript.AssignableRow = MainHudModelScript.AssignableRow.new()
	assignable.task_id = &"task_b"
	assignable.active_actor_id = &"actor_a"
	assignable.assigned_actor_id = &"actor_b"
	assignable.available = true
	model.assignable.append(assignable)
	for entry: Array in [[&"equipment_a", &"operational", 0, true], [&"equipment_b", &"disabled", 2, false]]:
		var row: MainHudModelScript.EquipmentRow = MainHudModelScript.EquipmentRow.new()
		row.equipment_id = entry[0]
		row.status = entry[1]
		row.disabled_units = entry[2]
		row.usable = entry[3]
		model.equipment.append(row)
	var repair: MainHudModelScript.RepairRow = MainHudModelScript.RepairRow.new()
	repair.puzzle_id = &"puzzle_a"
	repair.available = true
	model.repairs.append(repair)
	for entry: Array in [[&"occurrence_a", &"subject_a", 1, &"present"], [&"occurrence_b", &"subject_b", 2, &"permanent"]]:
		var row: MainHudModelScript.BodyRow = MainHudModelScript.BodyRow.new()
		row.occurrence_id = entry[0]
		row.subject_id = entry[1]
		row.night = entry[2]
		row.presence = entry[3]
		model.bodies.append(row)
	model.decision_id = &"decision_a"
	for choice_id: StringName in [&"choice_a", &"choice_b"]:
		var row: MainHudModelScript.ChoiceRow = MainHudModelScript.ChoiceRow.new()
		row.choice_id = choice_id
		row.available = true
		model.choices.append(row)
	model.advice_offered = true
	model.advisor_actor_id = &"actor_b"
	model.recommended_choice_id = &"choice_b"
	model.can_wait = true
	model.feedback_key = &"UI_HUD_DONE"
	return model
