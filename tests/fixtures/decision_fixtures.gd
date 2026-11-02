extends RefCounted
## Karar testleri için tarafsız veri ve sistem kurucuları (K-018). Oyun içeriği değildir.
## Dünya: res_a = 5 (0..10), res_b = 0 (alt 0, üst yok); güven 0..100, actor_a→actor_b 60, actor_b→actor_a 30;
## zaman 2 gece × 10 birim, action_a = 2, action_b = 0; olay yok.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const ResourceLimitsDataScript := preload("res://scripts/data/resource_limits_data.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")
const TrustRulesDataScript := preload("res://scripts/data/trust_rules_data.gd")
const TrustRelationshipDataScript := preload("res://scripts/data/trust_relationship_data.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const ChoiceDataScript := preload("res://scripts/data/choice_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")


class World:
	var state: GameStateScript
	var resources: ResourceSystemScript
	var trust: TrustSystemScript
	var time: TimeSystemScript


static func make_state_setup() -> InitialStateDataScript:
	var setup: InitialStateDataScript = InitialStateDataScript.new()
	setup.id = "state_setup_a"
	setup.starting_resources = {&"res_a": 5, &"res_b": 0}
	setup.rng_seed = 1
	return setup


## state verilmezse yeni bir GameState kurulur (test ikizleri için verilebilir).
static func make_world(state: GameStateScript = null) -> World:
	var world: World = World.new()
	world.state = state if state != null else GameStateScript.new(make_state_setup())
	var limits: ResourceLimitsDataScript = ResourceLimitsDataScript.new()
	limits.id = "limits_a"
	limits.min_values = {&"res_a": 0, &"res_b": 0}
	limits.max_values = {&"res_a": 10}
	world.resources = ResourceSystemScript.new(world.state, limits)
	var trust_rules: TrustRulesDataScript = TrustRulesDataScript.new()
	trust_rules.id = "trust_rules_a"
	trust_rules.min_value = 0
	trust_rules.max_value = 100
	for row in [["actor_a", "actor_b", 60], ["actor_b", "actor_a", 30]]:
		var relationship: TrustRelationshipDataScript = TrustRelationshipDataScript.new()
		relationship.source_actor_id = row[0]
		relationship.target_actor_id = row[1]
		relationship.starting_value = row[2]
		trust_rules.relationships.append(relationship)
	world.trust = TrustSystemScript.new(world.state, trust_rules)
	var time_rules: TimeRulesDataScript = TimeRulesDataScript.new()
	time_rules.id = "time_rules_a"
	time_rules.night_count = 2
	time_rules.night_length_units = 10
	time_rules.action_costs = {&"action_a": 2, &"action_b": 0}
	var no_events: Array[ScheduledEventDataScript] = []
	world.time = TimeSystemScript.new(world.state, time_rules, no_events)
	return world


## Güveni başlatır ve ilk geceyi açar.
static func start(world: World) -> void:
	world.trust.initialize_relationships()
	world.time.start_night()


static func make_condition(kind: StringName, fields: Dictionary = {}) -> ConditionDataScript:
	var condition: ConditionDataScript = ConditionDataScript.new()
	condition.kind = kind
	for key in fields:
		condition.set(key, fields[key])
	return condition


static func cond_resource(resource_id: String, comparison: StringName, value: int) -> ConditionDataScript:
	return make_condition(&"resource", {"resource_id": resource_id, "comparison": comparison, "value": value})


static func cond_trust(source: String, target: String, comparison: StringName, value: int) -> ConditionDataScript:
	return make_condition(&"trust", {"source_actor_id": source, "target_actor_id": target,
			"comparison": comparison, "value": value})


static func cond_flag(flag_id: String, expected: bool) -> ConditionDataScript:
	return make_condition(&"flag", {"flag_id": flag_id, "flag_value": expected})


static func make_effect(kind: StringName, fields: Dictionary = {}) -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.kind = kind
	for key in fields:
		effect.set(key, fields[key])
	return effect


static func eff_add(resource_id: String, amount: int) -> EffectDataScript:
	return make_effect(&"resource_add", {"resource_id": resource_id, "amount": amount})


static func eff_spend(resource_id: String, amount: int) -> EffectDataScript:
	return make_effect(&"resource_spend", {"resource_id": resource_id, "amount": amount})


static func eff_trust(source: String, target: String, delta: int) -> EffectDataScript:
	return make_effect(&"trust_change", {"source_actor_id": source, "target_actor_id": target, "amount": delta})


static func eff_flag(flag_id: String, value: bool) -> EffectDataScript:
	return make_effect(&"flag_set", {"flag_id": flag_id, "flag_value": value})


## conditions/effects içindeki null değerler boş kayıt olarak eklenir.
static func make_choice(id: String, conditions: Array = [], effects: Array = [], action_id: String = "") -> ChoiceDataScript:
	var choice: ChoiceDataScript = ChoiceDataScript.new()
	choice.id = id
	choice.action_id = action_id
	for condition in conditions:
		choice.conditions.append(condition)
	for effect in effects:
		choice.effects.append(effect)
	return choice


static func make_decision(id: String, choices: Array) -> DecisionDataScript:
	var decision: DecisionDataScript = DecisionDataScript.new()
	decision.id = id
	for choice in choices:
		decision.choices.append(choice)
	return decision


## task_definitions: durumda etkin olacak görevlerin tamamlanma tanımları (K-027).
static func make_system(world: World, decisions: Array, task_definitions: Array = []) -> DecisionSystemScript:
	var typed: Array[DecisionDataScript] = []
	for decision in decisions:
		typed.append(decision)
	return DecisionSystemScript.new(world.state, world.resources, world.trust, world.time,
			make_completion_system(world, task_definitions), typed)


static func make_completion_system(world: World, tasks: Array) -> TaskCompletionSystemScript:
	var typed: Array[TaskDataScript] = []
	for task in tasks:
		typed.append(task)
	return TaskCompletionSystemScript.new(world.state, world.resources, world.trust, world.time, typed)


## Yalnızca kimlik ve tamamlanma etkilerini taşıyan görev tanımı (atama alanları boş).
static func make_task_definition(id: String, completion_effects: Array = []) -> TaskDataScript:
	var task: TaskDataScript = TaskDataScript.new()
	task.id = id
	for effect in completion_effects:
		task.completion_effects.append(effect)
	return task
