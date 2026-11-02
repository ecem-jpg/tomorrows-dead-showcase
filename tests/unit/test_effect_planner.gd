extends "res://tests/framework/test_case.gd"
## EffectPlanner birim testleri (K-027). Yalnızca tarafsız kimlikler kullanılır (K-018).
## Dünya: res_a = 5 (0..10), res_b = 0 (alt 0); güven actor_a→actor_b 60, actor_b→actor_a 30 (0..100).

const Fixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const EffectPlannerScript := preload("res://scripts/systems/effect_planner.gd")
const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")
const OccurrenceFixtures := preload("res://tests/fixtures/occurrence_fixtures.gd")


func test_resource_add_clamps_and_reports_the_applied_change() -> void:
	var planner: EffectPlannerScript = _planner(_started_world())
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var outcome: DecisionEffectOutcomeScript = planner.plan(0, Fixtures.eff_add("res_a", 20), change)
	assert_eq([outcome.index, outcome.kind, outcome.resource_id, outcome.requested, outcome.previous, outcome.applied],
			[0, &"resource_add", &"res_a", 20, 5, 5])
	assert_eq(change.resource_values[&"res_a"], 10)


func test_insufficient_spend_returns_null_and_leaves_the_change_untouched() -> void:
	var planner: EffectPlannerScript = _planner(_started_world())
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.resource_values[&"res_a"] = 3
	assert_eq(planner.plan(0, Fixtures.eff_spend("res_a", 4), change), null)
	assert_eq(change.resource_values.size(), 1)
	assert_eq(change.resource_values[&"res_a"], 3)
	assert_true(change.flag_values.is_empty() and change.trust_values.is_empty())


func test_trust_change_clamps_and_is_directional() -> void:
	var planner: EffectPlannerScript = _planner(_started_world())
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var outcome: DecisionEffectOutcomeScript = planner.plan(0, Fixtures.eff_trust("actor_b", "actor_a", -50), change)
	assert_eq([outcome.source_actor_id, outcome.target_actor_id, outcome.previous, outcome.applied],
			[&"actor_b", &"actor_a", 30, -30])
	assert_eq(change.trust_values.size(), 1)
	assert_eq([change.trust_values[0].source_actor_id, change.trust_values[0].value], [&"actor_b", 0])


func test_flag_set_reports_previous_value_and_may_create_a_flag() -> void:
	var planner: EffectPlannerScript = _planner(_started_world())
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var outcome: DecisionEffectOutcomeScript = planner.plan(0, Fixtures.eff_flag("flag_z", true), change)
	assert_eq([outcome.flag_id, outcome.previous_flag, outcome.flag_value], [&"flag_z", false, true])
	assert_eq(change.flag_values[&"flag_z"], true)


func test_resource_values_accumulate_in_the_change_with_clamping_per_step() -> void:
	var planner: EffectPlannerScript = _planner(_started_world())
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var steps: Array = [Fixtures.eff_add("res_a", 3), Fixtures.eff_add("res_a", 5), Fixtures.eff_spend("res_a", 4)]
	var described: Array = []
	for i in steps.size():
		var outcome: DecisionEffectOutcomeScript = planner.plan(i, steps[i], change)
		described.append([outcome.previous, outcome.applied])
	assert_eq(described, [[5, 3], [8, 2], [10, -4]])
	assert_eq(change.resource_values[&"res_a"], 6)


func test_trust_values_accumulate_without_duplicate_entries() -> void:
	var planner: EffectPlannerScript = _planner(_started_world())
	var change: GameStateChangeScript = GameStateChangeScript.new()
	planner.plan(0, Fixtures.eff_trust("actor_a", "actor_b", 10), change)
	var second: DecisionEffectOutcomeScript = planner.plan(1, Fixtures.eff_trust("actor_a", "actor_b", 50), change)
	assert_eq([second.previous, second.applied], [70, 30])
	assert_eq(change.trust_values.size(), 1)
	assert_eq(change.trust_values[0].value, 100)


func test_flag_previous_value_is_read_from_the_change() -> void:
	var planner: EffectPlannerScript = _planner(_started_world())
	var change: GameStateChangeScript = GameStateChangeScript.new()
	planner.plan(0, Fixtures.eff_flag("flag_a", true), change)
	var second: DecisionEffectOutcomeScript = planner.plan(1, Fixtures.eff_flag("flag_a", false), change)
	assert_eq([second.previous_flag, second.flag_value], [true, false])
	assert_eq(change.flag_values[&"flag_a"], false)


func test_errors_keep_the_decision_system_messages() -> void:
	var planner: EffectPlannerScript = _planner(Fixtures.make_world())
	var p: String = "x: "
	var cases: Array = [
		[null, ["x: tanımsız kayıt"]],
		[Fixtures.make_effect(&"unknown"), ["x: tanımsız tür 'unknown'"]],
		[Fixtures.eff_add("res_a", -1), ["x: negatif miktar: -1"]],
		[Fixtures.eff_spend("missing_id", 1), ["x: tanımsız kaynak 'missing_id'"]],
		[Fixtures.eff_trust("actor_b", "actor_c", 5), ["x: tanımsız güven ilişkisi 'actor_b' -> 'actor_c'"]],
		[Fixtures.eff_trust("actor_a", "actor_a", 5), ["x: kendine güven ilişkisi 'actor_a'"]],
		[Fixtures.eff_flag("", true), ["x: eksik alan 'flag_id'"]],
		[Fixtures.make_effect(&"flag_set", {"flag_id": "flag_b", "amount": 3}), ["x: ilgisiz alan dolu 'amount'"]],
		[Fixtures.make_effect(&"resource_add", {"resource_id": "res_b", "amount": 1, "flag_value": true}),
				["x: ilgisiz alan dolu 'flag_value'"]],
		[Fixtures.eff_add("res_a", 1), []],
	]
	for case in cases:
		assert_eq(planner.get_errors(p, case[0]), PackedStringArray(case[1]), str(case[1]))
	assert_eq(take_engine_errors().size(), 0)


func test_same_target_rules() -> void:
	var planner: EffectPlannerScript = _planner(Fixtures.make_world())
	assert_true(planner.is_same_target(Fixtures.eff_add("res_a", 1), Fixtures.eff_spend("res_a", 1)))
	assert_false(planner.is_same_target(Fixtures.eff_add("res_a", 1), Fixtures.eff_add("res_b", 1)))
	assert_true(planner.is_same_target(Fixtures.eff_trust("actor_a", "actor_b", 1), Fixtures.eff_trust("actor_a", "actor_b", 2)))
	assert_false(planner.is_same_target(Fixtures.eff_trust("actor_a", "actor_b", 1), Fixtures.eff_trust("actor_b", "actor_a", 1)))
	assert_true(planner.is_same_target(Fixtures.eff_flag("flag_a", true), Fixtures.eff_flag("flag_a", false)))
	assert_false(planner.is_same_target(Fixtures.eff_flag("flag_a", true), Fixtures.eff_add("res_a", 1)))
	assert_false(planner.is_same_target(null, Fixtures.eff_add("res_a", 1)))


func test_uses_trust_detects_only_trust_effects() -> void:
	var planner: EffectPlannerScript = _planner(Fixtures.make_world())
	var without_trust: Array[EffectDataScript] = [Fixtures.eff_add("res_a", 1), null]
	var with_trust: Array[EffectDataScript] = [null, Fixtures.eff_trust("actor_a", "actor_b", 1)]
	assert_false(planner.uses_trust(without_trust))
	assert_true(planner.uses_trust(with_trust))


func test_planner_never_writes_state() -> void:
	var world: Fixtures.World = _started_world()
	var planner: EffectPlannerScript = _planner(world)
	var calls: Array[int] = [0]
	world.state.state_changed.connect(func() -> void: calls[0] += 1)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	planner.plan(0, Fixtures.eff_spend("res_a", 2), change)
	planner.plan(1, Fixtures.eff_trust("actor_a", "actor_b", 5), change)
	planner.plan(2, Fixtures.eff_flag("flag_a", true), change)
	assert_eq(calls[0], 0)
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_false(world.state.get_flag(&"flag_a"))


func test_occurrence_effects_resolve_only_pending_occurrences() -> void:
	var world: Fixtures.World = OccurrenceFixtures.make_world()
	var planner: EffectPlannerScript = _planner(world)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	assert_eq(planner.plan(0, OccurrenceFixtures.eff_prevent("occurrence_a"), change), null)
	assert_true(change.occurrence_statuses.is_empty())
	var setup: GameStateChangeScript = GameStateChangeScript.new()
	setup.occurrence_statuses[&"occurrence_a"] = &"pending"
	setup.occurrence_statuses[&"occurrence_b"] = &"pending"
	world.state.apply_changes(setup)
	var prevent: DecisionEffectOutcomeScript = planner.plan(0, OccurrenceFixtures.eff_prevent("occurrence_a"), change)
	var permanent: DecisionEffectOutcomeScript = planner.plan(1, OccurrenceFixtures.eff_permanent("occurrence_b"), change)
	assert_eq([prevent.kind, prevent.occurrence_id, prevent.previous_occurrence_status, prevent.occurrence_status],
			[&"occurrence_prevent_death", &"occurrence_a", &"pending", &"death_prevented"])
	assert_eq([permanent.previous_occurrence_status, permanent.occurrence_status], [&"pending", &"death_permanent"])
	assert_eq([change.occurrence_statuses[&"occurrence_a"], change.occurrence_statuses[&"occurrence_b"]],
			[&"death_prevented", &"death_permanent"])
	assert_eq(world.state.get_occurrence_status(&"occurrence_a"), &"pending")


func test_second_occurrence_effect_sees_the_accumulated_final_status() -> void:
	var world: Fixtures.World = OccurrenceFixtures.make_world()
	var setup: GameStateChangeScript = GameStateChangeScript.new()
	setup.occurrence_statuses[&"occurrence_a"] = &"pending"
	world.state.apply_changes(setup)
	var planner: EffectPlannerScript = _planner(world)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	assert_true(planner.plan(0, OccurrenceFixtures.eff_prevent("occurrence_a"), change) != null)
	assert_eq(planner.plan(1, OccurrenceFixtures.eff_permanent("occurrence_a"), change), null)
	assert_eq(change.occurrence_statuses[&"occurrence_a"], &"death_prevented")


func test_occurrence_effect_errors_and_same_target_rule() -> void:
	var planner: EffectPlannerScript = _planner(OccurrenceFixtures.make_world())
	var p: String = "x: "
	assert_eq(planner.get_errors(p, OccurrenceFixtures.eff_permanent("occurrence_a")), PackedStringArray())
	assert_eq(planner.get_errors(p, OccurrenceFixtures.eff_prevent("missing_id")), PackedStringArray(["x: tanımsız görünüm 'missing_id'"]))
	assert_eq(planner.get_errors(p, Fixtures.make_effect(&"occurrence_prevent_death", {"resource_id": "res_a", "amount": 2})),
			PackedStringArray(["x: eksik alan 'occurrence_id'", "x: ilgisiz alan dolu 'resource_id'", "x: ilgisiz alan dolu 'amount'"]))
	assert_eq(planner.get_errors(p, Fixtures.make_effect(&"flag_set", {"flag_id": "flag_a", "occurrence_id": "occurrence_a"})),
			PackedStringArray(["x: ilgisiz alan dolu 'occurrence_id'"]))
	assert_true(planner.is_same_target(OccurrenceFixtures.eff_prevent("occurrence_a"), OccurrenceFixtures.eff_permanent("occurrence_a")))
	assert_false(planner.is_same_target(OccurrenceFixtures.eff_prevent("occurrence_a"), OccurrenceFixtures.eff_prevent("occurrence_b")))
	assert_eq(take_engine_errors().size(), 0)


# --- Yardımcılar ---

func _started_world() -> Fixtures.World:
	var world: Fixtures.World = Fixtures.make_world()
	Fixtures.start(world)
	return world


func _planner(world: Fixtures.World) -> EffectPlannerScript:
	return EffectPlannerScript.new(world.state, world.resources, world.trust)
