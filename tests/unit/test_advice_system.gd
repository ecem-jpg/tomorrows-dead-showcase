extends "res://tests/framework/test_case.gd"
## AdviceSystem birim ve senaryo testleri (K-028). Yalnızca tarafsız kimlikler kullanılır (K-018).
## Dünya: res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30 (0..100); zaman 2 gece × 10 birim,
## action_a = 2. Varsayılan karar: decision_a → choice_a, choice_b. Bilgi bayrakları: information_a, information_b.

const Fixtures := preload("res://tests/fixtures/advice_fixtures.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const TaskFixtures := preload("res://tests/fixtures/task_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const AdviceDataScript := preload("res://scripts/data/advice_data.gd")
const AdviceVariantDataScript := preload("res://scripts/data/advice_variant_data.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const AdviceSystemScript := preload("res://scripts/systems/advice_system.gd")
const AdviceResultScript := preload("res://scripts/systems/advice_result.gd")
const AdviceEvaluationScript := preload("res://scripts/systems/advice_evaluation.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")

const FIXTURE_PATH: String = "res://tests/fixtures/advice/advice_a.tres"
const CORRECT: StringName = AdviceVariantDataScript.ACCURACY_CORRECT
const INCOMPLETE: StringName = AdviceVariantDataScript.ACCURACY_INCOMPLETE
const INCORRECT: StringName = AdviceVariantDataScript.ACCURACY_INCORRECT


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), [_advice_a(_presentation())])
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_true(system.has_advice(&"advice_a"))
	assert_false(system.has_advice(&"missing_id"))


func test_fixture_file_builds_a_valid_system() -> void:
	var advice: AdviceDataScript = ResourceLoader.load(FIXTURE_PATH) as AdviceDataScript
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), [advice])
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_configuration_reports_advice_level_errors_in_order() -> void:
	var missing_context: AdviceDataScript = Fixtures.make_advice("advice_x", "actor_b", "actor_a", "", [])
	missing_context.context = null
	var advices: Array = [
		null,
		Fixtures.make_advice("", "actor_b", "actor_a", "", [_fallback()]),
		missing_context,
		Fixtures.make_advice("advice_y", "actor_b", "actor_a", "", [_fallback()]),
		Fixtures.make_advice("advice_y", "actor_b", "actor_a", "", [_fallback()]),
	]
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), advices)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız öneri kaydı (#0)",
		"Boş öneri kimliği (#1)",
		"'advice_x': eksik bağlam",
		"'advice_x': öneride biçim yok",
		"Tekrarlanan öneri kimliği: 'advice_y'",
	]))


func test_configuration_reports_context_errors_in_order() -> void:
	var advices: Array = [
		Fixtures.make_advice("advice_a", "", "", "", [_fallback()]),
		Fixtures.make_advice("advice_b", "actor_a", "actor_a", "", [_fallback()]),
		Fixtures.make_advice("advice_c", "actor_b", "actor_a", "missing_id", [_fallback()]),
	]
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), advices)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"'advice_a' bağlam: eksik alan 'advisor_actor_id'",
		"'advice_a' bağlam: eksik alan 'recipient_actor_id'",
		"'advice_b' bağlam: kendine öneri 'actor_a'",
		"'advice_c' bağlam: tanımsız karar 'missing_id'",
	]))
	assert_eq(take_engine_errors().size(), 0)


func test_configuration_reports_variant_errors_in_order() -> void:
	var info: Callable = func() -> Object: return DecisionFixtures.cond_flag("information_a", true)
	var advices: Array = [
		Fixtures.make_advice("advice_a", "actor_b", "actor_a", "decision_a", [
			null,
			Fixtures.make_variant("", CORRECT, [info.call()]),
			Fixtures.make_variant("variant_a", &"", [info.call()]),
			Fixtures.make_variant("variant_a", &"certain", [info.call()]),
			Fixtures.make_variant("variant_b", CORRECT, [DecisionFixtures.make_condition(&"flag")], "missing_id"),
		]),
		Fixtures.make_advice("advice_b", "actor_b", "actor_a", "", [Fixtures.make_variant("variant_a", INCORRECT, [], "choice_a")]),
	]
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), advices)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"'advice_a' biçim #0: tanımsız kayıt",
		"'advice_a' biçim #1: boş biçim kimliği",
		"'advice_a' biçim #2: eksik alan 'accuracy'",
		"'advice_a' biçim #3: tekrarlanan biçim kimliği 'variant_a'",
		"'advice_a' biçim #3: tanımsız doğruluk sınıfı 'certain'",
		"'advice_a' biçim #4: koşul #0: eksik alan 'flag_id'",
		"'advice_a' biçim #4: tanımsız seçenek 'missing_id'",
		"'advice_b' biçim #0: karar yokken önerilen seçenek 'choice_a'",
	]))


func test_trust_is_forbidden_in_variant_conditions_but_allowed_in_presentation() -> void:
	var trust: Callable = func() -> Object: return DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 20)
	var advices: Array = [
		Fixtures.make_advice("advice_a", "actor_b", "actor_a", "", [
			Fixtures.make_variant("variant_a", CORRECT, [trust.call(), DecisionFixtures.cond_flag("information_a", true)]),
		]),
		Fixtures.make_advice("advice_b", "actor_b", "actor_a", "", [_fallback()], [trust.call()]),
	]
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), advices)
	assert_eq(system.get_configuration_errors(), PackedStringArray(["'advice_a' biçim #0: biçim koşulunda güven kullanılamaz"]))


func test_unconditional_variant_is_optional() -> void:
	var advice: AdviceDataScript = Fixtures.make_advice("advice_a", "actor_b", "actor_a", "", [
		Fixtures.make_variant("variant_a", CORRECT, [DecisionFixtures.cond_flag("information_a", true)]),
		Fixtures.make_variant("variant_b", INCORRECT, [DecisionFixtures.cond_flag("information_a", false)]),
	])
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), [advice])
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_more_than_one_unconditional_variant_is_a_configuration_error() -> void:
	var advice: AdviceDataScript = Fixtures.make_advice("advice_a", "actor_b", "actor_a", "", [
		Fixtures.make_variant("variant_a", CORRECT, [DecisionFixtures.cond_flag("information_a", true)]),
		Fixtures.make_variant("variant_b", INCOMPLETE),
		Fixtures.make_variant("variant_c", INCORRECT),
	])
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), [advice])
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"'advice_a' biçim #1: koşulsuz biçim son biçim olmalı",
		"'advice_a' biçim #2: birden fazla koşulsuz biçim (#1 ile)",
	]))


func test_unconditional_variant_must_be_the_last_variant() -> void:
	var advice: AdviceDataScript = Fixtures.make_advice("advice_a", "actor_b", "actor_a", "", [
		Fixtures.make_variant("variant_a", INCORRECT),
		Fixtures.make_variant("variant_b", CORRECT, [DecisionFixtures.cond_flag("information_a", true)]),
	])
	var system: AdviceSystemScript = Fixtures.make_system(DecisionFixtures.make_world(), [advice])
	assert_eq(system.get_configuration_errors(), PackedStringArray(["'advice_a' biçim #0: koşulsuz biçim son biçim olmalı"]))


func test_condition_errors_match_the_decision_system_messages() -> void:
	var make_conditions: Callable = func() -> Array:
		return [null, DecisionFixtures.cond_resource("missing_id", &"ge", 1),
				DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 150), DecisionFixtures.make_condition(&"flag")]
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var advice_errors: PackedStringArray = Fixtures.make_system(world, [
		Fixtures.make_advice("advice_a", "actor_b", "actor_a", "", [_fallback()], make_conditions.call()),
	]).get_configuration_errors()
	var decision: Object = DecisionFixtures.make_decision("decision_a", [DecisionFixtures.make_choice("choice_a", make_conditions.call())])
	var decision_errors: PackedStringArray = DecisionFixtures.make_system(world, [decision]).get_configuration_errors()
	assert_eq(advice_errors.size(), 4)
	assert_eq(_strip(advice_errors, "'advice_a' sunulma koşulu "), _strip(decision_errors, "'decision_a' / 'choice_a' koşul "))


func test_trust_errors_are_included_but_decision_system_errors_are_not() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	world.time.start_night()
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	world.state.set_trust_state(partial)
	var broken_decisions: DecisionSystemScript = DecisionFixtures.make_system(world, [
		DecisionFixtures.make_decision("decision_a", [DecisionFixtures.make_choice("choice_a")]),
		DecisionFixtures.make_decision("decision_z", []),
	])
	assert_false(broken_decisions.get_configuration_errors().is_empty())
	var system: AdviceSystemScript = Fixtures.make_system(world, [
		Fixtures.make_advice("advice_a", "actor_b", "actor_a", "decision_a", [Fixtures.make_variant("variant_a", INCORRECT, [], "choice_a")]),
	], broken_decisions)
	var errors: PackedStringArray = system.get_configuration_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].begins_with("TrustSystem: ") and errors[0].contains("eksik güven ilişkisi"),
			" | ".join(errors))


func test_configuration_errors_are_deterministic() -> void:
	var build: Callable = func() -> PackedStringArray:
		var advices: Array = [null, Fixtures.make_advice("advice_a", "actor_a", "actor_a", "missing_id", [
			Fixtures.make_variant("variant_a", &"", [DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 1)]),
			Fixtures.make_variant("variant_b", INCORRECT),
			Fixtures.make_variant("variant_c", INCORRECT),
		])]
		return Fixtures.make_system(DecisionFixtures.make_world(), advices).get_configuration_errors()
	var first: PackedStringArray = build.call()
	assert_eq(first, build.call())
	assert_eq(first.size(), 7)


func test_advice_data_is_copied_on_creation() -> void:
	var world: DecisionFixtures.World = _started_world()
	var advice: AdviceDataScript = _advice_a(_presentation())
	var system: AdviceSystemScript = Fixtures.make_system(world, [advice])
	advice.id = "advice_z"
	advice.context.advisor_actor_id = "actor_a"
	advice.presentation_conditions[0].value = 99
	advice.variants[2].accuracy = CORRECT
	advice.variants[2].recommended_choice_id = "choice_a"
	advice.variants.append(null)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq([evaluation.result.status, evaluation.result.advisor_actor_id, evaluation.result.recommended_choice_id,
			evaluation.accuracy], [AdviceResultScript.STATUS_OFFERED, &"actor_b", &"choice_b", INCORRECT])


# --- Değerlendirme ---

func test_first_matching_variant_in_data_order_wins() -> void:
	var world: DecisionFixtures.World = _started_world()
	_learn(world, ["information_a", "information_b"])
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a()])
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	# variant_b'nin koşulu da sağlanıyor; veri sırasında önce gelen variant_a seçilir.
	assert_eq([evaluation.variant_id, evaluation.accuracy, evaluation.result.recommended_choice_id],
			[&"variant_a", CORRECT, &"choice_a"])


func test_unconditional_variant_is_the_fallback() -> void:
	var system: AdviceSystemScript = Fixtures.make_system(_started_world(), [_advice_a()])
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq([evaluation.variant_id, evaluation.accuracy], [&"variant_c", INCORRECT])


func test_no_matching_variant_is_a_normal_result() -> void:
	var advice: AdviceDataScript = Fixtures.make_advice("advice_a", "actor_b", "actor_a", "decision_a", [
		Fixtures.make_variant("variant_a", CORRECT, [DecisionFixtures.cond_flag("information_a", true)], "choice_a"),
	])
	var system: AdviceSystemScript = Fixtures.make_system(_started_world(), [advice])
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq(evaluation.result.status, AdviceResultScript.STATUS_NO_APPLICABLE_VARIANT)
	assert_false(evaluation.result.is_offered() or evaluation.result.is_failed())
	assert_eq([evaluation.result.failure, evaluation.result.recommended_choice_id, evaluation.variant_id, evaluation.accuracy],
			[&"", &"", &"", &""])
	assert_eq(take_engine_errors().size(), 0)


func test_failed_presentation_condition_is_not_offered() -> void:
	var world: DecisionFixtures.World = _started_world()
	_learn(world, ["information_a", "information_b"])
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a([DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 50)])])
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq(evaluation.result.status, AdviceResultScript.STATUS_NOT_OFFERED)
	assert_eq([evaluation.result.advisor_actor_id, evaluation.result.decision_id], [&"actor_b", &"decision_a"])
	assert_eq([evaluation.result.recommended_choice_id, evaluation.variant_id, evaluation.accuracy], [&"", &"", &""])
	assert_eq(take_engine_errors().size(), 0)


func test_information_flags_select_correct_incomplete_and_incorrect() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())])
	var observed: Array = [_describe(system.evaluate(&"advice_a"))]
	_learn(world, ["information_a"])
	observed.append(_describe(system.evaluate(&"advice_a")))
	_learn(world, ["information_b"])
	observed.append(_describe(system.evaluate(&"advice_a")))
	assert_eq(observed, [
		[&"offered", &"", &"choice_b", &"variant_c", INCORRECT],
		[&"offered", &"", &"", &"variant_b", INCOMPLETE],
		[&"offered", &"", &"choice_a", &"variant_a", CORRECT],
	])


func test_advice_result_never_exposes_accuracy_or_variant() -> void:
	var names: Array[String] = []
	for property in AdviceResultScript.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_false(names.has("accuracy"), str(names))
	assert_false(names.has("variant_id"), str(names))
	assert_eq(names, ["status", "failure", "advice_id", "advisor_actor_id", "recipient_actor_id", "decision_id",
			"recommended_choice_id"] as Array[String])
	var system: AdviceSystemScript = Fixtures.make_system(_started_world(), [_advice_a()])
	assert_true(system.get_advice(&"advice_a").get_script() == AdviceResultScript)


func test_evaluate_returns_the_hidden_classification_with_the_same_result() -> void:
	var world: DecisionFixtures.World = _started_world()
	_learn(world, ["information_a"])
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())])
	var advice: AdviceResultScript = system.get_advice(&"advice_a")
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq(_describe_result(evaluation.result), _describe_result(advice))
	assert_eq([evaluation.variant_id, evaluation.accuracy], [&"variant_b", INCOMPLETE])
	assert_true(evaluation.result != advice)


func test_unknown_advice_is_a_flow_error() -> void:
	var system: AdviceSystemScript = Fixtures.make_system(_started_world(), [_advice_a()])
	var result: AdviceResultScript = system.get_advice(&"missing_id")
	assert_eq([result.status, result.failure, result.advice_id], [&"", AdviceResultScript.FAILURE_UNKNOWN_ADVICE, &"missing_id"])
	assert_true(result.is_failed())
	_assert_one_engine_error("tanımsız öneri")


func test_invalid_configuration_blocks_get_advice_and_evaluate() -> void:
	var system: AdviceSystemScript = Fixtures.make_system(_started_world(), [
		Fixtures.make_advice("advice_a", "actor_b", "actor_a", "", []),
	])
	assert_eq(system.get_advice(&"advice_a").failure, AdviceResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("geçersiz yapılandırma")
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq(evaluation.result.failure, AdviceResultScript.FAILURE_INVALID_CONFIGURATION)
	assert_eq([evaluation.variant_id, evaluation.accuracy], [&"", &""])
	_assert_one_engine_error("geçersiz yapılandırma")


func test_trust_presentation_before_initialization_is_system_not_ready() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())])
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq(evaluation.result.failure, AdviceResultScript.FAILURE_SYSTEM_NOT_READY)
	assert_eq([evaluation.result.status, evaluation.variant_id, evaluation.accuracy], [&"", &"", &""])
	_assert_one_engine_error("güven başlatılmadı")


func test_trust_free_advice_works_before_trust_is_initialized() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a()])
	assert_true(system.get_advice(&"advice_a").is_offered())
	assert_false(world.trust.is_initialized())
	assert_eq(take_engine_errors().size(), 0)


func test_partial_trust_state_is_invalid_configuration() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	world.state.set_trust_state(partial)
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a()])
	assert_eq(system.get_advice(&"advice_a").failure, AdviceResultScript.FAILURE_INVALID_CONFIGURATION)
	_assert_one_engine_error("eksik güven ilişkisi")


# --- Salt okunurluk ve determinizm ---

func test_advice_never_writes_state() -> void:
	var state: CountingGameState = CountingGameState.new(DecisionFixtures.make_state_setup())
	var world: DecisionFixtures.World = DecisionFixtures.make_world(state)
	DecisionFixtures.start(world)
	_learn(world, ["information_a"])
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())])
	var before: Array = _snapshot(world.state)
	state.apply_calls = 0
	state.other_writes = 0
	var calls: Array[int] = _count_signals(world.state)
	for i in 3:
		system.get_advice(&"advice_a")
		system.evaluate(&"advice_a")
	system.get_configuration_errors()
	assert_eq([state.apply_calls, state.other_writes, calls[0]], [0, 0, 0])
	assert_eq(_snapshot(world.state), before)


func test_mutating_a_result_does_not_affect_later_calls() -> void:
	var system: AdviceSystemScript = Fixtures.make_system(_started_world(), [_advice_a()])
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	evaluation.accuracy = CORRECT
	evaluation.variant_id = &"variant_a"
	evaluation.result.recommended_choice_id = &"choice_a"
	evaluation.result.status = AdviceResultScript.STATUS_NOT_OFFERED
	var advice: AdviceResultScript = system.get_advice(&"advice_a")
	advice.recommended_choice_id = &"choice_a"
	assert_eq(_describe(system.evaluate(&"advice_a")), [&"offered", &"", &"choice_b", &"variant_c", INCORRECT])


func test_same_start_and_same_actions_produce_same_advice() -> void:
	assert_eq(_run_reference_sequence(), _run_reference_sequence())


# --- Güven ilkeleri (K-021, K-023) ---

func test_high_trust_does_not_make_advice_correct() -> void:
	var world: DecisionFixtures.World = _started_world()
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())])
	world.trust.change_trust(&"actor_b", &"actor_a", 100)
	assert_eq(world.state.get_trust(&"actor_b", &"actor_a"), 100)
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_true(evaluation.result.is_offered())
	assert_eq(evaluation.accuracy, INCORRECT)


func test_low_trust_with_information_gives_correct_advice() -> void:
	var world: DecisionFixtures.World = _started_world()
	_learn(world, ["information_a", "information_b"])
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a()])
	world.trust.change_trust(&"actor_b", &"actor_a", -100)
	assert_eq(world.state.get_trust(&"actor_b", &"actor_a"), 0)
	assert_eq(system.evaluate(&"advice_a").accuracy, CORRECT)


func test_trust_changes_only_whether_advice_is_offered() -> void:
	var world: DecisionFixtures.World = _started_world()
	_learn(world, ["information_a"])
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())])
	var observed: Array = [[world.state.get_trust(&"actor_b", &"actor_a"), _describe(system.evaluate(&"advice_a"))]]
	for delta in [70, -60, -40]:
		world.trust.change_trust(&"actor_b", &"actor_a", delta)
		observed.append([world.state.get_trust(&"actor_b", &"actor_a"), _describe(system.evaluate(&"advice_a"))])
	assert_eq(observed, [
		[30, [&"offered", &"", &"", &"variant_b", INCOMPLETE]],
		[100, [&"offered", &"", &"", &"variant_b", INCOMPLETE]],
		[40, [&"offered", &"", &"", &"variant_b", INCOMPLETE]],
		[0, [&"not_offered", &"", &"", &"", &""]],
	])


# --- Oyuncu seçimi (K-021) ---

func test_advice_never_changes_the_players_choice() -> void:
	var world: DecisionFixtures.World = _started_world()
	var decisions: DecisionSystemScript = _effectful_decisions(world)
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a()], decisions)
	assert_eq(system.get_advice(&"advice_a").recommended_choice_id, &"choice_b")
	var result: DecisionResultScript = decisions.choose(&"decision_a", &"choice_a")
	assert_true(result.ok)
	assert_eq(result.choice_id, &"choice_a")
	assert_eq(world.state.get_resource(&"res_b"), 1)


func test_decision_results_are_identical_with_or_without_advice() -> void:
	assert_eq(_run_decisions(false), _run_decisions(true))


# --- Uçtan uca senaryo ---

func test_scenario_advice_follows_information_while_the_player_decides() -> void:
	assert_eq(_run_scenario(), _run_scenario())


# --- Yardımcılar ---

func _run_scenario() -> Array:
	var world: DecisionFixtures.World = _started_world()
	var task_a: TaskDataScript = TaskFixtures.make_task("task_a", 2, "actor_a", "actor_b", [], "",
			[DecisionFixtures.eff_flag("information_a", true)])
	var completions: TaskCompletionSystemScript = DecisionFixtures.make_completion_system(world, [task_a])
	var tasks: TaskSystemScript = TaskFixtures.make_system_with(world, [task_a], completions)
	var decision_data: Array[DecisionDataScript] = [
		DecisionFixtures.make_decision("decision_a", [
			DecisionFixtures.make_choice("choice_a", [], [DecisionFixtures.eff_add("res_b", 1)]),
			DecisionFixtures.make_choice("choice_b", [], [DecisionFixtures.eff_add("res_b", 2)]),
		]),
		DecisionFixtures.make_decision("decision_b", [
			DecisionFixtures.make_choice("choice_wait", [], [], "action_a"),
			DecisionFixtures.make_choice("choice_learn", [], [DecisionFixtures.eff_flag("information_b", true)]),
		]),
	]
	var decisions: DecisionSystemScript = DecisionSystemScript.new(world.state, world.resources, world.trust, world.time,
			completions, decision_data)
	var advice: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())], decisions)
	assert_eq(advice.get_configuration_errors(), PackedStringArray())
	var observed: Array = []

	# 1. Bilgi yokken öneri yedek biçimdir (gizli: hatalı) ve choice_b'yi gösterir.
	observed.append(_describe(advice.evaluate(&"advice_a")))
	assert_eq(observed[-1], [&"offered", &"", &"choice_b", &"variant_c", INCORRECT])
	# 2. Oyuncu choice_a'yı seçer; seçim olduğu gibi uygulanır.
	assert_eq(decisions.choose(&"decision_a", &"choice_a").choice_id, &"choice_a")
	assert_eq(world.state.get_resource(&"res_b"), 1)
	# 3. Görev tamamlanınca information_a öğrenilir; öneri eksik olur ve seçenek göstermez.
	assert_true(tasks.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())
	assert_eq(decisions.choose(&"decision_b", &"choice_wait").task_completions.size(), 1)
	assert_true(world.state.get_flag(&"information_a"))
	observed.append(_describe(advice.evaluate(&"advice_a")))
	assert_eq(observed[-1], [&"offered", &"", &"", &"variant_b", INCOMPLETE])
	# 4. Bir karar etkisiyle information_b öğrenilir; öneri doğru olur ve choice_a'yı gösterir.
	assert_true(decisions.choose(&"decision_b", &"choice_learn").ok)
	observed.append(_describe(advice.evaluate(&"advice_a")))
	assert_eq(observed[-1], [&"offered", &"", &"choice_a", &"variant_a", CORRECT])
	# 5. Güven en yükseğe çıkar; biçim ve sınıflandırma değişmez.
	world.trust.change_trust(&"actor_b", &"actor_a", 100)
	observed.append(_describe(advice.evaluate(&"advice_a")))
	assert_eq(observed[-1], [&"offered", &"", &"choice_a", &"variant_a", CORRECT])
	# 6. Güven eşiğin altına düşer; öneri sunulmaz.
	world.trust.change_trust(&"actor_b", &"actor_a", -100)
	observed.append(_describe(advice.evaluate(&"advice_a")))
	assert_eq(observed[-1], [&"not_offered", &"", &"", &"", &""])
	observed.append(_snapshot(world.state))
	return observed


func _run_reference_sequence() -> Array:
	var world: DecisionFixtures.World = _started_world()
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())])
	var observed: Array = []
	var steps: Array = [[], ["information_b"], ["information_a"]]
	for step in steps:
		_learn(world, step)
		observed.append(_describe(system.evaluate(&"advice_a")))
		observed.append(_describe_result(system.get_advice(&"advice_a")))
	return observed


func _run_decisions(with_advice: bool) -> Array:
	var world: DecisionFixtures.World = _started_world()
	var decisions: DecisionSystemScript = _effectful_decisions(world)
	var system: AdviceSystemScript = Fixtures.make_system(world, [_advice_a(_presentation())], decisions)
	var observed: Array = []
	for choice_id in [&"choice_a", &"choice_b", &"choice_a"]:
		if with_advice:
			system.get_advice(&"advice_a")
			system.evaluate(&"advice_a")
		var result: DecisionResultScript = decisions.choose(&"decision_a", choice_id)
		observed.append([result.ok, result.choice_id, result.failure])
	observed.append(_snapshot(world.state))
	return observed


func _effectful_decisions(world: DecisionFixtures.World) -> DecisionSystemScript:
	return DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a", [
		DecisionFixtures.make_choice("choice_a", [], [DecisionFixtures.eff_add("res_b", 1)]),
		DecisionFixtures.make_choice("choice_b", [], [DecisionFixtures.eff_add("res_b", 2)]),
	])])


## actor_b → actor_a, decision_a hakkında; veri sırasıyla:
## variant_a correct (information_a ve information_b) → choice_a; variant_b incomplete (information_a);
## variant_c incorrect (koşulsuz) → choice_b.
func _advice_a(presentation: Array = []) -> AdviceDataScript:
	return Fixtures.make_advice("advice_a", "actor_b", "actor_a", "decision_a", [
		Fixtures.make_variant("variant_a", CORRECT, [DecisionFixtures.cond_flag("information_a", true),
				DecisionFixtures.cond_flag("information_b", true)], "choice_a"),
		Fixtures.make_variant("variant_b", INCOMPLETE, [DecisionFixtures.cond_flag("information_a", true)]),
		Fixtures.make_variant("variant_c", INCORRECT, [], "choice_b"),
	], presentation)


## actor_b'nin actor_a'ya güveni en az 20 ise öneri sunulur.
func _presentation() -> Array:
	return [DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 20)]


func _fallback() -> AdviceVariantDataScript:
	return Fixtures.make_variant("variant_a", INCORRECT)


func _learn(world: DecisionFixtures.World, flags: Array) -> void:
	for flag_id in flags:
		world.state.set_flag(StringName(flag_id), true)


func _started_world() -> DecisionFixtures.World:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	DecisionFixtures.start(world)
	return world


func _describe(evaluation: AdviceEvaluationScript) -> Array:
	return [evaluation.result.status, evaluation.result.failure, evaluation.result.recommended_choice_id,
			evaluation.variant_id, evaluation.accuracy]


func _describe_result(result: AdviceResultScript) -> Array:
	return [result.status, result.failure, result.advice_id, result.advisor_actor_id, result.recipient_actor_id,
			result.decision_id, result.recommended_choice_id]


func _snapshot(state: GameStateScript) -> Array:
	var trust_rows: Array = []
	for entry in state.get_trust_snapshot():
		trust_rows.append([String(entry.source_actor_id), String(entry.target_actor_id), entry.value])
	var task_rows: Array = []
	for task in state.get_tasks_snapshot():
		task_rows.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return [state.get_resources_snapshot(), state.get_flags_snapshot(), trust_rows, state.get_night(),
			state.get_elapsed_units(), state.is_night_ended(), task_rows]


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
