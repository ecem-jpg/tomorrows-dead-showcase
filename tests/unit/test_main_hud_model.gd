extends "res://tests/framework/test_case.gd"
## MainHudModel: oturumsuz model, isimli alanlı satırlar, bağımsız kopyalar ve gizli öneri alanlarının yokluğu.

const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")

const FORBIDDEN_FIELDS: Array[String] = ["accuracy", "variant", "variant_id", "failed_condition_indexes",
		"internal_skip_reasons", "trust", "condition"]
const ROW_FIELDS: Dictionary = {
	"resources": ["resource_id", "value"],
	"tasks": ["task_id", "assigned_actor_id", "remaining_units"],
	"assignable": ["task_id", "active_actor_id", "assigned_actor_id", "available"],
	"equipment": ["equipment_id", "status", "disabled_units", "usable"],
	"repairs": ["puzzle_id", "available"],
	"bodies": ["occurrence_id", "subject_id", "night", "presence"],
	"choices": ["choice_id", "available"],
}


func test_empty_model_has_no_session_and_no_actions() -> void:
	var model: MainHudModelScript = MainHudModelScript.empty(&"UI_HUD_NO_SESSION")
	var data: Dictionary = model.to_dict()
	assert_false(model.has_session)
	assert_eq(model.feedback_key, &"UI_HUD_NO_SESSION")
	for key: String in ROW_FIELDS:
		assert_eq(data[key], [], "%s boş olmalı." % key)
	assert_eq([model.night, model.night_count, model.elapsed_units, model.night_length_units, model.night_ended],
			[0, 0, 0, 0, false])
	assert_eq([model.can_wait, model.can_start_night, model.advice_offered], [false, false, false])
	assert_eq([model.decision_id, model.recommended_choice_id, model.advisor_actor_id, model.ending_id], [&"", &"", &"", &""])
	assert_eq(MainHudModelScript.empty().feedback_key, &"")


func test_every_row_type_carries_named_fields() -> void:
	var data: Dictionary = _filled().to_dict()
	for key: String in ROW_FIELDS:
		assert_eq(data[key].size(), 1, "%s satırı olmalı." % key)
		if data[key].size() == 1:
			var fields: Array = data[key][0].keys()
			fields.sort()
			var expected: Array = ROW_FIELDS[key].duplicate()
			expected.sort()
			assert_eq(fields, expected, "%s alanları" % key)
	assert_eq(data["resources"][0], {"resource_id": &"resource_a", "value": 3})
	assert_eq(data["bodies"][0], {"occurrence_id": &"occurrence_a", "subject_id": &"subject_a", "night": 1,
			"presence": &"present"})


func test_copy_is_independent_and_equal() -> void:
	var original: MainHudModelScript = _filled()
	var copy: MainHudModelScript = original.copy()
	assert_true(copy.equals(original))
	assert_eq(copy.to_dict(), original.to_dict())
	copy.resources[0].value = 99
	copy.tasks.clear()
	copy.choices[0].available = false
	copy.bodies.append(MainHudModelScript.BodyRow.new())
	copy.feedback_key = &"changed"
	assert_eq(original.resources[0].value, 3)
	assert_eq(original.tasks.size(), 1)
	assert_true(original.choices[0].available)
	assert_eq(original.bodies.size(), 1)
	assert_eq(original.feedback_key, &"UI_HUD_DONE")
	assert_false(copy.equals(original))


func test_models_do_not_share_collections() -> void:
	var first: MainHudModelScript = MainHudModelScript.empty()
	var second: MainHudModelScript = MainHudModelScript.empty()
	first.resources.append(MainHudModelScript.ResourceRow.new())
	first.equipment.append(MainHudModelScript.EquipmentRow.new())
	assert_eq(second.resources.size(), 0)
	assert_eq(second.equipment.size(), 0)
	var dict: Dictionary = first.to_dict()
	dict["resources"].clear()
	assert_eq(first.resources.size(), 1, "to_dict bağımsız bir gösterimdir.")


func test_model_has_no_hidden_advice_or_internal_fields() -> void:
	var model: MainHudModelScript = _filled()
	var names: Array[String] = _script_fields(model)
	for row: RefCounted in [model.resources[0], model.tasks[0], model.assignable[0], model.equipment[0],
			model.repairs[0], model.bodies[0], model.choices[0]]:
		names.append_array(_script_fields(row))
	for name: String in names:
		for forbidden: String in FORBIDDEN_FIELDS:
			assert_false(name == forbidden or name.begins_with(forbidden + "_"), "Yasaklı alan: %s" % name)
	var text: String = str(model.to_dict())
	for forbidden: String in ["accuracy", "variant", "correct", "incomplete"]:
		assert_false(text.contains(forbidden), "Modelde '%s' izi olmamalı." % forbidden)


func test_equals_compares_content() -> void:
	assert_true(_filled().equals(_filled()))
	var changed: MainHudModelScript = _filled()
	changed.recommended_choice_id = &"choice_b"
	assert_false(changed.equals(_filled()))
	assert_false(_filled().equals(null))


func _filled() -> MainHudModelScript:
	var model: MainHudModelScript = MainHudModelScript.new()
	model.has_session = true
	model.night = 1
	model.night_count = 2
	model.elapsed_units = 3
	model.night_length_units = 10
	var resource: MainHudModelScript.ResourceRow = MainHudModelScript.ResourceRow.new()
	resource.resource_id = &"resource_a"
	resource.value = 3
	model.resources.append(resource)
	var task: MainHudModelScript.TaskRow = MainHudModelScript.TaskRow.new()
	task.task_id = &"task_a"
	task.assigned_actor_id = &"actor_b"
	task.remaining_units = 3
	model.tasks.append(task)
	var assignable: MainHudModelScript.AssignableRow = MainHudModelScript.AssignableRow.new()
	assignable.task_id = &"task_a"
	assignable.active_actor_id = &"actor_a"
	assignable.assigned_actor_id = &"actor_b"
	model.assignable.append(assignable)
	var equipment: MainHudModelScript.EquipmentRow = MainHudModelScript.EquipmentRow.new()
	equipment.equipment_id = &"equipment_a"
	equipment.status = &"operational"
	equipment.usable = true
	model.equipment.append(equipment)
	var repair: MainHudModelScript.RepairRow = MainHudModelScript.RepairRow.new()
	repair.puzzle_id = &"puzzle_a"
	repair.available = true
	model.repairs.append(repair)
	var body: MainHudModelScript.BodyRow = MainHudModelScript.BodyRow.new()
	body.occurrence_id = &"occurrence_a"
	body.subject_id = &"subject_a"
	body.night = 1
	body.presence = &"present"
	model.bodies.append(body)
	model.decision_id = &"decision_a"
	var choice: MainHudModelScript.ChoiceRow = MainHudModelScript.ChoiceRow.new()
	choice.choice_id = &"choice_a"
	choice.available = true
	model.choices.append(choice)
	model.advice_offered = true
	model.advisor_actor_id = &"actor_b"
	model.recommended_choice_id = &"choice_a"
	model.can_wait = true
	model.feedback_key = &"UI_HUD_DONE"
	return model


static func _script_fields(object: Object) -> Array[String]:
	var result: Array[String] = []
	for property: Dictionary in object.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.append(String(property["name"]))
	return result
