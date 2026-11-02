extends "res://tests/framework/test_case.gd"
## Ekipman geçici devre dışı süresinin ortak oyun saatiyle ilişkisi (K-031): kronolojik parçalar, gece sınırları,
## süre bitiş kayıtları ve tek büyük ilerleme ile parçalı ilerlemenin eşdeğerliği. Yalnızca tarafsız kimlikler.
## Dünya: 2 gece × 10 birim. Görevler düşük seviyeli TimeSystem.start_task ile başlatılır; tanımları tamamlanma
## kataloğundadır. Zaman yalnızca TaskCompletionSystem.advance ile ilerletilir.

const Fixtures := preload("res://tests/fixtures/equipment_fixtures.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const EquipmentSystemScript := preload("res://scripts/systems/equipment_system.gd")

const OPERATIONAL: StringName = EquipmentStateScript.CONDITION_OPERATIONAL
const BROKEN: StringName = EquipmentStateScript.CONDITION_BROKEN


class Ctx:
	var world: DecisionFixtures.World
	var clock: TaskCompletionSystemScript


# --- Sınırlar ---

func test_one_unit_disable_expires_after_one_unit() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 1)])
	var result: TimeProgressResultScript = ctx.clock.advance(1)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 1, 1]])
	assert_eq(Fixtures.rows(ctx.world.state), [["equipment_a", OPERATIONAL, 0]])
	assert_true(Fixtures.make_system(ctx.world).is_usable(&"equipment_a"))


func test_disable_expires_within_the_same_night() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 4)])
	assert_eq(ctx.clock.advance(3).equipment_disable_expirations.size(), 0)
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 1])
	var result: TimeProgressResultScript = ctx.clock.advance(5)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 1, 4]])
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 0])


func test_expired_broken_equipment_stays_broken_and_unusable() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_b", BROKEN, 2)])
	var result: TimeProgressResultScript = ctx.clock.advance(2)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_b", 1, 2]])
	var system: EquipmentSystemScript = Fixtures.make_system(ctx.world)
	assert_eq([system.get_status(&"equipment_b"), system.is_usable(&"equipment_b")], [&"broken", false])
	assert_eq(Fixtures.rows(ctx.world.state), [["equipment_b", BROKEN, 0]])


func test_overflow_units_do_not_reduce_the_counter() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 15)])
	ctx.clock.advance(7)
	var result: TimeProgressResultScript = ctx.clock.advance(10)
	assert_eq([result.time_result.applied_units, result.time_result.overflow_units], [3, 7])
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 5])
	assert_eq(result.equipment_disable_expirations.size(), 0)


# --- Gece akışı ---

func test_disable_before_the_first_night_starts_counting_in_night_one() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL)], false)
	assert_true(_choose(ctx, [Fixtures.eff_disable("equipment_a", 3)]).ok)
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 3])
	ctx.world.time.start_night()
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 3])
	ctx.clock.advance(1)
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 2])


func test_disable_after_night_end_waits_for_the_next_night() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL)])
	ctx.clock.advance(10)
	assert_true(_choose(ctx, [Fixtures.eff_disable("equipment_a", 3)]).ok)
	ctx.world.time.start_night()
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 3])
	var result: TimeProgressResultScript = ctx.clock.advance(3)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 2, 3]])


func test_counter_pauses_between_nights_and_continues() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 12)])
	assert_eq(ctx.clock.advance(10).equipment_disable_expirations.size(), 0)
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 2])
	ctx.world.time.start_night()
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 2])
	var result: TimeProgressResultScript = ctx.clock.advance(5)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 2, 2]])


func test_multi_night_disable_survives_every_night() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 25)])
	ctx.clock.advance(10)
	ctx.world.time.start_night()
	ctx.clock.advance(10)
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 5])
	assert_eq(Fixtures.make_system(ctx.world).get_status(&"equipment_a"), &"disabled")


# --- Sıralama ---

func test_simultaneous_expirations_are_ordered_by_id() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_c", OPERATIONAL, 3), Fixtures.make_initial("equipment_a", BROKEN, 3),
			Fixtures.make_initial("equipment_b", OPERATIONAL, 2)])
	var result: TimeProgressResultScript = ctx.clock.advance(5)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations),
			[["equipment_b", 1, 2], ["equipment_a", 1, 3], ["equipment_c", 1, 3]])


func test_counter_expires_before_a_task_completing_at_the_same_unit() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 4)],
			true, [DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_disable("equipment_a", 2)])])
	ctx.world.time.start_task(&"task_a", &"actor_b", 4)
	var result: TimeProgressResultScript = ctx.clock.advance(4)
	# Sayaç 4'te biter; aynı andaki görev etkisi ondan sonra yeniden devre dışı bırakır.
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 1, 4]])
	assert_eq(result.completions[0].effect_outcomes[0].previous_disabled_units, 0)
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 2])
	var later: TimeProgressResultScript = ctx.clock.advance(2)
	assert_eq(Fixtures.expiration_rows(later.equipment_disable_expirations), [["equipment_a", 1, 6]])


func test_two_tasks_completing_together_affect_equipment_in_task_id_order() -> void:
	# task_a önce (arıza), task_b sonra (onarım): sonuç çalışıyor. Roller değişince sonuç da değişir.
	var forward: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL)], true, [
		DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_break("equipment_a")]),
		DecisionFixtures.make_task_definition("task_b", [Fixtures.eff_repair("equipment_a")]),
	])
	forward.world.time.start_task(&"task_b", &"actor_c", 3)
	forward.world.time.start_task(&"task_a", &"actor_b", 3)
	var forward_result: TimeProgressResultScript = forward.clock.advance(3)
	assert_eq([forward_result.completions[0].task_id, forward_result.completions[1].task_id], [&"task_a", &"task_b"])
	assert_eq([forward_result.completions[0].status, forward_result.completions[1].status], [&"applied", &"applied"])
	assert_eq(Fixtures.rows(forward.world.state)[0], ["equipment_a", OPERATIONAL, 0])
	var reverse: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL)], true, [
		DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_repair("equipment_a")]),
		DecisionFixtures.make_task_definition("task_b", [Fixtures.eff_break("equipment_a")]),
	])
	reverse.world.time.start_task(&"task_a", &"actor_b", 3)
	reverse.world.time.start_task(&"task_b", &"actor_c", 3)
	var reverse_result: TimeProgressResultScript = reverse.clock.advance(3)
	assert_eq([reverse_result.completions[0].status, reverse_result.completions[1].status], [&"effects_not_applicable", &"applied"])
	assert_eq(Fixtures.rows(reverse.world.state)[0], ["equipment_a", BROKEN, 0])


func test_task_effect_at_night_boundary_does_not_decay_between_nights() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL)], true,
			[DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_disable("equipment_a", 5)])])
	ctx.world.time.start_task(&"task_a", &"actor_b", 10)
	var result: TimeProgressResultScript = ctx.clock.advance(10)
	assert_true(result.time_result.night_ended())
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 5])
	ctx.world.time.start_night()
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 5])
	ctx.clock.advance(1)
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 4])


func test_same_equipment_can_expire_twice_in_one_call() -> void:
	var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 2)], true,
			[DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_disable("equipment_a", 3)])])
	ctx.world.time.start_task(&"task_a", &"actor_b", 5)
	var result: TimeProgressResultScript = ctx.clock.advance(10)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 1, 2], ["equipment_a", 1, 8]])
	assert_eq(Fixtures.rows(ctx.world.state)[0], ["equipment_a", OPERATIONAL, 0])


func test_countdown_and_task_effects_share_one_write() -> void:
	var state: CountingGameState = CountingGameState.new(Fixtures.make_setup([Fixtures.make_initial("equipment_a", OPERATIONAL, 3),
			Fixtures.make_initial("equipment_b", BROKEN)]))
	var ctx: Ctx = _ctx([], true, [DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_repair("equipment_b")])], state)
	ctx.world.time.start_task(&"task_a", &"actor_b", 2)
	state.apply_calls = 0
	state.other_writes = 0
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	var result: TimeProgressResultScript = ctx.clock.advance(5)
	assert_eq(Fixtures.expiration_rows(result.equipment_disable_expirations), [["equipment_a", 1, 3]])
	assert_eq([state.apply_calls, state.other_writes, calls[0]], [1, 0, 1])
	assert_eq(Fixtures.rows(state), [["equipment_a", OPERATIONAL, 0], ["equipment_b", OPERATIONAL, 0]])


# --- Büyük ilerleme ile parçalı ilerlemenin eşdeğerliği ---

func test_task_disable_in_one_advance_equals_split_advances() -> void:
	var setup: Callable = func() -> Ctx:
		var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL)], true,
				[DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_disable("equipment_a", 10)])])
		ctx.world.time.start_task(&"task_a", &"actor_b", 4)
		return ctx
	var whole: Array = _run(setup.call(), [10])
	var split: Array = _run(setup.call(), [4, 6])
	assert_eq(whole, split)
	assert_eq(whole[0], [["equipment_a", OPERATIONAL, 4]])


func test_expiration_then_task_disable_then_expiration_split_equivalence() -> void:
	var setup: Callable = func() -> Ctx:
		var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 3)], true,
				[DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_disable("equipment_a", 2)])])
		ctx.world.time.start_task(&"task_a", &"actor_b", 5)
		return ctx
	var whole: Array = _run(setup.call(), [8])
	var split: Array = _run(setup.call(), [5, 3])
	assert_eq(whole, split)
	assert_eq(whole[1], [["equipment_a", 1, 3], ["equipment_a", 1, 7]])
	assert_eq(whole[0], [["equipment_a", OPERATIONAL, 0]])


func test_choice_disable_split_equivalence() -> void:
	var setup: Callable = func() -> Ctx:
		var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL)])
		_choose(ctx, [Fixtures.eff_disable("equipment_a", 6)])
		return ctx
	var whole: Array = _run(setup.call(), [5])
	var split: Array = _run(setup.call(), [2, 3])
	assert_eq(whole, split)
	assert_eq(whole[0], [["equipment_a", OPERATIONAL, 1]])


func test_multiple_equipment_and_tasks_split_equivalence() -> void:
	var setup: Callable = func() -> Ctx:
		var ctx: Ctx = _ctx([Fixtures.make_initial("equipment_a", OPERATIONAL, 3), Fixtures.make_initial("equipment_b", BROKEN, 6),
				Fixtures.make_initial("equipment_c", OPERATIONAL)], true, [
			DecisionFixtures.make_task_definition("task_a", [Fixtures.eff_disable("equipment_c", 5)]),
			DecisionFixtures.make_task_definition("task_b", [Fixtures.eff_disable("equipment_a", 4), Fixtures.eff_repair("equipment_b")]),
		])
		ctx.world.time.start_task(&"task_a", &"actor_b", 4)
		ctx.world.time.start_task(&"task_b", &"actor_c", 7)
		return ctx
	var whole: Array = _run(setup.call(), [10])
	for steps in [[1, 9], [4, 6], [2, 3, 5]]:
		assert_eq(_run(setup.call(), steps), whole, str(steps))
	assert_eq(whole[1], [["equipment_a", 1, 3], ["equipment_b", 1, 6], ["equipment_c", 1, 9]])
	assert_eq(whole[0], [["equipment_a", OPERATIONAL, 1], ["equipment_b", OPERATIONAL, 0], ["equipment_c", OPERATIONAL, 0]])


# --- Yardımcılar ---

## Verilen adımlarla ilerletir; [nihai ekipman satırları, bütün süre bitişleri, tamamlanmalar, gece/süre].
func _run(ctx: Ctx, steps: Array) -> Array:
	var expirations: Array = []
	var completions: Array = []
	for step in steps:
		var result: TimeProgressResultScript = ctx.clock.advance(step)
		assert_true(result.ok, str(steps))
		expirations.append_array(Fixtures.expiration_rows(result.equipment_disable_expirations))
		for completion in result.completions:
			completions.append([String(completion.task_id), completion.night, completion.at_units, completion.status])
	return [Fixtures.rows(ctx.world.state), expirations, completions,
			[ctx.world.state.get_night(), ctx.world.state.get_elapsed_units()]]


func _ctx(entries: Array, start: bool = true, task_definitions: Array = [], state: GameStateScript = null) -> Ctx:
	var ctx: Ctx = Ctx.new()
	ctx.world = Fixtures.make_world(entries, state)
	ctx.world.trust.initialize_relationships()
	if start:
		ctx.world.time.start_night()
	ctx.clock = DecisionFixtures.make_completion_system(ctx.world, task_definitions)
	return ctx


func _choose(ctx: Ctx, effects: Array, action_id: String = "") -> DecisionResultScript:
	var system: DecisionSystemScript = DecisionFixtures.make_system(ctx.world, [DecisionFixtures.make_decision("decision_a",
			[DecisionFixtures.make_choice("choice_a", [], effects, action_id)])])
	return system.choose(&"decision_a", &"choice_a")


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
