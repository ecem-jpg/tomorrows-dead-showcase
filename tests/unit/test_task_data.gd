extends "res://tests/framework/test_case.gd"
## TaskData'nın iç içe tipli alt kaynaklarla (atama → kabul koşulları) yüklenmesi ve doğrulanması.

const TaskDataScript := preload("res://scripts/data/task_data.gd")
const TaskAssignmentDataScript := preload("res://scripts/data/task_assignment_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/tasks"
const FIXTURE_PATH: String = "res://tests/fixtures/tasks/task_a.tres"
const FIXTURE_B_PATH: String = "res://tests/fixtures/tasks/task_b.tres"


func test_defaults_are_empty() -> void:
	var task: TaskDataScript = TaskDataScript.new()
	assert_eq([task.id, task.duration_units], ["", 0])
	assert_eq(task.assignment, null)
	var assignment: TaskAssignmentDataScript = TaskAssignmentDataScript.new()
	assert_eq([assignment.active_actor_id, assignment.assigned_actor_id, assignment.action_id], ["", "", ""])
	assert_eq(assignment.acceptance_conditions.size(), 0)
	assert_eq(assignment.acceptance_conditions.get_typed_script(), ConditionDataScript)


func test_task_fixture_loads_nested_typed_sub_resources() -> void:
	var resource: Resource = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null, "Örnek dosya yüklenemedi.")
	if resource == null:
		return
	assert_true(resource.get_script() == TaskDataScript, "Kaynak TaskData değil.")
	var task: TaskDataScript = resource as TaskDataScript
	assert_eq([task.id, task.duration_units], ["task_a", 4])
	assert_true(task.assignment != null and task.assignment.get_script() == TaskAssignmentDataScript)
	if task.assignment == null:
		return
	var assignment: TaskAssignmentDataScript = task.assignment
	assert_eq([assignment.active_actor_id, assignment.assigned_actor_id, assignment.action_id],
			["actor_a", "actor_b", "action_a"])
	assert_eq(assignment.acceptance_conditions.get_typed_script(), ConditionDataScript)
	assert_eq(assignment.acceptance_conditions.size(), 2)
	var trust: ConditionDataScript = assignment.acceptance_conditions[0]
	var flag: ConditionDataScript = assignment.acceptance_conditions[1]
	assert_true(trust.get_script() == ConditionDataScript and flag.get_script() == ConditionDataScript)
	assert_eq([trust.kind, trust.source_actor_id, trust.target_actor_id, trust.comparison, trust.value],
			[&"trust", "actor_b", "actor_a", &"ge", 20])
	assert_eq([flag.kind, flag.flag_id, flag.flag_value], [&"flag", "flag_a", true])


func test_completion_effects_load_as_typed_sub_resources() -> void:
	var resource: Resource = ResourceLoader.load(FIXTURE_B_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null and resource.get_script() == TaskDataScript, "task_b yüklenemedi.")
	if resource == null:
		return
	var task: TaskDataScript = resource as TaskDataScript
	assert_eq(task.id, "task_b")
	assert_eq(task.completion_effects.get_typed_script(), EffectDataScript)
	assert_eq(task.completion_effects.size(), 2)
	var add: EffectDataScript = task.completion_effects[0]
	var flag: EffectDataScript = task.completion_effects[1]
	assert_true(add.get_script() == EffectDataScript and flag.get_script() == EffectDataScript)
	assert_eq([add.kind, add.resource_id, add.amount], [&"resource_add", "res_a", 2])
	assert_eq([flag.kind, flag.flag_id, flag.flag_value], [&"flag_set", "flag_b", true])
	var without_effects: TaskDataScript = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as TaskDataScript
	assert_eq(without_effects.completion_effects.size(), 0)


func test_task_fixture_passes_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
