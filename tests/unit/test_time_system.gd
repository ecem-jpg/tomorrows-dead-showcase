extends "res://tests/framework/test_case.gd"
## TimeSystem: yapılandırma, gece yaşam döngüsü ve temel ilerleme. Yalnızca tarafsız kimlikler (K-018).

const Fixtures := preload("res://tests/fixtures/time_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TimeOccurrenceScript := preload("res://scripts/systems/time_occurrence.gd")
const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/time"


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var system: TimeSystemScript = Fixtures.make_system(Fixtures.make_state())
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_fixture_files_build_a_valid_system() -> void:
	var rules: TimeRulesDataScript = ResourceLoader.load(FIXTURE_DIR.path_join("time_rules_a.tres")) as TimeRulesDataScript
	var events: Array[ScheduledEventDataScript] = []
	for name in ["event_a", "event_b", "event_c", "event_d", "event_e"]:
		events.append(ResourceLoader.load(FIXTURE_DIR.path_join(name + ".tres")) as ScheduledEventDataScript)
	var system: TimeSystemScript = TimeSystemScript.new(Fixtures.make_state(), rules, events)
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_configuration_reports_invalid_rules_in_order() -> void:
	var rules: TimeRulesDataScript = Fixtures.make_rules(0, 0)
	rules.action_costs = {&"action_b": -1, &"action_a": -2}
	var empty_events: Array[ScheduledEventDataScript] = []
	var system: TimeSystemScript = TimeSystemScript.new(Fixtures.make_state(), rules, empty_events)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Gece sayısı en az 1 olmalı: 0",
		"Gece uzunluğu en az 1 olmalı: 0",
		"Negatif eylem maliyeti: 'action_a' (-2)",
		"Negatif eylem maliyeti: 'action_b' (-1)",
	]))


func test_configuration_reports_invalid_events_in_order() -> void:
	var events: Array[ScheduledEventDataScript] = [
		Fixtures.make_event("event_z", 1, 11, 0),
		Fixtures.make_event("event_x", 1, 2, 0),
		null,
		Fixtures.make_event("event_y", 0, 1, 0),
		Fixtures.make_event("", 1, 1, 0),
		Fixtures.make_event("event_x", 1, 1, 0),
		Fixtures.make_event("event_w", 3, 0, 0),
	]
	var system: TimeSystemScript = TimeSystemScript.new(Fixtures.make_state(), Fixtures.make_rules(), events)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız olay kaydı",
		"Boş olay kimliği",
		"Olay gecesi aralık dışında: 'event_w' (gece 3, 1..2)",
		"Olay anı aralık dışında: 'event_w' (an 0, 1..10)",
		"Tekrarlanan olay kimliği: 'event_x'",
		"Olay gecesi aralık dışında: 'event_y' (gece 0, 1..2)",
		"Olay anı aralık dışında: 'event_z' (an 11, 1..10)",
	]))


func test_configuration_reports_inconsistent_state() -> void:
	var cases: Array = [
		[0, 3, false, [], "Gece başlamamışken süre 0 olmalı: 3"],
		[0, 0, true, [], "Gece başlamamışken bitiş işaretli olamaz"],
		[0, 0, false, [["task_a", "actor_a", 1]], "Gece başlamamışken görev olamaz: 1"],
		[3, 0, false, [], "Gece sayısı aşıldı: gece 3, gece sayısı 2"],
		[1, 10, false, [], "Etkin gecede süre gece uzunluğundan küçük olmalı: 10 / 10"],
		[1, 11, false, [], "Etkin gecede süre gece uzunluğundan küçük olmalı: 11 / 10"],
		[1, 4, true, [], "Bitmiş gecede süre gece uzunluğuna eşit olmalı: 4 / 10"],
	]
	for case in cases:
		var state: GameStateScript = Fixtures.make_state()
		state.set_time_state(case[0], case[1], case[2], _tasks(case[3]))
		var system: TimeSystemScript = Fixtures.make_system(state)
		assert_eq(system.get_configuration_errors(), PackedStringArray([case[4]]), str(case))


func test_cost_of_returns_data_values() -> void:
	var system: TimeSystemScript = Fixtures.make_system(Fixtures.make_state())
	assert_eq(system.cost_of(&"action_a"), 2)
	assert_eq(system.cost_of(&"action_b"), 0)


func test_cost_of_unknown_action_errors_and_returns_zero() -> void:
	var system: TimeSystemScript = Fixtures.make_system(Fixtures.make_state())
	assert_eq(system.cost_of(&"missing_id"), 0)
	_assert_one_engine_error("missing_id")


func test_rules_and_events_are_copied_on_creation() -> void:
	var rules: TimeRulesDataScript = Fixtures.make_rules()
	var events: Array[ScheduledEventDataScript] = Fixtures.default_events()
	var system: TimeSystemScript = TimeSystemScript.new(Fixtures.make_state(), rules, events)
	rules.night_count = 0
	rules.night_length_units = 0
	rules.action_costs[&"action_a"] = -9
	events[0].id = ""
	events[0].at_units = 99
	events.append(null)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_eq(system.cost_of(&"action_a"), 2)


# --- Gece yaşam döngüsü ---

func test_start_night_opens_first_night() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	assert_true(system.start_night())
	assert_eq(state.get_night(), 1)
	assert_eq(state.get_elapsed_units(), 0)
	assert_false(state.is_night_ended())


func test_start_night_while_night_is_active_errors_without_change() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.advance(3)
	var calls: Array[int] = _count_signals(state)
	assert_false(system.start_night())
	_assert_one_engine_error("gece sürerken")
	assert_eq(state.get_night(), 1)
	assert_eq(state.get_elapsed_units(), 3)
	assert_eq(calls[0], 0)


func test_start_night_after_night_end_opens_next_night() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.advance(10)
	assert_true(system.start_night())
	assert_eq(state.get_night(), 2)
	assert_eq(state.get_elapsed_units(), 0)
	assert_false(state.is_night_ended())


func test_start_night_after_last_night_errors_without_change() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	for night in 2:
		system.start_night()
		system.advance(10)
	var calls: Array[int] = _count_signals(state)
	assert_false(system.start_night())
	_assert_one_engine_error("son gece")
	assert_eq(state.get_night(), 2)
	assert_true(state.is_night_ended())
	assert_eq(calls[0], 0)


func test_has_next_night_follows_night_count() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	assert_true(system.has_next_night())
	system.start_night()
	assert_true(system.has_next_night())
	system.advance(10)
	system.start_night()
	assert_false(system.has_next_night())


# --- Temel ilerleme ---

func test_advance_moves_time_and_reports_applied_units() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	var result: TimeAdvanceResultScript = system.advance(3)
	assert_true(result.ok)
	assert_eq(result.applied_units, 3)
	assert_eq(result.overflow_units, 0)
	assert_eq(result.occurrences.size(), 0)
	assert_false(result.night_ended())
	assert_eq(state.get_elapsed_units(), 3)


func test_zero_advance_in_active_night_is_a_silent_noop() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.advance(3)
	var calls: Array[int] = _count_signals(state)
	var result: TimeAdvanceResultScript = system.advance(0)
	assert_true(result.ok)
	_assert_empty_result_values(result)
	assert_eq(state.get_elapsed_units(), 3)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_negative_advance_errors_without_change() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.advance(3)
	var calls: Array[int] = _count_signals(state)
	var result: TimeAdvanceResultScript = system.advance(-1)
	_assert_one_engine_error("negatif")
	_assert_failed_result(result)
	assert_eq(state.get_elapsed_units(), 3)
	assert_eq(calls[0], 0)


func test_advance_before_first_night_is_a_flow_error_even_for_zero() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	var calls: Array[int] = _count_signals(state)
	for amount in [3, 0]:
		var result: TimeAdvanceResultScript = system.advance(amount)
		_assert_one_engine_error("etkin gece yok")
		_assert_failed_result(result)
	assert_eq(state.get_night(), 0)
	assert_eq(calls[0], 0)


func test_advance_to_exact_boundary_ends_night_without_overflow() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.advance(6)
	var result: TimeAdvanceResultScript = system.advance(4)
	assert_true(result.ok)
	assert_eq(result.applied_units, 4)
	assert_eq(result.overflow_units, 0)
	assert_true(result.night_ended())
	assert_eq(result.occurrences.size(), 1)
	assert_eq(result.occurrences[0].kind, TimeOccurrenceScript.Kind.NIGHT_ENDED)
	assert_eq(result.occurrences[0].night, 1)
	assert_eq(result.occurrences[0].at_units, 10)
	assert_eq(state.get_elapsed_units(), 10)
	assert_true(state.is_night_ended())


func test_advance_past_boundary_reports_overflow() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.advance(7)
	var result: TimeAdvanceResultScript = system.advance(5)
	assert_eq(result.applied_units, 3)
	assert_eq(result.overflow_units, 2)
	assert_true(result.night_ended())
	assert_eq(state.get_elapsed_units(), 10)


func test_night_end_is_reported_once_and_ended_night_rejects_advance() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	assert_true(system.advance(10).night_ended())
	var calls: Array[int] = _count_signals(state)
	for amount in [1, 0]:
		var result: TimeAdvanceResultScript = system.advance(amount)
		_assert_one_engine_error("etkin gece yok")
		_assert_failed_result(result)
		assert_false(result.night_ended())
	assert_eq(state.get_elapsed_units(), 10)
	assert_true(state.is_night_ended())
	assert_eq(calls[0], 0)


func test_invalid_configuration_blocks_start_night_and_advance() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state, Fixtures.make_rules(0, 10))
	var calls: Array[int] = _count_signals(state)
	assert_false(system.start_night())
	_assert_one_engine_error("geçersiz yapılandırma")
	_assert_failed_result(system.advance(1))
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(state.get_night(), 0)
	assert_eq(calls[0], 0)


func test_each_successful_change_emits_one_signal() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	var calls: Array[int] = _count_signals(state)
	system.start_night()
	assert_eq(calls[0], 1)
	system.advance(3)
	assert_eq(calls[0], 2)
	system.advance(20)
	assert_eq(calls[0], 3)
	system.start_night()
	assert_eq(calls[0], 4)


# --- Yan etkisiz sorgu ve plan (K-025) ---

func test_has_action_cost_reports_without_errors() -> void:
	var system: TimeSystemScript = Fixtures.make_plain_system(Fixtures.make_state())
	assert_true(system.has_action_cost(&"action_a"))
	assert_true(system.has_action_cost(&"action_b"))
	assert_false(system.has_action_cost(&"missing_id"))
	assert_eq(take_engine_errors().size(), 0)


func test_plan_advance_computes_without_writing_or_signals() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_system(state)
	system.start_night()
	system.start_task(&"task_a", &"actor_a", 3)
	var calls: Array[int] = _count_signals(state)
	var plan: TimeAdvancePlanScript = system.plan_advance(12)
	assert_true(plan.is_valid())
	assert_true(plan.result.ok)
	assert_eq([plan.night, plan.elapsed_units, plan.night_ended], [1, 10, true])
	assert_eq(plan.tasks.size(), 0)
	assert_eq(plan.result.applied_units, 10)
	assert_eq(plan.result.overflow_units, 2)
	assert_eq(plan.result.completed_task_ids(), [&"task_a"] as Array[StringName])
	assert_true(plan.result.night_ended())
	assert_eq(state.get_elapsed_units(), 0)
	assert_eq(state.get_tasks_snapshot().size(), 1)
	assert_eq(calls[0], 0)


func test_plan_advance_reports_failures_without_engine_errors() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	var inactive: TimeAdvancePlanScript = system.plan_advance(0)
	assert_eq(inactive.failure, TimeAdvancePlanScript.FAILURE_NIGHT_NOT_ACTIVE)
	assert_false(inactive.result.ok)
	system.start_night()
	assert_eq(system.plan_advance(-1).failure, TimeAdvancePlanScript.FAILURE_NEGATIVE_AMOUNT)
	var invalid: TimeSystemScript = Fixtures.make_plain_system(Fixtures.make_state(), Fixtures.make_rules(0, 10))
	assert_eq(invalid.plan_advance(1).failure, TimeAdvancePlanScript.FAILURE_INVALID_CONFIGURATION)
	var zero: TimeAdvancePlanScript = system.plan_advance(0)
	assert_true(zero.is_valid() and zero.result.ok)
	assert_eq(zero.result.applied_units, 0)
	assert_eq(take_engine_errors().size(), 0)


func test_mutating_a_plan_does_not_affect_state_or_later_advances() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_system(state)
	system.start_night()
	system.start_task(&"task_a", &"actor_a", 5)
	var plan: TimeAdvancePlanScript = system.plan_advance(4)
	plan.tasks[0].remaining_units = 99
	plan.tasks.clear()
	plan.result.occurrences.clear()
	plan.elapsed_units = 9
	assert_eq(state.get_tasks_snapshot()[0].remaining_units, 5)
	assert_eq(state.get_elapsed_units(), 0)
	var result: TimeAdvanceResultScript = system.advance(4)
	assert_eq(result.triggered_event_ids(), [&"event_b", &"event_a", &"event_c"] as Array[StringName])
	assert_eq(state.get_tasks_snapshot()[0].remaining_units, 1)


func test_plan_add_task_adds_to_plan_without_writing() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.start_task(&"task_a", &"actor_a", 3)
	var calls: Array[int] = _count_signals(state)
	var plan: TimeAdvancePlanScript = system.plan_advance(2)
	assert_eq(system.plan_add_task(plan, &"task_b", &"actor_b", 3), &"")
	assert_eq(_task_rows(plan.tasks), [["task_a", "actor_a", 1], ["task_b", "actor_b", 3]])
	assert_eq(_task_rows(state.get_tasks_snapshot()), [["task_a", "actor_a", 3]])
	assert_eq(state.get_elapsed_units(), 0)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_plan_add_task_failures_leave_the_plan_unchanged() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.start_task(&"task_a", &"actor_a", 5)
	var plan: TimeAdvancePlanScript = system.plan_advance(2)
	var cases: Array = [
		[&"", &"actor_b", 3, TimeSystemScript.TASK_FAILURE_EMPTY_ID],
		[&"task_b", &"", 3, TimeSystemScript.TASK_FAILURE_EMPTY_ID],
		[&"task_b", &"actor_b", 0, TimeSystemScript.TASK_FAILURE_NON_POSITIVE_DURATION],
		[&"task_b", &"actor_b", -1, TimeSystemScript.TASK_FAILURE_NON_POSITIVE_DURATION],
		[&"task_a", &"actor_b", 3, TimeSystemScript.TASK_FAILURE_DUPLICATE],
	]
	for case in cases:
		assert_eq(system.plan_add_task(plan, case[0], case[1], case[2]), case[3], str(case))
		assert_eq(_task_rows(plan.tasks), [["task_a", "actor_a", 3]], str(case))
		assert_eq([plan.night, plan.elapsed_units, plan.night_ended], [1, 2, false], str(case))
	assert_eq(take_engine_errors().size(), 0)


func test_plan_add_task_requires_a_valid_plan_with_an_active_night() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	var before_night: TimeAdvancePlanScript = system.plan_advance(0)
	assert_eq(system.plan_add_task(before_night, &"task_a", &"actor_a", 3), TimeSystemScript.TASK_FAILURE_NIGHT_NOT_ACTIVE)
	assert_eq(before_night.tasks.size(), 0)
	system.start_night()
	var ending: TimeAdvancePlanScript = system.plan_advance(10)
	assert_eq(system.plan_add_task(ending, &"task_a", &"actor_a", 3), TimeSystemScript.TASK_FAILURE_NIGHT_NOT_ACTIVE)
	assert_eq(ending.tasks.size(), 0)
	var invalid: TimeSystemScript = Fixtures.make_plain_system(Fixtures.make_state(), Fixtures.make_rules(0, 10))
	assert_eq(system.plan_add_task(invalid.plan_advance(0), &"task_a", &"actor_a", 3), TimeSystemScript.TASK_FAILURE_INVALID_PLAN)
	assert_eq(system.plan_add_task(null, &"task_a", &"actor_a", 3), TimeSystemScript.TASK_FAILURE_INVALID_PLAN)
	assert_eq(take_engine_errors().size(), 0)


func test_plan_with_added_task_is_written_atomically() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	var plan: TimeAdvancePlanScript = system.plan_advance(2)
	system.plan_add_task(plan, &"task_a", &"actor_a", 4)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.set_time_state(plan.night, plan.elapsed_units, plan.night_ended, plan.tasks)
	var calls: Array[int] = _count_signals(state)
	assert_true(state.apply_changes(change))
	assert_eq(state.get_elapsed_units(), 2)
	assert_eq(_task_rows(state.get_tasks_snapshot()), [["task_a", "actor_a", 4]])
	assert_eq(calls[0], 1)


func test_plan_start_night_computes_without_writing() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	assert_eq(system.get_night_count(), 2)
	var calls: Array[int] = _count_signals(state)
	var plan: TimeAdvancePlanScript = system.plan_start_night()
	assert_true(plan.is_valid() and plan.result.ok)
	assert_eq([plan.night, plan.elapsed_units, plan.night_ended, plan.tasks.size()], [1, 0, false, 0])
	assert_eq([state.get_night(), calls[0]], [0, 0])
	assert_eq(take_engine_errors().size(), 0)


func test_plan_start_night_reports_failures_without_engine_errors() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	assert_eq(system.plan_start_night().failure, TimeAdvancePlanScript.FAILURE_NIGHT_ALREADY_ACTIVE)
	system.advance(10)
	system.start_night()
	system.advance(10)
	assert_eq(system.plan_start_night().failure, TimeAdvancePlanScript.FAILURE_NO_NEXT_NIGHT)
	var invalid: TimeSystemScript = Fixtures.make_plain_system(Fixtures.make_state(), Fixtures.make_rules(0, 10))
	assert_eq(invalid.plan_start_night().failure, TimeAdvancePlanScript.FAILURE_INVALID_CONFIGURATION)
	assert_eq(take_engine_errors().size(), 0)


func test_failed_state_write_returns_failed_result_without_change() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_state_setup())
	var system: TimeSystemScript = Fixtures.make_plain_system(state)
	system.start_night()
	system.advance(3)
	var calls: Array[int] = _count_signals(state)
	state.reject_time_writes = true
	var result: TimeAdvanceResultScript = system.advance(4)
	_assert_failed_result(result)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_true(errors.size() == 2 and errors[0].contains("test: yazma reddedildi"), " | ".join(errors))
	assert_true(errors.size() == 2 and errors[1].contains("zaman durumu yazılamadı"), " | ".join(errors))
	assert_eq(state.get_elapsed_units(), 3)
	assert_false(state.is_night_ended())
	assert_eq(calls[0], 0)


# Zaman yazmasını istendiğinde reddeden test ikizi; başarısız yazma yolunu sınamak için.
class RejectingGameState extends "res://scripts/core/game_state.gd":
	var reject_time_writes: bool = false

	func set_time_state(night: int, elapsed_units: int, night_ended: bool,
			tasks: Array[TimedTaskStateScript]) -> bool:
		if reject_time_writes:
			push_error("test: yazma reddedildi")
			return false
		return super(night, elapsed_units, night_ended, tasks)


# --- Yardımcılar ---

func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


func _assert_empty_result_values(result: TimeAdvanceResultScript) -> void:
	assert_eq(result.applied_units, 0)
	assert_eq(result.overflow_units, 0)
	assert_eq(result.occurrences.size(), 0)


func _assert_failed_result(result: TimeAdvanceResultScript) -> void:
	assert_false(result.ok)
	_assert_empty_result_values(result)

# [[task_id, actor_id, remaining], ...] biçiminden tipli görev listesi kurar.
func _tasks(rows: Array) -> Array[TimedTaskStateScript]:
	var result: Array[TimedTaskStateScript] = []
	for row in rows:
		result.append(TimedTaskStateScript.new(StringName(row[0]), StringName(row[1]), row[2]))
	return result


func _task_rows(tasks: Array[TimedTaskStateScript]) -> Array:
	var rows: Array = []
	for task in tasks:
		rows.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return rows


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_one_engine_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))
