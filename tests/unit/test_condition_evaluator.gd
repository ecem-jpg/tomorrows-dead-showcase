extends "res://tests/framework/test_case.gd"
## ConditionEvaluator birim testleri (K-026). Yalnızca tarafsız kimlikler kullanılır (K-018).
## Dünya: res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30 (0..100).

const Fixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const ConditionEvaluatorScript := preload("res://scripts/systems/condition_evaluator.gd")
const OccurrenceFixtures := preload("res://tests/fixtures/occurrence_fixtures.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")


func test_every_comparison_follows_its_meaning() -> void:
	var evaluator: ConditionEvaluatorScript = _evaluator(_started_world())
	var cases: Array = [
		[&"eq", 5, true], [&"eq", 4, false], [&"ne", 4, true], [&"ne", 5, false],
		[&"lt", 6, true], [&"lt", 5, false], [&"le", 5, true], [&"le", 4, false],
		[&"gt", 4, true], [&"gt", 5, false], [&"ge", 5, true], [&"ge", 6, false],
	]
	for case in cases:
		assert_eq(evaluator.is_met(Fixtures.cond_resource("res_a", case[0], case[1])), case[2], str(case))


func test_trust_condition_is_directional() -> void:
	var evaluator: ConditionEvaluatorScript = _evaluator(_started_world())
	assert_true(evaluator.is_met(Fixtures.cond_trust("actor_a", "actor_b", &"ge", 50)))
	assert_false(evaluator.is_met(Fixtures.cond_trust("actor_b", "actor_a", &"ge", 50)))


func test_undefined_flag_reads_false() -> void:
	var world: Fixtures.World = _started_world()
	var evaluator: ConditionEvaluatorScript = _evaluator(world)
	assert_true(evaluator.is_met(Fixtures.cond_flag("flag_z", false)))
	assert_false(evaluator.is_met(Fixtures.cond_flag("flag_z", true)))
	world.state.set_flag(&"flag_z", true)
	assert_true(evaluator.is_met(Fixtures.cond_flag("flag_z", true)))


func test_unknown_kind_or_comparison_is_never_met() -> void:
	var evaluator: ConditionEvaluatorScript = _evaluator(_started_world())
	assert_false(evaluator.is_met(Fixtures.make_condition(&"unknown")))
	assert_false(evaluator.is_met(Fixtures.cond_resource("res_a", &"zz", 5)))


func test_failed_indexes_follow_data_order() -> void:
	var evaluator: ConditionEvaluatorScript = _evaluator(_started_world())
	var conditions: Array[ConditionDataScript] = [
		Fixtures.cond_flag("flag_a", true),
		Fixtures.cond_resource("res_a", &"ge", 1),
		Fixtures.cond_trust("actor_b", "actor_a", &"gt", 30),
	]
	assert_eq(evaluator.get_failed_indexes(conditions), PackedInt32Array([0, 2]))
	var empty: Array[ConditionDataScript] = []
	assert_eq(evaluator.get_failed_indexes(empty), PackedInt32Array())


func test_uses_trust_detects_only_trust_conditions() -> void:
	var evaluator: ConditionEvaluatorScript = _evaluator(Fixtures.make_world())
	var without_trust: Array[ConditionDataScript] = [Fixtures.cond_flag("flag_a", true), null]
	var with_trust: Array[ConditionDataScript] = [null, Fixtures.cond_trust("actor_a", "actor_b", &"ge", 1)]
	assert_false(evaluator.uses_trust(without_trust))
	assert_true(evaluator.uses_trust(with_trust))


func test_errors_are_reported_in_fixed_order_without_engine_errors() -> void:
	var evaluator: ConditionEvaluatorScript = _evaluator(Fixtures.make_world())
	var p: String = "x: "
	assert_eq(evaluator.get_errors(p, null), PackedStringArray(["x: tanımsız kayıt"]))
	assert_eq(evaluator.get_errors(p, Fixtures.make_condition(&"unknown")), PackedStringArray(["x: tanımsız tür 'unknown'"]))
	assert_eq(evaluator.get_errors(p, Fixtures.make_condition(&"resource", {"comparison": &"zz", "flag_id": "flag_a"})),
			PackedStringArray(["x: eksik alan 'resource_id'", "x: ilgisiz alan dolu 'flag_id'", "x: tanımsız karşılaştırma 'zz'"]))
	assert_eq(evaluator.get_errors(p, Fixtures.cond_trust("actor_a", "actor_a", &"ge", 150)),
			PackedStringArray(["x: kendine güven ilişkisi 'actor_a'", "x: güven eşiği aralık dışında: 150"]))
	assert_eq(evaluator.get_errors(p, Fixtures.make_condition(&"flag", {"value": 3})),
			PackedStringArray(["x: eksik alan 'flag_id'", "x: ilgisiz alan dolu 'value'"]))
	assert_eq(evaluator.get_errors(p, Fixtures.cond_resource("res_a", &"ge", 1)), PackedStringArray())
	assert_eq(take_engine_errors().size(), 0)


func test_evaluator_never_writes_state() -> void:
	var world: Fixtures.World = _started_world()
	var evaluator: ConditionEvaluatorScript = _evaluator(world)
	var calls: Array[int] = [0]
	world.state.state_changed.connect(func() -> void: calls[0] += 1)
	var conditions: Array[ConditionDataScript] = [
		Fixtures.cond_resource("res_a", &"ge", 1), Fixtures.cond_trust("actor_a", "actor_b", &"ge", 1),
		Fixtures.cond_flag("flag_a", true),
	]
	evaluator.get_failed_indexes(conditions)
	evaluator.uses_trust(conditions)
	for condition in conditions:
		evaluator.get_errors("x: ", condition)
	assert_eq(calls[0], 0)
	assert_eq(world.state.get_flags_snapshot().size(), 0)


func test_occurrence_condition_reads_the_internal_status() -> void:
	var world: Fixtures.World = OccurrenceFixtures.make_world()
	var evaluator: ConditionEvaluatorScript = _evaluator(world)
	assert_true(evaluator.is_met(OccurrenceFixtures.cond_occurrence("occurrence_a", &"inactive")))
	assert_false(evaluator.is_met(OccurrenceFixtures.cond_occurrence("occurrence_a", &"pending")))
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.occurrence_statuses[&"occurrence_a"] = &"pending"
	world.state.apply_changes(change)
	assert_true(evaluator.is_met(OccurrenceFixtures.cond_occurrence("occurrence_a", &"pending")))
	# Görünüm durumu bayrağa kopyalanmaz; aynı adlı bayrak koşulu bağımsızdır.
	assert_false(evaluator.is_met(Fixtures.cond_flag("occurrence_a", true)))


func test_occurrence_condition_errors_are_reported_in_fixed_order() -> void:
	var evaluator: ConditionEvaluatorScript = _evaluator(OccurrenceFixtures.make_world())
	var p: String = "x: "
	assert_eq(evaluator.get_errors(p, OccurrenceFixtures.cond_occurrence("occurrence_a", &"death_prevented")), PackedStringArray())
	assert_eq(evaluator.get_errors(p, Fixtures.make_condition(&"occurrence",
			{"flag_id": "flag_a", "comparison": &"eq", "occurrence_status": &"lost"})), PackedStringArray([
		"x: eksik alan 'occurrence_id'",
		"x: ilgisiz alan dolu 'flag_id'",
		"x: ilgisiz alan dolu 'comparison'",
		"x: tanımsız görünüm durumu 'lost'",
	]))
	assert_eq(evaluator.get_errors(p, OccurrenceFixtures.cond_occurrence("missing_id", &"pending")),
			PackedStringArray(["x: tanımsız görünüm 'missing_id'"]))
	assert_eq(evaluator.get_errors(p, Fixtures.make_condition(&"flag", {"flag_id": "flag_a", "occurrence_id": "occurrence_a",
			"occurrence_status": &"pending"})), PackedStringArray([
		"x: ilgisiz alan dolu 'occurrence_id'",
		"x: ilgisiz alan dolu 'occurrence_status'",
	]))
	assert_eq(take_engine_errors().size(), 0)


# --- Yardımcılar ---

func _started_world() -> Fixtures.World:
	var world: Fixtures.World = Fixtures.make_world()
	Fixtures.start(world)
	return world


func _evaluator(world: Fixtures.World) -> ConditionEvaluatorScript:
	return ConditionEvaluatorScript.new(world.state, world.trust)
