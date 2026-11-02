extends "res://tests/framework/test_case.gd"
## EndingResolver birim testleri (K-030). Yalnızca tarafsız kimlikler kullanılır (K-018).
## Dünya: res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30; 2 gece × 10 birim;
## varsayılan görünüm kataloğu (occurrence_a/occurrence_c gece 1, occurrence_b gece 2). Oyun sonu oyun akışıyla
## kurulur: geceler OccurrenceSystem.start_night, zaman TaskCompletionSystem.advance ile.

const Fixtures := preload("res://tests/fixtures/ending_fixtures.gd")
const OccurrenceFixtures := preload("res://tests/fixtures/occurrence_fixtures.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const EndingDataScript := preload("res://scripts/data/ending_data.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const EndingResolverScript := preload("res://scripts/systems/ending_resolver.gd")
const EndingResultScript := preload("res://scripts/systems/ending_result.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/endings"


class Ctx:
	var world: DecisionFixtures.World
	var occurrences: OccurrenceSystemScript
	var clock: TaskCompletionSystemScript


# --- Oyun sonu ---

func test_game_not_over_before_any_night() -> void:
	var ctx: Ctx = _ctx()
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, _basic_endings())
	assert_false(resolver.is_game_over())
	_assert_game_not_over(resolver.resolve())
	assert_eq(take_engine_errors().size(), 0)


func test_game_not_over_after_an_intermediate_night_or_during_the_final_night() -> void:
	var ctx: Ctx = _ctx()
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, _basic_endings())
	ctx.occurrences.start_night()
	_assert_game_not_over(resolver.resolve())
	_end_night(ctx)
	assert_true(ctx.world.state.is_night_ended())
	assert_false(resolver.is_game_over())
	_assert_game_not_over(resolver.resolve())
	ctx.occurrences.start_night()
	ctx.clock.advance(9)
	assert_eq(ctx.world.state.get_night(), 2)
	assert_false(resolver.is_game_over())
	_assert_game_not_over(resolver.resolve())
	assert_eq(take_engine_errors().size(), 0)


func test_ending_is_resolved_when_the_final_night_ends() -> void:
	var ctx: Ctx = _ctx()
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, _basic_endings())
	_finish_game(ctx)
	assert_true(resolver.is_game_over())
	var result: EndingResultScript = resolver.resolve()
	assert_true(result.is_resolved())
	assert_eq([result.status, result.failure, result.ending_id], [EndingResultScript.STATUS_RESOLVED, &"", &"ending_z"])
	assert_eq(take_engine_errors().size(), 0)


func test_fixture_files_build_a_valid_resolver() -> void:
	var ctx: Ctx = _ctx()
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, [
		ResourceLoader.load(FIXTURE_DIR + "/ending_b.tres"), ResourceLoader.load(FIXTURE_DIR + "/ending_a.tres"),
	])
	assert_eq(resolver.get_configuration_errors(), PackedStringArray())
	assert_true(resolver.has_ending(&"ending_a") and resolver.has_ending(&"ending_b"))
	assert_false(resolver.has_ending(&"missing_id"))
	ctx.world.state.set_flag(&"flag_a", true)
	_finish_game(ctx)
	assert_eq(resolver.resolve().ending_id, &"ending_a")


# --- Seçim ---

func test_single_matching_ending_is_selected() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	ctx.world.state.set_flag(&"flag_a", true)
	assert_eq(Fixtures.make_resolver(ctx.world, _basic_endings()).resolve().ending_id, &"ending_a")


func test_smallest_priority_wins_among_matching_endings() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	ctx.world.state.set_flag(&"flag_a", true)
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, [
		Fixtures.make_ending("ending_b", 2, [DecisionFixtures.cond_flag("flag_a", true)]),
		Fixtures.make_ending("ending_z", 9),
		Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_resource("res_a", &"ge", 1)]),
	])
	assert_eq(resolver.resolve().ending_id, &"ending_a")


func test_input_order_never_changes_the_result() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	ctx.world.state.set_flag(&"flag_a", true)
	var orders: Array = [[0, 1, 2, 3], [3, 2, 1, 0], [2, 0, 3, 1], [1, 3, 0, 2]]
	var observed: Array = []
	for order in orders:
		var endings: Array = _ordered_endings()
		var shuffled: Array = []
		for index in order:
			shuffled.append(endings[index])
		var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, shuffled)
		assert_eq(resolver.get_configuration_errors(), PackedStringArray(), str(order))
		observed.append(resolver.resolve().ending_id)
	assert_eq(observed, [&"ending_b", &"ending_b", &"ending_b", &"ending_b"])


func test_fallback_is_selected_when_no_conditional_ending_matches() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	var result: EndingResultScript = Fixtures.make_resolver(ctx.world, _ordered_endings()).resolve()
	assert_eq([result.status, result.ending_id], [EndingResultScript.STATUS_RESOLVED, &"ending_z"])


func test_resolve_never_returns_an_empty_result_in_normal_flows() -> void:
	var cases: Array = [[false, 5], [true, 5], [false, 0], [true, 0]]
	for case in cases:
		var ctx: Ctx = _ctx()
		_finish_game(ctx)
		ctx.world.state.set_flag(&"flag_a", case[0])
		ctx.world.state.set_resource(&"res_a", case[1])
		var result: EndingResultScript = Fixtures.make_resolver(ctx.world, _ordered_endings()).resolve()
		assert_true(result.is_resolved(), str(case))
		assert_false(result.ending_id.is_empty(), str(case))
		assert_eq(result.failure, &"", str(case))
	assert_eq(take_engine_errors().size(), 0)


# --- Koşul türleri ---

func test_resource_condition() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	var endings: Array = [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_resource("res_a", &"ge", 6)]),
			Fixtures.make_ending("ending_z", 2)]
	assert_eq(Fixtures.make_resolver(ctx.world, endings).resolve().ending_id, &"ending_z")
	ctx.world.state.set_resource(&"res_a", 6)
	assert_eq(Fixtures.make_resolver(ctx.world, endings).resolve().ending_id, &"ending_a")


func test_flag_condition_treats_undefined_flag_as_false() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	var endings: Array = [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_z", false)]),
			Fixtures.make_ending("ending_z", 2)]
	assert_eq(Fixtures.make_resolver(ctx.world, endings).resolve().ending_id, &"ending_a")


func test_trust_condition_is_directional() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	var forward: Array = [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_trust("actor_a", "actor_b", &"ge", 50)]),
			Fixtures.make_ending("ending_z", 2)]
	var backward: Array = [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 50)]),
			Fixtures.make_ending("ending_z", 2)]
	assert_eq(Fixtures.make_resolver(ctx.world, forward).resolve().ending_id, &"ending_a")
	assert_eq(Fixtures.make_resolver(ctx.world, backward).resolve().ending_id, &"ending_z")


func test_occurrence_status_condition() -> void:
	var ctx: Ctx = _ctx()
	ctx.occurrences.start_night()
	var prevent: Object = DecisionFixtures.make_system(ctx.world, [DecisionFixtures.make_decision("decision_a",
			[DecisionFixtures.make_choice("choice_a", [], [OccurrenceFixtures.eff_prevent("occurrence_a")])])])
	assert_true(prevent.choose(&"decision_a", &"choice_a").ok)
	_finish_game(ctx)
	var endings: Array = [
		Fixtures.make_ending("ending_a", 1, [OccurrenceFixtures.cond_occurrence("occurrence_c", &"death_prevented")]),
		Fixtures.make_ending("ending_b", 2, [OccurrenceFixtures.cond_occurrence("occurrence_a", &"death_prevented"),
				OccurrenceFixtures.cond_occurrence("occurrence_c", &"death_permanent")]),
		Fixtures.make_ending("ending_z", 3),
	]
	assert_eq(Fixtures.make_resolver(ctx.world, endings).resolve().ending_id, &"ending_b")


# --- Güven ---

func test_higher_priority_match_skips_a_later_trust_conditioned_ending() -> void:
	var ctx: Ctx = _ctx(false)
	_finish_game(ctx)
	ctx.world.state.set_flag(&"flag_a", true)
	var result: EndingResultScript = Fixtures.make_resolver(ctx.world, _trust_endings()).resolve()
	assert_eq([result.status, result.ending_id], [EndingResultScript.STATUS_RESOLVED, &"ending_a"])
	assert_false(ctx.world.trust.is_initialized())
	assert_eq(take_engine_errors().size(), 0)


func test_evaluated_trust_conditioned_ending_requires_initialized_trust() -> void:
	var ctx: Ctx = _ctx(false)
	_finish_game(ctx)
	var result: EndingResultScript = Fixtures.make_resolver(ctx.world, _trust_endings()).resolve()
	assert_eq([result.status, result.failure, result.ending_id], [&"", EndingResultScript.FAILURE_SYSTEM_NOT_READY, &""])
	assert_true(result.is_failed())
	_assert_one_engine_error("güven başlatılmadı")


func test_partial_trust_state_is_invalid_configuration() -> void:
	var ctx: Ctx = _ctx(false)
	_finish_game(ctx)
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	ctx.world.state.set_trust_state(partial)
	var result: EndingResultScript = Fixtures.make_resolver(ctx.world, _basic_endings()).resolve()
	assert_eq(result.failure, EndingResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("eksik güven ilişkisi")


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var resolver: EndingResolverScript = Fixtures.make_resolver(_ctx().world, _ordered_endings())
	assert_eq(resolver.get_configuration_errors(), PackedStringArray())


func test_ending_level_errors_are_reported_in_order() -> void:
	var flag: Callable = func() -> Object: return DecisionFixtures.cond_flag("flag_a", true)
	var endings: Array = [
		null,
		Fixtures.make_ending("", 1, [flag.call()]),
		Fixtures.make_ending("ending_x", 0, [flag.call()]),
		Fixtures.make_ending("ending_a", 2, [flag.call()]),
		Fixtures.make_ending("ending_a", 3, [flag.call()]),
		Fixtures.make_ending("ending_z", 9),
	]
	assert_eq(Fixtures.make_resolver(_ctx().world, endings).get_configuration_errors(), PackedStringArray([
		"Tanımsız son kaydı (#0)",
		"Boş son kimliği (#1)",
		"'ending_x': öncelik 1 veya daha büyük olmalı (0)",
		"Tekrarlanan son kimliği: 'ending_a'",
	]))
	assert_eq(take_engine_errors().size(), 0)


func test_equal_priority_is_a_configuration_error() -> void:
	var endings: Array = [
		Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_a", true)]),
		Fixtures.make_ending("ending_b", 1, [DecisionFixtures.cond_flag("flag_b", true)]),
		Fixtures.make_ending("ending_z", 5),
	]
	assert_eq(Fixtures.make_resolver(_ctx().world, endings).get_configuration_errors(),
			PackedStringArray(["'ending_b': aynı öncelik ('ending_a' ile, 1)"]))


func test_missing_fallback_is_a_configuration_error() -> void:
	var endings: Array = [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_a", true)])]
	assert_eq(Fixtures.make_resolver(_ctx().world, endings).get_configuration_errors(), PackedStringArray(["Koşulsuz yedek son yok"]))


func test_more_than_one_fallback_is_a_configuration_error() -> void:
	var endings: Array = [
		Fixtures.make_ending("ending_z", 9),
		Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_a", true)]),
		Fixtures.make_ending("ending_y", 8),
	]
	assert_eq(Fixtures.make_resolver(_ctx().world, endings).get_configuration_errors(), PackedStringArray([
		"'ending_z': birden fazla koşulsuz son ('ending_y' ile)",
		"'ending_y': koşulsuz son en düşük öncelikte olmalı",
	]))


func test_fallback_must_have_the_greatest_priority() -> void:
	var before: Array = [Fixtures.make_ending("ending_z", 1), Fixtures.make_ending("ending_a", 2, [DecisionFixtures.cond_flag("flag_a", true)])]
	assert_eq(Fixtures.make_resolver(_ctx().world, before).get_configuration_errors(),
			PackedStringArray(["'ending_z': koşulsuz son en düşük öncelikte olmalı"]))
	var equal: Array = [Fixtures.make_ending("ending_z", 2), Fixtures.make_ending("ending_a", 2, [DecisionFixtures.cond_flag("flag_a", true)])]
	assert_eq(Fixtures.make_resolver(_ctx().world, equal).get_configuration_errors(), PackedStringArray([
		"'ending_a': aynı öncelik ('ending_z' ile, 2)",
		"'ending_z': koşulsuz son en düşük öncelikte olmalı",
	]))


func test_condition_errors_match_the_decision_system_messages() -> void:
	var make_conditions: Callable = func() -> Array:
		return [null, DecisionFixtures.cond_resource("missing_id", &"ge", 1),
				DecisionFixtures.cond_trust("actor_a", "actor_b", &"ge", 150), OccurrenceFixtures.cond_occurrence("missing_id", &"pending")]
	var world: DecisionFixtures.World = _ctx().world
	var ending_errors: PackedStringArray = Fixtures.make_resolver(world, [Fixtures.make_ending("ending_a", 1, make_conditions.call()),
			Fixtures.make_ending("ending_z", 2)]).get_configuration_errors()
	var decision: Object = DecisionFixtures.make_decision("decision_a", [DecisionFixtures.make_choice("choice_a", make_conditions.call())])
	var decision_errors: PackedStringArray = DecisionFixtures.make_system(world, [decision]).get_configuration_errors()
	assert_eq(ending_errors.size(), 4)
	assert_eq(_strip(ending_errors, "'ending_a' koşul "), _strip(decision_errors, "'decision_a' / 'choice_a' koşul "))


func test_dependency_errors_are_included() -> void:
	var world: DecisionFixtures.World = _ctx().world
	var rules: TimeRulesDataScript = TimeRulesDataScript.new()
	rules.id = "time_rules_a"
	rules.night_count = 0
	rules.night_length_units = 10
	var no_events: Array[ScheduledEventDataScript] = []
	world.time = TimeSystemScript.new(world.state, rules, no_events)
	assert_eq(Fixtures.make_resolver(world, _basic_endings()).get_configuration_errors(),
			PackedStringArray(["TimeSystem: Gece sayısı en az 1 olmalı: 0"]))


func test_configuration_errors_are_deterministic() -> void:
	var build: Callable = func() -> PackedStringArray:
		var endings: Array = [null, Fixtures.make_ending("ending_a", 0, [null]), Fixtures.make_ending("ending_b", 3),
				Fixtures.make_ending("ending_c", 3)]
		return Fixtures.make_resolver(_ctx().world, endings).get_configuration_errors()
	var first: PackedStringArray = build.call()
	assert_eq(first, build.call())
	assert_eq(first.size(), 6, " | ".join(first))


func test_invalid_configuration_blocks_resolve() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	var result: EndingResultScript = Fixtures.make_resolver(ctx.world, [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_a", true)])]).resolve()
	assert_eq([result.status, result.failure, result.ending_id], [&"", EndingResultScript.FAILURE_INVALID_CONFIGURATION, &""])
	_assert_one_engine_error("geçersiz yapılandırma")


# --- Güvenlik ve determinizm ---

func test_catalog_is_copied_on_creation() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	var endings: Array = _ordered_endings()
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, endings)
	endings[0].priority = 50
	endings[1].conditions.clear()
	endings[3].conditions.append(DecisionFixtures.cond_flag("flag_z", true))
	endings.append(null)
	assert_eq(resolver.get_configuration_errors(), PackedStringArray())
	assert_eq(resolver.resolve().ending_id, &"ending_z")


func test_resolve_never_changes_state_on_any_path() -> void:
	var state: CountingGameState = CountingGameState.new(OccurrenceFixtures.make_setup())
	var ctx: Ctx = _ctx(false, state)
	var ok: EndingResolverScript = Fixtures.make_resolver(ctx.world, _basic_endings())
	var trust: EndingResolverScript = Fixtures.make_resolver(ctx.world, _trust_endings())
	var invalid: EndingResolverScript = Fixtures.make_resolver(ctx.world, [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_a", true)])])
	var calls: Array[int] = _count_signals(state)
	_assert_resolve_is_read_only(state, calls, ok, EndingResultScript.STATUS_GAME_NOT_OVER, &"")
	_finish_game(ctx)
	_assert_resolve_is_read_only(state, calls, ok, EndingResultScript.STATUS_RESOLVED, &"")
	_assert_resolve_is_read_only(state, calls, trust, &"", EndingResultScript.FAILURE_SYSTEM_NOT_READY)
	_assert_one_engine_error("güven başlatılmadı")
	_assert_resolve_is_read_only(state, calls, invalid, &"", EndingResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("geçersiz yapılandırma")


func test_same_start_and_same_actions_produce_the_same_ending() -> void:
	assert_eq(_run_reference(), _run_reference())


func test_ending_result_exposes_only_the_approved_fields() -> void:
	var names: Array[String] = []
	for property in EndingResultScript.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["status", "failure", "ending_id"] as Array[String])


func test_mutating_a_result_does_not_affect_later_calls() -> void:
	var ctx: Ctx = _ctx()
	_finish_game(ctx)
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, _ordered_endings())
	var result: EndingResultScript = resolver.resolve()
	result.ending_id = &"ending_a"
	result.status = EndingResultScript.STATUS_GAME_NOT_OVER
	assert_eq(_describe(resolver.resolve()), [EndingResultScript.STATUS_RESOLVED, &"", &"ending_z"])


# --- Yardımcılar ---

## ending_a (öncelik 1, flag_a) → ending_z (öncelik 9, koşulsuz yedek).
func _basic_endings() -> Array:
	return [Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_a", true)]), Fixtures.make_ending("ending_z", 9)]


## Öncelik sırası: ending_c (3, res_a ≥ 10), ending_b (5, flag_a), ending_a (7, res_a ≥ 1 ve flag_b), ending_z (9, yedek).
func _ordered_endings() -> Array:
	return [
		Fixtures.make_ending("ending_a", 7, [DecisionFixtures.cond_resource("res_a", &"ge", 1), DecisionFixtures.cond_flag("flag_b", true)]),
		Fixtures.make_ending("ending_b", 5, [DecisionFixtures.cond_flag("flag_a", true)]),
		Fixtures.make_ending("ending_c", 3, [DecisionFixtures.cond_resource("res_a", &"ge", 10)]),
		Fixtures.make_ending("ending_z", 9),
	]


## ending_a (1, flag_a) → ending_b (2, güven actor_b→actor_a ≥ 10) → ending_z (3, yedek).
func _trust_endings() -> Array:
	return [
		Fixtures.make_ending("ending_b", 2, [DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 10)]),
		Fixtures.make_ending("ending_z", 3),
		Fixtures.make_ending("ending_a", 1, [DecisionFixtures.cond_flag("flag_a", true)]),
	]


func _run_reference() -> Array:
	var ctx: Ctx = _ctx()
	var resolver: EndingResolverScript = Fixtures.make_resolver(ctx.world, _ordered_endings())
	var observed: Array = [_describe(resolver.resolve())]
	ctx.occurrences.start_night()
	ctx.world.state.set_flag(&"flag_b", true)
	_end_night(ctx)
	observed.append(_describe(resolver.resolve()))
	ctx.occurrences.start_night()
	_end_night(ctx)
	observed.append(_describe(resolver.resolve()))
	observed.append(_snapshot(ctx.world.state))
	return observed


func _ctx(initialize_trust: bool = true, state: GameStateScript = null) -> Ctx:
	var ctx: Ctx = Ctx.new()
	ctx.world = OccurrenceFixtures.make_world(OccurrenceFixtures.DEFAULT_IDS, state)
	ctx.occurrences = OccurrenceFixtures.make_default_system(ctx.world)
	ctx.clock = OccurrenceFixtures.make_clock(ctx.world)
	if initialize_trust:
		ctx.world.trust.initialize_relationships()
	return ctx


## Kalan geceleri oyun akışıyla açar ve bitirir.
func _finish_game(ctx: Ctx) -> void:
	while not ctx.world.state.is_night_ended() or ctx.world.time.has_next_night():
		if ctx.world.state.get_night() == 0 or ctx.world.state.is_night_ended():
			assert_true(ctx.occurrences.start_night().ok)
		_end_night(ctx)


func _end_night(ctx: Ctx) -> void:
	assert_true(ctx.clock.advance(10 - ctx.world.state.get_elapsed_units()).ok)


func _assert_resolve_is_read_only(state: CountingGameState, calls: Array[int], resolver: EndingResolverScript,
		expected_status: StringName, expected_failure: StringName) -> void:
	var before: Array = _snapshot(state)
	var signals_before: int = calls[0]
	state.apply_calls = 0
	state.other_writes = 0
	var result: EndingResultScript = resolver.resolve()
	assert_eq([result.status, result.failure], [expected_status, expected_failure])
	assert_true(resolver.is_game_over() or expected_status == EndingResultScript.STATUS_GAME_NOT_OVER)
	assert_eq([state.apply_calls, state.other_writes, calls[0] - signals_before], [0, 0, 0])
	assert_eq(_snapshot(state), before)


func _assert_game_not_over(result: EndingResultScript) -> void:
	assert_eq(_describe(result), [EndingResultScript.STATUS_GAME_NOT_OVER, &"", &""])


func _describe(result: EndingResultScript) -> Array:
	return [result.status, result.failure, result.ending_id]


func _snapshot(state: GameStateScript) -> Array:
	var trust_rows: Array = []
	for entry in state.get_trust_snapshot():
		trust_rows.append([String(entry.source_actor_id), String(entry.target_actor_id), entry.value])
	var task_rows: Array = []
	for task in state.get_tasks_snapshot():
		task_rows.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return [state.get_resources_snapshot(), state.get_flags_snapshot(), trust_rows, state.get_night(),
			state.get_elapsed_units(), state.is_night_ended(), task_rows, state.get_occurrences_snapshot()]


func _strip(lines: PackedStringArray, prefix: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(line.trim_prefix(prefix))
	return result


func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_one_engine_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))


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
