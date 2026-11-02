class_name TaskCompletionSystem
extends RefCounted
## Görev tamamlanma etkilerini zaman ilerlemesiyle aynı atomik pakette hesaplar (K-025, K-027).
##
## Zaman sınırı: Oyun akışında zaman yalnızca bu sınıf üzerinden ilerler. Seçimden bağımsız zaman için
## advance, zaman harcayan seçim ve görev denemeleri için plan_time kullanılır. TimeSystem.advance düşük
## seviyeli bir uyumluluk yöntemidir; tamamlanma etkilerini uygulamaz ve üretim akışında çağrılmaz.
##
## Sıra: pakette önceden bulunan değişiklikler (ör. oyuncunun seçim etkileri) korunur; tamamlanan görevler
## TimeOccurrence kronolojik sırasıyla (aynı anda bitenler kimlik sırasıyla), her görevin etkileri veri
## sırasıyla, biriken değer üzerinde ve her biri ayrı ayrı sınırda kesilerek uygulanır. Plan geceyi bitiriyorsa
## en son, hâlâ pending olan ceset görünümleri death_permanent yapılır (K-029); böylece gece sınırında ölümü
## engelleyen bir etki kalıcılaştırmadan önce uygulanmış olur.
##
## Görev düzeyinde atomiklik: Her görevin etkileri ana paketin bağımsız bir geçici kopyasında planlanır.
## Hepsi uygulanabilirse kopya ana pakete kabul edilir; biri uygulanamazsa (yetersiz harcama) kopya atılır,
## görev yine tamamlanır ve sonucu effects_not_applicable olur. Önceki görevlerin ve seçimin etkileri korunur.
##
## Etkin veya tamamlanan her görevin bu katalogda tanımı olmalıdır; tanımsız görev yapılandırma hatasıdır.
## Rastgele sayı üreteci kullanılmaz.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")
const TimeOccurrenceScript := preload("res://scripts/systems/time_occurrence.gd")
const EffectPlannerScript := preload("res://scripts/systems/effect_planner.gd")
const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")
const TaskCompletionPlanScript := preload("res://scripts/systems/task_completion_plan.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")
const EquipmentSystemScript := preload("res://scripts/systems/equipment_system.gd")
const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

var _state: GameStateScript
var _resources: ResourceSystemScript
var _trust: TrustSystemScript
var _time: TimeSystemScript
var _effects: EffectPlannerScript
# Görevlerin kimlik ve tamamlanma etkilerinin bağımsız kopyaları; boş kayıtlar hata raporu için tutulur.
# Atama alanları burada kullanılmaz (TaskSystem'in işidir).
var _tasks: Array[TaskDataScript] = []


func _init(state: GameStateScript, resource_system: ResourceSystemScript, trust_system: TrustSystemScript,
		time_system: TimeSystemScript, tasks: Array[TaskDataScript]) -> void:
	if state == null or resource_system == null or trust_system == null or time_system == null:
		push_error("TaskCompletionSystem: oyun durumu ve bütün bağımlı sistemler verilmelidir.")
	_state = state
	_resources = resource_system
	_trust = trust_system
	_time = time_system
	_effects = EffectPlannerScript.new(state, resource_system, trust_system)
	for task in tasks:
		_tasks.append(null if task == null else _copy_task(task))


## Bağımlı sistemlerin hataları ve get_catalog_errors; deterministik sırayla, hiçbir değeri düzeltmeden.
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
	if _state == null or _resources == null or _trust == null or _time == null:
		return errors
	errors.append_array(get_catalog_errors())
	return errors


## Yalnızca bu sistemin kendi hataları: katalog (kimlikler, tamamlanma etkileri) ve durumdaki etkin
## görevlerin tanımları. Bağımlı sistem hatalarını içermez; aynı sistemleri kullanan DecisionSystem ve
## TaskSystem bunu kendi listelerine ekler. Bağımlılıklar verilmemişse boş döner.
func get_catalog_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if _state == null or _resources == null or _trust == null or _time == null:
		return errors
	var seen_ids: Array[String] = []
	for i in _tasks.size():
		var task: TaskDataScript = _tasks[i]
		if task == null:
			errors.append("Tanımsız görev kaydı (#%d)" % i)
			continue
		if task.id.is_empty():
			errors.append("Boş görev kimliği (#%d)" % i)
		elif seen_ids.has(task.id):
			errors.append("Tekrarlanan görev kimliği: '%s'" % task.id)
		else:
			seen_ids.append(task.id)
		for j in task.completion_effects.size():
			var effect: EffectDataScript = task.completion_effects[j]
			var p: String = "'%s' tamamlanma etkisi #%d: " % [task.id, j]
			errors.append_array(_effects.get_errors(p, effect))
			for k in j:
				if _effects.is_same_target(task.completion_effects[k], effect):
					errors.append(p + "aynı hedefe birden fazla etki (#%d ile)" % k)
					break
	for active_task in _state.get_tasks_snapshot():
		if _find_task(active_task.task_id) == null:
			errors.append("Etkin görevin tanımı yok: '%s'" % active_task.task_id)
	return errors


func has_definition(task_id: StringName) -> bool:
	return _find_task(task_id) != null


## Zamanı amount kadar yazmadan planlar ve tamamlanan görevlerin etkilerini change'e ekler (K-027).
## change'te önceden bulunan değerler korunur ve biriken değer olarak kullanılır. Zaman alanlarını change'e
## yazmak çağıranın işidir (plan.time_plan). Durumu değiştirmez, sinyal yaymaz ve hata basmaz; geçersiz
## istekte change'e dokunulmaz ve plan.failure doldurulur.
func plan_time(amount: int, change: GameStateChangeScript) -> TaskCompletionPlanScript:
	var plan: TaskCompletionPlanScript = TaskCompletionPlanScript.new()
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		plan.failure = TaskCompletionPlanScript.FAILURE_INVALID_CONFIGURATION
		plan.error_message = "TaskCompletionSystem: geçersiz yapılandırma; zaman planlanamaz: %s" % " | ".join(errors)
		return plan
	var time_plan: TimeAdvancePlanScript = _time.plan_advance(amount)
	if not time_plan.is_valid():
		plan.failure = time_plan.failure
		plan.error_message = time_plan.error_message
		return plan

	var completed: Array[TimeOccurrenceScript] = []
	for occurrence in time_plan.result.occurrences:
		if occurrence.kind == TimeOccurrenceScript.Kind.TASK_COMPLETED:
			completed.append(occurrence)
	for occurrence in completed:
		var task: TaskDataScript = _find_task(occurrence.id)
		# Etkin görevler yapılandırmada doğrulandığı için buraya yalnızca tutarsız bir plan düşebilir.
		if task == null:
			plan.failure = TaskCompletionPlanScript.FAILURE_INVALID_CONFIGURATION
			plan.error_message = "TaskCompletionSystem: tamamlanan görevin tanımı yok: '%s'" % occurrence.id
			return plan
		if _effects.uses_trust(task.completion_effects) and not _trust.is_initialized():
			plan.failure = TaskCompletionPlanScript.FAILURE_SYSTEM_NOT_READY
			plan.error_message = "TaskCompletionSystem: güven başlatılmadı; güven etkili görev tamamlanamaz: '%s'" \
					% occurrence.id
			return plan

	# Bütün denetimler geçti; change yalnızca bundan sonra güncellenir. Zaman, görev tamamlanma anlarında
	# parçalara bölünür (K-031): her parçada ekipman sayaçları bir kez azalır, aynı anda biten sayaç görev
	# etkisinden önce biter, görev etkisi gerçek tamamlanma anında uygulanır, son parça gecenin ilerlemesinin
	# sonuna kadar işlenir. Aynı andaki görevler arasında zaman ilerlemez.
	var night: int = time_plan.night
	var cursor: int = _state.get_elapsed_units()
	var index: int = 0
	while index < completed.size():
		var moment: int = completed[index].at_units
		plan.equipment_disable_expirations.append_array(
				EquipmentSystemScript.plan_countdown(_state, change, night, cursor, moment))
		cursor = moment
		while index < completed.size() and completed[index].at_units == moment:
			plan.completions.append(_complete(completed[index], _find_task(completed[index].id), change))
			index += 1
	plan.equipment_disable_expirations.append_array(
			EquipmentSystemScript.plan_countdown(_state, change, night, cursor, time_plan.elapsed_units))
	# Gece sonu, seçim ve tamamlanma etkilerinden ve bütün sayaçlardan sonra gelir: hâlâ pending olan
	# görünümler kalıcı olur (K-029).
	if time_plan.night_ended:
		plan.permanent_occurrence_ids = OccurrenceSystemScript.plan_night_end(_state, change)
	plan.time_plan = time_plan
	return plan


## advance'in yapacağını yazmadan hesaplar. Hatalar advance ile aynı biçimde basılır.
func preview_advance(amount: int) -> TimeProgressResultScript:
	return _evaluate(amount, GameStateChangeScript.new())


## Seçimden bağımsız zaman ilerlemesi: zaman, kalan görevler ve tamamlanma etkileri tek apply_changes ile
## yazılır. Hatalı yapılandırma, başlatılmamış güven (güven etkili görev tamamlanırken), negatif miktar,
## etkin olmayan gece ve başarısız yazma hata verir ve hiçbir şeyi değiştirmez.
func advance(amount: int) -> TimeProgressResultScript:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var result: TimeProgressResultScript = _evaluate(amount, change)
	if not result.ok or result.time_result.applied_units == 0:
		return result
	if not _state.apply_changes(change):
		push_error("TaskCompletionSystem: durum yazılamadı; zaman ilerlemesi uygulanmadı.")
		return _failed(TimeProgressResultScript.FAILURE_WRITE_FAILED)
	return result


# --- Planlama ---

func _evaluate(amount: int, change: GameStateChangeScript) -> TimeProgressResultScript:
	var plan: TaskCompletionPlanScript = plan_time(amount, change)
	if not plan.is_valid():
		push_error(plan.error_message)
		return _failed(plan.failure)
	var time_plan: TimeAdvancePlanScript = plan.time_plan
	change.set_time_state(time_plan.night, time_plan.elapsed_units, time_plan.night_ended, time_plan.tasks)
	var result: TimeProgressResultScript = TimeProgressResultScript.new()
	result.ok = true
	result.time_result = time_plan.result
	result.completions = plan.completions
	result.permanent_occurrence_ids = plan.permanent_occurrence_ids
	result.equipment_disable_expirations = copy_expirations(plan.equipment_disable_expirations)
	return result


# Görevin bütün etkilerini geçici kopyada planlar; hepsi uygulanabilirse kopyayı change'e kabul eder.
func _complete(occurrence: TimeOccurrenceScript, task: TaskDataScript,
		change: GameStateChangeScript) -> TaskCompletionOutcomeScript:
	var outcome: TaskCompletionOutcomeScript = TaskCompletionOutcomeScript.new()
	outcome.task_id = occurrence.id
	outcome.assigned_actor_id = occurrence.assigned_actor_id
	outcome.night = occurrence.night
	outcome.at_units = occurrence.at_units
	var scratch: GameStateChangeScript = _copy_effect_values(change)
	var effect_outcomes: Array[DecisionEffectOutcomeScript] = []
	for i in task.completion_effects.size():
		var effect_outcome: DecisionEffectOutcomeScript = _effects.plan(i, task.completion_effects[i], scratch)
		if effect_outcome == null:
			outcome.status = TaskCompletionOutcomeScript.STATUS_EFFECTS_NOT_APPLICABLE
			outcome.blocking_effect_index = i
			return outcome
		effect_outcomes.append(effect_outcome)
	change.resource_values = scratch.resource_values
	change.flag_values = scratch.flag_values
	change.trust_values = scratch.trust_values
	change.occurrence_statuses = scratch.occurrence_statuses
	change.equipment_values = scratch.equipment_values
	outcome.status = TaskCompletionOutcomeScript.STATUS_APPLIED
	outcome.effect_outcomes = effect_outcomes
	return outcome


# Etkilerin dokunduğu alanların (kaynak, bayrak, güven, görünüm, ekipman) bağımsız kopyası; zaman alanları
# kopyalanmaz.
func _copy_effect_values(change: GameStateChangeScript) -> GameStateChangeScript:
	var copy: GameStateChangeScript = GameStateChangeScript.new()
	copy.resource_values = change.resource_values.duplicate()
	copy.flag_values = change.flag_values.duplicate()
	copy.occurrence_statuses = change.occurrence_statuses.duplicate()
	for entry in change.trust_values:
		copy.trust_values.append(entry.copy())
	for entry in change.equipment_values:
		copy.equipment_values.append(entry.copy())
	return copy


## Süre bitiş kayıtlarının bağımsız kopyaları; sonuç nesneleri plandaki kayıtları paylaşmaz.
static func copy_expirations(source: Array[EquipmentDisableExpirationScript]) -> Array[EquipmentDisableExpirationScript]:
	var result: Array[EquipmentDisableExpirationScript] = []
	for expiration in source:
		result.append(expiration.copy())
	return result


func _find_task(task_id: StringName) -> TaskDataScript:
	for task in _tasks:
		if task != null and StringName(task.id) == task_id:
			return task
	return null


func _failed(failure: StringName) -> TimeProgressResultScript:
	var result: TimeProgressResultScript = TimeProgressResultScript.new()
	result.failure = failure
	return result


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result


# --- Kopyalama ---

func _copy_task(task: TaskDataScript) -> TaskDataScript:
	var copy: TaskDataScript = TaskDataScript.new()
	copy.id = task.id
	for effect in task.completion_effects:
		copy.completion_effects.append(null if effect == null else effect.copy())
	return copy
