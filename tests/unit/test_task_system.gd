extends "res://tests/framework/test_case.gd"
## TaskSystem birim ve senaryo testleri (K-026). Yalnızca tarafsız kimlikler kullanılır (K-018).
## Dünya: res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30 (0..100);
## zaman 2 gece × 10 birim, action_a = 2, action_b = 0. actor_c güven ilişkisi olmayan bir aktördür.

const Fixtures := preload("res://tests/fixtures/task_fixtures.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const TaskAssignmentResultScript := preload("res://scripts/systems/task_assignment_result.gd")

const FIXTURE_PATH: String = "res://tests/fixtures/tasks/task_a.tres"


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var system: TaskSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), [_task_a(_trust_and_flag()), _task_b()])
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_true(system.has_task(&"task_a"))
	assert_false(system.has_task(&"missing_id"))


func test_fixture_file_builds_a_valid_system() -> void:
	var task: TaskDataScript = ResourceLoader.load(FIXTURE_PATH) as TaskDataScript
	var system: TaskSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), [task])
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_configuration_reports_task_level_errors_in_order() -> void:
	var missing_assignment: TaskDataScript = Fixtures.make_task("task_z", 4, "actor_a", "actor_b")
	missing_assignment.assignment = null
	var tasks: Array = [
		null,
		Fixtures.make_task("", 4, "actor_a", "actor_b"),
		Fixtures.make_task("task_x", 0, "actor_a", "actor_b"),
		Fixtures.make_task("task_y", 4, "actor_a", "actor_b"),
		Fixtures.make_task("task_y", 4, "actor_a", "actor_b"),
		missing_assignment,
	]
	var system: TaskSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), tasks)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız görev kaydı (#0)",
		"Boş görev kimliği (#1)",
		"'task_x': görev süresi pozitif olmalı (0)",
		"Tekrarlanan görev kimliği: 'task_y'",
		"'task_z': eksik atama",
	]))


func test_configuration_reports_assignment_errors_in_order() -> void:
	var tasks: Array = [
		Fixtures.make_task("task_a", 4, "", ""),
		Fixtures.make_task("task_b", 4, "actor_a", "actor_a"),
		Fixtures.make_task("task_c", 4, "actor_a", "actor_b", [], "missing_id"),
	]
	var system: TaskSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), tasks)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"'task_a' atama: eksik alan 'active_actor_id'",
		"'task_a' atama: eksik alan 'assigned_actor_id'",
		"'task_b' atama: kendine görev atama 'actor_a'",
		"'task_c' atama: tanımsız eylem 'missing_id'",
	]))
	assert_eq(take_engine_errors().size(), 0)


func test_condition_errors_match_the_decision_system_messages() -> void:
	# Koşul doğrulamasının tek kaynağı ortak değerlendiricidir: önek dışında metinler aynıdır.
	var make_conditions: Callable = func() -> Array:
		return [null, DecisionFixtures.cond_resource("missing_id", &"ge", 1),
				DecisionFixtures.cond_trust("actor_a", "actor_b", &"ge", 150), DecisionFixtures.make_condition(&"flag")]
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var task_errors: PackedStringArray = Fixtures.make_system(world,
			[Fixtures.make_task("task_a", 4, "actor_a", "actor_b", make_conditions.call())]).get_configuration_errors()
	var decision: Object = DecisionFixtures.make_decision("decision_a", [DecisionFixtures.make_choice("choice_a", make_conditions.call())])
	var decision_errors: PackedStringArray = DecisionFixtures.make_system(world, [decision]).get_configuration_errors()
	assert_eq(task_errors, PackedStringArray([
		"'task_a' koşul #0: tanımsız kayıt",
		"'task_a' koşul #1: tanımsız kaynak 'missing_id'",
		"'task_a' koşul #2: güven eşiği aralık dışında: 150",
		"'task_a' koşul #3: eksik alan 'flag_id'",
	]))
	assert_eq(_strip(task_errors, "'task_a' koşul "), _strip(decision_errors, "'decision_a' / 'choice_a' koşul "))


func test_dependency_system_errors_are_included() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var rules: TimeRulesDataScript = TimeRulesDataScript.new()
	rules.id = "time_rules_a"
	rules.night_count = 0
	rules.night_length_units = 10
	var no_events: Array[ScheduledEventDataScript] = []
	world.time = TimeSystemScript.new(world.state, rules, no_events)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a()])
	assert_eq(system.get_configuration_errors(), PackedStringArray(["TimeSystem: Gece sayısı en az 1 olmalı: 0"]))


func test_configuration_errors_are_deterministic() -> void:
	var build: Callable = func() -> PackedStringArray:
		var tasks: Array = [null, Fixtures.make_task("task_a", 0, "actor_a", "actor_a",
				[DecisionFixtures.cond_resource("missing_id", &"ge", 1)], "missing_id")]
		return Fixtures.make_system(DecisionFixtures.make_world(), tasks).get_configuration_errors()
	var first: PackedStringArray = build.call()
	assert_eq(first, build.call())
	assert_eq(first.size(), 5)


func test_task_data_is_copied_on_creation() -> void:
	var world: DecisionFixtures.World = _started_world()
	var task: TaskDataScript = _task_a(_trust_and_flag())
	var system: TaskSystemScript = Fixtures.make_system(world, [task])
	task.id = "task_z"
	task.duration_units = 0
	task.assignment.assigned_actor_id = "actor_c"
	task.assignment.action_id = "missing_id"
	task.assignment.acceptance_conditions[1].flag_value = false
	task.assignment.acceptance_conditions.append(null)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	world.state.set_flag(&"flag_a", true)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_accepted())
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])


# --- Kabul ve ret ---

func test_accepted_task_starts_for_the_requested_actor_in_one_write() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 20)])])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_accepted())
	assert_false(result.is_rejected() or result.is_failed())
	assert_eq(result.failure, &"")
	assert_eq([result.task_id, result.active_actor_id, result.assigned_actor_id], [&"task_a", &"actor_a", &"actor_b"])
	assert_true(result.started_task.equals(TimedTaskStateScript.new(&"task_a", &"actor_b", 4)))
	assert_eq(result.failed_condition_indexes, PackedInt32Array())
	assert_eq(result.time_result, null)
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(calls[0], 1)
	assert_eq(take_engine_errors().size(), 0)


func test_preview_has_no_side_effects_and_matches_assign() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")])
	var calls: Array[int] = _count_signals(world.state)
	var preview: TaskAssignmentResultScript = system.preview_assignment(&"task_a", &"actor_a", &"actor_b")
	assert_true(preview.is_accepted())
	assert_eq(preview.time_result.applied_units, 2)
	assert_eq(_task_rows(world.state), [])
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(calls[0], 0)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(_describe(result), _describe(preview))


func test_failing_condition_rejects_and_reports_indexes() -> void:
	var world: DecisionFixtures.World = _started_world()
	var conditions: Array = [DecisionFixtures.cond_resource("res_a", &"ge", 1), DecisionFixtures.cond_flag("flag_a", true),
			DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 50)]
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a(conditions)])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_rejected())
	assert_false(result.is_failed())
	assert_eq(result.failure, &"")
	assert_eq(result.failed_condition_indexes, PackedInt32Array([1, 2]))
	assert_eq(result.started_task, null)
	assert_eq(result.time_result, null)
	assert_eq(_task_rows(world.state), [])
	# Deneme maliyeti yoksa ret hiçbir şey yazmaz.
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_rejection_never_starts_another_task_or_actor() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_flag("flag_a", true)]), _task_b()])
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_rejected())
	assert_eq([result.task_id, result.active_actor_id, result.assigned_actor_id], [&"task_a", &"actor_a", &"actor_b"])
	assert_eq(_task_rows(world.state), [])


func test_rejection_spends_the_same_attempt_time_as_acceptance() -> void:
	var rejected_world: DecisionFixtures.World = _started_world()
	var rejecting: TaskSystemScript = Fixtures.make_system(rejected_world, [_task_a([DecisionFixtures.cond_flag("flag_a", true)], "action_a")])
	var calls: Array[int] = _count_signals(rejected_world.state)
	var rejected: TaskAssignmentResultScript = rejecting.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(rejected.is_rejected())
	assert_eq(rejected.time_result.applied_units, 2)
	assert_eq(rejected_world.state.get_elapsed_units(), 2)
	assert_eq(_task_rows(rejected_world.state), [])
	assert_eq(calls[0], 1)

	var accepted_world: DecisionFixtures.World = _started_world()
	var accepting: TaskSystemScript = Fixtures.make_system(accepted_world, [_task_a([], "action_a")])
	var accepted: TaskAssignmentResultScript = accepting.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(accepted.is_accepted())
	assert_eq(accepted_world.state.get_elapsed_units(), rejected_world.state.get_elapsed_units())


# --- Zaman ---

func test_attempt_time_comes_first_and_task_starts_with_full_duration() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(result.time_result.applied_units, 2)
	assert_eq(world.state.get_elapsed_units(), 2)
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])
	assert_eq(calls[0], 1)


func test_attempt_time_progresses_existing_tasks_in_the_same_write() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.time.start_task(&"task_x", &"actor_c", 1)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")], [DecisionFixtures.make_task_definition("task_x")])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_accepted())
	assert_eq(result.time_result.completed_task_ids(), [&"task_x"] as Array[StringName])
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])
	assert_eq(calls[0], 1)


func test_attempt_that_would_end_the_night_is_time_unavailable() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.time.advance(9)
	var system: TaskSystemScript = Fixtures.make_system(world, [
		_task_a([], "action_a"),
		Fixtures.make_task("task_b", 4, "actor_a", "actor_c", [DecisionFixtures.cond_flag("flag_a", true)], "action_a"),
	])
	var calls: Array[int] = _count_signals(world.state)
	for pair in [[&"task_a", &"actor_b"], [&"task_b", &"actor_c"]]:
		var result: TaskAssignmentResultScript = system.assign_task(pair[0], &"actor_a", pair[1])
		assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_TIME_UNAVAILABLE, str(pair))
		_assert_failed_result_is_empty(result)
	assert_eq(world.state.get_elapsed_units(), 9)
	assert_false(world.state.is_night_ended())
	assert_eq(_task_rows(world.state), [])
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_inactive_night_is_time_unavailable_even_without_cost() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	world.trust.initialize_relationships()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a(), Fixtures.make_task("task_b", 4, "actor_a", "actor_c", [], "action_b")])
	assert_eq(system.assign_task(&"task_a", &"actor_a", &"actor_b").failure, TaskAssignmentResultScript.FAILURE_TIME_UNAVAILABLE)
	assert_eq(system.assign_task(&"task_b", &"actor_a", &"actor_c").failure, TaskAssignmentResultScript.FAILURE_TIME_UNAVAILABLE)
	assert_eq(_task_rows(world.state), [])
	assert_eq(take_engine_errors().size(), 0)


# --- Meşguliyet ve tekrar ---

func test_busy_actor_returns_actor_busy_without_time_or_changes() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.time.start_task(&"task_x", &"actor_b", 5)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_flag("flag_a", true)], "action_a")],
			[DecisionFixtures.make_task_definition("task_x")])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_ACTOR_BUSY)
	_assert_failed_result_is_empty(result)
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(_task_rows(world.state), [["task_x", "actor_b", 5]])
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_active_task_returns_task_already_active() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")])
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_TASK_ALREADY_ACTIVE)
	_assert_failed_result_is_empty(result)
	assert_eq(world.state.get_elapsed_units(), 2)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_completed_task_can_be_assigned_again() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a()])
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	assert_eq(world.time.advance(4).completed_task_ids(), [&"task_a"] as Array[StringName])
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])


# --- Görev tamamlanma etkileri (K-027) ---

func test_attempt_time_applies_effects_of_completing_tasks() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.time.start_task(&"task_x", &"actor_c", 1)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")],
			[DecisionFixtures.make_task_definition("task_x", [DecisionFixtures.eff_add("res_a", 2)])])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_accepted())
	assert_eq(result.task_completions.size(), 1)
	assert_eq(result.task_completions[0].task_id, &"task_x")
	assert_eq(world.state.get_resource(&"res_a"), 7)
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])
	assert_eq(calls[0], 1)


func test_rejected_attempt_also_applies_completion_effects() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.time.start_task(&"task_x", &"actor_c", 1)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_flag("flag_a", true)], "action_a")],
			[DecisionFixtures.make_task_definition("task_x", [DecisionFixtures.eff_add("res_a", 2)])])
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_rejected())
	assert_eq(result.task_completions.size(), 1)
	assert_eq(world.state.get_resource(&"res_a"), 7)
	assert_eq(world.state.get_elapsed_units(), 2)
	assert_eq(_task_rows(world.state), [])


func test_unavailable_attempt_writes_no_completion_effects() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.time.start_task(&"task_x", &"actor_b", 1)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")],
			[DecisionFixtures.make_task_definition("task_x", [DecisionFixtures.eff_add("res_a", 2)])])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_ACTOR_BUSY)
	assert_eq(result.task_completions.size(), 0)
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_eq(_task_rows(world.state), [["task_x", "actor_b", 1]])
	assert_eq(calls[0], 0)


func test_failed_write_with_completions_changes_nothing() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world(RejectingGameState.new(DecisionFixtures.make_state_setup()))
	DecisionFixtures.start(world)
	world.time.start_task(&"task_x", &"actor_c", 1)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")],
			[DecisionFixtures.make_task_definition("task_x", [DecisionFixtures.eff_add("res_a", 2), DecisionFixtures.eff_flag("flag_b", true)])])
	var calls: Array[int] = _count_signals(world.state)
	(world.state as RejectingGameState).reject_changes = true
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_WRITE_FAILED)
	assert_eq(take_engine_errors().size(), 2)
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_false(world.state.get_flag(&"flag_b"))
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(_task_rows(world.state), [["task_x", "actor_c", 1]])
	assert_eq(calls[0], 0)


func test_task_missing_from_the_completion_catalog_is_a_configuration_error() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system_with(world, [_task_a()], DecisionFixtures.make_completion_system(world, []))
	assert_eq(system.get_configuration_errors(), PackedStringArray(["'task_a': tamamlanma sisteminde tanımı yok"]))
	assert_eq(system.assign_task(&"task_a", &"actor_a", &"actor_b").failure,
			TaskAssignmentResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("tamamlanma sisteminde tanımı yok")
	assert_eq(_task_rows(world.state), [])


# --- Akış hataları ---

func test_unknown_task_is_a_flow_error() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a()])
	var result: TaskAssignmentResultScript = system.assign_task(&"missing_id", &"actor_a", &"actor_b")
	assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_UNKNOWN_TASK)
	_assert_failed_result_is_empty(result)
	_assert_one_engine_error("tanımsız görev")


func test_unknown_pair_never_falls_back_to_the_defined_pair() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a()])
	var calls: Array[int] = _count_signals(world.state)
	for pair in [[&"actor_a", &"actor_c"], [&"actor_c", &"actor_b"], [&"actor_b", &"actor_a"]]:
		var result: TaskAssignmentResultScript = system.assign_task(&"task_a", pair[0], pair[1])
		assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_UNKNOWN_ASSIGNMENT, str(pair))
		assert_eq([result.active_actor_id, result.assigned_actor_id], pair)
		_assert_failed_result_is_empty(result)
		_assert_one_engine_error("aktör çiftine tanımlı değil")
	assert_eq(_task_rows(world.state), [])
	assert_eq(calls[0], 0)


func test_trust_condition_before_initialization_is_system_not_ready() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	world.time.start_night()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 10)])])
	var calls: Array[int] = _count_signals(world.state)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_SYSTEM_NOT_READY)
	_assert_failed_result_is_empty(result)
	_assert_one_engine_error("güven başlatılmadı")
	assert_eq(_task_rows(world.state), [])
	assert_eq(calls[0], 0)


func test_trust_free_task_works_before_trust_is_initialized() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	world.time.start_night()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_resource("res_a", &"ge", 1)])])
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	assert_false(world.trust.is_initialized())
	assert_eq(take_engine_errors().size(), 0)


func test_invalid_configuration_blocks_preview_and_assign() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [Fixtures.make_task("task_a", 0, "actor_a", "actor_b")])
	assert_eq(system.preview_assignment(&"task_a", &"actor_a", &"actor_b").failure,
			TaskAssignmentResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(system.assign_task(&"task_a", &"actor_a", &"actor_b").failure,
			TaskAssignmentResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(_task_rows(world.state), [])


func test_partial_trust_state_is_invalid_configuration() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	world.time.start_night()
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	world.state.set_trust_state(partial)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a()])
	assert_eq(system.assign_task(&"task_a", &"actor_a", &"actor_b").failure,
			TaskAssignmentResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("Durumda eksik güven ilişkisi")


# --- Atomiklik ---

func test_failed_write_changes_nothing() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world(RejectingGameState.new(DecisionFixtures.make_state_setup()))
	DecisionFixtures.start(world)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")])
	var calls: Array[int] = _count_signals(world.state)
	(world.state as RejectingGameState).reject_changes = true
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(result.failure, TaskAssignmentResultScript.FAILURE_WRITE_FAILED)
	_assert_failed_result_is_empty(result)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_true(errors.size() == 2 and errors[0].contains("test: yazma reddedildi"), " | ".join(errors))
	assert_true(errors.size() == 2 and errors[1].contains("durum yazılamadı"), " | ".join(errors))
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(_task_rows(world.state), [])
	assert_eq(calls[0], 0)


func test_assignment_uses_exactly_one_write() -> void:
	var state: CountingGameState = CountingGameState.new(DecisionFixtures.make_state_setup())
	var world: DecisionFixtures.World = DecisionFixtures.make_world(state)
	DecisionFixtures.start(world)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a"),
			Fixtures.make_task("task_b", 4, "actor_a", "actor_c", [DecisionFixtures.cond_flag("flag_a", true)], "action_a")])
	state.apply_calls = 0
	state.other_writes = 0
	var calls: Array[int] = _count_signals(state)
	system.preview_assignment(&"task_a", &"actor_a", &"actor_b")
	assert_eq(state.apply_calls, 0)
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	assert_true(system.assign_task(&"task_b", &"actor_a", &"actor_c").is_rejected())
	assert_eq(state.apply_calls, 2)
	assert_eq(state.other_writes, 0)
	assert_eq(calls[0], 2)


# --- Kopyalama, önizleme bağımsızlığı, determinizm ---

func test_mutating_a_result_does_not_affect_state() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([], "action_a")])
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	result.started_task.remaining_units = 99
	result.started_task.assigned_actor_id = &"actor_c"
	result.time_result.applied_units = 9
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])
	assert_eq(world.state.get_elapsed_units(), 2)


func test_assign_reevaluates_instead_of_using_the_preview() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.state.set_flag(&"flag_a", true)
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_flag("flag_a", true)])])
	var preview: TaskAssignmentResultScript = system.preview_assignment(&"task_a", &"actor_a", &"actor_b")
	assert_true(preview.is_accepted())
	world.state.set_flag(&"flag_a", false)
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_rejected())
	assert_eq(_task_rows(world.state), [])


func test_same_start_and_same_attempts_produce_same_results() -> void:
	assert_eq(_run_reference_sequence(), _run_reference_sequence())


# --- Güven ilkeleri (K-021, K-023) ---

func test_task_without_trust_condition_can_be_accepted() -> void:
	var world: DecisionFixtures.World = _started_world()
	world.state.set_flag(&"flag_a", true)
	var conditions: Array = [DecisionFixtures.cond_flag("flag_a", true), DecisionFixtures.cond_resource("res_a", &"ge", 5)]
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a(conditions)])
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())


func test_satisfied_trust_alone_does_not_make_a_task_accepted() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a(_trust_and_flag())])
	var result: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(result.is_rejected())
	assert_eq(result.failed_condition_indexes, PackedInt32Array([1]))


func test_high_trust_does_not_override_a_failing_information_condition() -> void:
	# Güven en yüksekken bile bilgiye (bayrağa) bağlı koşul yanlışsa görev reddedilir;
	# güven en düşükken bilgi doğruysa kabul edilir. Kabul güvenden bağımsız belirlenebilir.
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a([DecisionFixtures.cond_flag("flag_a", true)])])
	world.trust.change_trust(&"actor_b", &"actor_a", 100)
	assert_eq(world.state.get_trust(&"actor_b", &"actor_a"), 100)
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_rejected())
	world.trust.change_trust(&"actor_b", &"actor_a", -100)
	world.state.set_flag(&"flag_a", true)
	assert_eq(world.state.get_trust(&"actor_b", &"actor_a"), 0)
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())


# --- Senaryolar ---

func test_scenario_rejected_then_accepted_after_state_change_then_completed() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a(_trust_and_flag(), "action_a")])
	var first: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(first.is_rejected())
	assert_eq(world.state.get_elapsed_units(), 2)
	world.state.set_flag(&"flag_a", true)
	var second: TaskAssignmentResultScript = system.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(second.is_accepted())
	assert_eq(world.state.get_elapsed_units(), 4)
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 4]])
	var advance: TimeAdvanceResultScript = world.time.advance(4)
	assert_eq(advance.completed_task_ids(), [&"task_a"] as Array[StringName])
	assert_eq(advance.occurrences[0].assigned_actor_id, &"actor_b")
	assert_eq(_task_rows(world.state), [])
	for result in [first, second]:
		assert_eq([result.task_id, result.active_actor_id, result.assigned_actor_id], [&"task_a", &"actor_a", &"actor_b"])


func test_scenario_tasks_for_different_actors_progress_in_parallel() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [
		Fixtures.make_task("task_a", 3, "actor_a", "actor_b"),
		Fixtures.make_task("task_b", 5, "actor_a", "actor_c"),
	])
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	assert_true(system.assign_task(&"task_b", &"actor_a", &"actor_c").is_accepted())
	assert_eq(world.time.advance(3).completed_task_ids(), [&"task_a"] as Array[StringName])
	assert_eq(_task_rows(world.state), [["task_b", "actor_c", 2]])
	assert_eq(world.time.advance(2).completed_task_ids(), [&"task_b"] as Array[StringName])
	assert_eq(world.state.get_elapsed_units(), 5)


# --- Yardımcılar ---

func _started_world() -> DecisionFixtures.World:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	DecisionFixtures.start(world)
	return world


## actor_a → actor_b, 4 birim.
func _task_a(conditions: Array = [], action_id: String = "") -> TaskDataScript:
	return Fixtures.make_task("task_a", 4, "actor_a", "actor_b", conditions, action_id)


## actor_a → actor_c, 3 birim, koşulsuz.
func _task_b() -> TaskDataScript:
	return Fixtures.make_task("task_b", 3, "actor_a", "actor_c")


## Sağlanan bir güven koşulu (b→a ≥ 20) ve başlangıçta sağlanmayan bir bilgi koşulu (flag_a).
func _trust_and_flag() -> Array:
	return [DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 20), DecisionFixtures.cond_flag("flag_a", true)]


func _run_reference_sequence() -> Array:
	var world: DecisionFixtures.World = _started_world()
	var system: TaskSystemScript = Fixtures.make_system(world, [_task_a(_trust_and_flag(), "action_a"), _task_b()])
	var observed: Array = []
	var attempts: Array = [[&"task_a", &"actor_b"], [&"task_b", &"actor_c"], [&"task_b", &"actor_c"], [&"task_a", &"actor_b"]]
	for i in attempts.size():
		if i == 3:
			world.state.set_flag(&"flag_a", true)
		observed.append(_describe(system.assign_task(attempts[i][0], &"actor_a", attempts[i][1])))
	observed.append([_task_rows(world.state), world.state.get_elapsed_units()])
	return observed


func _describe(result: TaskAssignmentResultScript) -> Array:
	var task_row: Array = [] if result.started_task == null \
			else [result.started_task.task_id, result.started_task.assigned_actor_id, result.started_task.remaining_units]
	var applied: int = -1 if result.time_result == null else result.time_result.applied_units
	return [result.status, result.failure, result.task_id, result.active_actor_id, result.assigned_actor_id,
			result.failed_condition_indexes, task_row, applied]


func _task_rows(state: GameStateScript) -> Array:
	var rows: Array = []
	for task in state.get_tasks_snapshot():
		rows.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return rows


func _strip(lines: PackedStringArray, prefix: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(line.trim_prefix(prefix))
	return result


func _assert_failed_result_is_empty(result: TaskAssignmentResultScript) -> void:
	assert_true(result.is_failed())
	assert_eq(result.status, &"")
	assert_eq(result.failed_condition_indexes, PackedInt32Array())
	assert_eq(result.started_task, null)
	assert_eq(result.time_result, null)


func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_one_engine_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))


# Atomik paketi istendiğinde reddeden test ikizi.
class RejectingGameState extends "res://scripts/core/game_state.gd":
	var reject_changes: bool = false

	func apply_changes(change: GameStateChangeScript) -> bool:
		if reject_changes:
			push_error("test: yazma reddedildi")
			return false
		return super(change)


# Yazma çağrılarını sayan test ikizi.
class CountingGameState extends "res://scripts/core/game_state.gd":
	var apply_calls: int = 0
	var other_writes: int = 0

	func apply_changes(change: GameStateChangeScript) -> bool:
		apply_calls += 1
		return super(change)

	func set_resource(resource_id: StringName, value: int) -> bool:
		other_writes += 1
		return super(resource_id, value)

	func set_flag(flag_id: StringName, value: bool) -> bool:
		other_writes += 1
		return super(flag_id, value)

	func set_time_state(night: int, elapsed_units: int, night_ended: bool, tasks: Array[TimedTaskStateScript]) -> bool:
		other_writes += 1
		return super(night, elapsed_units, night_ended, tasks)

	func set_trust_state(entries: Array[TrustRelationshipStateScript]) -> bool:
		other_writes += 1
		return super(entries)
