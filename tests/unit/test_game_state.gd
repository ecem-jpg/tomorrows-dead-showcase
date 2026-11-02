extends "res://tests/framework/test_case.gd"
## GameState birim testleri. Yalnızca tarafsız kimlikler kullanılır (K-018).

const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")

const RANDOM_SAMPLE_COUNT: int = 5
const RANDOM_MAX: int = 1_000_000


func test_starting_resources_match_setup() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	assert_true(state.has_resource(&"res_a"))
	assert_true(state.has_resource(&"res_b"))
	assert_false(state.has_resource(&"missing_id"))
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(state.get_resource(&"res_b"), 0)


func test_starting_flags_are_set_and_unknown_flags_are_false() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	assert_true(state.get_flag(&"flag_a"))
	assert_false(state.get_flag(&"flag_b"))


func test_set_resource_changes_value() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	assert_true(state.set_resource(&"res_a", 5))
	assert_eq(state.get_resource(&"res_a"), 5)
	# Sınır yok: negatif değer de saklanır (sınırlar ResourceSystem'in işi).
	assert_true(state.set_resource(&"res_b", -2))
	assert_eq(state.get_resource(&"res_b"), -2)


func test_undefined_resource_read_errors_without_changing_state() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var before: Dictionary = state.get_resources_snapshot()
	assert_eq(state.get_resource(&"missing_id"), 0)
	_assert_engine_error_mentions("missing_id")
	assert_eq(state.get_resources_snapshot(), before)


func test_undefined_resource_write_errors_without_change_or_signal() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	var before: Dictionary = state.get_resources_snapshot()

	assert_false(state.set_resource(&"missing_id", 1))
	_assert_engine_error_mentions("missing_id")
	assert_false(state.has_resource(&"missing_id"))
	assert_eq(state.get_resources_snapshot(), before)
	assert_eq(calls[0], 0)


func test_set_flag_toggles_value() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	assert_true(state.set_flag(&"flag_b", true))
	assert_true(state.get_flag(&"flag_b"))
	assert_true(state.set_flag(&"flag_a", false))
	assert_false(state.get_flag(&"flag_a"))


func test_setup_is_deep_copied_in_both_directions() -> void:
	var setup: InitialStateDataScript = _make_setup()
	var state: GameStateScript = GameStateScript.new(setup)

	state.set_resource(&"res_a", 9)
	state.set_flag(&"flag_b", true)
	assert_eq(setup.starting_resources[&"res_a"], 3)
	assert_eq(setup.starting_flags, PackedStringArray(["flag_a"]))

	setup.starting_resources[&"res_b"] = 7
	setup.starting_resources[&"res_new"] = 1
	setup.starting_flags.append("flag_c")
	assert_eq(state.get_resource(&"res_b"), 0)
	assert_false(state.has_resource(&"res_new"))
	assert_false(state.get_flag(&"flag_c"))


func test_snapshots_do_not_expose_internal_state() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())

	var resources: Dictionary = state.get_resources_snapshot()
	resources[&"res_a"] = 99
	resources[&"res_new"] = 1
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_false(state.has_resource(&"res_new"))

	var flags: Dictionary = state.get_flags_snapshot()
	flags[&"flag_a"] = false
	flags[&"flag_b"] = true
	assert_true(state.get_flag(&"flag_a"))
	assert_false(state.get_flag(&"flag_b"))


func test_same_seed_produces_same_sequence() -> void:
	var first: GameStateScript = GameStateScript.new(_make_setup())
	var second: GameStateScript = GameStateScript.new(_make_setup())
	assert_eq(_sample(first), _sample(second))


func test_different_seed_produces_different_sequence() -> void:
	var other_setup: InitialStateDataScript = _make_setup()
	other_setup.rng_seed = 54321
	var first: GameStateScript = GameStateScript.new(_make_setup())
	var second: GameStateScript = GameStateScript.new(other_setup)
	assert_ne(_sample(first), _sample(second))


func test_state_changed_emitted_once_per_real_change() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)

	state.set_resource(&"res_a", 4)
	assert_eq(calls[0], 1)
	state.set_flag(&"flag_b", true)
	assert_eq(calls[0], 2)


func test_state_changed_not_emitted_for_same_value() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)

	assert_true(state.set_resource(&"res_a", 3))
	assert_true(state.set_flag(&"flag_a", true))
	assert_true(state.set_flag(&"flag_b", false))
	assert_eq(calls[0], 0)


# --- Zaman ve görev durumu ---

func test_time_state_defaults_to_not_started() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	assert_eq(state.get_night(), 0)
	assert_eq(state.get_elapsed_units(), 0)
	assert_false(state.is_night_ended())
	assert_eq(state.get_tasks_snapshot().size(), 0)


func test_set_time_state_writes_values_and_emits_once() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var calls: Array[int] = _count_signals(state)
	assert_true(state.set_time_state(1, 4, false, _tasks([["task_a", "actor_a", 3]])))
	assert_eq(calls[0], 1)
	assert_eq(state.get_night(), 1)
	assert_eq(state.get_elapsed_units(), 4)
	assert_false(state.is_night_ended())
	var tasks: Array[TimedTaskStateScript] = state.get_tasks_snapshot()
	assert_eq(tasks.size(), 1)
	assert_eq(tasks[0].task_id, &"task_a")
	assert_eq(tasks[0].assigned_actor_id, &"actor_a")
	assert_eq(tasks[0].remaining_units, 3)


func test_set_time_state_with_same_values_does_not_emit() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_time_state(1, 4, false, _tasks([["task_a", "actor_a", 3]]))
	var calls: Array[int] = _count_signals(state)
	# Eşit içerikli yeni görev nesneleri değişiklik sayılmaz.
	assert_true(state.set_time_state(1, 4, false, _tasks([["task_a", "actor_a", 3]])))
	assert_eq(calls[0], 0)


func test_set_time_state_rejects_invalid_values_without_change() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_time_state(1, 2, false, _tasks([["task_a", "actor_a", 3]]))
	var calls: Array[int] = _count_signals(state)
	var invalid_cases: Array = [
		[-1, 0, false, _tasks([])],
		[1, -1, false, _tasks([])],
		[1, 0, false, _tasks([["", "actor_a", 1]])],
		[1, 0, false, _tasks([["task_b", "", 1]])],
		[1, 0, false, _tasks([["task_b", "actor_a", 0]])],
		[1, 0, false, _tasks([["task_b", "actor_a", 1], ["task_b", "actor_b", 2]])],
	]
	for case in invalid_cases:
		assert_false(state.set_time_state(case[0], case[1], case[2], case[3]), str(case))
		assert_eq(take_engine_errors().size(), 1, str(case))
	assert_eq(state.get_night(), 1)
	assert_eq(state.get_elapsed_units(), 2)
	assert_eq(state.get_tasks_snapshot().size(), 1)
	assert_eq(calls[0], 0)


func test_set_time_state_copies_input_tasks() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var input: Array[TimedTaskStateScript] = _tasks([["task_a", "actor_a", 3]])
	state.set_time_state(1, 0, false, input)
	input[0].remaining_units = 99
	input.append(TimedTaskStateScript.new(&"task_b", &"actor_a", 1))
	var tasks: Array[TimedTaskStateScript] = state.get_tasks_snapshot()
	assert_eq(tasks.size(), 1)
	assert_eq(tasks[0].remaining_units, 3)


func test_tasks_snapshot_does_not_expose_internal_state() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_time_state(1, 0, false, _tasks([["task_a", "actor_a", 3]]))
	var snapshot: Array[TimedTaskStateScript] = state.get_tasks_snapshot()
	snapshot[0].remaining_units = 99
	snapshot[0].assigned_actor_id = &"actor_b"
	snapshot.clear()
	var tasks: Array[TimedTaskStateScript] = state.get_tasks_snapshot()
	assert_eq(tasks.size(), 1)
	assert_eq(tasks[0].remaining_units, 3)
	assert_eq(tasks[0].assigned_actor_id, &"actor_a")


func test_tasks_are_kept_sorted_by_task_id() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_time_state(1, 0, false, _tasks([["task_c", "actor_a", 1], ["task_a", "actor_a", 1], ["task_b", "actor_b", 1]]))
	var ids: Array[StringName] = []
	for task in state.get_tasks_snapshot():
		ids.append(task.task_id)
	assert_eq(ids, [&"task_a", &"task_b", &"task_c"] as Array[StringName])


func test_timed_task_state_copy_is_independent_and_equal() -> void:
	var original: TimedTaskStateScript = TimedTaskStateScript.new(&"task_a", &"actor_a", 3)
	var duplicate: TimedTaskStateScript = original.copy()
	assert_true(original.equals(duplicate))
	duplicate.remaining_units = 2
	assert_false(original.equals(duplicate))
	assert_eq(original.remaining_units, 3)
	assert_false(original.equals(TimedTaskStateScript.new(&"task_a", &"actor_b", 3)))
	assert_false(original.equals(TimedTaskStateScript.new(&"task_b", &"actor_a", 3)))


# --- Güven durumu ---

func test_trust_state_defaults_to_empty() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	assert_eq(state.get_trust_snapshot().size(), 0)
	assert_false(state.has_trust(&"actor_a", &"actor_b"))


func test_set_trust_state_writes_values_and_emits_once() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var calls: Array[int] = _count_signals(state)
	assert_true(state.set_trust_state(_trust([["actor_a", "actor_b", 60], ["actor_b", "actor_a", 30]])))
	assert_eq(calls[0], 1)
	assert_true(state.has_trust(&"actor_a", &"actor_b"))
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq(state.get_trust(&"actor_b", &"actor_a"), 30)


func test_set_trust_state_with_same_values_does_not_emit() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_trust_state(_trust([["actor_a", "actor_b", 60]]))
	var calls: Array[int] = _count_signals(state)
	assert_true(state.set_trust_state(_trust([["actor_a", "actor_b", 60]])))
	assert_eq(calls[0], 0)


func test_set_trust_state_rejects_invalid_entries_without_change() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_trust_state(_trust([["actor_a", "actor_b", 60]]))
	var calls: Array[int] = _count_signals(state)
	var invalid_cases: Array = [
		_trust([["", "actor_b", 1]]),
		_trust([["actor_a", "", 1]]),
		_trust([["actor_a", "actor_a", 1]]),
		_trust([["actor_a", "actor_b", 1], ["actor_a", "actor_b", 2]]),
	]
	for entries in invalid_cases:
		assert_false(state.set_trust_state(entries))
		assert_eq(take_engine_errors().size(), 1)
	var with_null: Array[TrustRelationshipStateScript] = [null]
	assert_false(state.set_trust_state(with_null))
	assert_eq(take_engine_errors().size(), 1)
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq(state.get_trust_snapshot().size(), 1)
	assert_eq(calls[0], 0)


func test_get_trust_for_undefined_relationship_errors_and_returns_zero() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_trust_state(_trust([["actor_a", "actor_b", 60]]))
	assert_eq(state.get_trust(&"actor_b", &"actor_a"), 0)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))


func test_set_trust_state_copies_input_entries() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	var input: Array[TrustRelationshipStateScript] = _trust([["actor_a", "actor_b", 60]])
	state.set_trust_state(input)
	input[0].value = 99
	input.append(TrustRelationshipStateScript.new(&"actor_b", &"actor_a", 1))
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_false(state.has_trust(&"actor_b", &"actor_a"))


func test_trust_snapshot_does_not_expose_internal_state() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_trust_state(_trust([["actor_a", "actor_b", 60]]))
	var snapshot: Array[TrustRelationshipStateScript] = state.get_trust_snapshot()
	snapshot[0].value = 99
	snapshot[0].target_actor_id = &"actor_c"
	snapshot.clear()
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq(state.get_trust_snapshot().size(), 1)


func test_trust_entries_are_kept_sorted_by_source_then_target() -> void:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_trust_state(_trust([["actor_b", "actor_a", 1], ["actor_a", "actor_c", 2], ["actor_a", "actor_b", 3]]))
	var pairs: Array = []
	for entry in state.get_trust_snapshot():
		pairs.append("%s>%s" % [entry.source_actor_id, entry.target_actor_id])
	assert_eq(pairs, ["actor_a>actor_b", "actor_a>actor_c", "actor_b>actor_a"])


func test_trust_relationship_state_copy_is_independent_and_equal() -> void:
	var original: TrustRelationshipStateScript = TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)
	var duplicate: TrustRelationshipStateScript = original.copy()
	assert_true(original.equals(duplicate))
	duplicate.value = 61
	assert_false(original.equals(duplicate))
	assert_eq(original.value, 60)
	assert_false(original.equals(TrustRelationshipStateScript.new(&"actor_b", &"actor_a", 60)))


# --- Atomik değişiklik paketi ---

func test_apply_changes_writes_every_category_with_one_signal() -> void:
	var state: GameStateScript = _make_state_with_trust()
	var calls: Array[int] = _count_signals(state)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.resource_values[&"res_a"] = 7
	change.flag_values[&"flag_b"] = true
	change.trust_values.append(TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 70))
	change.set_time_state(1, 4, false, _tasks([["task_a", "actor_a", 3]]))
	assert_true(state.apply_changes(change))
	assert_eq(calls[0], 1)
	assert_eq(state.get_resource(&"res_a"), 7)
	assert_eq(state.get_resource(&"res_b"), 0)
	assert_true(state.get_flag(&"flag_b"))
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 70)
	assert_eq(state.get_trust(&"actor_b", &"actor_a"), 30)
	assert_eq([state.get_night(), state.get_elapsed_units(), state.is_night_ended()], [1, 4, false])
	assert_eq(state.get_tasks_snapshot()[0].task_id, &"task_a")


func test_apply_changes_with_empty_package_is_a_silent_success() -> void:
	var state: GameStateScript = _make_state_with_trust()
	var calls: Array[int] = _count_signals(state)
	assert_true(state.apply_changes(GameStateChangeScript.new()))
	assert_eq(calls[0], 0)


func test_apply_changes_without_real_change_does_not_emit() -> void:
	var state: GameStateScript = _make_state_with_trust()
	var calls: Array[int] = _count_signals(state)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.resource_values[&"res_a"] = 3
	change.flag_values[&"flag_a"] = true
	change.flag_values[&"flag_new"] = false
	change.trust_values.append(TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60))
	change.set_time_state(0, 0, false, _tasks([]))
	assert_true(state.apply_changes(change))
	assert_eq(calls[0], 0)
	assert_false(state.get_flags_snapshot().has(&"flag_new"))


func test_apply_changes_with_invalid_last_field_writes_nothing() -> void:
	var state: GameStateScript = _make_state_with_trust()
	var calls: Array[int] = _count_signals(state)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.resource_values[&"res_a"] = 9
	change.flag_values[&"flag_b"] = true
	change.trust_values.append(TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 90))
	change.set_time_state(-1, 0, false, _tasks([]))
	assert_false(state.apply_changes(change))
	assert_eq(take_engine_errors().size(), 1)
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_false(state.get_flag(&"flag_b"))
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq(state.get_night(), 0)
	assert_eq(calls[0], 0)


func test_apply_changes_rejects_each_invalid_field_without_change() -> void:
	var state: GameStateScript = _make_state_with_trust()
	var calls: Array[int] = _count_signals(state)
	var invalid_changes: Array = []
	var undefined_resource: GameStateChangeScript = GameStateChangeScript.new()
	undefined_resource.resource_values[&"missing_id"] = 1
	invalid_changes.append(undefined_resource)
	var empty_flag: GameStateChangeScript = GameStateChangeScript.new()
	empty_flag.flag_values[&""] = true
	invalid_changes.append(empty_flag)
	for row in [["actor_b", "actor_c", 1], ["actor_a", "actor_a", 1], ["", "actor_b", 1]]:
		var bad_trust: GameStateChangeScript = GameStateChangeScript.new()
		bad_trust.trust_values = _trust([row])
		invalid_changes.append(bad_trust)
	var duplicate_trust: GameStateChangeScript = GameStateChangeScript.new()
	duplicate_trust.trust_values = _trust([["actor_a", "actor_b", 1], ["actor_a", "actor_b", 2]])
	invalid_changes.append(duplicate_trust)
	var bad_task: GameStateChangeScript = GameStateChangeScript.new()
	bad_task.set_time_state(1, 0, false, _tasks([["task_a", "actor_a", 0]]))
	invalid_changes.append(bad_task)
	for change in invalid_changes:
		assert_false(state.apply_changes(change))
		assert_eq(take_engine_errors().size(), 1)
	assert_false(state.apply_changes(null))
	assert_eq(take_engine_errors().size(), 1)
	assert_eq(state.get_resources_snapshot(), {&"res_a": 3, &"res_b": 0})
	assert_eq(state.get_flags_snapshot(), {&"flag_a": true})
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq(state.get_night(), 0)
	assert_eq(calls[0], 0)


func test_apply_changes_copies_package_contents() -> void:
	var state: GameStateScript = _make_state_with_trust()
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.trust_values = _trust([["actor_a", "actor_b", 70]])
	change.set_time_state(1, 2, false, _tasks([["task_a", "actor_a", 3]]))
	state.apply_changes(change)
	change.trust_values[0].value = 1
	change.tasks[0].remaining_units = 99
	change.resource_values[&"res_a"] = 50
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 70)
	assert_eq(state.get_tasks_snapshot()[0].remaining_units, 3)
	assert_eq(state.get_resource(&"res_a"), 3)


func _make_state_with_trust() -> GameStateScript:
	var state: GameStateScript = GameStateScript.new(_make_setup())
	state.set_trust_state(_trust([["actor_a", "actor_b", 60], ["actor_b", "actor_a", 30]]))
	return state


# [[source, target, value], ...] biçiminden tipli güven listesi kurar.
func _trust(rows: Array) -> Array[TrustRelationshipStateScript]:
	var result: Array[TrustRelationshipStateScript] = []
	for row in rows:
		result.append(TrustRelationshipStateScript.new(StringName(row[0]), StringName(row[1]), row[2]))
	return result


func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


# [[task_id, actor_id, remaining], ...] biçiminden tipli görev listesi kurar.
func _tasks(rows: Array) -> Array[TimedTaskStateScript]:
	var result: Array[TimedTaskStateScript] = []
	for row in rows:
		result.append(TimedTaskStateScript.new(StringName(row[0]), StringName(row[1]), row[2]))
	return result


func _make_setup() -> InitialStateDataScript:
	var setup: InitialStateDataScript = InitialStateDataScript.new()
	setup.id = "state_setup_a"
	setup.starting_resources = {&"res_a": 3, &"res_b": 0}
	setup.starting_flags = PackedStringArray(["flag_a"])
	setup.rng_seed = 12345
	return setup


func _sample(state: GameStateScript) -> Array[int]:
	var values: Array[int] = []
	for i in RANDOM_SAMPLE_COUNT:
		values.append(state.random_int(0, RANDOM_MAX))
	return values


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_engine_error_mentions(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))
