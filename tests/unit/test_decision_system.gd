extends "res://tests/framework/test_case.gd"
## DecisionSystem birim testleri. Yalnızca tarafsız kimlikler kullanılır (K-018).
## Dünya: res_a = 5 (0..10), res_b = 0 (alt 0); güven actor_a→actor_b 60, actor_b→actor_a 30 (0..100);
## zaman 2 gece × 10 birim, action_a = 2, action_b = 0.

const Fixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const ResourceLimitsDataScript := preload("res://scripts/data/resource_limits_data.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")

const FIXTURE_PATH: String = "res://tests/fixtures/decisions/decision_a.tres"


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_fixture_file_builds_a_valid_system() -> void:
	var decision: DecisionDataScript = ResourceLoader.load(FIXTURE_PATH) as DecisionDataScript
	var system: DecisionSystemScript = Fixtures.make_system(Fixtures.make_world(), [decision])
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_configuration_reports_decision_level_errors_in_order() -> void:
	var valid_choice: Callable = func() -> Object: return Fixtures.make_choice("choice_a")
	var decisions: Array = [
		null,
		Fixtures.make_decision("", [valid_choice.call()]),
		Fixtures.make_decision("decision_x", []),
		Fixtures.make_decision("decision_y", [valid_choice.call()]),
		Fixtures.make_decision("decision_y", [valid_choice.call()]),
	]
	var system: DecisionSystemScript = Fixtures.make_system(Fixtures.make_world(), decisions)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız karar kaydı (#0)",
		"Boş karar kimliği (#1)",
		"Kararda seçenek yok: 'decision_x'",
		"Tekrarlanan karar kimliği: 'decision_y'",
	]))


func test_configuration_reports_choice_level_errors_in_order() -> void:
	var decision: DecisionDataScript = Fixtures.make_decision("decision_a", [
		null,
		Fixtures.make_choice(""),
		Fixtures.make_choice("choice_a"),
		Fixtures.make_choice("choice_a"),
	])
	var system: DecisionSystemScript = Fixtures.make_system(Fixtures.make_world(), [decision])
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"'decision_a' seçenek #0: tanımsız kayıt",
		"'decision_a' seçenek #1: boş seçenek kimliği",
		"'decision_a' seçenek #3: tekrarlanan seçenek kimliği 'choice_a'",
	]))


func test_configuration_reports_condition_errors_in_order() -> void:
	var conditions: Array = [
		null,
		Fixtures.make_condition(&"unknown"),
		Fixtures.make_condition(&"resource", {"comparison": &"zz", "flag_id": "flag_a"}),
		Fixtures.cond_resource("missing_id", &"ge", 1),
		Fixtures.cond_trust("actor_b", "actor_c", &"ge", 10),
		Fixtures.cond_trust("actor_a", "actor_a", &"ge", 10),
		Fixtures.cond_trust("actor_a", "actor_b", &"ge", 150),
		Fixtures.make_condition(&"flag", {"flag_id": "flag_a", "comparison": &"ge", "value": 3}),
		Fixtures.make_condition(&"flag"),
	]
	var decision: DecisionDataScript = Fixtures.make_decision("decision_a", [Fixtures.make_choice("choice_a", conditions)])
	var system: DecisionSystemScript = Fixtures.make_system(Fixtures.make_world(), [decision])
	var p: String = "'decision_a' / 'choice_a' koşul "
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		p + "#0: tanımsız kayıt",
		p + "#1: tanımsız tür 'unknown'",
		p + "#2: eksik alan 'resource_id'",
		p + "#2: ilgisiz alan dolu 'flag_id'",
		p + "#2: tanımsız karşılaştırma 'zz'",
		p + "#3: tanımsız kaynak 'missing_id'",
		p + "#4: tanımsız güven ilişkisi 'actor_b' -> 'actor_c'",
		p + "#5: kendine güven ilişkisi 'actor_a'",
		p + "#6: güven eşiği aralık dışında: 150",
		p + "#7: ilgisiz alan dolu 'comparison'",
		p + "#7: ilgisiz alan dolu 'value'",
		p + "#8: eksik alan 'flag_id'",
	]))


func test_configuration_reports_effect_errors_in_order() -> void:
	var effects: Array = [
		null,
		Fixtures.make_effect(&"unknown"),
		Fixtures.eff_add("res_a", -1),
		Fixtures.eff_spend("missing_id", 1),
		Fixtures.eff_trust("actor_b", "actor_c", 5),
		Fixtures.eff_trust("actor_a", "actor_a", 5),
		Fixtures.eff_flag("", true),
		Fixtures.make_effect(&"flag_set", {"flag_id": "flag_b", "amount": 3}),
		Fixtures.make_effect(&"resource_add", {"resource_id": "res_b", "amount": 1, "flag_value": true}),
	]
	var decision: DecisionDataScript = Fixtures.make_decision("decision_a", [Fixtures.make_choice("choice_a", [], effects)])
	var system: DecisionSystemScript = Fixtures.make_system(Fixtures.make_world(), [decision])
	var p: String = "'decision_a' / 'choice_a' etki "
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		p + "#0: tanımsız kayıt",
		p + "#1: tanımsız tür 'unknown'",
		p + "#2: negatif miktar: -1",
		p + "#3: tanımsız kaynak 'missing_id'",
		p + "#4: tanımsız güven ilişkisi 'actor_b' -> 'actor_c'",
		p + "#5: kendine güven ilişkisi 'actor_a'",
		p + "#6: eksik alan 'flag_id'",
		p + "#7: ilgisiz alan dolu 'amount'",
		p + "#8: ilgisiz alan dolu 'flag_value'",
	]))


func test_unknown_action_is_reported_without_engine_error() -> void:
	var decision: DecisionDataScript = Fixtures.make_decision("decision_a", [Fixtures.make_choice("choice_a", [], [], "missing_id")])
	var system: DecisionSystemScript = Fixtures.make_system(Fixtures.make_world(), [decision])
	assert_eq(system.get_configuration_errors(), PackedStringArray(["'decision_a' / 'choice_a': tanımsız eylem 'missing_id'"]))
	assert_eq(take_engine_errors().size(), 0)


func test_effects_on_the_same_target_are_configuration_errors() -> void:
	var effects: Array = [
		Fixtures.eff_add("res_a", 1),
		Fixtures.eff_spend("res_a", 1),
		Fixtures.eff_flag("flag_a", true),
		Fixtures.eff_flag("flag_a", false),
		Fixtures.eff_trust("actor_a", "actor_b", 1),
		Fixtures.eff_trust("actor_a", "actor_b", 2),
	]
	var decision: DecisionDataScript = Fixtures.make_decision("decision_a", [Fixtures.make_choice("choice_a", [], effects)])
	var system: DecisionSystemScript = Fixtures.make_system(Fixtures.make_world(), [decision])
	var p: String = "'decision_a' / 'choice_a' etki "
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		p + "#1: aynı hedefe birden fazla etki (#0 ile)",
		p + "#3: aynı hedefe birden fazla etki (#2 ile)",
		p + "#5: aynı hedefe birden fazla etki (#4 ile)",
	]))


func test_opposite_trust_directions_are_different_targets() -> void:
	var effects: Array = [Fixtures.eff_trust("actor_a", "actor_b", 5), Fixtures.eff_trust("actor_b", "actor_a", -5)]
	var decision: DecisionDataScript = Fixtures.make_decision("decision_a", [Fixtures.make_choice("choice_a", [], effects)])
	var world: Fixtures.World = Fixtures.make_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	Fixtures.start(world)
	assert_true(system.choose(&"decision_a", &"choice_a").ok)
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 65)
	assert_eq(world.state.get_trust(&"actor_b", &"actor_a"), 25)


func test_dependency_system_errors_are_included() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	var limits: ResourceLimitsDataScript = ResourceLimitsDataScript.new()
	limits.id = "limits_a"
	limits.min_values = {&"res_a": 5}
	limits.max_values = {&"res_a": 2}
	world.resources = ResourceSystemScript.new(world.state, limits)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"ResourceSystem: Alt sınır üst sınırdan büyük: 'res_a' (alt 5, üst 2)",
	]))


func test_configuration_errors_are_deterministic() -> void:
	var build: Callable = func() -> PackedStringArray:
		var decision: DecisionDataScript = Fixtures.make_decision("decision_a", [
			Fixtures.make_choice("choice_a", [null, Fixtures.cond_resource("missing_id", &"ge", 1)],
					[Fixtures.eff_add("res_a", -1), Fixtures.eff_spend("res_a", 1)], "missing_id"),
		])
		return Fixtures.make_system(Fixtures.make_world(), [decision]).get_configuration_errors()
	var first: PackedStringArray = build.call()
	assert_eq(first, build.call())
	assert_eq(first.size(), 5)


# --- Kullanılabilirlik ---

func test_choice_with_passing_conditions_is_available_and_preview_has_no_side_effects() -> void:
	var world: Fixtures.World = _started_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	var calls: Array[int] = _count_signals(world.state)
	var preview: DecisionResultScript = system.preview_choice(&"decision_a", &"choice_full")
	assert_true(preview.ok)
	assert_eq(preview.effect_outcomes.size(), 4)
	assert_eq(preview.time_result.applied_units, 2)
	assert_true(system.is_choice_available(&"decision_a", &"choice_full"))
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_single_failing_condition_is_reported_and_nothing_changes() -> void:
	var world: Fixtures.World = _started_world()
	var choice: Object = Fixtures.make_choice("choice_a",
			[Fixtures.cond_resource("res_a", &"ge", 1), Fixtures.cond_resource("res_b", &"gt", 0)],
			[Fixtures.eff_add("res_b", 1)], "action_a")
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [choice])])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_false(result.ok)
	assert_eq(result.failure, DecisionResultScript.FAILURE_CONDITIONS_NOT_MET)
	assert_eq(result.failed_condition_indexes, PackedInt32Array([1]))
	_assert_failed_result_is_empty(result)
	assert_eq(world.state.get_resource(&"res_b"), 0)
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_trust_condition_is_directional() -> void:
	var world: Fixtures.World = _started_world()
	var decision: Object = Fixtures.make_decision("decision_a", [
		Fixtures.make_choice("choice_a", [Fixtures.cond_trust("actor_a", "actor_b", &"ge", 50)]),
		Fixtures.make_choice("choice_b", [Fixtures.cond_trust("actor_b", "actor_a", &"ge", 50)]),
	])
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	assert_true(system.is_choice_available(&"decision_a", &"choice_a"))
	assert_false(system.is_choice_available(&"decision_a", &"choice_b"))


func test_flag_condition_treats_undefined_flag_as_false() -> void:
	var world: Fixtures.World = _started_world()
	var decision: Object = Fixtures.make_decision("decision_a", [
		Fixtures.make_choice("choice_a", [Fixtures.cond_flag("flag_z", false)]),
		Fixtures.make_choice("choice_b", [Fixtures.cond_flag("flag_z", true)]),
	])
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	assert_true(system.is_choice_available(&"decision_a", &"choice_a"))
	assert_false(system.is_choice_available(&"decision_a", &"choice_b"))


# --- Uygulama ---

func test_choose_applies_every_effect_and_time_with_one_signal() -> void:
	var world: Fixtures.World = _started_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_true(result.ok)
	assert_eq(result.failure, &"")
	assert_eq(calls[0], 1)
	assert_eq(world.state.get_resource(&"res_a"), 3)
	assert_eq(world.state.get_resource(&"res_b"), 3)
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 65)
	assert_true(world.state.get_flag(&"flag_a"))
	assert_eq(world.state.get_elapsed_units(), 2)
	assert_eq(result.time_result.applied_units, 2)
	assert_eq(_describe_outcomes(result), ["resource_spend:res_a:2:5:-2", "resource_add:res_b:3:0:3",
			"trust_change:actor_a>actor_b:5:60:5", "flag_set:flag_a:false>true"])


func test_insufficient_spend_leaves_no_partial_effect() -> void:
	var world: Fixtures.World = _started_world()
	var effects: Array = [Fixtures.eff_add("res_b", 3), Fixtures.eff_spend("res_a", 99),
			Fixtures.eff_flag("flag_a", true), Fixtures.eff_trust("actor_a", "actor_b", 5)]
	var choice: Object = Fixtures.make_choice("choice_a", [], effects, "action_a")
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [choice])])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_eq(result.failure, DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE)
	assert_eq(result.blocking_effect_index, 1)
	_assert_failed_result_is_empty(result)
	_assert_world_unchanged(world)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_clamping_is_visible_in_outcomes() -> void:
	var world: Fixtures.World = _started_world()
	var choice: Object = Fixtures.make_choice("choice_a", [], [Fixtures.eff_add("res_a", 20), Fixtures.eff_trust("actor_a", "actor_b", 100)])
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [choice])])
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_eq(_describe_outcomes(result), ["resource_add:res_a:20:5:5", "trust_change:actor_a>actor_b:100:60:40"])
	assert_eq(world.state.get_resource(&"res_a"), 10)
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 100)


func test_unknown_choice_is_a_flow_error() -> void:
	var world: Fixtures.World = _started_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	var result: DecisionResultScript = system.choose(&"decision_a", &"missing_id")
	assert_eq(result.failure, DecisionResultScript.FAILURE_UNKNOWN_CHOICE)
	_assert_one_engine_error("tanımsız karar veya seçenek")
	assert_false(system.has_choice(&"decision_a", &"missing_id"))
	assert_true(system.has_choice(&"decision_a", &"choice_full"))
	assert_eq(system.get_choice_ids(&"decision_a"), [&"choice_full"] as Array[StringName])


func test_unavailable_choice_never_falls_back_to_another_choice() -> void:
	var world: Fixtures.World = _started_world()
	var decision: Object = Fixtures.make_decision("decision_a", [
		Fixtures.make_choice("choice_a", [Fixtures.cond_flag("flag_a", true)], [Fixtures.eff_add("res_b", 1)]),
		Fixtures.make_choice("choice_b", [], [Fixtures.eff_add("res_b", 2)]),
	])
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_false(result.ok)
	assert_eq(result.choice_id, &"choice_a")
	assert_eq(world.state.get_resource(&"res_b"), 0)


func test_choice_without_effects_or_action_is_a_silent_success() -> void:
	var world: Fixtures.World = _started_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [Fixtures.make_choice("choice_a")])])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_true(result.ok)
	assert_eq(result.time_result, null)
	assert_eq(calls[0], 0)


# --- Güven yaşam döngüsü ve yapılandırma ---

func test_trust_free_choice_works_before_trust_is_initialized() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.time.start_night()
	var choice: Object = Fixtures.make_choice("choice_a", [Fixtures.cond_resource("res_a", &"ge", 1)],
			[Fixtures.eff_spend("res_a", 1), Fixtures.eff_flag("flag_a", true)], "action_a")
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [choice])])
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_true(result.ok)
	assert_eq(world.state.get_resource(&"res_a"), 4)
	assert_false(world.trust.is_initialized())
	assert_eq(take_engine_errors().size(), 0)


func test_trust_choice_before_initialization_is_system_not_ready() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.time.start_night()
	var decision: Object = Fixtures.make_decision("decision_a", [
		Fixtures.make_choice("choice_a", [Fixtures.cond_trust("actor_a", "actor_b", &"ge", 10)], [Fixtures.eff_add("res_b", 1)]),
		Fixtures.make_choice("choice_b", [], [Fixtures.eff_add("res_b", 1), Fixtures.eff_trust("actor_a", "actor_b", 5)]),
	])
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	var calls: Array[int] = _count_signals(world.state)
	for choice_id in [&"choice_a", &"choice_b"]:
		var result: DecisionResultScript = system.choose(&"decision_a", choice_id)
		assert_eq(result.failure, DecisionResultScript.FAILURE_SYSTEM_NOT_READY)
		_assert_failed_result_is_empty(result)
		_assert_one_engine_error("güven başlatılmadı")
	assert_eq(world.state.get_resource(&"res_b"), 0)
	assert_eq(world.state.get_trust_snapshot().size(), 0)
	assert_eq(calls[0], 0)


func test_invalid_configuration_blocks_preview_and_choose() -> void:
	var world: Fixtures.World = _started_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [])])
	assert_eq(system.preview_choice(&"decision_a", &"choice_a").failure, DecisionResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(system.choose(&"decision_a", &"choice_a").failure, DecisionResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("geçersiz yapılandırma")


func test_partial_trust_state_is_invalid_configuration() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.time.start_night()
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	world.state.set_trust_state(partial)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	assert_eq(system.choose(&"decision_a", &"choice_full").failure, DecisionResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("Durumda eksik güven ilişkisi")


# --- Zaman ---

func test_action_in_inactive_night_is_time_unavailable_without_changes() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.trust.initialize_relationships()
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_eq(result.failure, DecisionResultScript.FAILURE_TIME_UNAVAILABLE)
	_assert_failed_result_is_empty(result)
	assert_eq(world.state.get_resource(&"res_a"), 5)
	assert_false(world.state.get_flag(&"flag_a"))
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_zero_cost_action_requires_an_active_night() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	world.trust.initialize_relationships()
	var choice: Object = Fixtures.make_choice("choice_a", [], [Fixtures.eff_add("res_b", 1)], "action_b")
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [choice])])
	assert_eq(system.choose(&"decision_a", &"choice_a").failure, DecisionResultScript.FAILURE_TIME_UNAVAILABLE)
	world.time.start_night()
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_true(result.ok)
	assert_eq(result.time_result.applied_units, 0)
	assert_eq(world.state.get_elapsed_units(), 0)
	assert_eq(world.state.get_resource(&"res_b"), 1)


func test_action_time_advances_tasks_in_the_same_write() -> void:
	var world: Fixtures.World = _started_world()
	world.time.start_task(&"task_a", &"actor_b", 2)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()], [Fixtures.make_task_definition("task_a")])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_eq(result.time_result.completed_task_ids(), [&"task_a"] as Array[StringName])
	assert_eq(world.state.get_tasks_snapshot().size(), 0)
	assert_eq(calls[0], 1)


# --- Görev tamamlanma etkileri (K-027) ---

func test_tasks_completing_during_the_action_apply_their_effects_in_the_same_write() -> void:
	var world: Fixtures.World = _started_world()
	world.time.start_task(&"task_a", &"actor_b", 2)
	var definition: Object = Fixtures.make_task_definition("task_a", [Fixtures.eff_add("res_a", 4), Fixtures.eff_flag("flag_b", true)])
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()], [definition])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_true(result.ok)
	assert_eq(result.task_completions.size(), 1)
	var completion: TaskCompletionOutcomeScript = result.task_completions[0]
	assert_eq([completion.task_id, completion.status], [&"task_a", TaskCompletionOutcomeScript.STATUS_APPLIED])
	# Seçim res_a'yı 5→3 yaptı; tamamlanma etkisi biriken değer olan 3'ten başlar.
	assert_eq([completion.effect_outcomes[0].previous, completion.effect_outcomes[0].applied], [3, 4])
	assert_eq(world.state.get_resource(&"res_a"), 7)
	assert_true(world.state.get_flag(&"flag_b"))
	assert_eq(world.state.get_tasks_snapshot().size(), 0)
	assert_eq(calls[0], 1)


func test_choice_effects_come_before_completion_effects() -> void:
	# Seçim res_a'yı 5→10 yapar; tamamlanma 8 harcar → 2. Ters sırada harcama yetersiz kalırdı.
	var world: Fixtures.World = _started_world()
	world.time.start_task(&"task_a", &"actor_b", 2)
	var choice: Object = Fixtures.make_choice("choice_a", [], [Fixtures.eff_add("res_a", 5)], "action_a")
	var system: DecisionSystemScript = Fixtures.make_system(world, [Fixtures.make_decision("decision_a", [choice])],
			[Fixtures.make_task_definition("task_a", [Fixtures.eff_spend("res_a", 8)])])
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_eq(result.task_completions[0].status, TaskCompletionOutcomeScript.STATUS_APPLIED)
	assert_eq(world.state.get_resource(&"res_a"), 2)


func test_insufficient_completion_spend_does_not_block_the_choice() -> void:
	var world: Fixtures.World = _started_world()
	world.time.start_task(&"task_a", &"actor_b", 2)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()],
			[Fixtures.make_task_definition("task_a", [Fixtures.eff_flag("flag_b", true), Fixtures.eff_spend("res_b", 99)])])
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_true(result.ok)
	assert_eq(result.task_completions[0].status, TaskCompletionOutcomeScript.STATUS_EFFECTS_NOT_APPLICABLE)
	assert_eq(result.task_completions[0].blocking_effect_index, 1)
	assert_false(world.state.get_flag(&"flag_b"))
	assert_eq(world.state.get_resource(&"res_b"), 3)
	assert_eq(world.state.get_tasks_snapshot().size(), 0)
	assert_eq(take_engine_errors().size(), 0)


func test_failed_write_with_completions_changes_nothing() -> void:
	var world: Fixtures.World = Fixtures.make_world(RejectingGameState.new(Fixtures.make_state_setup()))
	Fixtures.start(world)
	world.time.start_task(&"task_a", &"actor_b", 2)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()],
			[Fixtures.make_task_definition("task_a", [Fixtures.eff_add("res_a", 4), Fixtures.eff_trust("actor_b", "actor_a", 5),
			Fixtures.eff_flag("flag_b", true)])])
	var calls: Array[int] = _count_signals(world.state)
	(world.state as RejectingGameState).reject_changes = true
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_eq(result.failure, DecisionResultScript.FAILURE_WRITE_FAILED)
	assert_eq(result.task_completions.size(), 0)
	assert_eq(take_engine_errors().size(), 2)
	_assert_world_unchanged(world)
	assert_eq(world.state.get_trust(&"actor_b", &"actor_a"), 30)
	assert_false(world.state.get_flag(&"flag_b"))
	assert_eq(world.state.get_tasks_snapshot().size(), 1)
	assert_eq(calls[0], 0)


func test_undefined_active_task_blocks_the_choice_as_invalid_configuration() -> void:
	var world: Fixtures.World = _started_world()
	world.time.start_task(&"task_x", &"actor_b", 2)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_eq(result.failure, DecisionResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("Etkin görevin tanımı yok: 'task_x'")
	_assert_world_unchanged(world)
	assert_eq(world.state.get_tasks_snapshot().size(), 1)
	assert_eq(calls[0], 0)


# --- Atomiklik ---

func test_failed_write_changes_no_category() -> void:
	var world: Fixtures.World = Fixtures.make_world(RejectingGameState.new(Fixtures.make_state_setup()))
	Fixtures.start(world)
	world.time.start_task(&"task_a", &"actor_b", 2)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()], [Fixtures.make_task_definition("task_a")])
	var calls: Array[int] = _count_signals(world.state)
	(world.state as RejectingGameState).reject_changes = true
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_eq(result.failure, DecisionResultScript.FAILURE_WRITE_FAILED)
	_assert_failed_result_is_empty(result)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_true(errors.size() == 2 and errors[0].contains("test: yazma reddedildi"), " | ".join(errors))
	assert_true(errors.size() == 2 and errors[1].contains("durum yazılamadı"), " | ".join(errors))
	_assert_world_unchanged(world)
	assert_eq(world.state.get_tasks_snapshot().size(), 1)
	assert_eq(calls[0], 0)


func test_atomic_choice_uses_exactly_one_write_and_at_most_one_signal() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_state_setup())
	var world: Fixtures.World = Fixtures.make_world(state)
	Fixtures.start(world)
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	state.apply_calls = 0
	state.other_writes = 0
	var calls: Array[int] = _count_signals(state)
	system.preview_choice(&"decision_a", &"choice_full")
	assert_eq(state.apply_calls, 0)
	assert_true(system.choose(&"decision_a", &"choice_full").ok)
	assert_eq(state.apply_calls, 1)
	assert_eq(state.other_writes, 0)
	assert_eq(calls[0], 1)


# --- Kopyalama, önizleme bağımsızlığı, determinizm ---

func test_mutated_preview_cannot_affect_choose() -> void:
	var world: Fixtures.World = _started_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	var preview: DecisionResultScript = system.preview_choice(&"decision_a", &"choice_full")
	preview.ok = false
	preview.failure = DecisionResultScript.FAILURE_WRITE_FAILED
	preview.effect_outcomes[0].applied = -99
	preview.effect_outcomes.clear()
	preview.time_result.applied_units = 9
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	assert_true(result.ok)
	assert_eq(result.effect_outcomes.size(), 4)
	assert_eq(world.state.get_resource(&"res_a"), 3)
	assert_eq(world.state.get_elapsed_units(), 2)


func test_decision_data_is_copied_on_creation() -> void:
	var world: Fixtures.World = _started_world()
	var decision: DecisionDataScript = _full_decision()
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	decision.id = "decision_z"
	decision.choices[0].id = "choice_z"
	decision.choices[0].action_id = "missing_id"
	decision.choices[0].conditions[0].value = 99
	decision.choices[0].effects[0].amount = 99
	decision.choices[0].effects.append(null)
	decision.choices.append(null)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_true(system.choose(&"decision_a", &"choice_full").ok)
	assert_eq(world.state.get_resource(&"res_a"), 3)


func test_mutating_a_result_does_not_affect_state() -> void:
	var world: Fixtures.World = _started_world()
	var system: DecisionSystemScript = Fixtures.make_system(world, [_full_decision()])
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_full")
	result.effect_outcomes[0].previous = 99
	result.time_result.occurrences.clear()
	assert_eq(world.state.get_resource(&"res_a"), 3)
	assert_eq(world.state.get_elapsed_units(), 2)


func test_same_start_and_same_choices_produce_same_results() -> void:
	assert_eq(_run_reference_sequence(), _run_reference_sequence())


# --- Öneri doğruluğu (K-021, K-023) ---

func test_high_trust_does_not_make_an_information_condition_true() -> void:
	# Güven en yüksekken bile bilgiye (bayrağa) bağlı koşul yanlışsa seçenek kullanılamaz;
	# güven en düşükken bilgi doğruysa kullanılabilir. Doğruluk güvenden bağımsızdır.
	var world: Fixtures.World = _started_world()
	var decision: Object = Fixtures.make_decision("decision_a", [
		Fixtures.make_choice("choice_info", [Fixtures.cond_flag("flag_a", true)]),
		Fixtures.make_choice("choice_raise", [], [Fixtures.eff_trust("actor_a", "actor_b", 100)]),
		Fixtures.make_choice("choice_lower", [], [Fixtures.eff_trust("actor_a", "actor_b", -100)]),
		Fixtures.make_choice("choice_learn", [], [Fixtures.eff_flag("flag_a", true)]),
	])
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	system.choose(&"decision_a", &"choice_raise")
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 100)
	assert_false(system.is_choice_available(&"decision_a", &"choice_info"))
	system.choose(&"decision_a", &"choice_lower")
	system.choose(&"decision_a", &"choice_learn")
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 0)
	assert_true(system.is_choice_available(&"decision_a", &"choice_info"))


# --- Yardımcılar ---

func _started_world() -> Fixtures.World:
	var world: Fixtures.World = Fixtures.make_world()
	Fixtures.start(world)
	return world


## Dört kategoriye dokunan tek seçenekli karar: res_a ≥ 1 ve a→b güveni ≥ 50 ise
## res_a −2, res_b +3, a→b +5, flag_a = true ve action_a (2 birim).
func _full_decision() -> DecisionDataScript:
	return Fixtures.make_decision("decision_a", [
		Fixtures.make_choice("choice_full",
				[Fixtures.cond_resource("res_a", &"ge", 1), Fixtures.cond_trust("actor_a", "actor_b", &"ge", 50)],
				[Fixtures.eff_spend("res_a", 2), Fixtures.eff_add("res_b", 3),
				Fixtures.eff_trust("actor_a", "actor_b", 5), Fixtures.eff_flag("flag_a", true)],
				"action_a"),
	])


func _run_reference_sequence() -> Array:
	var world: Fixtures.World = _started_world()
	var decision: Object = Fixtures.make_decision("decision_a", [
		Fixtures.make_choice("choice_a", [Fixtures.cond_resource("res_a", &"ge", 2)],
				[Fixtures.eff_spend("res_a", 2), Fixtures.eff_trust("actor_b", "actor_a", 7)], "action_a"),
		Fixtures.make_choice("choice_b", [], [Fixtures.eff_add("res_a", 4), Fixtures.eff_flag("flag_b", true)], "action_b"),
	])
	var system: DecisionSystemScript = Fixtures.make_system(world, [decision])
	var observed: Array = []
	for choice_id in [&"choice_a", &"choice_a", &"choice_a", &"choice_b", &"choice_a"]:
		var result: DecisionResultScript = system.choose(&"decision_a", choice_id)
		observed.append([result.ok, result.failure, _describe_outcomes(result)])
	observed.append([world.state.get_resources_snapshot(), world.state.get_flags_snapshot(),
			world.state.get_trust(&"actor_b", &"actor_a"), world.state.get_elapsed_units()])
	return observed


func _describe_outcomes(result: DecisionResultScript) -> Array:
	var lines: Array = []
	for outcome in result.effect_outcomes:
		match outcome.kind:
			&"flag_set":
				lines.append("%s:%s:%s>%s" % [outcome.kind, outcome.flag_id, outcome.previous_flag, outcome.flag_value])
			&"trust_change":
				lines.append("%s:%s>%s:%d:%d:%d" % [outcome.kind, outcome.source_actor_id, outcome.target_actor_id,
						outcome.requested, outcome.previous, outcome.applied])
			_:
				lines.append("%s:%s:%d:%d:%d" % [outcome.kind, outcome.resource_id, outcome.requested,
						outcome.previous, outcome.applied])
	return lines


func _assert_failed_result_is_empty(result: DecisionResultScript) -> void:
	assert_false(result.ok)
	assert_eq(result.effect_outcomes.size(), 0)
	assert_eq(result.time_result, null)


# Başlatılmış dünyanın ilk değerleri: res_a 5, res_b 0, flag_a yok, a→b 60, gece 1 / süre 0.
func _assert_world_unchanged(world: Fixtures.World) -> void:
	assert_eq(world.state.get_resources_snapshot(), {&"res_a": 5, &"res_b": 0})
	assert_false(world.state.get_flag(&"flag_a"))
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq([world.state.get_night(), world.state.get_elapsed_units()], [1, 0])


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
