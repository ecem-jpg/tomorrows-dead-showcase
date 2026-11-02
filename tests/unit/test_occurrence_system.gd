extends "res://tests/framework/test_case.gd"
## OccurrenceSystem, görünüm durumu yazma kuralları ve atomik bütünleşme testleri (K-029).
## Yalnızca tarafsız kimlikler kullanılır (K-018). Dünya: res_a = 5, res_b = 0; güven actor_a→actor_b 60,
## actor_b→actor_a 30; 2 gece × 10 birim, action_a = 2. Varsayılan katalog için bkz. occurrence_fixtures.

const Fixtures := preload("res://tests/fixtures/occurrence_fixtures.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const SubjectDataScript := preload("res://scripts/data/subject_data.gd")
const OccurrenceDataScript := preload("res://scripts/data/occurrence_data.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")
const NightStartResultScript := preload("res://scripts/systems/night_start_result.gd")
const BodyViewScript := preload("res://scripts/systems/body_view.gd")

const INACTIVE: StringName = OccurrenceStatusScript.STATUS_INACTIVE
const PENDING: StringName = OccurrenceStatusScript.STATUS_PENDING
const PREVENTED: StringName = OccurrenceStatusScript.STATUS_DEATH_PREVENTED
const PERMANENT: StringName = OccurrenceStatusScript.STATUS_DEATH_PERMANENT
const FIXTURE_DIR: String = "res://tests/fixtures/occurrences"


class Ctx:
	var world: DecisionFixtures.World
	var system: OccurrenceSystemScript
	var clock: TaskCompletionSystemScript


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var system: OccurrenceSystemScript = Fixtures.make_default_system(Fixtures.make_world())
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_true(system.has_occurrence(&"occurrence_b"))
	assert_false(system.has_occurrence(&"missing_id"))


func test_fixture_files_build_a_valid_system() -> void:
	var subject: SubjectDataScript = ResourceLoader.load(FIXTURE_DIR + "/subject_a.tres") as SubjectDataScript
	var first: OccurrenceDataScript = ResourceLoader.load(FIXTURE_DIR + "/occurrence_a.tres") as OccurrenceDataScript
	var second: OccurrenceDataScript = ResourceLoader.load(FIXTURE_DIR + "/occurrence_b.tres") as OccurrenceDataScript
	var world: DecisionFixtures.World = Fixtures.make_world(["occurrence_a", "occurrence_b"])
	assert_eq(Fixtures.make_system(world, [subject], [first, second]).get_configuration_errors(), PackedStringArray())


func test_subject_errors_are_reported_in_order() -> void:
	var subjects: Array = [null, Fixtures.make_subject(""), Fixtures.make_subject("subject_a"), Fixtures.make_subject("subject_a")]
	var system: OccurrenceSystemScript = Fixtures.make_system(Fixtures.make_world([]), subjects, [])
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız kişi kaydı (#0)",
		"Boş kişi kimliği (#1)",
		"Tekrarlanan kişi kimliği: 'subject_a'",
	]))


func test_occurrence_errors_are_reported_in_order() -> void:
	var occurrences: Array = [
		null,
		Fixtures.make_occurrence("", "subject_b", 1),
		Fixtures.make_occurrence("occurrence_x", "", 0),
		Fixtures.make_occurrence("occurrence_y", "subject_z", 3),
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_a", "subject_a", 2),
	]
	var world: DecisionFixtures.World = Fixtures.make_world(["occurrence_x", "occurrence_y", "occurrence_a"])
	var system: OccurrenceSystemScript = Fixtures.make_system(world, Fixtures.default_subjects(), occurrences)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız görünüm kaydı (#0)",
		"Boş görünüm kimliği (#1)",
		"'occurrence_x': eksik alan 'subject_id'",
		"'occurrence_x': gece aralık dışında (0, 1..2)",
		"'occurrence_y': tanımsız kişi 'subject_z'",
		"'occurrence_y': gece aralık dışında (3, 1..2)",
		"Tekrarlanan görünüm kimliği: 'occurrence_a'",
	]))
	assert_eq(take_engine_errors().size(), 0)


func test_same_subject_cannot_have_two_occurrences_on_one_night() -> void:
	var occurrences: Array = [
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_b", "subject_a", 1),
	]
	var system: OccurrenceSystemScript = Fixtures.make_system(Fixtures.make_world(["occurrence_a", "occurrence_b"]),
			Fixtures.default_subjects(), occurrences)
	assert_eq(system.get_configuration_errors(),
			PackedStringArray(["'occurrence_b': aynı kişinin aynı gecede ikinci görünümü ('occurrence_a' ile)"]))


func test_arrival_condition_errors_use_shared_messages() -> void:
	var conditions: Array = [
		null,
		Fixtures.cond_occurrence("missing_id", PENDING),
		Fixtures.cond_occurrence("occurrence_a", &"lost"),
		DecisionFixtures.make_condition(&"occurrence", {"occurrence_id": "occurrence_a"}),
	]
	var occurrences: Array = [
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_b", "subject_a", 2, conditions),
	]
	var system: OccurrenceSystemScript = Fixtures.make_system(Fixtures.make_world(["occurrence_a", "occurrence_b"]),
			Fixtures.default_subjects(), occurrences)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"'occurrence_b' varış koşulu #0: tanımsız kayıt",
		"'occurrence_b' varış koşulu #1: tanımsız görünüm 'missing_id'",
		"'occurrence_b' varış koşulu #2: tanımsız görünüm durumu 'lost'",
		"'occurrence_b' varış koşulu #3: eksik alan 'occurrence_status'",
	]))


func test_catalog_and_initial_state_ids_must_match() -> void:
	var occurrences: Array = [
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_b", "subject_a", 2),
	]
	var system: OccurrenceSystemScript = Fixtures.make_system(Fixtures.make_world(["occurrence_a", "occurrence_z"]),
			Fixtures.default_subjects(), occurrences)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Başlangıç durumunda görünüm yok: 'occurrence_b'",
		"Katalogda tanımsız görünüm: 'occurrence_z'",
	]))


func test_trust_errors_are_included() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	world.state.set_trust_state(partial)
	var errors: PackedStringArray = Fixtures.make_default_system(world).get_configuration_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].begins_with("TrustSystem: "), " | ".join(errors))


func test_future_night_occurrence_cannot_be_active_in_state() -> void:
	var ctx: Ctx = _default_ctx()
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.occurrence_statuses[&"occurrence_b"] = PENDING
	assert_true(ctx.world.state.apply_changes(change))
	assert_eq(ctx.system.get_configuration_errors(), PackedStringArray(["Gelecek gecenin görünümü etkin: 'occurrence_b' (gece 2)"]))


func test_configuration_errors_are_deterministic() -> void:
	var build: Callable = func() -> PackedStringArray:
		var occurrences: Array = [null, Fixtures.make_occurrence("occurrence_a", "subject_z", 5, [null]),
				Fixtures.make_occurrence("occurrence_b", "subject_a", 1)]
		return Fixtures.make_system(Fixtures.make_world(["occurrence_a", "occurrence_c"]), Fixtures.default_subjects(),
				occurrences).get_configuration_errors()
	var first: PackedStringArray = build.call()
	assert_eq(first, build.call())
	assert_eq(first.size(), 6, " | ".join(first))


func test_catalog_is_copied_on_creation() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var subjects: Array = Fixtures.default_subjects()
	var occurrences: Array = Fixtures.default_occurrences()
	var system: OccurrenceSystemScript = Fixtures.make_system(world, subjects, occurrences)
	subjects[0].id = "subject_z"
	occurrences[0].night = 2
	occurrences[1].arrival_conditions.clear()
	occurrences.append(null)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	world.trust.initialize_relationships()
	assert_eq(system.start_night().arrived_ids, [&"occurrence_a", &"occurrence_c"] as Array[StringName])


# --- Gece başlangıcı ve varış ---

func test_start_night_activates_first_night_occurrences_in_one_write() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	world.trust.initialize_relationships()
	var system: OccurrenceSystemScript = Fixtures.make_default_system(world)
	var calls: Array[int] = _count_signals(world.state)
	var result: NightStartResultScript = system.start_night()
	assert_true(result.ok)
	assert_eq([result.failure, result.night], [&"", 1])
	assert_eq(result.arrived_ids, [&"occurrence_a", &"occurrence_c"] as Array[StringName])
	assert_eq(result.internal_skip_reasons.size(), 0)
	assert_eq(_statuses(world.state), [PENDING, INACTIVE, PENDING])
	assert_eq([world.state.get_night(), world.state.get_elapsed_units(), world.state.is_night_ended()], [1, 0, false])
	assert_eq(calls[0], 1)
	assert_eq(take_engine_errors().size(), 0)


func test_unmet_arrival_conditions_keep_the_occurrence_inactive() -> void:
	var ctx: Ctx = _custom_ctx([Fixtures.make_occurrence("occurrence_x", "subject_a", 1, [DecisionFixtures.cond_flag("flag_a", true)])],
			["occurrence_x"], false)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_true(result.ok)
	assert_eq(result.arrived_ids.size(), 0)
	assert_eq(_reasons(result), [["occurrence_x", NightStartResultScript.SKIP_CONDITIONS_NOT_MET]])
	assert_eq(ctx.system.get_status(&"occurrence_x"), INACTIVE)
	assert_eq(take_engine_errors().size(), 0)


func test_missed_night_is_never_retried() -> void:
	var ctx: Ctx = _custom_ctx([Fixtures.make_occurrence("occurrence_x", "subject_a", 1, [DecisionFixtures.cond_flag("flag_a", true)])],
			["occurrence_x"])
	assert_eq(ctx.system.get_status(&"occurrence_x"), INACTIVE)
	ctx.world.state.set_flag(&"flag_a", true)
	_end_night(ctx)
	var second: NightStartResultScript = ctx.system.start_night()
	assert_eq([second.night, second.arrived_ids.size(), second.internal_skip_reasons.size()], [2, 0, 0])
	assert_eq(ctx.system.get_status(&"occurrence_x"), INACTIVE)


func test_pending_occurrence_blocks_the_next_one_as_subject_busy() -> void:
	var ctx: Ctx = _custom_ctx([
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_b", "subject_a", 2),
	], ["occurrence_a", "occurrence_b"])
	# Düşük seviyeli TimeSystem.advance gece sonu kesinleşmesi yapmaz; occurrence_a pending kalır.
	ctx.world.time.advance(10)
	assert_eq(ctx.system.get_status(&"occurrence_a"), PENDING)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_eq(_reasons(result), [["occurrence_b", NightStartResultScript.SKIP_SUBJECT_BUSY]])
	assert_eq(ctx.system.get_status(&"occurrence_b"), INACTIVE)
	assert_eq(take_engine_errors().size(), 0)


func test_permanent_death_blocks_later_occurrences_as_subject_dead() -> void:
	var ctx: Ctx = _custom_ctx([
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_b", "subject_a", 2),
	], ["occurrence_a", "occurrence_b"])
	_end_night(ctx)
	assert_eq(ctx.system.get_status(&"occurrence_a"), PERMANENT)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_true(result.ok)
	assert_eq(_reasons(result), [["occurrence_b", NightStartResultScript.SKIP_SUBJECT_DEAD]])
	assert_eq(ctx.system.get_status(&"occurrence_b"), INACTIVE)
	assert_eq(take_engine_errors().size(), 0)


func test_prevented_subject_can_start_a_separate_occurrence_whose_conditions_hold() -> void:
	var ctx: Ctx = _default_ctx()
	assert_true(_prevent_by_choice(ctx, "occurrence_a").ok)
	_end_night(ctx)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_eq(result.arrived_ids, [&"occurrence_b"] as Array[StringName])
	assert_eq(_statuses(ctx.world.state), [PREVENTED, PENDING, PERMANENT])


func test_prevented_occurrence_does_not_start_the_next_one_by_itself() -> void:
	var ctx: Ctx = _default_ctx()
	_prevent_by_choice(ctx, "occurrence_a")
	assert_eq(ctx.system.get_status(&"occurrence_b"), INACTIVE)
	ctx.world.state.set_flag(&"condition_a", true)
	_end_night(ctx)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_eq(_reasons(result), [["occurrence_b", NightStartResultScript.SKIP_CONDITIONS_NOT_MET]])
	assert_eq(ctx.system.get_status(&"occurrence_b"), INACTIVE)


func test_night_flow_errors_change_nothing() -> void:
	var ctx: Ctx = _default_ctx()
	var calls: Array[int] = _count_signals(ctx.world.state)
	assert_eq(ctx.system.start_night().failure, NightStartResultScript.FAILURE_NIGHT_ALREADY_ACTIVE)
	_assert_one_engine_error("gece sürerken")
	assert_eq(calls[0], 0)
	_end_night(ctx)
	ctx.system.start_night()
	_end_night(ctx)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_eq([result.ok, result.failure, result.night], [false, NightStartResultScript.FAILURE_NO_NEXT_NIGHT, 0])
	_assert_one_engine_error("son gece bitti")


func test_trust_arrival_condition_before_initialization_is_system_not_ready() -> void:
	var ctx: Ctx = _custom_ctx([Fixtures.make_occurrence("occurrence_x", "subject_a", 1,
			[DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 10)])], ["occurrence_x"], false, false)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_eq(result.failure, NightStartResultScript.FAILURE_SYSTEM_NOT_READY)
	_assert_one_engine_error("güven başlatılmadı")
	assert_eq(ctx.world.state.get_night(), 0)
	assert_eq(ctx.system.get_status(&"occurrence_x"), INACTIVE)


func test_subject_dead_is_checked_before_trust_readiness() -> void:
	# Güven başlatılmadı; sonraki görünümün güven koşulu hiç değerlendirilmeden subject_dead ile atlanmalı.
	var ctx: Ctx = _custom_ctx(_trust_conditioned_pair(), ["occurrence_a", "occurrence_b"], true, false)
	_end_night(ctx)
	assert_eq(ctx.system.get_status(&"occurrence_a"), PERMANENT)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_true(result.ok)
	assert_eq([result.failure, result.night, result.arrived_ids.size()], [&"", 2, 0])
	assert_eq(_reasons(result), [["occurrence_b", NightStartResultScript.SKIP_SUBJECT_DEAD]])
	assert_eq(ctx.system.get_status(&"occurrence_b"), INACTIVE)
	assert_false(ctx.world.trust.is_initialized())
	assert_eq(take_engine_errors().size(), 0)


func test_subject_busy_is_checked_before_trust_readiness() -> void:
	# Güven başlatılmadı; düşük seviyeli advance occurrence_a'yı pending bırakır. Sonraki görünümün güven koşulu
	# hiç değerlendirilmeden subject_busy ile atlanmalı.
	var ctx: Ctx = _custom_ctx(_trust_conditioned_pair(), ["occurrence_a", "occurrence_b"], true, false)
	ctx.world.time.advance(10)
	assert_eq(ctx.system.get_status(&"occurrence_a"), PENDING)
	var result: NightStartResultScript = ctx.system.start_night()
	assert_true(result.ok)
	assert_eq([result.failure, result.night, result.arrived_ids.size()], [&"", 2, 0])
	assert_eq(_reasons(result), [["occurrence_b", NightStartResultScript.SKIP_SUBJECT_BUSY]])
	assert_eq(ctx.system.get_status(&"occurrence_b"), INACTIVE)
	assert_false(ctx.world.trust.is_initialized())
	assert_eq(take_engine_errors().size(), 0)


func test_preview_has_no_side_effects_and_matches_start() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	world.trust.initialize_relationships()
	var system: OccurrenceSystemScript = Fixtures.make_default_system(world)
	var calls: Array[int] = _count_signals(world.state)
	var preview: NightStartResultScript = system.preview_start_night()
	assert_eq([world.state.get_night(), calls[0]], [0, 0])
	assert_eq(_statuses(world.state), [INACTIVE, INACTIVE, INACTIVE])
	assert_eq(_describe_start(system.start_night()), _describe_start(preview))


func test_failed_night_start_write_changes_nothing() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = Fixtures.make_world([], state)
	world.trust.initialize_relationships()
	var system: OccurrenceSystemScript = Fixtures.make_default_system(world)
	var before: Array = _snapshot(state)
	var calls: Array[int] = _count_signals(state)
	state.reject_changes = true
	var result: NightStartResultScript = system.start_night()
	assert_eq(result.failure, NightStartResultScript.FAILURE_WRITE_FAILED)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_true(errors.size() == 2 and errors[1].contains("gece başlatılmadı"), " | ".join(errors))
	assert_eq(_snapshot(state), before)
	assert_eq(calls[0], 0)


func test_start_night_uses_exactly_one_write() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = Fixtures.make_world([], state)
	world.trust.initialize_relationships()
	var system: OccurrenceSystemScript = Fixtures.make_default_system(world)
	state.apply_calls = 0
	state.other_writes = 0
	system.preview_start_night()
	assert_true(system.start_night().ok)
	assert_eq([state.apply_calls, state.other_writes], [1, 0])


func test_same_start_and_same_actions_produce_same_results() -> void:
	assert_eq(_run_reference_sequence(), _run_reference_sequence())


# --- Gece sonu kesinleşmesi ---

func test_night_end_makes_pending_occurrences_permanent_in_the_same_write() -> void:
	var ctx: Ctx = _default_ctx()
	var calls: Array[int] = _count_signals(ctx.world.state)
	var result: TimeProgressResultScript = ctx.clock.advance(10)
	assert_true(result.ok and result.time_result.night_ended())
	assert_eq(result.permanent_occurrence_ids, [&"occurrence_a", &"occurrence_c"] as Array[StringName])
	assert_eq(_statuses(ctx.world.state), [PERMANENT, INACTIVE, PERMANENT])
	assert_true(ctx.world.state.is_night_ended())
	assert_eq(calls[0], 1)


func test_advance_without_night_end_does_not_finalize() -> void:
	var ctx: Ctx = _default_ctx()
	var result: TimeProgressResultScript = ctx.clock.advance(9)
	assert_eq(result.permanent_occurrence_ids.size(), 0)
	assert_eq(_statuses(ctx.world.state), [PENDING, INACTIVE, PENDING])


func test_boundary_task_prevention_is_applied_before_finalization() -> void:
	var ctx: Ctx = _default_ctx([DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_prevent("occurrence_a")])])
	ctx.world.time.start_task(&"task_a", &"actor_b", 10)
	var result: TimeProgressResultScript = ctx.clock.advance(10)
	assert_eq(result.completions[0].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	assert_eq(result.permanent_occurrence_ids, [&"occurrence_c"] as Array[StringName])
	assert_eq(_statuses(ctx.world.state), [PREVENTED, INACTIVE, PERMANENT])


func test_boundary_choice_prevention_is_applied_before_finalization() -> void:
	var ctx: Ctx = _default_ctx()
	ctx.clock.advance(8)
	var result: DecisionResultScript = _prevent_by_choice(ctx, "occurrence_a", "action_a")
	assert_true(result.ok)
	assert_true(ctx.world.state.is_night_ended())
	assert_eq(_statuses(ctx.world.state), [PREVENTED, INACTIVE, PERMANENT])


# --- Etkiler ve atomik yazma ---

func test_choice_prevents_death_with_other_effects_in_one_write() -> void:
	var ctx: Ctx = _default_ctx()
	var calls: Array[int] = _count_signals(ctx.world.state)
	var system: DecisionSystemScript = _decisions(ctx, [DecisionFixtures.eff_spend("res_a", 2),
			DecisionFixtures.eff_flag("flag_a", true), Fixtures.eff_prevent("occurrence_a")], "action_a")
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_true(result.ok)
	assert_eq([result.effect_outcomes[2].occurrence_id, result.effect_outcomes[2].previous_occurrence_status,
			result.effect_outcomes[2].occurrence_status], [&"occurrence_a", PENDING, PREVENTED])
	assert_eq([ctx.world.state.get_resource(&"res_a"), ctx.world.state.get_flag(&"flag_a"), ctx.world.state.get_elapsed_units()],
			[3, true, 2])
	assert_eq(ctx.system.get_status(&"occurrence_a"), PREVENTED)
	assert_eq(calls[0], 1)


func test_resolution_of_a_non_pending_occurrence_is_not_applicable() -> void:
	var ctx: Ctx = _default_ctx()
	var calls: Array[int] = _count_signals(ctx.world.state)
	for occurrence_id in ["occurrence_b"]:
		var system: DecisionSystemScript = _decisions(ctx, [DecisionFixtures.eff_add("res_b", 1), Fixtures.eff_prevent(occurrence_id)])
		var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
		assert_eq([result.failure, result.blocking_effect_index], [DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE, 1])
	_prevent_by_choice(ctx, "occurrence_a")
	var again: DecisionSystemScript = _decisions(ctx, [Fixtures.eff_permanent("occurrence_a")])
	assert_eq(again.choose(&"decision_a", &"choice_a").failure, DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE)
	assert_eq(ctx.world.state.get_resource(&"res_b"), 0)
	assert_eq(_statuses(ctx.world.state), [PREVENTED, INACTIVE, PENDING])
	assert_eq(calls[0], 1)
	assert_eq(take_engine_errors().size(), 0)


func test_two_effects_on_one_occurrence_are_a_configuration_error() -> void:
	var ctx: Ctx = _default_ctx()
	var system: DecisionSystemScript = _decisions(ctx, [Fixtures.eff_prevent("occurrence_a"), Fixtures.eff_permanent("occurrence_a")])
	assert_eq(system.get_configuration_errors(),
			PackedStringArray(["'decision_a' / 'choice_a' etki #1: aynı hedefe birden fazla etki (#0 ile)"]))


func test_failed_choice_write_changes_no_category_including_occurrences() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_setup())
	var ctx: Ctx = _default_ctx([], state)
	var system: DecisionSystemScript = _decisions(ctx, [DecisionFixtures.eff_spend("res_a", 2),
			DecisionFixtures.eff_trust("actor_a", "actor_b", 5), DecisionFixtures.eff_flag("flag_a", true),
			Fixtures.eff_prevent("occurrence_a")], "action_a")
	var before: Array = _snapshot(state)
	var calls: Array[int] = _count_signals(state)
	state.reject_changes = true
	assert_eq(system.choose(&"decision_a", &"choice_a").failure, DecisionResultScript.FAILURE_WRITE_FAILED)
	assert_eq(take_engine_errors().size(), 2)
	assert_eq(_snapshot(state), before)
	assert_eq(calls[0], 0)


func test_task_completion_prevents_death() -> void:
	var ctx: Ctx = _default_ctx([DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_prevent("occurrence_c")])])
	ctx.world.time.start_task(&"task_a", &"actor_b", 2)
	var result: TimeProgressResultScript = ctx.clock.advance(2)
	assert_eq(result.completions[0].effect_outcomes[0].occurrence_status, PREVENTED)
	assert_eq(_statuses(ctx.world.state), [PENDING, INACTIVE, PREVENTED])


func test_second_task_on_the_same_occurrence_is_not_applicable() -> void:
	var ctx: Ctx = _default_ctx([
		DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_prevent("occurrence_a")]),
		DecisionFixtures.make_task_definition("task_b", [DecisionFixtures.eff_add("res_a", 1), Fixtures.eff_permanent("occurrence_a")]),
	])
	ctx.world.time.start_task(&"task_a", &"actor_b", 1)
	ctx.world.time.start_task(&"task_b", &"actor_c", 2)
	var result: TimeProgressResultScript = ctx.clock.advance(2)
	assert_eq(result.completions[0].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	assert_eq([result.completions[1].status, result.completions[1].blocking_effect_index],
			[TaskCompletionOutcomeScript.STATUS_EFFECTS_NOT_APPLICABLE, 1])
	assert_eq(ctx.world.state.get_resource(&"res_a"), 5)
	assert_eq(ctx.system.get_status(&"occurrence_a"), PREVENTED)
	assert_eq(take_engine_errors().size(), 0)


func test_failed_night_end_write_changes_nothing() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_setup())
	var ctx: Ctx = _default_ctx([DecisionFixtures.make_task_definition("task_a",
			[Fixtures.eff_prevent("occurrence_a"), DecisionFixtures.eff_add("res_a", 2)])], state)
	ctx.world.time.start_task(&"task_a", &"actor_b", 10)
	var before: Array = _snapshot(state)
	var calls: Array[int] = _count_signals(state)
	state.reject_changes = true
	assert_eq(ctx.clock.advance(10).failure, TimeProgressResultScript.FAILURE_WRITE_FAILED)
	assert_eq(take_engine_errors().size(), 2)
	assert_eq(_snapshot(state), before)
	assert_eq(calls[0], 0)


# --- GameState yazma kuralları ---

func test_initial_state_creates_every_occurrence_as_inactive() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup())
	assert_eq(state.get_occurrences_snapshot().size(), 3)
	assert_eq(_statuses(state), [INACTIVE, INACTIVE, INACTIVE])
	assert_true(state.has_occurrence(&"occurrence_a"))
	assert_false(state.has_occurrence(&"missing_id"))


func test_empty_or_duplicate_initial_occurrence_ids_are_rejected() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(["occurrence_a", "", "occurrence_a"]))
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_eq(state.get_occurrences_snapshot().size(), 1)


func test_apply_changes_rejects_invalid_transitions_without_partial_writes() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup())
	var calls: Array[int] = _count_signals(state)
	var invalid_steps: Array = [[&"occurrence_a", PREVENTED], [&"occurrence_a", &"lost"], [&"missing_id", PENDING]]
	for step in invalid_steps:
		assert_false(_write(state, step[0], step[1], 9), str(step))
		assert_eq(take_engine_errors().size(), 1, str(step))
	assert_true(_write(state, &"occurrence_a", PENDING, 9))
	assert_false(_write(state, &"occurrence_a", INACTIVE, 8))
	assert_true(_write(state, &"occurrence_a", PREVENTED, 7))
	for final_target in [PERMANENT, PENDING, INACTIVE]:
		assert_false(_write(state, &"occurrence_a", final_target, 1), str(final_target))
	assert_eq(take_engine_errors().size(), 4)
	assert_eq([state.get_occurrence_status(&"occurrence_a"), state.get_resource(&"res_a")], [PREVENTED, 7])
	assert_eq(calls[0], 2)


func test_rewriting_the_same_status_is_a_silent_noop() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup())
	var calls: Array[int] = _count_signals(state)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.occurrence_statuses[&"occurrence_a"] = INACTIVE
	assert_true(state.apply_changes(change))
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_occurrences_have_no_direct_setter_and_snapshots_are_copies() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup())
	assert_false(state.has_method("set_occurrence_status"))
	var snapshot: Dictionary[StringName, StringName] = state.get_occurrences_snapshot()
	snapshot[&"occurrence_a"] = PREVENTED
	assert_eq(state.get_occurrence_status(&"occurrence_a"), INACTIVE)


# --- Arayüz görünümü ---

func test_visible_bodies_hide_prevented_and_future_occurrences() -> void:
	var occurrences: Array = [
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_c", "subject_b", 1),
		Fixtures.make_occurrence("occurrence_d", "subject_c", 2),
	]
	var ctx: Ctx = _custom_ctx(occurrences, ["occurrence_a", "occurrence_c", "occurrence_d"], false)
	assert_eq(_describe_bodies(ctx.system.get_visible_bodies()), [])
	ctx.system.start_night()
	assert_eq(_describe_bodies(ctx.system.get_visible_bodies()), [["occurrence_a", 1, &"present"], ["occurrence_c", 1, &"present"]])
	_prevent_by_choice(ctx, "occurrence_c")
	_end_night(ctx)
	assert_eq(_describe_bodies(ctx.system.get_visible_bodies()), [["occurrence_a", 1, &"permanent"]])
	ctx.system.start_night()
	assert_eq(_describe_bodies(ctx.system.get_visible_bodies()), [["occurrence_a", 1, &"permanent"], ["occurrence_d", 2, &"present"]])
	assert_eq(ctx.system.get_status(&"occurrence_c"), PREVENTED)


func test_visible_bodies_are_ordered_by_night_then_id() -> void:
	var occurrences: Array = [
		Fixtures.make_occurrence("occurrence_c", "subject_c", 2),
		Fixtures.make_occurrence("occurrence_b", "subject_b", 1),
		Fixtures.make_occurrence("occurrence_a", "subject_a", 2),
		Fixtures.make_occurrence("occurrence_d", "subject_d", 1),
	]
	var ctx: Ctx = _custom_ctx(occurrences, ["occurrence_a", "occurrence_b", "occurrence_c", "occurrence_d"])
	_end_night(ctx)
	ctx.system.start_night()
	assert_eq(_describe_bodies(ctx.system.get_visible_bodies()), [["occurrence_b", 1, &"permanent"],
			["occurrence_d", 1, &"permanent"], ["occurrence_a", 2, &"present"], ["occurrence_c", 2, &"present"]])


func test_body_view_exposes_no_internal_fields() -> void:
	var names: Array[String] = []
	for property in BodyViewScript.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["occurrence_id", "subject_id", "night", "presence"] as Array[String])


func test_mutating_body_views_does_not_affect_state() -> void:
	var ctx: Ctx = _default_ctx()
	var bodies: Array[BodyViewScript] = ctx.system.get_visible_bodies()
	bodies[0].presence = BodyViewScript.PRESENCE_PERMANENT
	bodies.clear()
	assert_eq(ctx.system.get_visible_bodies().size(), 2)
	assert_eq(ctx.system.get_status(&"occurrence_a"), PENDING)


# --- Uçtan uca senaryo ---

func test_scenario_branch_prevented_with_unresolved_condition_brings_the_next_occurrence() -> void:
	var first: Array = _run_branch(&"prevent")
	assert_eq(first, _run_branch(&"prevent"))
	assert_eq(first[-1], [PREVENTED, PENDING, PERMANENT])


func test_scenario_branch_without_intervention_makes_death_permanent() -> void:
	var first: Array = _run_branch(&"ignore")
	assert_eq(first, _run_branch(&"ignore"))
	assert_eq(first[-1], [PERMANENT, INACTIVE, PERMANENT])


func test_scenario_branch_resolved_condition_keeps_the_next_occurrence_away() -> void:
	var first: Array = _run_branch(&"resolve")
	assert_eq(first, _run_branch(&"resolve"))
	assert_eq(first[-1], [PREVENTED, INACTIVE, PERMANENT])


# --- Yardımcılar ---

# prevent: occurrence_a engellenir, neden çözülmez → occurrence_b gece 2'de gelir.
# ignore: müdahale yok → occurrence_a gece sonunda kalıcı; occurrence_b gelmez.
# resolve: occurrence_a engellenir ve condition_a çözülür → occurrence_b gelmez.
func _run_branch(branch: StringName) -> Array:
	var ctx: Ctx = _default_ctx()
	var observed: Array = [_statuses(ctx.world.state), _describe_bodies(ctx.system.get_visible_bodies())]
	assert_eq(observed[0], [PENDING, INACTIVE, PENDING])
	if branch != &"ignore":
		var result: DecisionResultScript = _prevent_by_choice(ctx, "occurrence_a", "", [DecisionFixtures.eff_add("res_b", 1)])
		assert_true(result.ok)
		assert_eq(ctx.world.state.get_resource(&"res_b"), 1)
	if branch == &"resolve":
		ctx.world.state.set_flag(&"condition_a", true)
	var night_end: TimeProgressResultScript = ctx.clock.advance(10)
	observed.append(night_end.permanent_occurrence_ids)
	var second: NightStartResultScript = ctx.system.start_night()
	observed.append(_describe_start(second))
	observed.append(_describe_bodies(ctx.system.get_visible_bodies()))
	observed.append(_snapshot(ctx.world.state))
	observed.append(_statuses(ctx.world.state))
	return observed


func _run_reference_sequence() -> Array:
	var ctx: Ctx = _default_ctx([DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_prevent("occurrence_c")])])
	var observed: Array = [_statuses(ctx.world.state)]
	ctx.world.time.start_task(&"task_a", &"actor_b", 3)
	observed.append(_describe_progress(ctx.clock.advance(4)))
	_prevent_by_choice(ctx, "occurrence_a")
	observed.append(_describe_progress(ctx.clock.advance(10)))
	observed.append(_describe_start(ctx.system.start_night()))
	observed.append(_describe_bodies(ctx.system.get_visible_bodies()))
	observed.append(_snapshot(ctx.world.state))
	return observed


## Varsayılan kataloglu, güveni başlatılmış ve ilk gecesi açılmış dünya.
func _default_ctx(task_definitions: Array = [], state: GameStateScript = null) -> Ctx:
	var ctx: Ctx = Ctx.new()
	ctx.world = Fixtures.make_world(Fixtures.DEFAULT_IDS, state)
	ctx.system = Fixtures.make_default_system(ctx.world)
	ctx.clock = DecisionFixtures.make_completion_system(ctx.world, task_definitions)
	Fixtures.start(ctx.world, ctx.system)
	return ctx


## Kişiler subject_a..subject_d; start = true ise ilk gece açılır, initialize_trust = false ise güven başlatılmaz.
func _custom_ctx(occurrences: Array, ids: Array, start: bool = true, initialize_trust: bool = true) -> Ctx:
	var ctx: Ctx = Ctx.new()
	ctx.world = Fixtures.make_world(ids)
	var subjects: Array = [Fixtures.make_subject("subject_a"), Fixtures.make_subject("subject_b"),
			Fixtures.make_subject("subject_c"), Fixtures.make_subject("subject_d")]
	ctx.system = Fixtures.make_system(ctx.world, subjects, occurrences)
	ctx.clock = Fixtures.make_clock(ctx.world)
	if initialize_trust:
		ctx.world.trust.initialize_relationships()
	if start:
		assert_true(ctx.system.start_night().ok)
	return ctx


## occurrence_a (subject_a, gece 1, koşulsuz) ve occurrence_b (subject_a, gece 2, güven koşullu).
func _trust_conditioned_pair() -> Array:
	return [
		Fixtures.make_occurrence("occurrence_a", "subject_a", 1),
		Fixtures.make_occurrence("occurrence_b", "subject_a", 2, [DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 10)]),
	]


func _decisions(ctx: Ctx, effects: Array, action_id: String = "") -> DecisionSystemScript:
	return DecisionFixtures.make_system(ctx.world, [DecisionFixtures.make_decision("decision_a",
			[DecisionFixtures.make_choice("choice_a", [], effects, action_id)])])


func _prevent_by_choice(ctx: Ctx, occurrence_id: String, action_id: String = "", extra_effects: Array = []) -> DecisionResultScript:
	var effects: Array = extra_effects.duplicate()
	effects.append(Fixtures.eff_prevent(occurrence_id))
	return _decisions(ctx, effects, action_id).choose(&"decision_a", &"choice_a")


func _end_night(ctx: Ctx) -> void:
	assert_true(ctx.clock.advance(10 - ctx.world.state.get_elapsed_units()).ok)


func _write(state: GameStateScript, occurrence_id: StringName, status: StringName, res_a: int) -> bool:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.resource_values[&"res_a"] = res_a
	change.occurrence_statuses[occurrence_id] = status
	return state.apply_changes(change)


func _statuses(state: GameStateScript) -> Array:
	var result: Array = []
	for occurrence_id in [&"occurrence_a", &"occurrence_b", &"occurrence_c"]:
		result.append(state.get_occurrence_status(occurrence_id) if state.has_occurrence(occurrence_id) else &"")
	return result


func _describe_bodies(bodies: Array[BodyViewScript]) -> Array:
	var rows: Array = []
	for body in bodies:
		rows.append([String(body.occurrence_id), body.night, body.presence])
	return rows


func _describe_start(result: NightStartResultScript) -> Array:
	return [result.ok, result.failure, result.night, result.arrived_ids, _reasons(result)]


# İç atlanma nedenleri, kimlik sırasıyla [kimlik, neden] satırları.
func _reasons(result: NightStartResultScript) -> Array:
	var ids: Array[String] = []
	for occurrence_id in result.internal_skip_reasons:
		ids.append(String(occurrence_id))
	ids.sort()
	var rows: Array = []
	for occurrence_id in ids:
		rows.append([occurrence_id, result.internal_skip_reasons[StringName(occurrence_id)]])
	return rows


func _describe_progress(result: TimeProgressResultScript) -> Array:
	return [result.ok, result.completed_task_ids(), result.permanent_occurrence_ids]


func _snapshot(state: GameStateScript) -> Array:
	var trust_rows: Array = []
	for entry in state.get_trust_snapshot():
		trust_rows.append([String(entry.source_actor_id), String(entry.target_actor_id), entry.value])
	var task_rows: Array = []
	for task in state.get_tasks_snapshot():
		task_rows.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return [state.get_resources_snapshot(), state.get_flags_snapshot(), trust_rows, state.get_night(),
			state.get_elapsed_units(), state.is_night_ended(), task_rows, state.get_occurrences_snapshot()]


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
