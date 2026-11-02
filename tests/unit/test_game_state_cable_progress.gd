extends "res://tests/framework/test_case.gd"
## GameState içindeki kablo bulmacası ilerlemesi (K-032): başlangıç kayıtları, okuma ve apply_changes geçiş
## kuralları. Yalnızca tarafsız kimlikler.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const CablePuzzleProgressStateScript := preload("res://scripts/core/cable_puzzle_progress_state.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const Fixtures := preload("res://tests/fixtures/cable_repair_fixtures.gd")


# --- Başlangıç ve okuma ---

func test_initial_records_are_sorted_and_start_unsolved() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_c", "puzzle_a", "puzzle_b"]))
	assert_eq(Fixtures.progress_rows(state), [["puzzle_a", 0, false], ["puzzle_b", 0, false], ["puzzle_c", 0, false]])
	assert_eq([state.has_cable_puzzle(&"puzzle_b"), state.has_cable_puzzle(&"puzzle_x")], [true, false])


func test_empty_and_duplicate_initial_ids_are_skipped_with_errors() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_b", "", "puzzle_b", "puzzle_a"]))
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	for error in errors:
		assert_true(error.contains("boş veya tekrarlanan kablo bulmacası kimliği"), error)
	assert_eq(Fixtures.progress_rows(state), [["puzzle_a", 0, false], ["puzzle_b", 0, false]])


func test_no_cable_puzzles_by_default() -> void:
	var state: GameStateScript = GameStateScript.new(DecisionFixtures.make_state_setup())
	assert_eq(state.get_cable_puzzle_progress_snapshot().size(), 0)


func test_snapshot_and_single_read_are_independent_copies() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a"]))
	var snapshot: Array[CablePuzzleProgressStateScript] = state.get_cable_puzzle_progress_snapshot()
	snapshot[0].resolutions_used = 5
	snapshot.clear()
	var single: CablePuzzleProgressStateScript = state.get_cable_puzzle_progress(&"puzzle_a")
	single.solved = true
	assert_eq(Fixtures.progress_rows(state), [["puzzle_a", 0, false]])
	assert_false(is_same(state.get_cable_puzzle_progress(&"puzzle_a"), state.get_cable_puzzle_progress(&"puzzle_a")))


func test_reading_an_unknown_puzzle_is_an_error() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a"]))
	assert_true(state.get_cable_puzzle_progress(&"puzzle_x") == null)
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.size() == 1 and errors[0].contains("tanımsız kablo bulmacası okunamaz: 'puzzle_x'"),
			" | ".join(errors))


# --- Geçerli geçişler ---

func test_failed_resolution_increments_once_with_one_signal() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a", "puzzle_b"]))
	var signals: Array = _count_signals(state)
	assert_true(state.apply_changes(_change([_progress("puzzle_a", 1, false)])))
	assert_eq(Fixtures.progress_rows(state), [["puzzle_a", 1, false], ["puzzle_b", 0, false]])
	assert_eq(signals[0], 1)


func test_solved_resolution_increments_and_solves() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a"]))
	var signals: Array = _count_signals(state)
	assert_true(state.apply_changes(_change([_progress("puzzle_a", 1, true)])))
	assert_eq(Fixtures.progress_rows(state), [["puzzle_a", 1, true]])
	assert_eq(signals[0], 1)


func test_solving_after_a_failed_resolution() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a"]))
	assert_true(state.apply_changes(_change([_progress("puzzle_a", 1, false)])))
	assert_true(state.apply_changes(_change([_progress("puzzle_a", 2, true)])))
	assert_eq(Fixtures.progress_rows(state), [["puzzle_a", 2, true]])


func test_identical_entry_is_a_silent_no_op() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a"]))
	assert_true(state.apply_changes(_change([_progress("puzzle_a", 1, true)])))
	var signals: Array = _count_signals(state)
	assert_true(state.apply_changes(_change([_progress("puzzle_a", 1, true)])))
	var fresh: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a"]))
	var fresh_signals: Array = _count_signals(fresh)
	assert_true(fresh.apply_changes(_change([_progress("puzzle_a", 0, false)])))
	assert_eq([signals[0], fresh_signals[0]], [0, 0])
	assert_eq(Fixtures.progress_rows(state), [["puzzle_a", 1, true]])
	assert_eq(take_engine_errors().size(), 0)


# --- Geçersiz geçişler: her biri bütün paketi reddeder ---

func test_negative_count_is_rejected() -> void:
	_assert_rejected([_progress("puzzle_a", -1, false)], "negatif çözüm sayısı")


func test_count_cannot_go_back() -> void:
	_assert_rejected([_progress("puzzle_a", 0, false)], "geri gidemez", [_progress("puzzle_a", 1, false)])


func test_count_cannot_grow_by_more_than_one() -> void:
	_assert_rejected([_progress("puzzle_a", 2, false)], "en fazla bir artar")


func test_solved_cannot_become_unsolved() -> void:
	_assert_rejected([_progress("puzzle_a", 1, false)], "çözülmüş kablo bulmacası değiştirilemez",
			[_progress("puzzle_a", 1, true)])


func test_solved_record_cannot_change_at_all() -> void:
	_assert_rejected([_progress("puzzle_a", 2, true)], "çözülmüş kablo bulmacası değiştirilemez",
			[_progress("puzzle_a", 1, true)])


func test_solving_without_increment_is_rejected() -> void:
	_assert_rejected([_progress("puzzle_a", 0, true)], "artmadan çözülmüş olamaz")
	_assert_rejected([_progress("puzzle_a", 1, true)], "artmadan çözülmüş olamaz", [_progress("puzzle_a", 1, false)])


func test_unknown_puzzle_is_rejected() -> void:
	_assert_rejected([_progress("puzzle_x", 1, false)], "tanımsız kablo bulmacası: 'puzzle_x'")


func test_duplicate_puzzle_in_one_package_is_rejected() -> void:
	_assert_rejected([_progress("puzzle_a", 1, false), _progress("puzzle_a", 1, false)],
			"tekrarlanan kablo bulmacası: 'puzzle_a'")


func test_null_and_empty_entries_are_rejected() -> void:
	_assert_rejected([null], "geçersiz kablo bulmacası kaydı")
	_assert_rejected([_progress("", 1, false)], "geçersiz kablo bulmacası kaydı")


func test_rejection_keeps_every_category_and_emits_nothing() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world(["puzzle_a", "puzzle_b"])
	Fixtures.start(world)
	var state: GameStateScript = world.state
	var before: Array = Fixtures.describe_state(state)
	var signals: Array = _count_signals(state)
	var change: GameStateChangeScript = _change([_progress("puzzle_a", 1, false), _progress("puzzle_b", 3, false)])
	change.resource_values[&"res_a"] = 1
	change.flag_values[&"flag_x"] = true
	change.equipment_values.append(EquipmentStateScript.new(&"equipment_b", EquipmentStateScript.CONDITION_OPERATIONAL))
	var no_tasks: Array[TimedTaskStateScript] = []
	change.set_time_state(1, 4, false, no_tasks)
	assert_false(state.apply_changes(change))
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.size() == 1 and errors[0].contains("en fazla bir artar"), " | ".join(errors))
	assert_eq(Fixtures.describe_state(state), before)
	assert_eq(signals[0], 0)


func test_valid_combined_package_emits_one_signal() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world(["puzzle_a", "puzzle_b"])
	Fixtures.start(world)
	var signals: Array = _count_signals(world.state)
	var change: GameStateChangeScript = _change([_progress("puzzle_b", 1, true)])
	change.resource_values[&"res_a"] = 1
	var no_tasks: Array[TimedTaskStateScript] = []
	change.set_time_state(1, 4, false, no_tasks)
	assert_true(world.state.apply_changes(change))
	assert_eq(signals[0], 1)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 0, false], ["puzzle_b", 1, true]])
	assert_eq([world.state.get_resource(&"res_a"), world.state.get_elapsed_units()], [1, 4])


func test_is_empty_covers_cable_progress() -> void:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	assert_true(change.is_empty())
	change.cable_puzzle_progress.append(_progress("puzzle_a", 1, false))
	assert_false(change.is_empty())


# --- Yardımcılar ---

func _progress(puzzle_id: String, resolutions_used: int, solved: bool) -> CablePuzzleProgressStateScript:
	return CablePuzzleProgressStateScript.new(StringName(puzzle_id), resolutions_used, solved)


# entries içindeki null değerler boş kayıt olarak eklenir.
func _change(entries: Array) -> GameStateChangeScript:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	for entry in entries:
		change.cable_puzzle_progress.append(entry)
	return change


func _count_signals(state: GameStateScript) -> Array:
	var counter: Array = [0]
	state.state_changed.connect(func() -> void: counter[0] += 1)
	return counter


# Önce prior paketini uygular, sonra entries paketinin tek hatayla reddedildiğini ve hiçbir şeyin değişmediğini sınar.
func _assert_rejected(entries: Array, error_text: String, prior: Array = []) -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["puzzle_a"]))
	if not prior.is_empty():
		assert_true(state.apply_changes(_change(prior)))
	var before: Array = Fixtures.progress_rows(state)
	var signals: Array = _count_signals(state)
	assert_false(state.apply_changes(_change(entries)))
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.size() == 1 and errors[0].contains(error_text), "%s | %s" % [error_text, " | ".join(errors)])
	assert_eq(Fixtures.progress_rows(state), before)
	assert_eq(signals[0], 0)
