extends RefCounted
## Görev testleri için tarafsız veri ve sistem kurucuları (K-018). Oyun içeriği değildir.
## Dünya decision_fixtures ile aynıdır: res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30;
## zaman 2 gece × 10 birim, action_a = 2, action_b = 0. actor_c güven ilişkisi olmayan bir aktördür.

const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const TaskAssignmentDataScript := preload("res://scripts/data/task_assignment_data.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")


## conditions içindeki null değerler boş kayıt olarak eklenir.
static func make_task(id: String, duration_units: int, active_actor_id: String, assigned_actor_id: String,
		conditions: Array = [], action_id: String = "", completion_effects: Array = []) -> TaskDataScript:
	var assignment: TaskAssignmentDataScript = TaskAssignmentDataScript.new()
	assignment.active_actor_id = active_actor_id
	assignment.assigned_actor_id = assigned_actor_id
	assignment.action_id = action_id
	for condition in conditions:
		assignment.acceptance_conditions.append(condition)
	var task: TaskDataScript = TaskDataScript.new()
	task.id = id
	task.duration_units = duration_units
	task.assignment = assignment
	for effect in completion_effects:
		task.completion_effects.append(effect)
	return task


## Tamamlanma kataloğu, tasks içindeki tanımlanabilir kayıtlardan (boş olmayan, tekil kimlikli) ve
## extra_definitions'tan kurulur. Böylece TaskSystem'in kendi yapılandırma hataları tamamlanma sisteminde
## ikinci kez raporlanmaz.
static func make_system(world: DecisionFixtures.World, tasks: Array, extra_definitions: Array = []) -> TaskSystemScript:
	var catalog: Array = []
	var seen_ids: Array[String] = []
	for task in tasks:
		if task != null and not task.id.is_empty() and not seen_ids.has(task.id):
			seen_ids.append(task.id)
			catalog.append(task)
	catalog.append_array(extra_definitions)
	return make_system_with(world, tasks, DecisionFixtures.make_completion_system(world, catalog))


## Paylaşılan bir tamamlanma sistemiyle (ör. karar sistemiyle aynı örnek) TaskSystem kurar.
static func make_system_with(world: DecisionFixtures.World, tasks: Array,
		completions: TaskCompletionSystemScript) -> TaskSystemScript:
	var typed: Array[TaskDataScript] = []
	for task in tasks:
		typed.append(task)
	return TaskSystemScript.new(world.state, world.trust, world.time, completions, typed)
