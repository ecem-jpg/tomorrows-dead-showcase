extends "res://tests/framework/test_case.gd"
## CableRepairSystem oturum açma ve sahiplik testleri (K-032): başlatma sonuçları, oyun geneli tekrar, iki dalın
## yan etkisiz ön planlaması, yabancı/bitmemiş/uygulanmış/eski oturumlar. Yalnızca tarafsız kimlikler.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CableRepairSystemScript := preload("res://scripts/systems/cable_repair_system.gd")
const CablePuzzleStartResultScript := preload("res://scripts/systems/cable_puzzle_start_result.gd")
const CableRepairResultScript := preload("res://scripts/systems/cable_repair_result.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const EquipmentFixtures := preload("res://tests/fixtures/equipment_fixtures.gd")
const Fixtures := preload("res://tests/fixtures/cable_repair_fixtures.gd")


# --- Başlatma sonuçları ---

func test_started_session_writes_nothing() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	var result: CablePuzzleStartResultScript = system.start_session(&"puzzle_a")
	assert_true(result.is_started())
	assert_eq([result.status, result.failure, result.puzzle_id], [&"started", &"", &"puzzle_a"])
	assert_true(result.session != null)
	assert_eq([result.session.get_puzzle_id(), result.session.get_status()], [&"puzzle_a", &"in_progress"])
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(signals[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_conditions_not_met_is_a_normal_result() -> void:
	var world: DecisionFixtures.World = _started_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle()
	puzzle.start_conditions.append(DecisionFixtures.cond_resource("res_a", &"ge", 1))
	puzzle.start_conditions.append(DecisionFixtures.cond_flag("flag_x", true))
	var result: CablePuzzleStartResultScript = Fixtures.make_system(world, [puzzle]).start_session(&"puzzle_a")
	assert_eq([result.is_started(), result.failure, result.failed_condition_indexes, result.session],
			[false, &"conditions_not_met", PackedInt32Array([1]), null])
	assert_eq(take_engine_errors().size(), 0)


func test_trust_condition_requires_initialized_trust() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	world.time.start_night()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle()
	puzzle.start_conditions.append(DecisionFixtures.cond_trust("actor_a", "actor_b", &"ge", 10))
	var result: CablePuzzleStartResultScript = Fixtures.make_system(world, [puzzle]).start_session(&"puzzle_a")
	assert_eq([result.failure, result.session], [&"system_not_ready", null])
	_assert_one_error("güven başlatılmadı")


func test_trust_effect_in_a_branch_requires_initialized_trust() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	world.time.start_night()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a", [], [DecisionFixtures.eff_trust("actor_a", "actor_b", -5)])
	var result: CablePuzzleStartResultScript = Fixtures.make_system(world, [puzzle]).start_session(&"puzzle_a")
	assert_eq(result.failure, &"system_not_ready")
	_assert_one_error("güven başlatılmadı")


func test_trust_is_not_required_without_trust_usage() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	world.time.start_night()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_add("res_b", 1)], [], "action_a")
	puzzle.start_conditions.append(DecisionFixtures.cond_resource("res_a", &"ge", 1))
	var result: CablePuzzleStartResultScript = Fixtures.make_system(world, [puzzle]).start_session(&"puzzle_a")
	assert_true(result.is_started())
	assert_eq(take_engine_errors().size(), 0)


func test_unknown_puzzle_is_a_flow_error() -> void:
	var world: DecisionFixtures.World = _started_world()
	var result: CablePuzzleStartResultScript = Fixtures.make_system(world, [Fixtures.make_puzzle()]).start_session(&"puzzle_x")
	assert_eq([result.failure, result.puzzle_id, result.session], [&"unknown_puzzle", &"puzzle_x", null])
	_assert_one_error("tanımsız kablo bulmacası: 'puzzle_x'")


func test_solved_puzzle_cannot_be_started_again() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	assert_true(system.apply_result(session).ok)
	var result: CablePuzzleStartResultScript = system.start_session(&"puzzle_a")
	assert_eq([result.failure, result.session], [&"already_solved", null])
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, true]])
	assert_eq(take_engine_errors().size(), 0)


func test_failure_with_remaining_resolutions_allows_a_new_session() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	assert_true(system.apply_result(session).ok)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, false]])
	assert_true(system.start_session(&"puzzle_a").is_started())


func test_last_resolution_is_consumed_and_unsolved_puzzle_cannot_restart() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	for i in 2:
		var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
		Fixtures.fail(session)
		assert_true(system.apply_result(session).ok)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 2, false]])
	var result: CablePuzzleStartResultScript = system.start_session(&"puzzle_a")
	assert_eq([result.failure, result.session], [&"resolution_limit_reached", null])
	assert_eq(take_engine_errors().size(), 0)


func test_abandoned_sessions_use_no_resolution() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var before: Array = Fixtures.describe_state(world.state)
	for i in 3:
		var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
		session.connect_terminals(Fixtures.A, Fixtures.D)
		assert_eq(session.submit(), &"incomplete")
	var unsent: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(unsent)
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 0, false]])


# --- Dalların ön planlaması ---

func test_unapplicable_success_effect_blocks_the_start() -> void:
	var world: DecisionFixtures.World = _started_world()
	_assert_outcome_unavailable(world, Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_spend("res_a", 9)]))


func test_unapplicable_failure_effect_blocks_the_start() -> void:
	var world: DecisionFixtures.World = _started_world()
	_assert_outcome_unavailable(world, Fixtures.make_puzzle("puzzle_a", [], [DecisionFixtures.eff_spend("res_a", 9)]))


func test_success_repair_of_working_equipment_blocks_the_start() -> void:
	var world: DecisionFixtures.World = _started_world()
	_assert_outcome_unavailable(world, Fixtures.make_puzzle("puzzle_a", [EquipmentFixtures.eff_repair("equipment_a")]))


func test_branch_cost_without_an_active_night_blocks_the_start() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	world.trust.initialize_relationships()
	_assert_outcome_unavailable(world, Fixtures.make_puzzle("puzzle_a", [], [], "", "action_a"))
	_assert_outcome_unavailable(world, Fixtures.make_puzzle("puzzle_a", [], [], "action_a", ""))
	# Gece bittikten sonra da aynı.
	world.time.start_night()
	DecisionFixtures.make_completion_system(world, []).advance(10)
	assert_true(world.state.is_night_ended())
	_assert_outcome_unavailable(world, Fixtures.make_puzzle("puzzle_a", [], [], "", "action_a"))


func test_both_applicable_branches_start_the_session() -> void:
	var world: DecisionFixtures.World = _started_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a",
			[EquipmentFixtures.eff_repair("equipment_b"), DecisionFixtures.eff_add("res_b", 2)],
			[EquipmentFixtures.eff_disable("equipment_b", 2), DecisionFixtures.eff_spend("res_a", 5)], "action_a", "action_a")
	assert_true(Fixtures.make_system(world, [puzzle]).start_session(&"puzzle_a").is_started())
	assert_eq(take_engine_errors().size(), 0)


func test_preplanning_keeps_completions_expirations_and_night_end_temporary() -> void:
	var world: DecisionFixtures.World = _started_world()
	var task: Variant = Fixtures.make_task("task_a", [DecisionFixtures.eff_add("res_b", 3)])
	DecisionFixtures.make_completion_system(world, [task]).advance(8)
	assert_true(world.time.start_task(&"task_a", &"actor_a", 1))
	# Başarısızlık dalı: devre dışı (1 birimde biter), görev 9'da tamamlanır, gece 10'da biter.
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a", [], [EquipmentFixtures.eff_disable("equipment_c", 1)],
			"", "action_a")
	var system: CableRepairSystemScript = Fixtures.make_system(world, [puzzle], [task])
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	assert_true(system.start_session(&"puzzle_a").is_started())
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq([world.state.get_elapsed_units(), world.state.is_night_ended(), world.state.get_resource(&"res_b")],
			[8, false, 0])
	assert_eq(world.state.get_tasks_snapshot().size(), 1)
	assert_eq(signals[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_preplanning_uses_no_resolution() -> void:
	var world: DecisionFixtures.World = _started_world()
	var blocked: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [], [DecisionFixtures.eff_spend("res_a", 9)])])
	var open: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	for i in 3:
		assert_eq(blocked.start_session(&"puzzle_a").failure, &"outcome_unavailable")
		assert_true(open.start_session(&"puzzle_a").is_started())
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 0, false]])


# --- Sahiplik ---

func test_session_created_directly_is_foreign() -> void:
	var world: DecisionFixtures.World = _started_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_add("res_b", 1)])
	var system: CableRepairSystemScript = Fixtures.make_system(world, [puzzle])
	var session: CablePuzzleSessionScript = CablePuzzleSessionScript.create(puzzle)
	Fixtures.solve(session)
	_assert_rejected_without_change(world, system, session, &"foreign_session", "bu sistemin açmadığı oturum")


func test_session_of_another_system_is_foreign() -> void:
	var world: DecisionFixtures.World = _started_world()
	var first: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var second: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = first.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	_assert_rejected_without_change(world, second, session, &"foreign_session", "bu sistemin açmadığı oturum")


func test_recreated_system_rejects_sessions_of_the_old_one() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	system = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	_assert_rejected_without_change(world, system, session, &"foreign_session", "bu sistemin açmadığı oturum")


func test_null_session_is_foreign() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	_assert_rejected_without_change(world, system, null, &"foreign_session", "bu sistemin açmadığı oturum")


func test_unfinished_session_is_a_flow_error() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	session.connect_terminals(Fixtures.A, Fixtures.B)
	_assert_rejected_without_change(world, system, session, &"session_not_finished", "oturum henüz bitmedi")


func test_applied_session_cannot_be_applied_again() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(session)
	assert_true(system.apply_result(session).ok)
	_assert_rejected_without_change(world, system, session, &"already_applied", "zaten uygulandı")
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, false]])


func test_second_session_of_the_same_version_is_stale() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_add("res_b", 1)], [DecisionFixtures.eff_add("res_b", 2)])])
	var first: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	var second: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.fail(first)
	Fixtures.solve(second)
	assert_true(system.apply_result(first).ok)
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	for result: CableRepairResultScript in [system.preview_result(second), system.apply_result(second)]:
		assert_eq([result.ok, result.failure, result.puzzle_id, result.outcome],
				[false, &"stale_session", &"puzzle_a", &"solved"])
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, false]])
	assert_eq(world.state.get_resource(&"res_b"), 2)
	assert_eq(signals[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_start_conditions_are_not_reevaluated_when_applying() -> void:
	var world: DecisionFixtures.World = _started_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle()
	puzzle.start_conditions.append(DecisionFixtures.cond_flag("flag_a", true))
	world.state.set_flag(&"flag_a", true)
	var system: CableRepairSystemScript = Fixtures.make_system(world, [puzzle])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	world.state.set_flag(&"flag_a", false)
	Fixtures.solve(session)
	assert_true(system.apply_result(session).ok)
	assert_eq(Fixtures.progress_rows(world.state), [["puzzle_a", 1, true]])


func test_dead_session_records_are_pruned_on_new_starts() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle()])
	for i in 3:
		_start_and_drop(system)
	var kept: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	assert_eq((system.get("_records") as Array).size(), 1)
	Fixtures.solve(kept)
	assert_true(system.apply_result(kept).ok)


# --- Yardımcılar ---

func _started_world() -> DecisionFixtures.World:
	var world: DecisionFixtures.World = Fixtures.make_world()
	Fixtures.start(world)
	return world


func _count_signals(state: GameStateScript) -> Array:
	var counter: Array = [0]
	state.state_changed.connect(func() -> void: counter[0] += 1)
	return counter


func _start_and_drop(system: CableRepairSystemScript) -> void:
	assert_true(system.start_session(&"puzzle_a").is_started())


func _assert_one_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.size() == 1 and errors[0].contains(text), "%s | %s" % [text, " | ".join(errors)])


func _assert_outcome_unavailable(world: DecisionFixtures.World, puzzle: CablePuzzleDataScript) -> void:
	var system: CableRepairSystemScript = Fixtures.make_system(world, [puzzle])
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	var result: CablePuzzleStartResultScript = system.start_session(&"puzzle_a")
	assert_eq([result.is_started(), result.failure, result.failed_condition_indexes, result.session],
			[false, &"outcome_unavailable", PackedInt32Array(), null])
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(signals[0], 0)
	assert_eq(take_engine_errors().size(), 0)


# Önizleme ve uygulama aynı akış hatasıyla, çağrı başına tek motor hatasıyla reddedilir; hiçbir şey değişmez.
func _assert_rejected_without_change(world: DecisionFixtures.World, system: CableRepairSystemScript,
		session: CablePuzzleSessionScript, failure: StringName, error_text: String) -> void:
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = _count_signals(world.state)
	var preview: CableRepairResultScript = system.preview_result(session)
	_assert_one_error(error_text)
	var applied: CableRepairResultScript = system.apply_result(session)
	_assert_one_error(error_text)
	for result in [preview, applied]:
		assert_eq([result.ok, result.failure, result.effect_outcomes.size(), result.applied_units], [false, failure, 0, 0])
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(signals[0], 0)
