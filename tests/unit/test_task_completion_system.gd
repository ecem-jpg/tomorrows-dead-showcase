extends "res://tests/framework/test_case.gd"
## TaskCompletionSystem birim ve senaryo testleri (K-027). Yalnızca tarafsız kimlikler kullanılır (K-018).
## Dünya: res_a = 5 (0..10), res_b = 0 (alt 0); güven actor_a→actor_b 60, actor_b→actor_a 30 (0..100);
## zaman 2 gece × 10 birim, action_a = 2, action_b = 0. Görevler doğrudan TimeSystem.start_task ile
## başlatılır; tanımları tamamlanma kataloğunda bulunur.

const Fixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const TaskFixtures := preload("res://tests/fixtures/task_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const TaskCompletionPlanScript := preload("res://scripts/systems/task_completion_plan.gd")
const TimeOccurrenceScript := preload("res://scripts/systems/time_occurrence.gd")


# --- Yapılandırma ---

func test_valid_catalog_has_no_errors() -> void:
	var system: TaskCompletionSystemScript = _system(Fixtures.make_world(), [
		_def("task_a", [Fixtures.eff_add("res_a", 1), Fixtures.eff_trust("actor_a", "actor_b", 1), Fixtures.eff_flag("flag_a", true)]),
		_def("task_b"),
	])
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_true(system.has_definition(&"task_a"))
	assert_false(system.has_definition(&"missing_id"))


func test_catalog_errors_are_reported_in_order() -> void:
	var tasks: Array = [
		null,
		_def(""),
		_def("task_a"),
		_def("task_a"),
		_def("task_b", [Fixtures.eff_add("missing_id", 1), Fixtures.eff_flag("flag_a", true), Fixtures.eff_flag("flag_a", false)]),
	]
	var system: TaskCompletionSystemScript = _system(Fixtures.make_world(), tasks)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız görev kaydı (#0)",
		"Boş görev kimliği (#1)",
		"Tekrarlanan görev kimliği: 'task_a'",
		"'task_b' tamamlanma etkisi #0: tanımsız kaynak 'missing_id'",
		"'task_b' tamamlanma etkisi #2: aynı hedefe birden fazla etki (#1 ile)",
	]))
	assert_eq(take_engine_errors().size(), 0)


func test_undefined_active_task_is_a_configuration_error_without_change() -> void:
	var world: Fixtures.World = _started_world()
	world.time.start_task(&"task_x", &"actor_b", 2)
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a")])
	assert_eq(system.get_catalog_errors(), PackedStringArray(["Etkin görevin tanımı yok: 'task_x'"]))
	var before: Array = _snapshot(world.state)
	var calls: Array[int] = _count_signals(world.state)
	var result: TimeProgressResultScript = system.advance(5)
	assert_eq(result.failure, TimeProgressResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_failed_result_is_empty(result)
	_assert_one_engine_error("Etkin görevin tanımı yok")
	assert_eq(_snapshot(world.state), before)
	assert_eq(calls[0], 0)


func test_dependency_errors_are_not_part_of_catalog_errors() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	var rules: TimeRulesDataScript = TimeRulesDataScript.new()
	rules.id = "time_rules_a"
	rules.night_count = 0
	rules.night_length_units = 10
	var no_events: Array[ScheduledEventDataScript] = []
	world.time = TimeSystemScript.new(world.state, rules, no_events)
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a")])
	assert_eq(system.get_configuration_errors(), PackedStringArray(["TimeSystem: Gece sayısı en az 1 olmalı: 0"]))
	assert_eq(system.get_catalog_errors(), PackedStringArray())


func test_task_data_is_copied_on_creation() -> void:
	var world: Fixtures.World = _started_world()
	var task: TaskDataScript = _def("task_a", [Fixtures.eff_add("res_a", 2)])
	var system: TaskCompletionSystemScript = _system(world, [task])
	task.id = "task_z"
	task.completion_effects[0].amount = 99
	task.completion_effects.append(null)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	world.time.start_task(&"task_a", &"actor_b", 1)
	assert_true(system.advance(1).ok)
	assert_eq(world.state.get_resource(&"res_a"), 7)


# --- Tek tamamlanma ---

func test_completion_effects_apply_with_time_in_one_write() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_add("res_a", 3), Fixtures.eff_flag("flag_a", true), Fixtures.eff_trust("actor_a", "actor_b", 5)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var calls: Array[int] = _count_signals(world.state)
	var result: TimeProgressResultScript = system.advance(3)
	assert_true(result.ok)
	assert_eq(result.failure, &"")
	assert_eq(result.completed_task_ids(), [&"task_a"] as Array[StringName])
	assert_eq(result.time_result.applied_units, 3)
	var completion: TaskCompletionOutcomeScript = result.completions[0]
	assert_eq([completion.task_id, completion.assigned_actor_id, completion.night, completion.at_units, completion.status],
			[&"task_a", &"actor_b", 1, 2, TaskCompletionOutcomeScript.STATUS_APPLIED])
	assert_eq(completion.blocking_effect_index, -1)
	assert_eq(_describe_effects(completion), ["resource_add:res_a:3:5:3", "flag_set:flag_a:false>true",
			"trust_change:actor_a>actor_b:5:60:5"])
	assert_eq(world.state.get_resource(&"res_a"), 8)
	assert_true(world.state.get_flag(&"flag_a"))
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 65)
	assert_eq(world.state.get_elapsed_units(), 3)
	assert_eq(_task_rows(world.state), [])
	assert_eq(calls[0], 1)
	assert_eq(take_engine_errors().size(), 0)


func test_task_without_effects_completes_as_applied() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a")])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var result: TimeProgressResultScript = system.advance(2)
	assert_eq(result.completions[0].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	assert_eq(result.completions[0].effect_outcomes.size(), 0)
	assert_eq(_task_rows(world.state), [])


func test_unfinished_task_has_no_effect_yet() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_add("res_a", 3)])])
	world.time.start_task(&"task_a", &"actor_b", 4)
	var result: TimeProgressResultScript = system.advance(3)
	assert_eq(result.completions.size(), 0)
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_eq(_task_rows(world.state), [["task_a", "actor_b", 1]])


# --- Birden fazla tamamlanma ---

func test_simultaneous_completions_follow_id_order() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_b", [Fixtures.eff_flag("flag_a", false)]),
		_def("task_a", [Fixtures.eff_flag("flag_a", true)]),
	])
	world.time.start_task(&"task_b", &"actor_c", 2)
	world.time.start_task(&"task_a", &"actor_b", 2)
	var result: TimeProgressResultScript = system.advance(2)
	assert_eq(result.completed_task_ids(), [&"task_a", &"task_b"] as Array[StringName])
	assert_eq(_describe_effects(result.completions[1]), ["flag_set:flag_a:true>false"])
	assert_false(world.state.get_flag(&"flag_a"))


func test_completions_follow_chronological_order_with_clamping_per_step() -> void:
	# task_b önce biter (+6: 5→10, kesilir), task_a sonra (−4: 10→6). Ters sıra 5−4+6 = 7 verirdi.
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_spend("res_a", 4)]),
		_def("task_b", [Fixtures.eff_add("res_a", 6)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 3)
	world.time.start_task(&"task_b", &"actor_c", 1)
	var result: TimeProgressResultScript = system.advance(3)
	assert_eq(result.completed_task_ids(), [&"task_b", &"task_a"] as Array[StringName])
	assert_eq(_describe_effects(result.completions[0]), ["resource_add:res_a:6:5:5"])
	assert_eq(_describe_effects(result.completions[1]), ["resource_spend:res_a:4:10:-4"])
	assert_eq(world.state.get_resource(&"res_a"), 6)


func test_same_resource_accumulates_and_only_the_final_value_is_written() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_add("res_a", 4)]),
		_def("task_b", [Fixtures.eff_add("res_a", 4)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 2)
	world.time.start_task(&"task_b", &"actor_c", 2)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var plan: TaskCompletionPlanScript = system.plan_time(2, change)
	assert_true(plan.is_valid())
	assert_eq(change.resource_values.size(), 1)
	assert_eq(change.resource_values[&"res_a"], 10)
	assert_eq(_describe_effects(plan.completions[0]), ["resource_add:res_a:4:5:4"])
	assert_eq(_describe_effects(plan.completions[1]), ["resource_add:res_a:4:9:1"])
	assert_false(change.has_time_state)


func test_trust_effects_accumulate_and_directions_stay_independent() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_trust("actor_a", "actor_b", 30)]),
		_def("task_b", [Fixtures.eff_trust("actor_a", "actor_b", 30), Fixtures.eff_trust("actor_b", "actor_a", -10)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 2)
	world.time.start_task(&"task_b", &"actor_c", 2)
	var result: TimeProgressResultScript = system.advance(2)
	assert_eq(_describe_effects(result.completions[1]), ["trust_change:actor_a>actor_b:30:90:10",
			"trust_change:actor_b>actor_a:-10:30:-10"])
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 100)
	assert_eq(world.state.get_trust(&"actor_b", &"actor_a"), 20)


# --- Yetersiz harcama (görev düzeyinde atomiklik) ---

func test_insufficient_spend_discards_every_effect_of_that_task_only() -> void:
	# task_a önce biter ve etkileri uygulanır. task_b'nin ilk iki etkisi tek başına uygulanabilirdi; üçüncüsü
	# (harcama) yetersiz olduğu için task_b'nin hiçbir etkisi uygulanmaz, task_a'nınkiler korunur.
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_add("res_b", 2), Fixtures.eff_flag("flag_b", true)]),
		_def("task_b", [Fixtures.eff_add("res_a", 3), Fixtures.eff_flag("flag_a", true), Fixtures.eff_spend("res_b", 50)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 1)
	world.time.start_task(&"task_b", &"actor_c", 2)
	var calls: Array[int] = _count_signals(world.state)
	var result: TimeProgressResultScript = system.advance(3)
	assert_true(result.ok)
	assert_eq(result.completed_task_ids(), [&"task_a", &"task_b"] as Array[StringName])
	assert_eq(result.completions[0].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	var failed: TaskCompletionOutcomeScript = result.completions[1]
	assert_eq(failed.status, TaskCompletionOutcomeScript.STATUS_EFFECTS_NOT_APPLICABLE)
	assert_eq(failed.blocking_effect_index, 2)
	assert_eq(failed.effect_outcomes.size(), 0)
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_false(world.state.get_flag(&"flag_a"))
	assert_eq(world.state.get_resource(&"res_b"), 2)
	assert_true(world.state.get_flag(&"flag_b"))
	assert_eq(_task_rows(world.state), [])
	assert_eq(world.state.get_elapsed_units(), 3)
	assert_eq(calls[0], 1)
	assert_eq(take_engine_errors().size(), 0)


func test_spend_is_checked_against_the_accumulated_value() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_add("res_b", 3)]),
		_def("task_b", [Fixtures.eff_spend("res_b", 3)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 1)
	world.time.start_task(&"task_b", &"actor_c", 2)
	var result: TimeProgressResultScript = system.advance(2)
	assert_eq(result.completions[1].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	assert_eq(world.state.get_resource(&"res_b"), 0)


func test_not_applicable_task_does_not_block_later_tasks() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_spend("res_b", 1)]),
		_def("task_b", [Fixtures.eff_add("res_a", 1)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 1)
	world.time.start_task(&"task_b", &"actor_c", 2)
	var result: TimeProgressResultScript = system.advance(2)
	assert_eq(result.completions[0].status, TaskCompletionOutcomeScript.STATUS_EFFECTS_NOT_APPLICABLE)
	assert_eq(result.completions[1].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	assert_eq(world.state.get_resource(&"res_a"), 6)


# --- Zaman ---

func test_negative_amount_and_inactive_night_are_errors_without_change() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.trust.initialize_relationships()
	var system: TaskCompletionSystemScript = _system(world, [])
	assert_eq(system.advance(1).failure, TimeProgressResultScript.FAILURE_NIGHT_NOT_ACTIVE)
	_assert_one_engine_error("etkin gece yokken")
	world.time.start_night()
	var result: TimeProgressResultScript = system.advance(-1)
	assert_eq(result.failure, TimeProgressResultScript.FAILURE_NEGATIVE_AMOUNT)
	_assert_failed_result_is_empty(result)
	_assert_one_engine_error("negatif zaman ilerlemesi")
	assert_eq(world.state.get_elapsed_units(), 0)


func test_boundary_completion_applies_effects_and_overflow_does_not() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_add("res_a", 1)])])
	world.time.start_task(&"task_a", &"actor_b", 10)
	var result: TimeProgressResultScript = system.advance(15)
	assert_eq(result.time_result.overflow_units, 5)
	assert_true(result.time_result.night_ended())
	assert_eq(result.completed_task_ids(), [&"task_a"] as Array[StringName])
	assert_eq(world.state.get_resource(&"res_a"), 6)
	assert_true(world.state.is_night_ended())


func test_zero_advance_writes_nothing() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_state_setup())
	var world: Fixtures.World = Fixtures.make_world(state)
	Fixtures.start(world)
	var system: TaskCompletionSystemScript = _system(world, [])
	state.apply_calls = 0
	var result: TimeProgressResultScript = system.advance(0)
	assert_true(result.ok)
	assert_eq(result.time_result.applied_units, 0)
	assert_eq(state.apply_calls, 0)


# --- Güven ---

func test_trust_effect_before_initialization_is_system_not_ready() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.time.start_night()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_trust("actor_a", "actor_b", 5)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var before: Array = _snapshot(world.state)
	var result: TimeProgressResultScript = system.advance(3)
	assert_eq(result.failure, TimeProgressResultScript.FAILURE_SYSTEM_NOT_READY)
	_assert_failed_result_is_empty(result)
	_assert_one_engine_error("güven başlatılmadı")
	assert_eq(_snapshot(world.state), before)


func test_trust_free_effects_work_before_initialization() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.time.start_night()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_add("res_a", 1)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	assert_true(system.advance(2).ok)
	assert_eq(world.state.get_resource(&"res_a"), 6)
	assert_false(world.trust.is_initialized())


# --- Önizleme ---

func test_preview_has_no_side_effects_and_matches_advance() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_add("res_a", 3)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var calls: Array[int] = _count_signals(world.state)
	var preview: TimeProgressResultScript = system.preview_advance(3)
	assert_true(preview.ok)
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(calls[0], 0)
	var result: TimeProgressResultScript = system.advance(3)
	assert_eq(_describe_result(result), _describe_result(preview))


func test_advance_reevaluates_instead_of_using_the_preview() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_spend("res_a", 5)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	assert_eq(system.preview_advance(2).completions[0].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	world.state.set_resource(&"res_a", 4)
	var result: TimeProgressResultScript = system.advance(2)
	assert_eq(result.completions[0].status, TaskCompletionOutcomeScript.STATUS_EFFECTS_NOT_APPLICABLE)
	assert_eq(world.state.get_resource(&"res_a"), 4)


# --- Atomiklik ---

func test_failed_write_changes_nothing_in_any_category() -> void:
	var world: Fixtures.World = Fixtures.make_world(RejectingGameState.new(Fixtures.make_state_setup()))
	Fixtures.start(world)
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_add("res_a", 3), Fixtures.eff_trust("actor_a", "actor_b", 5)]),
		_def("task_b", [Fixtures.eff_flag("flag_a", true), Fixtures.eff_add("res_b", 1)]),
	])
	world.time.start_task(&"task_a", &"actor_b", 2)
	world.time.start_task(&"task_b", &"actor_c", 2)
	var before: Array = _snapshot(world.state)
	var calls: Array[int] = _count_signals(world.state)
	(world.state as RejectingGameState).reject_changes = true
	var result: TimeProgressResultScript = system.advance(3)
	assert_eq(result.failure, TimeProgressResultScript.FAILURE_WRITE_FAILED)
	_assert_failed_result_is_empty(result)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_true(errors.size() == 2 and errors[0].contains("test: yazma reddedildi"), " | ".join(errors))
	assert_true(errors.size() == 2 and errors[1].contains("durum yazılamadı"), " | ".join(errors))
	assert_eq(_snapshot(world.state), before)
	assert_eq(calls[0], 0)
	# Yazma yeniden mümkün olunca etkiler tam bir kez uygulanır.
	(world.state as RejectingGameState).reject_changes = false
	assert_true(system.advance(3).ok)
	assert_eq([world.state.get_resource(&"res_a"), world.state.get_resource(&"res_b")], [8, 1])
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 65)
	assert_true(world.state.get_flag(&"flag_a"))
	assert_eq(calls[0], 1)


func test_advance_uses_exactly_one_write() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_state_setup())
	var world: Fixtures.World = Fixtures.make_world(state)
	Fixtures.start(world)
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_add("res_a", 3)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	state.apply_calls = 0
	state.other_writes = 0
	system.preview_advance(3)
	assert_eq(state.apply_calls, 0)
	assert_true(system.advance(3).ok)
	assert_eq(state.apply_calls, 1)
	assert_eq(state.other_writes, 0)


func test_mutating_a_result_does_not_affect_state() -> void:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [_def("task_a", [Fixtures.eff_add("res_a", 3)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var result: TimeProgressResultScript = system.advance(3)
	result.completions[0].effect_outcomes[0].applied = 99
	result.completions.clear()
	result.time_result.occurrences.clear()
	assert_eq(world.state.get_resource(&"res_a"), 8)
	assert_eq(world.state.get_elapsed_units(), 3)


func test_same_start_and_same_sequence_produce_same_results() -> void:
	assert_eq(_run_reference_sequence(), _run_reference_sequence())


# --- Uçtan uca senaryo ---

func test_scenario_assignment_choice_and_advance_share_one_completion_flow() -> void:
	assert_eq(_run_scenario(), _run_scenario())


# --- Yardımcılar ---

func _run_scenario() -> Array:
	var world: Fixtures.World = _started_world()
	var task_a: TaskDataScript = TaskFixtures.make_task("task_a", 2, "actor_a", "actor_b", [], "",
			[Fixtures.eff_add("res_a", 3), Fixtures.eff_flag("flag_a", true)])
	var task_b: TaskDataScript = TaskFixtures.make_task("task_b", 4, "actor_a", "actor_c", [], "",
			[Fixtures.eff_add("res_a", 4)])
	var completions: TaskCompletionSystemScript = _system(world, [task_a, task_b])
	var tasks: TaskSystemScript = TaskFixtures.make_system_with(world, [task_a, task_b], completions)
	var decisions: Array[DecisionDataScript] = [
		Fixtures.make_decision("decision_a", [Fixtures.make_choice("choice_wait", [], [], "action_a")]),
	]
	var decision_system: DecisionSystemScript = DecisionSystemScript.new(world.state, world.resources, world.trust,
			world.time, completions, decisions)
	assert_eq(tasks.get_configuration_errors(), PackedStringArray())
	assert_eq(decision_system.get_configuration_errors(), PackedStringArray())
	var observed: Array = []

	# 1-2. İki görev verilir ve kabul edilir.
	assert_true(tasks.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	assert_true(tasks.assign_task(&"task_b", &"actor_a", &"actor_c").is_accepted())
	# 3. Seçimin eylem süresi task_a'yı bitirir; etkileri aynı yazmada uygulanır.
	var calls: Array[int] = _count_signals(world.state)
	var choice: DecisionResultScript = decision_system.choose(&"decision_a", &"choice_wait")
	assert_true(choice.ok)
	assert_eq(calls[0], 1)
	assert_eq(choice.task_completions.size(), 1)
	assert_eq(choice.task_completions[0].task_id, &"task_a")
	assert_eq(world.state.get_resource(&"res_a"), 8)
	assert_true(world.state.get_flag(&"flag_a"))
	assert_eq(_task_rows(world.state), [["task_b", "actor_c", 2]])
	observed.append([world.state.get_resource(&"res_a"), _task_rows(world.state)])
	# 4. Tamamlanan task_a yeniden verilir.
	assert_true(tasks.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	# 5. Seçimden bağımsız zaman: iki görev aynı anda biter; kimlik sırasıyla, biriken değer üzerinden.
	var progress: TimeProgressResultScript = completions.advance(10)
	assert_true(progress.ok)
	assert_eq(progress.completed_task_ids(), [&"task_a", &"task_b"] as Array[StringName])
	assert_eq(_describe_effects(progress.completions[0]), ["resource_add:res_a:3:8:2", "flag_set:flag_a:true>true"])
	assert_eq(_describe_effects(progress.completions[1]), ["resource_add:res_a:4:10:0"])
	assert_eq(world.state.get_resource(&"res_a"), 10)
	var night_ends: int = 0
	for occurrence in progress.time_result.occurrences:
		if occurrence.kind == TimeOccurrenceScript.Kind.NIGHT_ENDED:
			night_ends += 1
	assert_eq(night_ends, 1)
	assert_true(world.state.is_night_ended())
	observed.append(_describe_result(progress))
	observed.append(_snapshot(world.state))
	return observed


func _run_reference_sequence() -> Array:
	var world: Fixtures.World = _started_world()
	var system: TaskCompletionSystemScript = _system(world, [
		_def("task_a", [Fixtures.eff_add("res_a", 4), Fixtures.eff_trust("actor_b", "actor_a", 5)]),
		_def("task_b", [Fixtures.eff_spend("res_a", 7), Fixtures.eff_flag("flag_a", true)]),
		_def("task_c", [Fixtures.eff_spend("res_a", 3)]),
	])
	world.time.start_task(&"task_b", &"actor_c", 3)
	world.time.start_task(&"task_a", &"actor_b", 1)
	world.time.start_task(&"task_c", &"actor_a", 3)
	var observed: Array = []
	for amount in [1, 2, 4]:
		observed.append(_describe_result(system.advance(amount)))
	observed.append(_snapshot(world.state))
	return observed


func _started_world() -> Fixtures.World:
	var world: Fixtures.World = Fixtures.make_world()
	Fixtures.start(world)
	return world


func _system(world: Fixtures.World, tasks: Array) -> TaskCompletionSystemScript:
	return Fixtures.make_completion_system(world, tasks)


func _def(id: String, effects: Array = []) -> TaskDataScript:
	return Fixtures.make_task_definition(id, effects)


func _describe_result(result: TimeProgressResultScript) -> Array:
	var completions: Array = []
	for completion in result.completions:
		completions.append([completion.task_id, completion.at_units, completion.status, completion.blocking_effect_index,
				_describe_effects(completion)])
	var applied: int = -1 if result.time_result == null else result.time_result.applied_units
	return [result.ok, result.failure, applied, completions]


func _describe_effects(completion: TaskCompletionOutcomeScript) -> Array:
	var lines: Array = []
	for outcome in completion.effect_outcomes:
		match outcome.kind:
			&"flag_set":
				lines.append("%s:%s:%s>%s" % [outcome.kind, outcome.flag_id, outcome.previous_flag, outcome.flag_value])
			&"trust_change":
				lines.append("%s:%s>%s:%d:%d:%d" % [outcome.kind, outcome.source_actor_id, outcome.target_actor_id,
						outcome.requested, outcome.previous, outcome.applied])
			_:
				lines.append("%s:%s:%d:%d:%d" % [outcome.kind, outcome.resource_id, outcome.requested,
						outcome.previous, outcome.applied])
	return lines


func _snapshot(state: GameStateScript) -> Array:
	var trust_rows: Array = []
	for entry in state.get_trust_snapshot():
		trust_rows.append([String(entry.source_actor_id), String(entry.target_actor_id), entry.value])
	return [state.get_resources_snapshot(), state.get_flags_snapshot(), trust_rows, state.get_night(),
			state.get_elapsed_units(), state.is_night_ended(), _task_rows(state)]


func _task_rows(state: GameStateScript) -> Array:
	var rows: Array = []
	for task in state.get_tasks_snapshot():
		rows.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return rows


func _assert_failed_result_is_empty(result: TimeProgressResultScript) -> void:
	assert_false(result.ok)
	assert_eq(result.time_result, null)
	assert_eq(result.completions.size(), 0)


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
