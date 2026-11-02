extends "res://tests/framework/test_case.gd"
## TimeSystem: olaylar, görevler ve birleşik kronolojik oluşum listesi. Yalnızca tarafsız kimlikler (K-018).
## Varsayılan olaylar: 1. gecede 4. birimde event_b (order 0), event_a ve event_c (order 1);
## 1. gecede 10. birimde event_d; 2. gecede 3. birimde event_e.

const Fixtures := preload("res://tests/fixtures/time_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TimeOccurrenceScript := preload("res://scripts/systems/time_occurrence.gd")


# --- Olaylar ---

func test_events_trigger_when_crossed_and_not_before() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	assert_eq(system.advance(3).occurrences.size(), 0)
	var result: TimeAdvanceResultScript = system.advance(1)
	assert_eq(_describe(result), ["4:E:event_b", "4:E:event_a", "4:E:event_c"])


func test_event_order_field_wins_over_id() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	assert_eq(system.advance(4).triggered_event_ids(), [&"event_b", &"event_a", &"event_c"] as Array[StringName])


func test_event_occurrence_carries_time_fields() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	var occurrence: TimeOccurrenceScript = system.advance(4).occurrences[0]
	assert_eq(occurrence.kind, TimeOccurrenceScript.Kind.EVENT_TRIGGERED)
	assert_eq(occurrence.night, 1)
	assert_eq(occurrence.at_units, 4)
	assert_eq(occurrence.id, &"event_b")
	assert_eq(occurrence.order, 0)
	assert_eq(occurrence.assigned_actor_id, &"")


func test_boundary_event_is_reported_before_night_end() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	system.advance(4)
	var result: TimeAdvanceResultScript = system.advance(6)
	assert_eq(_describe(result), ["10:E:event_d", "10:N:"])
	assert_true(result.night_ended())


func test_large_advance_reports_all_events_chronologically() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	var result: TimeAdvanceResultScript = system.advance(12)
	assert_eq(_describe(result), ["4:E:event_b", "4:E:event_a", "4:E:event_c", "10:E:event_d", "10:N:"])
	assert_eq(result.applied_units, 10)
	assert_eq(result.overflow_units, 2)


func test_events_fire_only_in_their_own_night_and_only_once() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	system.advance(4)
	assert_eq(system.advance(1).occurrences.size(), 0)
	assert_false(system.advance(5).triggered_event_ids().has(&"event_e"))
	system.start_night()
	assert_eq(_describe(system.advance(3)), ["3:E:event_e"])


func test_event_data_is_copied_on_creation() -> void:
	var events: Array[ScheduledEventDataScript] = Fixtures.default_events()
	var system: TimeSystemScript = TimeSystemScript.new(Fixtures.make_state(), Fixtures.make_rules(), events)
	for event in events:
		event.at_units = 1
		event.order = 9
	system.start_night()
	assert_eq(system.advance(1).occurrences.size(), 0)
	assert_eq(_describe(system.advance(3)), ["4:E:event_b", "4:E:event_a", "4:E:event_c"])


# --- Görevler ---

func test_start_task_records_task_with_assigned_actor() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	var calls: Array[int] = _count_signals(state)
	assert_true(system.start_task(&"task_a", &"actor_a", 5))
	assert_eq(calls[0], 1)
	var tasks: Array = state.get_tasks_snapshot()
	assert_eq(tasks.size(), 1)
	assert_eq(tasks[0].task_id, &"task_a")
	assert_eq(tasks[0].assigned_actor_id, &"actor_a")
	assert_eq(tasks[0].remaining_units, 5)


func test_start_task_rejects_invalid_input_without_change() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	system.start_task(&"task_a", &"actor_a", 5)
	var calls: Array[int] = _count_signals(state)
	var invalid_cases: Array = [
		[&"", &"actor_a", 3, "boş"],
		[&"task_b", &"", 3, "boş"],
		[&"task_b", &"actor_a", 0, "pozitif"],
		[&"task_b", &"actor_a", -2, "pozitif"],
		[&"task_a", &"actor_b", 3, "zaten var"],
	]
	for case in invalid_cases:
		assert_false(system.start_task(case[0], case[1], case[2]), str(case))
		_assert_one_engine_error(case[3])
	assert_eq(state.get_tasks_snapshot().size(), 1)
	assert_eq(calls[0], 0)


func test_start_task_requires_an_active_night() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_system(state)
	assert_false(system.start_task(&"task_a", &"actor_a", 3))
	_assert_one_engine_error("etkin gece yok")
	system.start_night()
	system.advance(10)
	assert_false(system.start_task(&"task_a", &"actor_a", 3))
	_assert_one_engine_error("etkin gece yok")
	assert_eq(state.get_tasks_snapshot().size(), 0)


func test_start_task_is_blocked_by_invalid_configuration() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	# Durumu kurallarla çelişecek biçimde dışarıdan bozar: etkin gecede süre sınırda.
	state.set_time_state(1, 10, false, state.get_tasks_snapshot())
	var calls: Array[int] = _count_signals(state)
	assert_false(system.start_task(&"task_a", &"actor_a", 3))
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(state.get_tasks_snapshot().size(), 0)
	assert_eq(calls[0], 0)


func test_same_actor_may_hold_several_tasks() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	assert_true(system.start_task(&"task_a", &"actor_a", 3))
	assert_true(system.start_task(&"task_b", &"actor_a", 6))
	assert_eq(state.get_tasks_snapshot().size(), 2)


func test_tasks_progress_by_applied_units() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	system.start_task(&"task_a", &"actor_a", 5)
	system.advance(2)
	assert_eq(state.get_tasks_snapshot()[0].remaining_units, 3)


func test_main_scenario_orders_tasks_before_events_and_night_end_last() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	system.start_task(&"task_b", &"actor_a", 4)
	system.start_task(&"task_a", &"actor_b", 4)
	system.start_task(&"task_c", &"actor_a", 15)
	var result: TimeAdvanceResultScript = system.advance(12)
	assert_eq(_describe(result), [
		"4:T:task_a", "4:T:task_b",
		"4:E:event_b", "4:E:event_a", "4:E:event_c",
		"10:E:event_d", "10:N:",
	])
	assert_eq(result.applied_units, 10)
	assert_eq(result.overflow_units, 2)
	assert_eq(result.occurrences[0].assigned_actor_id, &"actor_b")
	assert_eq(result.occurrences[1].assigned_actor_id, &"actor_a")
	# Taşan 2 birim görevi ilerletmez: 15 - 10 = 5.
	var tasks: Array = state.get_tasks_snapshot()
	assert_eq(tasks.size(), 1)
	assert_eq(tasks[0].task_id, &"task_c")
	assert_eq(tasks[0].remaining_units, 5)


func test_task_completing_on_boundary_precedes_boundary_event_and_night_end() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	system.advance(4)
	system.start_task(&"task_a", &"actor_a", 6)
	assert_eq(_describe(system.advance(6)), ["10:T:task_a", "10:E:event_d", "10:N:"])


func test_unfinished_task_pauses_after_night_end_and_continues_next_night() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	system.start_task(&"task_c", &"actor_a", 15)
	system.advance(10)
	system.advance(3)
	_assert_one_engine_error("etkin gece yok")
	assert_eq(state.get_tasks_snapshot()[0].remaining_units, 5)
	system.start_night()
	assert_eq(state.get_tasks_snapshot()[0].remaining_units, 5)
	var result: TimeAdvanceResultScript = system.advance(5)
	assert_eq(_describe(result), ["3:E:event_e", "5:T:task_c"])
	assert_eq(result.occurrences[1].night, 2)
	assert_eq(result.occurrences[1].assigned_actor_id, &"actor_a")
	assert_eq(state.get_tasks_snapshot().size(), 0)


func test_completed_task_ids_view_matches_occurrences() -> void:
	var system: TimeSystemScript = _started_system(Fixtures.make_state())
	system.start_task(&"task_b", &"actor_a", 2)
	system.start_task(&"task_a", &"actor_a", 2)
	var result: TimeAdvanceResultScript = system.advance(2)
	assert_eq(result.completed_task_ids(), [&"task_a", &"task_b"] as Array[StringName])
	assert_eq(result.triggered_event_ids().size(), 0)
	assert_false(result.night_ended())


# --- Sinyal, kopyalama, determinizm ---

func test_advance_with_many_changes_emits_a_single_signal() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	system.start_task(&"task_a", &"actor_a", 2)
	system.start_task(&"task_b", &"actor_b", 20)
	var calls: Array[int] = _count_signals(state)
	# Süre, görev tamamlanması, görev ilerlemesi, olaylar ve gece sonu tek çağrıda.
	system.advance(10)
	assert_eq(calls[0], 1)


func test_mutating_results_does_not_affect_the_system() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = _started_system(state)
	system.start_task(&"task_a", &"actor_a", 2)
	system.start_task(&"task_b", &"actor_b", 8)
	var first: TimeAdvanceResultScript = system.advance(2)
	first.occurrences[0].at_units = 99
	first.occurrences[0].id = &"task_b"
	first.occurrences.clear()
	first.applied_units = 99
	var tasks: Array = state.get_tasks_snapshot()
	tasks[0].remaining_units = 1
	assert_eq(state.get_elapsed_units(), 2)
	assert_eq(state.get_tasks_snapshot()[0].remaining_units, 6)
	assert_eq(_describe(system.advance(2)), ["4:E:event_b", "4:E:event_a", "4:E:event_c"])


func test_same_start_and_same_actions_produce_same_results() -> void:
	assert_eq(_run_reference_sequence(), _run_reference_sequence())


# --- Yardımcılar ---

# Sabit bir eylem dizisini yeni bir durumla oynatır ve gözlenebilir her şeyi döndürür.
func _run_reference_sequence() -> Array:
	var state: GameStateScript = Fixtures.make_state()
	var system: TimeSystemScript = Fixtures.make_system(state)
	var observed: Array = []
	system.start_night()
	system.start_task(&"task_b", &"actor_a", 4)
	system.start_task(&"task_a", &"actor_b", 4)
	system.start_task(&"task_c", &"actor_a", 15)
	for amount in [system.cost_of(&"action_a"), 1, system.cost_of(&"action_b"), 9]:
		var result: TimeAdvanceResultScript = system.advance(amount)
		observed.append([result.ok, result.applied_units, result.overflow_units, _describe(result)])
	system.start_night()
	var last: TimeAdvanceResultScript = system.advance(6)
	observed.append([last.ok, last.applied_units, last.overflow_units, _describe(last)])
	observed.append([state.get_night(), state.get_elapsed_units(), state.is_night_ended(),
			state.get_tasks_snapshot().size()])
	return observed

func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_one_engine_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))

func _started_system(state: GameStateScript) -> TimeSystemScript:
	var system: TimeSystemScript = Fixtures.make_system(state)
	system.start_night()
	return system


# Oluşumları "an:tür:kimlik" biçiminde özetler (T = görev, E = olay, N = gece sonu).
func _describe(result: TimeAdvanceResultScript) -> Array:
	var lines: Array = []
	for occurrence in result.occurrences:
		var kind_text: String = "T"
		if occurrence.kind == TimeOccurrenceScript.Kind.EVENT_TRIGGERED:
			kind_text = "E"
		elif occurrence.kind == TimeOccurrenceScript.Kind.NIGHT_ENDED:
			kind_text = "N"
		lines.append("%d:%s:%s" % [occurrence.at_units, kind_text, occurrence.id])
	return lines
