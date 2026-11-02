class_name DecisionSystem
extends RefCounted
## Oyuncunun açıkça seçtiği seçeneği koşullarına göre değerlendirir ve bütün etkilerini, varsa eylemin
## zaman ilerlemesi ve o sürede tamamlanan görevlerin etkileriyle birlikte, tek bir atomik GameStateChange
## olarak uygular (K-024, K-025, K-027).
##
## - Seçim asla değiştirilmez: uygulanamayan seçenekte başka bir seçeneğe geçilmez.
## - Yeni değerler yan etkisiz hesaplanır (EffectPlanner, TaskCompletionSystem.plan_time); durum yalnızca
##   GameState.apply_changes ile, seçim başına bir kez yazılır. Böylece birden fazla sistemi değiştiren bir
##   seçim yarım uygulanmış kalamaz.
## - Zaman yalnızca TaskCompletionSystem.plan_time ile planlanır; TimeSystem.advance/plan_advance doğrudan
##   kullanılmaz, böylece eylem süresinde biten görevlerin etkileri atlanamaz. Seçimin etkileri önce,
##   tamamlanma etkileri sonra ve biriken değer üzerinden uygulanır.
## - Güven bir önerinin doğruluğunu belirlemez; bu sınıf rastgele sayı üreteci kullanmaz.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TaskCompletionPlanScript := preload("res://scripts/systems/task_completion_plan.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const ChoiceDataScript := preload("res://scripts/data/choice_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")
const ConditionEvaluatorScript := preload("res://scripts/systems/condition_evaluator.gd")
const EffectPlannerScript := preload("res://scripts/systems/effect_planner.gd")

## Geriye dönük uyumluluk için; tek kaynak ConditionEvaluator'dır.
const COMPARISONS: Array[StringName] = ConditionEvaluatorScript.COMPARISONS

var _state: GameStateScript
var _resources: ResourceSystemScript
var _trust: TrustSystemScript
var _time: TimeSystemScript
var _completions: TaskCompletionSystemScript
# Koşul değerlendirme ve doğrulamasının tek kaynağı (K-026).
var _conditions: ConditionEvaluatorScript
# Etki planlama ve doğrulamasının tek kaynağı (K-027).
var _effects: EffectPlannerScript
# Kararların bağımsız derin kopyaları; boş kayıtlar hata raporu için yerinde tutulur.
var _decisions: Array[DecisionDataScript] = []


## task_completion_system zorunludur; aynı oyun durumu ve sistemlerle kurulmuş olmalıdır.
func _init(state: GameStateScript, resource_system: ResourceSystemScript, trust_system: TrustSystemScript,
		time_system: TimeSystemScript, task_completion_system: TaskCompletionSystemScript,
		decisions: Array[DecisionDataScript]) -> void:
	if state == null or resource_system == null or trust_system == null or time_system == null \
			or task_completion_system == null:
		push_error("DecisionSystem: oyun durumu ve bütün bağımlı sistemler verilmelidir.")
	_state = state
	_resources = resource_system
	_trust = trust_system
	_time = time_system
	_completions = task_completion_system
	_conditions = ConditionEvaluatorScript.new(state, trust_system)
	_effects = EffectPlannerScript.new(state, resource_system, trust_system)
	for decision in decisions:
		_decisions.append(null if decision == null else _copy_decision(decision))


## Bağımlı sistemlerin, kararların, seçeneklerin, koşul ve etkilerin tutarsızlıklarını deterministik
## sırayla döndürür; hiçbir değeri düzeltmez ve motor hatası üretmez.
func get_configuration_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if _state == null:
		errors.append("Oyun durumu verilmedi")
	if _resources == null:
		errors.append("Kaynak sistemi verilmedi")
	else:
		errors.append_array(_prefixed("ResourceSystem: ", _resources.get_configuration_errors()))
	if _trust == null:
		errors.append("Güven sistemi verilmedi")
	else:
		errors.append_array(_prefixed("TrustSystem: ", _trust.get_configuration_errors()))
	if _time == null:
		errors.append("Zaman sistemi verilmedi")
	else:
		errors.append_array(_prefixed("TimeSystem: ", _time.get_configuration_errors()))
	if _completions == null:
		errors.append("Görev tamamlanma sistemi verilmedi")
	else:
		errors.append_array(_prefixed("TaskCompletionSystem: ", _completions.get_catalog_errors()))
	if _state == null or _resources == null or _trust == null or _time == null or _completions == null:
		return errors

	var seen_decision_ids: Array[String] = []
	for i in _decisions.size():
		var decision: DecisionDataScript = _decisions[i]
		if decision == null:
			errors.append("Tanımsız karar kaydı (#%d)" % i)
			continue
		if decision.id.is_empty():
			errors.append("Boş karar kimliği (#%d)" % i)
		elif seen_decision_ids.has(decision.id):
			errors.append("Tekrarlanan karar kimliği: '%s'" % decision.id)
		else:
			seen_decision_ids.append(decision.id)
		if decision.choices.is_empty():
			errors.append("Kararda seçenek yok: '%s'" % decision.id)
		var seen_choice_ids: Array[String] = []
		for j in decision.choices.size():
			var choice: ChoiceDataScript = decision.choices[j]
			if choice == null:
				errors.append("'%s' seçenek #%d: tanımsız kayıt" % [decision.id, j])
				continue
			if choice.id.is_empty():
				errors.append("'%s' seçenek #%d: boş seçenek kimliği" % [decision.id, j])
			elif seen_choice_ids.has(choice.id):
				errors.append("'%s' seçenek #%d: tekrarlanan seçenek kimliği '%s'" % [decision.id, j, choice.id])
			else:
				seen_choice_ids.append(choice.id)
			errors.append_array(_choice_errors("'%s' / '%s'" % [decision.id, choice.id], choice))
	return errors


func has_choice(decision_id: StringName, choice_id: StringName) -> bool:
	return _find_choice(decision_id, choice_id) != null


## Kararın seçenek kimlikleri, veri sırasıyla. Tanımsız kararda boş liste; hata vermez.
func get_choice_ids(decision_id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = []
	for decision in _decisions:
		if decision != null and StringName(decision.id) == decision_id:
			for choice in decision.choices:
				if choice != null:
					ids.append(StringName(choice.id))
			break
	return ids


## Seçimi yan etkisiz değerlendirir: hiçbir şey yazmaz, sinyal yaymaz. choose ile aynı sonuç biçimi.
## Sonuçtaki görev tamamlanma ayrıntıları iç sistem verisidir; oyuncuya gizli bilgiyi bedelsiz açıklamak
## için kullanılmaz.
func preview_choice(decision_id: StringName, choice_id: StringName) -> DecisionResultScript:
	return _plan(decision_id, choice_id, GameStateChangeScript.new())


func is_choice_available(decision_id: StringName, choice_id: StringName) -> bool:
	return preview_choice(decision_id, choice_id).ok


## Yalnızca verilen seçeneği uygular. Mevcut durumu yeniden değerlendirip taze bir plan kurar
## (önceden alınmış bir önizleme kullanılmaz) ve geçerliyse durumu tek apply_changes ile yazar.
func choose(decision_id: StringName, choice_id: StringName) -> DecisionResultScript:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var result: DecisionResultScript = _plan(decision_id, choice_id, change)
	if not result.ok:
		return result
	if not _state.apply_changes(change):
		push_error("DecisionSystem: durum yazılamadı; seçim uygulanmadı: '%s' / '%s'" % [decision_id, choice_id])
		return _failed(decision_id, choice_id, DecisionResultScript.FAILURE_WRITE_FAILED)
	return result


# --- Planlama ---

# Seçimi değerlendirir ve geçerliyse yazılacak yeni değerleri change'e ekler; hiçbir şey yazmaz.
func _plan(decision_id: StringName, choice_id: StringName, change: GameStateChangeScript) -> DecisionResultScript:
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		push_error("DecisionSystem: geçersiz yapılandırma; seçim değerlendirilemez: %s" % " | ".join(errors))
		return _failed(decision_id, choice_id, DecisionResultScript.FAILURE_INVALID_CONFIGURATION)
	var choice: ChoiceDataScript = _find_choice(decision_id, choice_id)
	if choice == null:
		push_error("DecisionSystem: tanımsız karar veya seçenek: '%s' / '%s'" % [decision_id, choice_id])
		return _failed(decision_id, choice_id, DecisionResultScript.FAILURE_UNKNOWN_CHOICE)
	if _uses_trust(choice) and not _trust.is_initialized():
		push_error("DecisionSystem: güven başlatılmadı; güven kullanan seçim değerlendirilemez: '%s' / '%s'"
				% [decision_id, choice_id])
		return _failed(decision_id, choice_id, DecisionResultScript.FAILURE_SYSTEM_NOT_READY)

	var failed_conditions: PackedInt32Array = _conditions.get_failed_indexes(choice.conditions)
	if not failed_conditions.is_empty():
		var not_met: DecisionResultScript = _failed(decision_id, choice_id, DecisionResultScript.FAILURE_CONDITIONS_NOT_MET)
		not_met.failed_condition_indexes = failed_conditions
		return not_met

	# Aynı seçimde aynı hedefe birden fazla etki yasak olduğu için her etki mevcut değerden hesaplanır.
	var outcomes: Array[DecisionEffectOutcomeScript] = []
	for i in choice.effects.size():
		var outcome: DecisionEffectOutcomeScript = _effects.plan(i, choice.effects[i], change)
		if outcome == null:
			var blocked: DecisionResultScript = _failed(decision_id, choice_id,
					DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE)
			blocked.blocking_effect_index = i
			return blocked
		outcomes.append(outcome)

	var result: DecisionResultScript = DecisionResultScript.new()
	if not choice.action_id.is_empty():
		# Tamamlanma etkileri seçimin etkilerinden sonra, aynı pakete birikerek eklenir.
		var plan: TaskCompletionPlanScript = _completions.plan_time(_time.cost_of(StringName(choice.action_id)), change)
		if plan.failure == TaskCompletionPlanScript.FAILURE_NIGHT_NOT_ACTIVE:
			return _failed(decision_id, choice_id, DecisionResultScript.FAILURE_TIME_UNAVAILABLE)
		if plan.failure == TaskCompletionPlanScript.FAILURE_SYSTEM_NOT_READY:
			push_error(plan.error_message)
			return _failed(decision_id, choice_id, DecisionResultScript.FAILURE_SYSTEM_NOT_READY)
		if not plan.is_valid():
			push_error("DecisionSystem: zaman planlanamadı: %s" % plan.error_message)
			return _failed(decision_id, choice_id, DecisionResultScript.FAILURE_INVALID_CONFIGURATION)
		var time_plan: TimeAdvancePlanScript = plan.time_plan
		change.set_time_state(time_plan.night, time_plan.elapsed_units, time_plan.night_ended, time_plan.tasks)
		result.time_result = time_plan.result
		result.task_completions = plan.completions
		result.equipment_disable_expirations = TaskCompletionSystemScript.copy_expirations(plan.equipment_disable_expirations)

	result.ok = true
	result.decision_id = decision_id
	result.choice_id = choice_id
	result.effect_outcomes = outcomes
	return result


func _uses_trust(choice: ChoiceDataScript) -> bool:
	return _conditions.uses_trust(choice.conditions) or _effects.uses_trust(choice.effects)


func _find_choice(decision_id: StringName, choice_id: StringName) -> ChoiceDataScript:
	for decision in _decisions:
		if decision == null or StringName(decision.id) != decision_id:
			continue
		for choice in decision.choices:
			if choice != null and StringName(choice.id) == choice_id:
				return choice
	return null


func _failed(decision_id: StringName, choice_id: StringName, failure: StringName) -> DecisionResultScript:
	var result: DecisionResultScript = DecisionResultScript.new()
	result.decision_id = decision_id
	result.choice_id = choice_id
	result.failure = failure
	return result


# --- Doğrulama ---

func _choice_errors(prefix: String, choice: ChoiceDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	for i in choice.conditions.size():
		errors.append_array(_conditions.get_errors("%s koşul #%d: " % [prefix, i], choice.conditions[i]))
	for j in choice.effects.size():
		var effect: EffectDataScript = choice.effects[j]
		var effect_prefix: String = "%s etki #%d: " % [prefix, j]
		errors.append_array(_effects.get_errors(effect_prefix, effect))
		for i in j:
			if _effects.is_same_target(choice.effects[i], effect):
				errors.append(effect_prefix + "aynı hedefe birden fazla etki (#%d ile)" % i)
				break
	if not choice.action_id.is_empty() and not _time.has_action_cost(StringName(choice.action_id)):
		errors.append("%s: tanımsız eylem '%s'" % [prefix, choice.action_id])
	return errors


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result


# --- Kopyalama ---

func _copy_decision(decision: DecisionDataScript) -> DecisionDataScript:
	var copy: DecisionDataScript = DecisionDataScript.new()
	copy.id = decision.id
	for choice in decision.choices:
		copy.choices.append(null if choice == null else _copy_choice(choice))
	return copy


func _copy_choice(choice: ChoiceDataScript) -> ChoiceDataScript:
	var copy: ChoiceDataScript = ChoiceDataScript.new()
	copy.id = choice.id
	copy.action_id = choice.action_id
	for condition in choice.conditions:
		copy.conditions.append(null if condition == null else condition.copy())
	for effect in choice.effects:
		copy.effects.append(null if effect == null else effect.copy())
	return copy
