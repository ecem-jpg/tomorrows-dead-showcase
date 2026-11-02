extends "res://tests/framework/test_case.gd"
## EquipmentSystem, ekipman koşulları/etkileri, atomiklik ve sonuçlara aktarılan süre bitişleri (K-031).
## Yalnızca tarafsız kimlikler kullanılır (K-018). Varsayılan: equipment_a çalışıyor, equipment_b arızalı,
## equipment_c çalışıyor; 2 gece × 10 birim, action_a = 2, action_b = 0.

const Fixtures := preload("res://tests/fixtures/equipment_fixtures.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const TaskFixtures := preload("res://tests/fixtures/task_fixtures.gd")
const OccurrenceFixtures := preload("res://tests/fixtures/occurrence_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const EquipmentSystemScript := preload("res://scripts/systems/equipment_system.gd")
const EquipmentViewScript := preload("res://scripts/systems/equipment_view.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const TaskAssignmentResultScript := preload("res://scripts/systems/task_assignment_result.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")

const OPERATIONAL: StringName = EquipmentStateScript.CONDITION_OPERATIONAL
const BROKEN: StringName = EquipmentStateScript.CONDITION_BROKEN


# --- Sorgu ve görünümler ---

func test_views_are_sorted_and_carry_every_field() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([
		Fixtures.make_initial("equipment_c", BROKEN, 2), Fixtures.make_initial("equipment_a", OPERATIONAL),
		Fixtures.make_initial("equipment_b", OPERATIONAL, 3),
	])
	var rows: Array = []
	for view in Fixtures.make_system(world).get_views():
		rows.append([String(view.equipment_id), view.condition, view.status, view.disabled_units, view.usable])
	assert_eq(rows, [
		["equipment_a", OPERATIONAL, &"operational", 0, true],
		["equipment_b", OPERATIONAL, &"disabled", 3, false],
		["equipment_c", BROKEN, &"broken", 2, false],
	])
	var names: Array[String] = []
	for property in EquipmentViewScript.new().get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["equipment_id", "condition", "status", "disabled_units", "usable"] as Array[String])


func test_views_are_independent() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world(Fixtures.default_equipment())
	var system: EquipmentSystemScript = Fixtures.make_system(world)
	var views: Array[EquipmentViewScript] = system.get_views()
	views[0].status = &"broken"
	views[0].usable = false
	views.clear()
	assert_true(system.is_usable(&"equipment_a"))
	assert_eq(system.get_views()[0].status, &"operational")


func test_status_and_usability_queries() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL),
			Fixtures.make_initial("equipment_b", BROKEN, 2), Fixtures.make_initial("equipment_c", OPERATIONAL, 1)])
	var system: EquipmentSystemScript = Fixtures.make_system(world)
	assert_eq([system.get_status(&"equipment_a"), system.get_status(&"equipment_b"), system.get_status(&"equipment_c")],
			[&"operational", &"broken", &"disabled"])
	assert_eq([system.is_usable(&"equipment_a"), system.is_usable(&"equipment_b"), system.is_usable(&"equipment_c")],
			[true, false, false])
	assert_eq(system.get_status(&"missing_id"), &"")
	_assert_one_engine_error("tanımsız ekipman okunamaz")


# --- Geçişler ---

func test_break_and_repair_transitions() -> void:
	var world: DecisionFixtures.World = _started_world()
	assert_true(_choose(world, [Fixtures.eff_break("equipment_a")]).ok)
	assert_eq(Fixtures.rows(world.state)[0], ["equipment_a", BROKEN, 0])
	var repaired: DecisionResultScript = _choose(world, [Fixtures.eff_repair("equipment_a")])
	assert_true(repaired.ok)
	var outcome: Object = repaired.effect_outcomes[0]
	assert_eq([outcome.equipment_id, outcome.previous_equipment_condition, outcome.equipment_condition],
			[&"equipment_a", BROKEN, OPERATIONAL])
	assert_eq(Fixtures.rows(world.state)[0], ["equipment_a", OPERATIONAL, 0])


func test_repeated_break_or_repair_is_not_applicable() -> void:
	var world: DecisionFixtures.World = _started_world()
	var calls: Array[int] = _count_signals(world.state)
	for case in [[Fixtures.eff_break("equipment_b")], [Fixtures.eff_repair("equipment_a")]]:
		var result: DecisionResultScript = _choose(world, [DecisionFixtures.eff_add("res_b", 1), case[0]])
		assert_eq([result.failure, result.blocking_effect_index], [DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE, 1])
	assert_eq(world.state.get_resource(&"res_b"), 0)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_disable_keeps_the_longer_duration() -> void:
	var world: DecisionFixtures.World = _started_world()
	_choose(world, [Fixtures.eff_disable("equipment_a", 5)])
	var shorter: DecisionResultScript = _choose(world, [Fixtures.eff_disable("equipment_a", 3)])
	assert_eq([shorter.effect_outcomes[0].previous_disabled_units, shorter.effect_outcomes[0].disabled_units], [5, 5])
	assert_eq(Fixtures.rows(world.state)[0], ["equipment_a", OPERATIONAL, 5])
	_choose(world, [Fixtures.eff_disable("equipment_a", 8)])
	assert_eq(Fixtures.rows(world.state)[0], ["equipment_a", OPERATIONAL, 8])


func test_disable_does_not_change_condition() -> void:
	var world: DecisionFixtures.World = _started_world()
	_choose(world, [Fixtures.eff_disable("equipment_b", 3)])
	assert_eq(Fixtures.rows(world.state)[1], ["equipment_b", BROKEN, 3])
	assert_eq(Fixtures.make_system(world).get_status(&"equipment_b"), &"broken")


# --- Yapılandırma ---

func test_disable_amount_must_be_at_least_one() -> void:
	var errors: PackedStringArray = _choice_errors([Fixtures.eff_disable("equipment_a", 0), Fixtures.eff_disable("equipment_b", -1)])
	assert_eq(errors, PackedStringArray([
		"'decision_a' / 'choice_a' etki #0: devre dışı süresi en az 1 olmalı: 0",
		"'decision_a' / 'choice_a' etki #1: devre dışı süresi en az 1 olmalı: -1",
	]))


func test_break_and_repair_require_zero_amount() -> void:
	var errors: PackedStringArray = _choice_errors([
		DecisionFixtures.make_effect(&"equipment_break", {"equipment_id": "equipment_a", "amount": 2}),
		DecisionFixtures.make_effect(&"equipment_repair", {"equipment_id": "equipment_b", "amount": 1}),
	])
	assert_eq(errors, PackedStringArray([
		"'decision_a' / 'choice_a' etki #0: ilgisiz alan dolu 'amount'",
		"'decision_a' / 'choice_a' etki #1: ilgisiz alan dolu 'amount'",
	]))


func test_unknown_equipment_in_conditions_and_effects_is_a_configuration_error() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world(Fixtures.default_equipment())
	var choice: Object = DecisionFixtures.make_choice("choice_a", [Fixtures.cond_equipment("missing_id", &"operational")],
			[Fixtures.eff_break("missing_id")])
	assert_eq(DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a", [choice])]).get_configuration_errors(),
			PackedStringArray([
				"'decision_a' / 'choice_a' koşul #0: tanımsız ekipman 'missing_id'",
				"'decision_a' / 'choice_a' etki #0: tanımsız ekipman 'missing_id'",
			]))


func test_equipment_condition_and_unrelated_field_errors() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world(Fixtures.default_equipment())
	var choice: Object = DecisionFixtures.make_choice("choice_a", [
		DecisionFixtures.make_condition(&"equipment", {"equipment_id": "equipment_a"}),
		Fixtures.cond_equipment("equipment_a", &"lost"),
		DecisionFixtures.make_condition(&"equipment", {"equipment_id": "equipment_a", "equipment_status": &"broken", "value": 3}),
		DecisionFixtures.make_condition(&"flag", {"flag_id": "flag_a", "equipment_id": "equipment_a", "equipment_status": &"broken"}),
	], [DecisionFixtures.make_effect(&"flag_set", {"flag_id": "flag_a", "flag_value": true, "equipment_id": "equipment_a"})])
	var p: String = "'decision_a' / 'choice_a' "
	assert_eq(DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a", [choice])]).get_configuration_errors(),
			PackedStringArray([
				p + "koşul #0: eksik alan 'equipment_status'",
				p + "koşul #1: tanımsız ekipman durumu 'lost'",
				p + "koşul #2: ilgisiz alan dolu 'value'",
				p + "koşul #3: ilgisiz alan dolu 'equipment_id'",
				p + "koşul #3: ilgisiz alan dolu 'equipment_status'",
				p + "etki #0: ilgisiz alan dolu 'equipment_id'",
			]))


func test_two_equipment_effects_on_one_equipment_in_a_choice_are_a_configuration_error() -> void:
	var errors: PackedStringArray = _choice_errors([Fixtures.eff_repair("equipment_b"), Fixtures.eff_disable("equipment_b", 2),
			Fixtures.eff_break("equipment_a")])
	assert_eq(errors, PackedStringArray(["'decision_a' / 'choice_a' etki #1: aynı hedefe birden fazla etki (#0 ile)"]))


func test_two_equipment_effects_on_one_equipment_in_a_completion_task_are_a_configuration_error() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world(Fixtures.default_equipment())
	var completions: TaskCompletionSystemScript = DecisionFixtures.make_completion_system(world, [DecisionFixtures.make_task_definition(
			"task_a", [Fixtures.eff_break("equipment_a"), Fixtures.eff_disable("equipment_a", 2)])])
	assert_eq(completions.get_catalog_errors(),
			PackedStringArray(["'task_a' tamamlanma etkisi #1: aynı hedefe birden fazla etki (#0 ile)"]))


# --- Koşullar ---

func test_condition_reads_each_visible_status() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL),
			Fixtures.make_initial("equipment_b", BROKEN), Fixtures.make_initial("equipment_c", OPERATIONAL, 2),
			Fixtures.make_initial("equipment_d", BROKEN, 2)])
	Fixtures.start(world)
	var cases: Array = [["equipment_a", &"operational"], ["equipment_b", &"broken"], ["equipment_c", &"disabled"],
			["equipment_d", &"broken"]]
	for case in cases:
		for status in [&"operational", &"broken", &"disabled"]:
			var choice: Object = DecisionFixtures.make_choice("choice_a", [Fixtures.cond_equipment(case[0], status)])
			var system: DecisionSystemScript = DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a", [choice])])
			assert_eq(system.is_choice_available(&"decision_a", &"choice_a"), status == case[1], "%s %s" % [case[0], status])


# --- Seçim ve görev etkileri ---

func test_task_completion_effects_change_equipment() -> void:
	var world: DecisionFixtures.World = _started_world()
	var clock: TaskCompletionSystemScript = DecisionFixtures.make_completion_system(world, [
		DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_repair("equipment_b"), Fixtures.eff_break("equipment_c")])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var result: TimeProgressResultScript = clock.advance(2)
	assert_eq(result.completions[0].status, &"applied")
	assert_eq(Fixtures.rows(world.state), [["equipment_a", OPERATIONAL, 0], ["equipment_b", OPERATIONAL, 0], ["equipment_c", BROKEN, 0]])


func test_choice_disable_counts_down_during_its_own_action() -> void:
	var world: DecisionFixtures.World = _started_world()
	var result: DecisionResultScript = _choose(world, [Fixtures.eff_disable("equipment_a", 5)], "action_a")
	assert_true(result.ok)
	assert_eq(Fixtures.rows(world.state)[0], ["equipment_a", OPERATIONAL, 3])
	assert_eq(result.equipment_disable_expirations.size(), 0)


# --- Atomiklik ---

func test_all_categories_apply_in_one_write() -> void:
	var setup: InitialStateDataScript = OccurrenceFixtures.make_setup()
	for entry in Fixtures.default_equipment():
		setup.starting_equipment.append(entry)
	var world: DecisionFixtures.World = DecisionFixtures.make_world(GameStateScript.new(setup))
	var occurrences: OccurrenceSystemScript = OccurrenceFixtures.make_default_system(world)
	OccurrenceFixtures.start(world, occurrences)
	var calls: Array[int] = _count_signals(world.state)
	var result: DecisionResultScript = _choose(world, [DecisionFixtures.eff_spend("res_a", 2), DecisionFixtures.eff_trust("actor_a", "actor_b", 5),
			DecisionFixtures.eff_flag("flag_a", true), OccurrenceFixtures.eff_prevent("occurrence_a"), Fixtures.eff_break("equipment_a"),
			Fixtures.eff_disable("equipment_c", 4)], "action_a")
	assert_true(result.ok)
	assert_eq(calls[0], 1)
	assert_eq([world.state.get_resource(&"res_a"), world.state.get_trust(&"actor_a", &"actor_b"), world.state.get_flag(&"flag_a")],
			[3, 65, true])
	assert_eq(world.state.get_occurrence_status(&"occurrence_a"), &"death_prevented")
	assert_eq(world.state.get_elapsed_units(), 2)
	assert_eq(Fixtures.rows(world.state), [["equipment_a", BROKEN, 0], ["equipment_b", BROKEN, 0], ["equipment_c", OPERATIONAL, 2]])


func test_failed_choice_write_changes_no_category() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_setup([Fixtures.make_initial("equipment_a", OPERATIONAL, 1),
			Fixtures.make_initial("equipment_b", BROKEN)]))
	var world: DecisionFixtures.World = Fixtures.make_world([], state)
	Fixtures.start(world)
	var system: DecisionSystemScript = DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a",
			[DecisionFixtures.make_choice("choice_a", [], [DecisionFixtures.eff_spend("res_a", 2), DecisionFixtures.eff_trust("actor_a", "actor_b", 5),
			DecisionFixtures.eff_flag("flag_a", true), Fixtures.eff_repair("equipment_b")], "action_a")])])
	var before: Array = _snapshot(state)
	var calls: Array[int] = _count_signals(state)
	state.reject_changes = true
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_eq(result.failure, DecisionResultScript.FAILURE_WRITE_FAILED)
	assert_eq(result.equipment_disable_expirations.size(), 0)
	assert_eq(take_engine_errors().size(), 2)
	assert_eq(_snapshot(state), before)
	assert_eq(calls[0], 0)


func test_failed_advance_write_changes_no_category() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_setup([Fixtures.make_initial("equipment_a", OPERATIONAL, 1),
			Fixtures.make_initial("equipment_b", BROKEN)]))
	var world: DecisionFixtures.World = Fixtures.make_world([], state)
	Fixtures.start(world)
	var clock: TaskCompletionSystemScript = DecisionFixtures.make_completion_system(world, [DecisionFixtures.make_task_definition(
			"task_a", [Fixtures.eff_repair("equipment_b"), DecisionFixtures.eff_add("res_b", 2)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var before: Array = _snapshot(state)
	var calls: Array[int] = _count_signals(state)
	state.reject_changes = true
	var result: TimeProgressResultScript = clock.advance(3)
	assert_eq(result.failure, TimeProgressResultScript.FAILURE_WRITE_FAILED)
	assert_eq(result.equipment_disable_expirations.size(), 0)
	assert_eq(take_engine_errors().size(), 2)
	assert_eq(_snapshot(state), before)
	assert_eq(calls[0], 0)


func test_insufficient_spend_discards_the_tasks_equipment_effects_too() -> void:
	var world: DecisionFixtures.World = _started_world()
	var clock: TaskCompletionSystemScript = DecisionFixtures.make_completion_system(world, [DecisionFixtures.make_task_definition(
			"task_a", [Fixtures.eff_break("equipment_a"), Fixtures.eff_disable("equipment_c", 3), DecisionFixtures.eff_spend("res_b", 50)])])
	world.time.start_task(&"task_a", &"actor_b", 2)
	var result: TimeProgressResultScript = clock.advance(2)
	assert_eq([result.completions[0].status, result.completions[0].blocking_effect_index], [&"effects_not_applicable", 2])
	assert_eq(Fixtures.rows(world.state), [["equipment_a", OPERATIONAL, 0], ["equipment_b", BROKEN, 0], ["equipment_c", OPERATIONAL, 0]])


func test_copies_carry_new_condition_and_effect_fields() -> void:
	var condition: ConditionDataScript = Fixtures.cond_equipment("equipment_a", &"disabled")
	var effect: EffectDataScript = Fixtures.eff_disable("equipment_a", 4)
	var condition_copy: ConditionDataScript = condition.copy()
	var effect_copy: EffectDataScript = effect.copy()
	assert_eq([condition_copy.kind, condition_copy.equipment_id, condition_copy.equipment_status], [&"equipment", "equipment_a", &"disabled"])
	assert_eq([effect_copy.kind, effect_copy.equipment_id, effect_copy.amount], [&"equipment_disable", "equipment_a", 4])
	condition_copy.equipment_id = "equipment_z"
	effect_copy.equipment_id = "equipment_z"
	assert_eq([condition.equipment_id, effect.equipment_id], ["equipment_a", "equipment_a"])


# --- Sonuçlara aktarılan süre bitişleri ---

func test_decision_result_reports_expirations_during_the_action() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 1),
			Fixtures.make_initial("equipment_b", BROKEN, 2)])
	Fixtures.start(world)
	var result: DecisionResultScript = _choose(world, [DecisionFixtures.eff_add("res_b", 1)], "action_a")
	assert_true(result.ok)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 1, 1], ["equipment_b", 1, 2]])
	# Süresi biten arızalı ekipman arızalı kalır ve kullanılamaz.
	assert_false(Fixtures.make_system(world).is_usable(&"equipment_b"))
	assert_true(Fixtures.make_system(world).is_usable(&"equipment_a"))


func test_task_assignment_accept_and_reject_report_expirations() -> void:
	var results: Array = []
	for conditions in [[], [DecisionFixtures.cond_flag("flag_a", true)]]:
		var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 2)])
		Fixtures.start(world)
		var tasks: TaskSystemScript = TaskFixtures.make_system(world, [TaskFixtures.make_task("task_a", 4, "actor_a", "actor_b",
				conditions, "action_a")])
		var result: TaskAssignmentResultScript = tasks.assign_task(&"task_a", &"actor_a", &"actor_b")
		results.append([result.status, Fixtures.expiration_rows(result.equipment_disable_expirations)])
	assert_eq(results, [[&"accepted", [["equipment_a", 1, 2]]], [&"rejected", [["equipment_a", 1, 2]]]])


func test_no_action_means_no_expirations() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 1)])
	Fixtures.start(world)
	assert_eq(_choose(world, [DecisionFixtures.eff_add("res_b", 1)]).equipment_disable_expirations.size(), 0)
	var tasks: TaskSystemScript = TaskFixtures.make_system(world, [TaskFixtures.make_task("task_a", 4, "actor_a", "actor_b")])
	var assigned: TaskAssignmentResultScript = tasks.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_true(assigned.is_accepted())
	assert_eq(assigned.equipment_disable_expirations.size(), 0)
	assert_eq(Fixtures.rows(world.state), [["equipment_a", OPERATIONAL, 1]])


func test_failed_results_have_no_expirations_and_state_is_unchanged() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 1)])
	Fixtures.start(world)
	var not_met: DecisionResultScript = _choose(world, [DecisionFixtures.eff_add("res_b", 1)], "action_a",
			[DecisionFixtures.cond_flag("flag_a", true)])
	assert_eq([not_met.failure, not_met.equipment_disable_expirations.size()], [DecisionResultScript.FAILURE_CONDITIONS_NOT_MET, 0])
	assert_eq([world.state.get_elapsed_units(), Fixtures.rows(world.state)], [0, [["equipment_a", OPERATIONAL, 1]]])


func test_preview_and_real_call_report_the_same_expirations() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 1),
			Fixtures.make_initial("equipment_c", OPERATIONAL, 2)])
	Fixtures.start(world)
	var decisions: DecisionSystemScript = _decision_system(world, [DecisionFixtures.eff_add("res_b", 1)], "action_a")
	var preview: DecisionResultScript = decisions.preview_choice(&"decision_a", &"choice_a")
	var real: DecisionResultScript = decisions.choose(&"decision_a", &"choice_a")
	assert_eq(Fixtures.expiration_rows(preview.equipment_disable_expirations), Fixtures.expiration_rows(real.equipment_disable_expirations))
	assert_eq(Fixtures.expiration_rows(real.equipment_disable_expirations), [["equipment_a", 1, 1], ["equipment_c", 1, 2]])
	var second: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 1)])
	Fixtures.start(second)
	var tasks: TaskSystemScript = TaskFixtures.make_system(second, [TaskFixtures.make_task("task_a", 4, "actor_a", "actor_b", [], "action_a")])
	var task_preview: TaskAssignmentResultScript = tasks.preview_assignment(&"task_a", &"actor_a", &"actor_b")
	var task_real: TaskAssignmentResultScript = tasks.assign_task(&"task_a", &"actor_a", &"actor_b")
	assert_eq(Fixtures.expiration_rows(task_preview.equipment_disable_expirations),
			Fixtures.expiration_rows(task_real.equipment_disable_expirations))
	assert_eq(Fixtures.expiration_rows(task_real.equipment_disable_expirations), [["equipment_a", 1, 1]])


func test_expiration_records_are_independent_copies() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 1)])
	Fixtures.start(world)
	var decisions: DecisionSystemScript = _decision_system(world, [DecisionFixtures.eff_add("res_b", 1)], "action_a")
	var preview: DecisionResultScript = decisions.preview_choice(&"decision_a", &"choice_a")
	preview.equipment_disable_expirations[0].at_units = 99
	preview.equipment_disable_expirations[0].equipment_id = &"equipment_z"
	preview.equipment_disable_expirations.clear()
	var real: DecisionResultScript = decisions.choose(&"decision_a", &"choice_a")
	assert_eq(Fixtures.expiration_rows(real.equipment_disable_expirations), [["equipment_a", 1, 1]])
	real.equipment_disable_expirations[0].night = 7
	assert_eq(Fixtures.rows(world.state), [["equipment_a", OPERATIONAL, 0]])


func test_same_start_and_same_actions_produce_same_results() -> void:
	assert_eq(_run_reference(), _run_reference())


# --- Yardımcılar ---

func _run_reference() -> Array:
	var world: DecisionFixtures.World = Fixtures.make_world([Fixtures.make_initial("equipment_a", OPERATIONAL, 3),
			Fixtures.make_initial("equipment_b", BROKEN, 1), Fixtures.make_initial("equipment_c", OPERATIONAL)])
	Fixtures.start(world)
	var observed: Array = []
	var first: DecisionResultScript = _choose(world, [Fixtures.eff_disable("equipment_c", 2), Fixtures.eff_repair("equipment_b")], "action_a")
	observed.append([first.ok, Fixtures.expiration_rows(first.equipment_disable_expirations)])
	var second: DecisionResultScript = _choose(world, [Fixtures.eff_break("equipment_a")], "action_a")
	observed.append([second.ok, Fixtures.expiration_rows(second.equipment_disable_expirations)])
	observed.append(Fixtures.rows(world.state))
	return observed


func _started_world() -> DecisionFixtures.World:
	var world: DecisionFixtures.World = Fixtures.make_world(Fixtures.default_equipment())
	Fixtures.start(world)
	return world


func _decision_system(world: DecisionFixtures.World, effects: Array, action_id: String = "", conditions: Array = []) -> DecisionSystemScript:
	return DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a",
			[DecisionFixtures.make_choice("choice_a", conditions, effects, action_id)])])


func _choose(world: DecisionFixtures.World, effects: Array, action_id: String = "", conditions: Array = []) -> DecisionResultScript:
	return _decision_system(world, effects, action_id, conditions).choose(&"decision_a", &"choice_a")


func _choice_errors(effects: Array) -> PackedStringArray:
	return _decision_system(Fixtures.make_world(Fixtures.default_equipment()), effects).get_configuration_errors()


func _snapshot(state: GameStateScript) -> Array:
	var trust_rows: Array = []
	for entry in state.get_trust_snapshot():
		trust_rows.append([String(entry.source_actor_id), String(entry.target_actor_id), entry.value])
	var task_rows: Array = []
	for task in state.get_tasks_snapshot():
		task_rows.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return [state.get_resources_snapshot(), state.get_flags_snapshot(), trust_rows, state.get_night(), state.get_elapsed_units(),
			state.is_night_ended(), task_rows, state.get_occurrences_snapshot(), Fixtures.rows(state)]


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
