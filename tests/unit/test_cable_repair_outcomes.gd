extends "res://tests/framework/test_case.gd"
## CableRepairSystem sonuç uygulama testleri (K-032): veri tanımlı dallar, tek atomik yazma, zaman ve görev
## tamamlanmaları, gece sınırı, tam geri alma, salt okunur önizleme ve determinizm. Yalnızca tarafsız kimlikler.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CableRepairSystemScript := preload("res://scripts/systems/cable_repair_system.gd")
const CableRepairResultScript := preload("res://scripts/systems/cable_repair_result.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const EquipmentFixtures := preload("res://tests/fixtures/equipment_fixtures.gd")
const Fixtures := preload("res://tests/fixtures/cable_repair_fixtures.gd")

const OPERATIONAL: StringName = EquipmentStateScript.CONDITION_OPERATIONAL
const BROKEN: StringName = EquipmentStateScript.CONDITION_BROKEN


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


class RejectingGameState extends "res://scripts/core/game_state.gd":
	var reject_changes: bool = false

	func apply_changes(change: GameStateChangeScript) -> bool:
		if reject_changes:
			push_error("test: yazma reddedildi")
			return false
		return super(change)


# --- Veri tanımlı dallar ---

func test_success_applies_branch_time_and_progress_in_one_write_and_one_signal() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = _started_world(state)
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle("puzzle_a",
			[EquipmentFixtures.eff_repair("equipment_b"), DecisionFixtures.eff_add("res_b", 2)], [], "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	var writes_before: int = state.other_writes
	var signals: Array = _count_signals(state)
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.ok, result.failure, result.puzzle_id, result.outcome], [true, &"", &"puzzle_a", &"solved"])
	assert_eq([state.apply_calls, state.other_writes - writes_before, signals[0]], [1, 0, 1])
	assert_eq(_rows_of(world.state, "equipment_b"), ["equipment_b", OPERATIONAL, 0])
	assert_eq([world.state.get_resource(&"res_b"), world.state.get_elapsed_units()], [2, 2])
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, true]])
	assert_eq([result.applied_units, result.overflow_units, result.night_ended], [2, 0, false])
	assert_eq(_effect_rows(result), [[0, &"equipment_repair", 0], [1, &"resource_add", 2]])
	assert_eq(take_engine_errors().size(), 0)


func test_failure_applies_branch_time_and_progress_in_one_write_and_one_signal() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = _started_world(state)
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle("puzzle_a", [],
			[EquipmentFixtures.eff_disable("equipment_a", 3), DecisionFixtures.eff_spend("res_a", 2)], "", "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	var signals: Array = _count_signals(state)
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.ok, result.outcome], [true, &"failed"])
	assert_eq([state.apply_calls, signals[0]], [1, 1])
	# Etki önce (3 birim), eylem süresi sonra (2 birim) işlenir.
	assert_eq(_rows_of(world.state, "equipment_a"), ["equipment_a", OPERATIONAL, 1])
	assert_eq([world.state.get_resource(&"res_a"), world.state.get_elapsed_units()], [3, 2])
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, false]])


func test_success_repair_comes_only_from_data() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.ok, result.effect_outcomes.size()], [true, 0])
	assert_eq(_rows_of(world.state, "equipment_b"), ["equipment_b", BROKEN, 0])
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, true]])


func test_failure_disable_comes_only_from_data() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	var before: Array = EquipmentFixtures.rows(world.state)
	assert_true(system.apply_result(session).ok)
	assert_eq(EquipmentFixtures.rows(world.state), before)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, false]])


func test_without_an_action_only_effects_and_progress_change() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [], [DecisionFixtures.eff_flag("flag_x", true)])])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	var before: Array = Fixtures.describe_state(world.state)
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.applied_units, result.overflow_units, result.night_ended, result.completed_task_ids,
			result.permanent_occurrence_ids, result.equipment_disable_expirations.size()],
			[0, 0, false, [] as Array[StringName], [] as Array[StringName], 0])
	var after: Array = Fixtures.describe_state(world.state)
	var flags: Dictionary = after[1]
	assert_eq([flags.size(), flags.get(&"flag_x", false)], [1, true])
	assert_eq(after[7], [["puzzle_a", 1, false]])
	# Bayrak ve ilerleme dışında hiçbir kategori değişmedi.
	for i in [0, 2, 3, 4, 5, 6]:
		assert_eq(after[i], before[i], "Kategori #%d" % i)


# --- Zaman ---

func test_task_completion_effects_join_the_same_package() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = _started_world(state)
	var task: Variant = Fixtures.make_task("task_a", [DecisionFixtures.eff_add("res_b", 4)])
	assert_true(world.time.start_task(&"task_a", &"actor_a", 2))
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_add("res_b", 1)], [], "action_a")], [task])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	var calls_before: int = state.apply_calls
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq(state.apply_calls - calls_before, 1)
	assert_eq(result.completed_task_ids, [&"task_a"] as Array[StringName])
	assert_eq([world.state.get_resource(&"res_b"), world.state.get_tasks_snapshot().size()], [5, 0])
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, true]])


func test_equipment_disable_expirations_are_reported_as_copies() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [], [EquipmentFixtures.eff_disable("equipment_c", 1)], "", "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	var preview: CableRepairResultScript = system.preview_result(session)
	assert_eq(EquipmentFixtures.expiration_rows(preview.equipment_disable_expirations), [["equipment_c", 1, 1]])
	preview.equipment_disable_expirations[0].at_units = 99
	preview.equipment_disable_expirations.clear()
	preview.completed_task_ids.append(&"task_z")
	var applied: CableRepairResultScript = system.apply_result(session)
	assert_eq(EquipmentFixtures.expiration_rows(applied.equipment_disable_expirations), [["equipment_c", 1, 1]])
	assert_eq(applied.completed_task_ids, [] as Array[StringName])
	assert_eq(_rows_of(world.state, "equipment_c"), ["equipment_c", OPERATIONAL, 0])


func test_night_boundary_and_overflow_match_the_time_system() -> void:
	var world: DecisionFixtures.World = _started_world()
	var clock: Variant = DecisionFixtures.make_completion_system(world, [])
	clock.advance(9)
	var expected: TimeProgressResultScript = clock.preview_advance(2)
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [], [DecisionFixtures.eff_add("res_b", 1)], "", "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.ok, result.applied_units, result.overflow_units, result.night_ended],
			[true, expected.time_result.applied_units, expected.time_result.overflow_units, true])
	assert_eq([result.applied_units, result.overflow_units], [1, 1])
	assert_eq(result.permanent_occurrence_ids, expected.permanent_occurrence_ids)
	assert_eq([world.state.get_night(), world.state.get_elapsed_units(), world.state.is_night_ended()], [1, 10, true])
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, false]])


func test_the_system_never_selects_an_ending() -> void:
	var script: GDScript = CableRepairSystemScript as GDScript
	var constants: Dictionary = script.get_script_constant_map()
	for constant_name: String in constants:
		var value: Variant = constants[constant_name]
		if value is Script:
			assert_false((value as Script).resource_path.contains("ending"), "Son bağımlılığı: %s" % constant_name)
	var names: Array[String] = []
	for property in CableRepairResultScript.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_false(names.has("ending_id"))


# --- Tam geri alma ---

func test_unapplicable_effect_at_apply_changes_nothing_and_keeps_the_session() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [], [DecisionFixtures.eff_spend("res_a", 4)], "", "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	world.state.set_resource(&"res_a", 1)
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.ok, result.failure, result.blocking_effect_index, result.outcome, result.effect_outcomes.size()],
			[false, &"effect_not_applicable", 0, &"failed", 0])
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(signals[0], 0)
	assert_eq(take_engine_errors().size(), 0)
	world.state.set_resource(&"res_a", 5)
	assert_true(system.apply_result(session).ok)
	assert_eq([world.state.get_resource(&"res_a"), world.state.get_elapsed_units()], [1, 2])


func test_time_unavailable_at_apply_changes_nothing_and_keeps_the_session() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_add("res_b", 1)], [], "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	DecisionFixtures.make_completion_system(world, []).advance(10)
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.ok, result.failure, result.outcome], [false, &"time_unavailable", &"solved"])
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(signals[0], 0)
	assert_eq(take_engine_errors().size(), 0)
	assert_true(world.time.start_night())
	assert_true(system.apply_result(session).ok)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, true]])


func test_failed_write_changes_nothing_and_keeps_the_session() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = _started_world(state)
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [EquipmentFixtures.eff_repair("equipment_b")], [], "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	state.reject_changes = true
	var result: CableRepairResultScript = system.apply_result(session)
	assert_eq([result.ok, result.failure, result.outcome, result.effect_outcomes.size(), result.applied_units],
			[false, &"write_failed", &"solved", 0, 0])
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_true(errors.size() == 2 and errors[1].contains("durum yazılamadı"), " | ".join(errors))
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(signals[0], 0)
	state.reject_changes = false
	assert_true(system.apply_result(session).ok)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, true]])


# --- Önizleme ---

func test_preview_is_read_only_repeatable_and_matches_apply() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = _started_world(state)
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle("puzzle_a",
			[EquipmentFixtures.eff_repair("equipment_b"), DecisionFixtures.eff_add("res_b", 2)], [], "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	var before: Array = Fixtures.describe_state(world.state)
	var writes_before: Array = [state.apply_calls, state.other_writes]
	var signals: Array = _count_signals(state)
	var previews: Array = []
	for i in 3:
		previews.append(_describe_result(system.preview_result(session)))
	assert_eq([state.apply_calls, state.other_writes], writes_before)
	assert_eq(signals[0], 0)
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(previews[1], previews[0])
	assert_eq(previews[2], previews[0])
	var applied: CableRepairResultScript = system.apply_result(session)
	assert_eq(_describe_result(applied), previews[0])
	assert_eq(take_engine_errors().size(), 0)


func test_result_does_not_expose_internal_completion_details() -> void:
	var names: Array[String] = []
	for property in CableRepairResultScript.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["ok", "failure", "puzzle_id", "outcome", "blocking_effect_index", "effect_outcomes",
			"applied_units", "overflow_units", "night_ended", "completed_task_ids", "permanent_occurrence_ids",
			"equipment_disable_expirations"] as Array[String])


# --- Determinizm ---

func test_same_inputs_and_moves_produce_same_results() -> void:
	var first: Array = _play_scenario()
	var second: Array = _play_scenario()
	assert_eq(first, second)
	assert_eq(first[first.size() - 1][7], [["puzzle_a", 1, false], ["puzzle_b", 1, true]])


# --- Yardımcılar ---

func _started_world(state: GameStateScript = null) -> DecisionFixtures.World:
	var world: DecisionFixtures.World = Fixtures.make_world(["puzzle_a"], state)
	Fixtures.start(world)
	return world


func _count_signals(state: GameStateScript) -> Array:
	var counter: Array = [0]
	state.state_changed.connect(func() -> void: counter[0] += 1)
	return counter


func _rows_of(state: GameStateScript, equipment_id: String) -> Array:
	for row in EquipmentFixtures.rows(state):
		if row[0] == equipment_id:
			return row
	return []


func _effect_rows(result: CableRepairResultScript) -> Array:
	var rows: Array = []
	for outcome in result.effect_outcomes:
		rows.append([outcome.index, outcome.kind, outcome.applied])
	return rows


func _describe_result(result: CableRepairResultScript) -> Array:
	return [result.ok, result.failure, result.puzzle_id, result.outcome, result.blocking_effect_index,
			_effect_rows(result), result.applied_units, result.overflow_units, result.night_ended,
			result.completed_task_ids, result.permanent_occurrence_ids,
			EquipmentFixtures.expiration_rows(result.equipment_disable_expirations)]


# Sabit bir senaryo: iki bulmaca, başarısız ve başarılı sonuçlar, bir eski oturum; her adımın sonucu kaydedilir.
func _play_scenario() -> Array:
	var world: DecisionFixtures.World = Fixtures.make_world(["puzzle_a", "puzzle_b"])
	Fixtures.start(world)
	var system: CableRepairSystemScript = Fixtures.make_system(world, [
			Fixtures.make_puzzle("puzzle_b", [EquipmentFixtures.eff_repair("equipment_b")], [], "action_a"),
			Fixtures.make_puzzle("puzzle_a", [], [EquipmentFixtures.eff_disable("equipment_a", 3)], "", "action_a")])
	var steps: Array = []
	var a: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	var a_parallel: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(a)
	Fixtures.solve(a_parallel)
	steps.append(_describe_result(system.preview_result(a)))
	steps.append(_describe_result(system.apply_result(a)))
	steps.append(_describe_result(system.apply_result(a_parallel)))
	var b: CablePuzzleSessionScript = system.start_session(&"puzzle_b").session
	Fixtures.solve(b)
	steps.append(_describe_result(system.apply_result(b)))
	steps.append(system.start_session(&"puzzle_b").failure)
	steps.append(Fixtures.describe_state(world.state))
	return steps
