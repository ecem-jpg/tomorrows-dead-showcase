extends RefCounted
## Genel senaryo bütünleşme testleri için tarafsız dünya, yazma sayan test ikizi ve senaryo sürücüsü (K-018).
## Oyun içeriği değildir; sayılar yalnızca testi küçük ve okunur tutar. Bütün veri her dünya için bellekte yeniden
## kurulur (.tres yok, önbellek paylaşımı yok); sistemler yalnızca açık kurucu ve yöntemleriyle kullanılır.
##
## Dünya: resource_a = 3 (0..10); güven actor_a↔actor_b 50 (0..100); 2 gece × 10 birim; action_a = 2 (kablo),
## action_b = 1 (atama), action_c = 1 (karar); occurrence_a (subject_a, 1. gece), occurrence_b (subject_b, 2. gece);
## equipment_a arızalı; puzzle_a (tek gönderim, tek çözüm hakkı); task_a, decision_a, advice_a; ending_a (öncelik 1,
## iki görünüm de death_prevented), ending_b (öncelik 2, koşulsuz).

# İç sınıflar kendi betiğinin statik yöntemlerine yol ile başvurur.
const FullScenarioFixtures := preload("res://tests/fixtures/full_scenario_fixtures.gd")
const TestCaseScript := preload("res://tests/framework/test_case.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const InitialEquipmentDataScript := preload("res://scripts/data/initial_equipment_data.gd")
const ResourceLimitsDataScript := preload("res://scripts/data/resource_limits_data.gd")
const TrustRulesDataScript := preload("res://scripts/data/trust_rules_data.gd")
const TrustRelationshipDataScript := preload("res://scripts/data/trust_relationship_data.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const TaskAssignmentDataScript := preload("res://scripts/data/task_assignment_data.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const ChoiceDataScript := preload("res://scripts/data/choice_data.gd")
const AdviceDataScript := preload("res://scripts/data/advice_data.gd")
const AdviceContextDataScript := preload("res://scripts/data/advice_context_data.gd")
const AdviceVariantDataScript := preload("res://scripts/data/advice_variant_data.gd")
const SubjectDataScript := preload("res://scripts/data/subject_data.gd")
const OccurrenceDataScript := preload("res://scripts/data/occurrence_data.gd")
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CableTerminalDataScript := preload("res://scripts/data/cable_terminal_data.gd")
const CableConnectionDataScript := preload("res://scripts/data/cable_connection_data.gd")
const CablePuzzleRulesDataScript := preload("res://scripts/data/cable_puzzle_rules_data.gd")
const CablePuzzleOutcomeDataScript := preload("res://scripts/data/cable_puzzle_outcome_data.gd")
const EndingDataScript := preload("res://scripts/data/ending_data.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const AdviceSystemScript := preload("res://scripts/systems/advice_system.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")
const EquipmentSystemScript := preload("res://scripts/systems/equipment_system.gd")
const CableRepairSystemScript := preload("res://scripts/systems/cable_repair_system.gd")
const EndingResolverScript := preload("res://scripts/systems/ending_resolver.gd")

const ACTOR_A: String = "actor_a"
const ACTOR_B: String = "actor_b"
const RESOURCE_A: String = "resource_a"
const FLAG_A: String = "flag_a"
const EQUIPMENT_A: String = "equipment_a"
const OCCURRENCE_A: String = "occurrence_a"
const OCCURRENCE_B: String = "occurrence_b"
const TASK_A: String = "task_a"
const DECISION_A: String = "decision_a"
const CHOICE_A: String = "choice_a"
const CHOICE_B: String = "choice_b"
const ADVICE_A: String = "advice_a"
const VARIANT_A: String = "variant_a"
const VARIANT_B: String = "variant_b"
const PUZZLE_A: String = "puzzle_a"
const ENDING_A: String = "ending_a"
const ENDING_B: String = "ending_b"
const ACTION_CABLE: String = "action_a"
const ACTION_ASSIGN: String = "action_b"
const ACTION_DECIDE: String = "action_c"
const TERMINAL_A: StringName = &"terminal_a"
const TERMINAL_B: StringName = &"terminal_b"
const TERMINAL_C: StringName = &"terminal_c"
const TERMINAL_D: StringName = &"terminal_d"

## Sayaç sırası: apply_changes, set_resource, set_flag, set_time_state, set_trust_state, state_changed.
const COUNTER_NAMES: Array[String] = ["apply_changes", "set_resource", "set_flag", "set_time_state", "set_trust_state",
		"state_changed"]
## Özet alanları, sabit sırayla.
const SUMMARY_FIELDS: Array[String] = ["ending", "time", "resources", "flags", "trust", "tasks", "occurrences",
		"equipment", "cable"]


## Yazma yöntemlerini ve state_changed sinyalini ayrı ayrı sayan GameState ikizi (yalnızca test).
class CountingGameState extends "res://scripts/core/game_state.gd":
	var apply_calls: int = 0
	var set_resource_calls: int = 0
	var set_flag_calls: int = 0
	var set_time_state_calls: int = 0
	var set_trust_state_calls: int = 0
	var signal_count: int = 0

	func _init(setup: InitialStateDataScript) -> void:
		super(setup)
		# Yöntem bağlantısı: self yakalayan lambda kendi sinyalinde başvuru döngüsü kurar ve nesne serbest kalmaz.
		state_changed.connect(_on_state_changed)

	func _on_state_changed() -> void:
		signal_count += 1

	func apply_changes(change: GameStateChangeScript) -> bool:
		apply_calls += 1
		return super(change)

	func set_resource(resource_id: StringName, value: int) -> bool:
		set_resource_calls += 1
		return super(resource_id, value)

	func set_flag(flag_id: StringName, value: bool) -> bool:
		set_flag_calls += 1
		return super(flag_id, value)

	func set_time_state(night: int, elapsed_units: int, night_ended: bool, tasks: Array[TimedTaskStateScript]) -> bool:
		set_time_state_calls += 1
		return super(night, elapsed_units, night_ended, tasks)

	func set_trust_state(entries: Array[TrustRelationshipStateScript]) -> bool:
		set_trust_state_calls += 1
		return super(entries)

	func counters() -> Array[int]:
		return [apply_calls, set_resource_calls, set_flag_calls, set_time_state_calls, set_trust_state_calls, signal_count]


## Bir senaryo dünyası: yeni veri, yeni durum ve yeni sistem örnekleri.
class World extends RefCounted:
	var setup: InitialStateDataScript
	var limits: ResourceLimitsDataScript
	var trust_rules: TrustRulesDataScript
	var time_rules: TimeRulesDataScript
	var tasks_data: Array[TaskDataScript] = []
	var decisions_data: Array[DecisionDataScript] = []
	var advices_data: Array[AdviceDataScript] = []
	var subjects_data: Array[SubjectDataScript] = []
	var occurrences_data: Array[OccurrenceDataScript] = []
	var puzzles_data: Array[CablePuzzleDataScript] = []
	var endings_data: Array[EndingDataScript] = []

	var state: CountingGameState
	var resources: ResourceSystemScript
	var trust: TrustSystemScript
	var time: TimeSystemScript
	var completions: TaskCompletionSystemScript
	var decisions: DecisionSystemScript
	var tasks: TaskSystemScript
	var advice: AdviceSystemScript
	var occurrences: OccurrenceSystemScript
	var equipment: EquipmentSystemScript
	var cable: CableRepairSystemScript
	var endings: EndingResolverScript

	## Desteklenen bütün yapılandırma denetimleri, sistem adıyla önekli.
	func configuration_errors() -> PackedStringArray:
		var errors: PackedStringArray = []
		var checks: Dictionary = {
			"ResourceSystem": resources.get_configuration_errors(),
			"TrustSystem": trust.get_configuration_errors(),
			"TimeSystem": time.get_configuration_errors(),
			"TaskCompletionSystem": completions.get_configuration_errors(),
			"DecisionSystem": decisions.get_configuration_errors(),
			"TaskSystem": tasks.get_configuration_errors(),
			"AdviceSystem": advice.get_configuration_errors(),
			"OccurrenceSystem": occurrences.get_configuration_errors(),
			"CableRepairSystem": cable.get_configuration_errors(),
			"EndingResolver": endings.get_configuration_errors(),
		}
		for system_name: String in checks:
			for line: String in checks[system_name]:
				errors.append("%s: %s" % [system_name, line])
		return errors

	## Dünyanın bütün sistem örnekleri.
	func systems() -> Array[RefCounted]:
		return [resources, trust, time, completions, decisions, tasks, advice, occurrences, equipment, cable, endings]

	## Dünyanın verdiği bütün veri kaynakları ve alt kaynakları (derinlemesine).
	func all_resources() -> Array[Resource]:
		var roots: Array = [setup, limits, trust_rules, time_rules]
		for catalog: Array in [tasks_data, decisions_data, advices_data, subjects_data, occurrences_data, puzzles_data,
				endings_data]:
			roots.append_array(catalog)
		var result: Array[Resource] = []
		for root: Variant in roots:
			_collect(root, result)
		return result

	static func _collect(value: Variant, into: Array[Resource]) -> void:
		if value is Resource:
			var resource: Resource = value
			if into.has(resource):
				return
			into.append(resource)
			for property: Dictionary in resource.get_property_list():
				if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
					_collect(resource.get(property["name"]), into)
		elif value is Array:
			for item: Variant in value:
				_collect(item, into)


## Senaryo sürücüsü (yalnızca test yardımcısı): adımları sırayla açık üretim API'leriyle çalıştırır, her adımın
## sayaç farkını ve önceki/sonraki özetini kaydeder. Beklenmeyen sonuçta adımı başarısız kaydeder ve yolu durdurur;
## başka seçim, düzeltme veya yedek akış uygulamaz. Hiçbir yazma yöntemini doğrudan çağırmaz.
class ScenarioHarness extends RefCounted:
	var world: World
	var halted: bool = false
	var records: Array[Dictionary] = []
	var _test: TestCaseScript
	var _path: String

	func _init(p_world: World, test: TestCaseScript, path: String) -> void:
		world = p_world
		_test = test
		_path = path

	## action sonucu döndürür; accept(sonuç) false ise yol durur. writes: beklenen apply_changes ve sinyal sayısı
	## (0 veya 1). trust_writes: beklenen set_trust_state sayısı (yalnızca güven başlatmada 1).
	func step(label: String, writes: int, action: Callable, accept: Callable, trust_writes: int = 0) -> Variant:
		if halted:
			return null
		var before_summary: Array = FullScenarioFixtures.summary(world)
		var before: Array[int] = world.state.counters()
		var result: Variant = action.call()
		var after: Array[int] = world.state.counters()
		var after_summary: Array = FullScenarioFixtures.summary(world)
		var delta: Array[int] = []
		for i in before.size():
			delta.append(after[i] - before[i])
		var accepted: bool = accept.call(result)
		var expected: Array[int] = [writes, 0, 0, 0, trust_writes, maxi(writes, trust_writes)]
		records.append({
			"label": label, "accepted": accepted, "result": result, "delta": delta, "expected": expected,
			"changed": before_summary != after_summary, "before": before_summary, "after": after_summary,
		})
		_test.assert_true(accepted, "%s / %s: beklenmeyen üretim sonucu" % [_path, label])
		_test.assert_eq(delta, expected, "%s / %s: sayaç farkı %s" % [_path, label, COUNTER_NAMES])
		_test.assert_eq(before_summary != after_summary, expected[5] > 0,
				"%s / %s: özet yalnızca yazan adımda değişmeli" % [_path, label])
		if not accepted:
			halted = true
		return result

	func record(label: String) -> Dictionary:
		for entry: Dictionary in records:
			if entry["label"] == label:
				return entry
		return {}


## Tamamen yeni bir dünya: bütün veri, durum ve sistemler yeniden kurulur.
static func make_world() -> World:
	var world: World = World.new()
	world.setup = _make_setup()
	world.limits = _make_limits()
	world.trust_rules = _make_trust_rules()
	world.time_rules = _make_time_rules()
	world.tasks_data.append(_make_task())
	world.decisions_data.append(_make_decision())
	world.advices_data.append(_make_advice())
	world.subjects_data.append(_make_subject("subject_a"))
	world.subjects_data.append(_make_subject("subject_b"))
	world.occurrences_data.append(_make_occurrence(OCCURRENCE_A, "subject_a", 1))
	world.occurrences_data.append(_make_occurrence(OCCURRENCE_B, "subject_b", 2))
	world.puzzles_data.append(_make_puzzle())
	world.endings_data.append(_make_ending(ENDING_A, 1, [_occurrence_is(OCCURRENCE_A, OccurrenceStatusScript.STATUS_DEATH_PREVENTED),
			_occurrence_is(OCCURRENCE_B, OccurrenceStatusScript.STATUS_DEATH_PREVENTED)]))
	world.endings_data.append(_make_ending(ENDING_B, 2, []))

	# Kurulum sırası: durum → kaynak, güven, zaman → görev tamamlanma → karar, görev, öneri → görünüm → ekipman →
	# kablo → son.
	world.state = CountingGameState.new(world.setup)
	world.resources = ResourceSystemScript.new(world.state, world.limits)
	world.trust = TrustSystemScript.new(world.state, world.trust_rules)
	var events: Array[ScheduledEventDataScript] = []
	world.time = TimeSystemScript.new(world.state, world.time_rules, events)
	world.completions = TaskCompletionSystemScript.new(world.state, world.resources, world.trust, world.time,
			world.tasks_data)
	world.decisions = DecisionSystemScript.new(world.state, world.resources, world.trust, world.time, world.completions,
			world.decisions_data)
	world.tasks = TaskSystemScript.new(world.state, world.trust, world.time, world.completions, world.tasks_data)
	world.advice = AdviceSystemScript.new(world.state, world.trust, world.decisions, world.advices_data)
	world.occurrences = OccurrenceSystemScript.new(world.state, world.trust, world.time, world.subjects_data,
			world.occurrences_data)
	world.equipment = EquipmentSystemScript.new(world.state)
	world.cable = CableRepairSystemScript.new(world.state, world.resources, world.trust, world.time, world.completions,
			world.puzzles_data)
	world.endings = EndingResolverScript.new(world.state, world.trust, world.time, world.endings_data)
	return world


## Salt okunur, kimlik sırasıyla normalize edilmiş özet: [[alan, değer], ...] SUMMARY_FIELDS sırasıyla.
static func summary(world: World) -> Array:
	var state: GameStateScript = world.state
	var resolved: Variant = world.endings.resolve()
	var ending: Array = [String(resolved.status), String(resolved.ending_id)]

	var resources: Dictionary[StringName, int] = state.get_resources_snapshot()
	var flags: Dictionary[StringName, bool] = state.get_flags_snapshot()
	var occurrences: Dictionary[StringName, StringName] = state.get_occurrences_snapshot()
	var trust: Array = []
	for entry in state.get_trust_snapshot():
		trust.append([String(entry.source_actor_id), String(entry.target_actor_id), entry.value])
	var tasks: Array = []
	for task in state.get_tasks_snapshot():
		tasks.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	var equipment: Array = []
	for entry in state.get_equipment_snapshot():
		equipment.append([String(entry.equipment_id), String(entry.condition), String(entry.get_status()),
				entry.disabled_units])
	var cable: Array = []
	for entry in state.get_cable_puzzle_progress_snapshot():
		cable.append([String(entry.puzzle_id), entry.resolutions_used, entry.solved])
	return [
		["ending", ending],
		["time", [state.get_night(), state.get_elapsed_units(), state.is_night_ended()]],
		["resources", _sorted_pairs(resources)],
		["flags", _sorted_pairs(flags)],
		["trust", _sorted_rows(trust)],
		["tasks", _sorted_rows(tasks)],
		["occurrences", _sorted_pairs(occurrences)],
		["equipment", _sorted_rows(equipment)],
		["cable", _sorted_rows(cable)],
	]


## Özetten tek alan.
static func field(summary_rows: Array, name: String) -> Variant:
	for row: Array in summary_rows:
		if row[0] == name:
			return row[1]
	return null


## Durumlara göre görünüm sayıları.
static func occurrence_counts(world: World) -> Dictionary:
	var counts: Dictionary = {}
	for status: StringName in OccurrenceStatusScript.STATUSES:
		counts[String(status)] = 0
	var snapshot: Dictionary[StringName, StringName] = world.state.get_occurrences_snapshot()
	for occurrence_id: StringName in snapshot:
		counts[String(snapshot[occurrence_id])] += 1
	return counts


# --- Normalizasyon ---

static func _sorted_pairs(source: Dictionary) -> Array:
	var keys: Array[String] = []
	for key: Variant in source:
		keys.append(String(key))
	keys.sort()
	var result: Array = []
	for key: String in keys:
		var value: Variant = source[StringName(key)]
		result.append([key, String(value) if value is StringName else value])
	return result


static func _sorted_rows(rows: Array) -> Array:
	var result: Array = rows.duplicate(true)
	result.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	return result


# --- Veri kurucuları ---

static func _make_setup() -> InitialStateDataScript:
	var setup: InitialStateDataScript = InitialStateDataScript.new()
	setup.id = "scenario_setup"
	setup.starting_resources = {StringName(RESOURCE_A): 3}
	setup.rng_seed = 1
	setup.occurrence_ids = PackedStringArray([OCCURRENCE_A, OCCURRENCE_B])
	var equipment: InitialEquipmentDataScript = InitialEquipmentDataScript.new()
	equipment.id = EQUIPMENT_A
	equipment.condition = EquipmentStateScript.CONDITION_BROKEN
	setup.starting_equipment.append(equipment)
	setup.cable_puzzle_ids = PackedStringArray([PUZZLE_A])
	return setup


static func _make_limits() -> ResourceLimitsDataScript:
	var limits: ResourceLimitsDataScript = ResourceLimitsDataScript.new()
	limits.id = "scenario_limits"
	limits.min_values = {StringName(RESOURCE_A): 0}
	limits.max_values = {StringName(RESOURCE_A): 10}
	return limits


static func _make_trust_rules() -> TrustRulesDataScript:
	var rules: TrustRulesDataScript = TrustRulesDataScript.new()
	rules.id = "scenario_trust"
	rules.min_value = 0
	rules.max_value = 100
	for pair: Array in [[ACTOR_A, ACTOR_B], [ACTOR_B, ACTOR_A]]:
		var relationship: TrustRelationshipDataScript = TrustRelationshipDataScript.new()
		relationship.source_actor_id = pair[0]
		relationship.target_actor_id = pair[1]
		relationship.starting_value = 50
		rules.relationships.append(relationship)
	return rules


static func _make_time_rules() -> TimeRulesDataScript:
	var rules: TimeRulesDataScript = TimeRulesDataScript.new()
	rules.id = "scenario_time"
	rules.night_count = 2
	rules.night_length_units = 10
	rules.action_costs = {StringName(ACTION_CABLE): 2, StringName(ACTION_ASSIGN): 1, StringName(ACTION_DECIDE): 1}
	return rules


static func _make_task() -> TaskDataScript:
	var assignment: TaskAssignmentDataScript = TaskAssignmentDataScript.new()
	assignment.active_actor_id = ACTOR_A
	assignment.assigned_actor_id = ACTOR_B
	assignment.action_id = ACTION_ASSIGN
	assignment.acceptance_conditions.append(_trust_at_least(ACTOR_B, ACTOR_A, 40))
	assignment.acceptance_conditions.append(_equipment_is(EQUIPMENT_A, EquipmentStateScript.STATUS_OPERATIONAL))
	var task: TaskDataScript = TaskDataScript.new()
	task.id = TASK_A
	task.duration_units = 3
	task.assignment = assignment
	task.completion_effects.append(_prevent_death(OCCURRENCE_A))
	task.completion_effects.append(_trust_change(ACTOR_B, ACTOR_A, 5))
	return task


static func _make_decision() -> DecisionDataScript:
	var choice_a: ChoiceDataScript = ChoiceDataScript.new()
	choice_a.id = CHOICE_A
	choice_a.conditions.append(_resource_at_least(RESOURCE_A, 1))
	choice_a.effects.append(_prevent_death(OCCURRENCE_B))
	choice_a.effects.append(_resource_spend(RESOURCE_A, 1))
	choice_a.effects.append(_flag_set(FLAG_A, true))
	choice_a.action_id = ACTION_DECIDE
	var choice_b: ChoiceDataScript = ChoiceDataScript.new()
	choice_b.id = CHOICE_B
	choice_b.effects.append(_trust_change(ACTOR_A, ACTOR_B, -5))
	choice_b.action_id = ACTION_DECIDE
	var decision: DecisionDataScript = DecisionDataScript.new()
	decision.id = DECISION_A
	decision.choices.append(choice_a)
	decision.choices.append(choice_b)
	return decision


static func _make_advice() -> AdviceDataScript:
	var context: AdviceContextDataScript = AdviceContextDataScript.new()
	context.advisor_actor_id = ACTOR_B
	context.recipient_actor_id = ACTOR_A
	context.decision_id = DECISION_A
	var variant_a: AdviceVariantDataScript = AdviceVariantDataScript.new()
	variant_a.id = VARIANT_A
	variant_a.accuracy = AdviceVariantDataScript.ACCURACY_INCORRECT
	variant_a.conditions.append(_occurrence_is(OCCURRENCE_A, OccurrenceStatusScript.STATUS_DEATH_PREVENTED))
	variant_a.recommended_choice_id = CHOICE_B
	var variant_b: AdviceVariantDataScript = AdviceVariantDataScript.new()
	variant_b.id = VARIANT_B
	variant_b.accuracy = AdviceVariantDataScript.ACCURACY_CORRECT
	variant_b.recommended_choice_id = CHOICE_A
	var advice: AdviceDataScript = AdviceDataScript.new()
	advice.id = ADVICE_A
	advice.context = context
	advice.presentation_conditions.append(_trust_at_least(ACTOR_B, ACTOR_A, 40))
	advice.variants.append(variant_a)
	advice.variants.append(variant_b)
	return advice


static func _make_subject(id: String) -> SubjectDataScript:
	var subject: SubjectDataScript = SubjectDataScript.new()
	subject.id = id
	return subject


static func _make_occurrence(id: String, subject_id: String, night: int) -> OccurrenceDataScript:
	var occurrence: OccurrenceDataScript = OccurrenceDataScript.new()
	occurrence.id = id
	occurrence.subject_id = subject_id
	occurrence.night = night
	return occurrence


static func _make_puzzle() -> CablePuzzleDataScript:
	var puzzle: CablePuzzleDataScript = CablePuzzleDataScript.new()
	puzzle.id = PUZZLE_A
	for terminal: Array in [[TERMINAL_A, CableTerminalDataScript.SIDE_LEFT], [TERMINAL_C, CableTerminalDataScript.SIDE_LEFT],
			[TERMINAL_B, CableTerminalDataScript.SIDE_RIGHT], [TERMINAL_D, CableTerminalDataScript.SIDE_RIGHT]]:
		var data: CableTerminalDataScript = CableTerminalDataScript.new()
		data.id = String(terminal[0])
		data.side = terminal[1]
		puzzle.terminals.append(data)
	for pair: Array in [[TERMINAL_A, TERMINAL_B], [TERMINAL_C, TERMINAL_D]]:
		var connection: CableConnectionDataScript = CableConnectionDataScript.new()
		connection.terminal_a = String(pair[0])
		connection.terminal_b = String(pair[1])
		puzzle.required_connections.append(connection)
	var rules: CablePuzzleRulesDataScript = CablePuzzleRulesDataScript.new()
	rules.equipment_id = EQUIPMENT_A
	rules.max_submissions = 1
	rules.max_resolutions = 1
	puzzle.rules = rules
	puzzle.start_conditions.append(_equipment_is(EQUIPMENT_A, EquipmentStateScript.STATUS_BROKEN))
	var success: CablePuzzleOutcomeDataScript = CablePuzzleOutcomeDataScript.new()
	success.effects.append(_equipment_effect(EffectDataScript.KIND_EQUIPMENT_REPAIR, EQUIPMENT_A, 0))
	success.action_id = ACTION_CABLE
	puzzle.success = success
	var failure: CablePuzzleOutcomeDataScript = CablePuzzleOutcomeDataScript.new()
	failure.effects.append(_equipment_effect(EffectDataScript.KIND_EQUIPMENT_DISABLE, EQUIPMENT_A, 4))
	failure.effects.append(_resource_spend(RESOURCE_A, 1))
	failure.action_id = ACTION_CABLE
	puzzle.failure = failure
	return puzzle


static func _make_ending(id: String, priority: int, conditions: Array) -> EndingDataScript:
	var ending: EndingDataScript = EndingDataScript.new()
	ending.id = id
	ending.priority = priority
	for condition: ConditionDataScript in conditions:
		ending.conditions.append(condition)
	return ending


# --- Koşul ve etki kurucuları ---

static func _trust_at_least(source: String, target: String, value: int) -> ConditionDataScript:
	var condition: ConditionDataScript = ConditionDataScript.new()
	condition.kind = ConditionDataScript.KIND_TRUST
	condition.source_actor_id = source
	condition.target_actor_id = target
	condition.comparison = ConditionDataScript.COMPARISON_GE
	condition.value = value
	return condition


static func _resource_at_least(resource_id: String, value: int) -> ConditionDataScript:
	var condition: ConditionDataScript = ConditionDataScript.new()
	condition.kind = ConditionDataScript.KIND_RESOURCE
	condition.resource_id = resource_id
	condition.comparison = ConditionDataScript.COMPARISON_GE
	condition.value = value
	return condition


static func _occurrence_is(occurrence_id: String, status: StringName) -> ConditionDataScript:
	var condition: ConditionDataScript = ConditionDataScript.new()
	condition.kind = ConditionDataScript.KIND_OCCURRENCE
	condition.occurrence_id = occurrence_id
	condition.occurrence_status = status
	return condition


static func _equipment_is(equipment_id: String, status: StringName) -> ConditionDataScript:
	var condition: ConditionDataScript = ConditionDataScript.new()
	condition.kind = ConditionDataScript.KIND_EQUIPMENT
	condition.equipment_id = equipment_id
	condition.equipment_status = status
	return condition


static func _prevent_death(occurrence_id: String) -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.kind = EffectDataScript.KIND_OCCURRENCE_PREVENT_DEATH
	effect.occurrence_id = occurrence_id
	return effect


static func _trust_change(source: String, target: String, amount: int) -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.kind = EffectDataScript.KIND_TRUST_CHANGE
	effect.source_actor_id = source
	effect.target_actor_id = target
	effect.amount = amount
	return effect


static func _resource_spend(resource_id: String, amount: int) -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.kind = EffectDataScript.KIND_RESOURCE_SPEND
	effect.resource_id = resource_id
	effect.amount = amount
	return effect


static func _flag_set(flag_id: String, value: bool) -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.kind = EffectDataScript.KIND_FLAG_SET
	effect.flag_id = flag_id
	effect.flag_value = value
	return effect


static func _equipment_effect(kind: StringName, equipment_id: String, amount: int) -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.kind = kind
	effect.equipment_id = equipment_id
	effect.amount = amount
	return effect
