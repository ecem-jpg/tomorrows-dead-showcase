class_name MainHudPresenter
extends RefCounted
## Ana arayüzün sunum katmanı: mevcut sistemlerin açık API'lerinden salt okunur MainHudModel kurar ve kullanıcı
## komutlarını sistemlere iletir. İş kuralı uygulamaz; kararları sistemler verir.
##
## - Bir komut en fazla bir durum değiştiren sistem çağrısı yapar (assign_task, choose, advance, start_night,
##   start_session, apply_result). Salt okunur sorgular (ör. cost_of, plan_start_night) buna dahil değildir.
## - GameState.apply_changes, set_* veya sistemlerin özel yöntemleri hiçbir zaman çağrılmaz.
## - Başarısız komut başka bir komuta dönüşmez; öneri otomatik seçilmez. Öneri yalnızca get_advice ile okunur.
## - Geçersiz yapılandırma veya yapılandırma dışı kimlik presenter düzeyinde reddedilir: hiçbir sistem çağrılmaz,
##   motor hatası basılmaz, komut null döner ve geri bildirim UI_HUD_ERROR olur. Ayrıntı get_configuration_errors'tadır.
## - build_model yazmaz ve sinyal yaymaz; aynı durumdan aynı içerik çıkar. Önizlemeler yalnızca etkin gecede yapılır.
## - Komutlar sistemlerin sonuç nesnelerini olduğu gibi döndürür; presenter reddederse null döner. Arayüz için
##   yalnızca genel bir geri bildirim anahtarı saklanır.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const AdviceSystemScript := preload("res://scripts/systems/advice_system.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")
const EquipmentSystemScript := preload("res://scripts/systems/equipment_system.gd")
const CableRepairSystemScript := preload("res://scripts/systems/cable_repair_system.gd")
const EndingResolverScript := preload("res://scripts/systems/ending_resolver.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const TaskAssignmentResultScript := preload("res://scripts/systems/task_assignment_result.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const NightStartResultScript := preload("res://scripts/systems/night_start_result.gd")
const CablePuzzleStartResultScript := preload("res://scripts/systems/cable_puzzle_start_result.gd")
const CableRepairResultScript := preload("res://scripts/systems/cable_repair_result.gd")
const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")
const MainHudConfigScript := preload("res://scripts/presentation/main_hud_config.gd")

const FEEDBACK_DONE: StringName = &"UI_HUD_DONE"
const FEEDBACK_REJECTED: StringName = &"UI_HUD_REJECTED"
const FEEDBACK_UNAVAILABLE: StringName = &"UI_HUD_UNAVAILABLE"
const FEEDBACK_ERROR: StringName = &"UI_HUD_ERROR"

## Sistemlerin normal (hata basmayan) ret sonuçları; diğer başarısızlıklar akış hatasıdır.
const NORMAL_ASSIGNMENT_FAILURES: Array[StringName] = [TaskAssignmentResultScript.FAILURE_TIME_UNAVAILABLE,
		TaskAssignmentResultScript.FAILURE_ACTOR_BUSY, TaskAssignmentResultScript.FAILURE_TASK_ALREADY_ACTIVE]
const NORMAL_DECISION_FAILURES: Array[StringName] = [DecisionResultScript.FAILURE_CONDITIONS_NOT_MET,
		DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE, DecisionResultScript.FAILURE_TIME_UNAVAILABLE]
const NORMAL_START_FAILURES: Array[StringName] = [CablePuzzleStartResultScript.FAILURE_CONDITIONS_NOT_MET,
		CablePuzzleStartResultScript.FAILURE_ALREADY_SOLVED, CablePuzzleStartResultScript.FAILURE_RESOLUTION_LIMIT_REACHED,
		CablePuzzleStartResultScript.FAILURE_OUTCOME_UNAVAILABLE]
const NORMAL_REPAIR_FAILURES: Array[StringName] = [CableRepairResultScript.FAILURE_STALE_SESSION,
		CableRepairResultScript.FAILURE_EFFECT_NOT_APPLICABLE, CableRepairResultScript.FAILURE_TIME_UNAVAILABLE]

## Kalan gece süresini yan etkisiz önizlemeyle bulmak için yeterince büyük miktar (zaman sistemi gece sınırında keser).
const NIGHT_REMAINDER_PROBE_UNITS: int = 1 << 30

var _state: GameStateScript
var _time: TimeSystemScript
var _completions: TaskCompletionSystemScript
var _tasks: TaskSystemScript
var _decisions: DecisionSystemScript
var _advice: AdviceSystemScript
var _occurrences: OccurrenceSystemScript
var _equipment: EquipmentSystemScript
var _cable: CableRepairSystemScript
var _endings: EndingResolverScript
var _config: MainHudConfigScript
var _feedback_key: StringName = &""


## Bütün sistemler aynı oyun durumuyla kurulmuş olmalıdır.
func _init(state: GameStateScript, time_system: TimeSystemScript, task_completion_system: TaskCompletionSystemScript,
		task_system: TaskSystemScript, decision_system: DecisionSystemScript, advice_system: AdviceSystemScript,
		occurrence_system: OccurrenceSystemScript, equipment_system: EquipmentSystemScript,
		cable_repair_system: CableRepairSystemScript, ending_resolver: EndingResolverScript,
		config: MainHudConfigScript) -> void:
	_state = state
	_time = time_system
	_completions = task_completion_system
	_tasks = task_system
	_decisions = decision_system
	_advice = advice_system
	_occurrences = occurrence_system
	_equipment = equipment_system
	_cable = cable_repair_system
	_endings = ending_resolver
	_config = config


## Eksik bağımlılıklar, sistemlerin kendi yapılandırma hataları, yapılandırmanın tutarlılığı ve yapılandırmadaki
## kimliklerin sistemlerde tanımlı olması; deterministik sırayla, hiçbir değeri düzeltmeden.
func get_configuration_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	var dependencies: Dictionary = {
		"Oyun durumu": _state, "Zaman sistemi": _time, "Görev tamamlanma sistemi": _completions,
		"Görev sistemi": _tasks, "Karar sistemi": _decisions, "Öneri sistemi": _advice,
		"Görünüm sistemi": _occurrences, "Ekipman sistemi": _equipment, "Kablo tamir sistemi": _cable,
		"Son belirleyici": _endings, "Yapılandırma": _config,
	}
	for label: String in dependencies:
		if dependencies[label] == null:
			errors.append("%s verilmedi" % label)
	if not errors.is_empty():
		return errors

	var system_errors: Dictionary = {
		"TaskCompletionSystem": _completions.get_configuration_errors(),
		"TaskSystem": _tasks.get_configuration_errors(),
		"DecisionSystem": _decisions.get_configuration_errors(),
		"AdviceSystem": _advice.get_configuration_errors(),
		"OccurrenceSystem": _occurrences.get_configuration_errors(),
		"CableRepairSystem": _cable.get_configuration_errors(),
		"EndingResolver": _endings.get_configuration_errors(),
	}
	for system_name: String in system_errors:
		for line: String in system_errors[system_name]:
			errors.append("%s: %s" % [system_name, line])
	for line in _config.get_errors():
		errors.append("MainHudConfig: %s" % line)

	for entry in _config.get_assignments():
		if not entry.task_id.is_empty() and not _tasks.has_task(entry.task_id):
			errors.append("Yapılandırmada tanımsız görev '%s'" % entry.task_id)
	var decision_id: StringName = _config.get_decision_id()
	if not decision_id.is_empty() and _decisions.get_choice_ids(decision_id).is_empty():
		errors.append("Yapılandırmada tanımsız karar '%s'" % decision_id)
	var advice_id: StringName = _config.get_advice_id()
	if not advice_id.is_empty() and not _advice.has_advice(advice_id):
		errors.append("Yapılandırmada tanımsız öneri '%s'" % advice_id)
	for puzzle_id in _config.get_repair_puzzle_ids():
		if not puzzle_id.is_empty() and not _cable.has_puzzle(puzzle_id):
			errors.append("Yapılandırmada tanımsız bulmaca '%s'" % puzzle_id)
	var wait_action_id: StringName = _config.get_wait_action_id()
	if not wait_action_id.is_empty() and not _time.has_action_cost(wait_action_id):
		errors.append("Yapılandırmada tanımsız bekleme eylemi '%s'" % wait_action_id)
	return errors


## Son komutun genel geri bildirim anahtarı; henüz komut yoksa boş.
func get_feedback_key() -> StringName:
	return _feedback_key


## Yeni ve bağımsız salt okunur model. Geçersiz yapılandırmada hiçbir sistem sorgulanmaz; oturumsuz model ve
## UI_HUD_ERROR döner.
func build_model() -> MainHudModelScript:
	if not get_configuration_errors().is_empty():
		return MainHudModelScript.empty(FEEDBACK_ERROR)
	var model: MainHudModelScript = MainHudModelScript.new()
	var active: bool = _is_night_active()
	model.has_session = true
	model.night = _state.get_night()
	model.night_count = _time.get_night_count()
	model.elapsed_units = _state.get_elapsed_units()
	model.night_ended = _state.is_night_ended()
	model.night_length_units = _night_length(active)

	var resources: Dictionary[StringName, int] = _state.get_resources_snapshot()
	for resource_id: StringName in _sorted_ids(resources.keys()):
		var row: MainHudModelScript.ResourceRow = MainHudModelScript.ResourceRow.new()
		row.resource_id = resource_id
		row.value = resources[resource_id]
		model.resources.append(row)
	for task in _state.get_tasks_snapshot():
		var row: MainHudModelScript.TaskRow = MainHudModelScript.TaskRow.new()
		row.task_id = task.task_id
		row.assigned_actor_id = task.assigned_actor_id
		row.remaining_units = task.remaining_units
		model.tasks.append(row)
	model.tasks.sort_custom(func(a: MainHudModelScript.TaskRow, b: MainHudModelScript.TaskRow) -> bool:
		return String(a.task_id) < String(b.task_id))
	for entry in _config.get_assignments():
		var row: MainHudModelScript.AssignableRow = MainHudModelScript.AssignableRow.new()
		row.task_id = entry.task_id
		row.active_actor_id = entry.active_actor_id
		row.assigned_actor_id = entry.assigned_actor_id
		# Ret de bir denemedir; yalnızca denemenin yapılamadığı durumlar (gece yok, meşgul) kapalıdır.
		row.available = active and not _tasks.preview_assignment(entry.task_id, entry.active_actor_id,
				entry.assigned_actor_id).is_failed()
		model.assignable.append(row)
	for view in _equipment.get_views():
		var row: MainHudModelScript.EquipmentRow = MainHudModelScript.EquipmentRow.new()
		row.equipment_id = view.equipment_id
		row.status = view.status
		row.disabled_units = view.disabled_units
		row.usable = view.usable
		model.equipment.append(row)
	for puzzle_id in _config.get_repair_puzzle_ids():
		var row: MainHudModelScript.RepairRow = MainHudModelScript.RepairRow.new()
		row.puzzle_id = puzzle_id
		row.available = active
		model.repairs.append(row)
	for body in _occurrences.get_visible_bodies():
		var row: MainHudModelScript.BodyRow = MainHudModelScript.BodyRow.new()
		row.occurrence_id = body.occurrence_id
		row.subject_id = body.subject_id
		row.night = body.night
		row.presence = body.presence
		model.bodies.append(row)

	var decision_id: StringName = _config.get_decision_id()
	if not decision_id.is_empty():
		model.decision_id = decision_id
		for choice_id in _decisions.get_choice_ids(decision_id):
			var row: MainHudModelScript.ChoiceRow = MainHudModelScript.ChoiceRow.new()
			row.choice_id = choice_id
			row.available = active and _decisions.is_choice_available(decision_id, choice_id)
			model.choices.append(row)
		if active:
			var advice: Variant = _advice.get_advice(_config.get_advice_id())
			if advice.is_offered():
				model.advice_offered = true
				model.advisor_actor_id = advice.advisor_actor_id
				model.recommended_choice_id = advice.recommended_choice_id

	model.can_wait = active
	model.can_start_night = _time.plan_start_night().is_valid()
	if _endings.is_game_over():
		var ending: Variant = _endings.resolve()
		if ending.is_resolved():
			model.ending_id = ending.ending_id
	model.feedback_key = _feedback_key
	return model


# --- Komutlar ---

## Yapılandırmadaki görev atamasını, verideki aktör çiftiyle dener (TaskSystem.assign_task).
func assign(task_id: StringName) -> TaskAssignmentResultScript:
	var entry: MainHudConfigScript.Assignment = _config.get_assignment(task_id) if _is_ready() else null
	if entry == null:
		_feedback_key = FEEDBACK_ERROR
		return null
	var result: TaskAssignmentResultScript = _tasks.assign_task(entry.task_id, entry.active_actor_id,
			entry.assigned_actor_id)
	if result.is_accepted():
		_feedback_key = FEEDBACK_DONE
	elif result.is_rejected():
		_feedback_key = FEEDBACK_REJECTED
	else:
		_feedback_key = _failure_feedback(result.failure, NORMAL_ASSIGNMENT_FAILURES)
	return result


## Sunulan kararın verilen seçeneğini uygular (DecisionSystem.choose); öneriye bakmaz.
func choose(choice_id: StringName) -> DecisionResultScript:
	var decision_id: StringName = _config.get_decision_id() if _is_ready() else &""
	if decision_id.is_empty() or not _decisions.has_choice(decision_id, choice_id):
		_feedback_key = FEEDBACK_ERROR
		return null
	var result: DecisionResultScript = _decisions.choose(decision_id, choice_id)
	_feedback_key = FEEDBACK_DONE if result.ok else _failure_feedback(result.failure, NORMAL_DECISION_FAILURES)
	return result


## Bekleme eyleminin verideki süresi kadar zamanı ilerletir (TaskCompletionSystem.advance). Etkin gece yoksa
## hiçbir sistem çağrılmaz.
func wait() -> TimeProgressResultScript:
	if not _is_ready():
		_feedback_key = FEEDBACK_ERROR
		return null
	if not _is_night_active():
		_feedback_key = FEEDBACK_UNAVAILABLE
		return null
	var cost: int = _time.cost_of(_config.get_wait_action_id())
	var result: TimeProgressResultScript = _completions.advance(cost)
	_feedback_key = FEEDBACK_DONE if result.ok else FEEDBACK_ERROR
	return result


## Sonraki geceyi başlatır (OccurrenceSystem.start_night). Gece başlatılamıyorsa hiçbir sistem çağrılmaz.
func start_night() -> NightStartResultScript:
	if not _is_ready():
		_feedback_key = FEEDBACK_ERROR
		return null
	if not _time.plan_start_night().is_valid():
		_feedback_key = FEEDBACK_UNAVAILABLE
		return null
	var result: NightStartResultScript = _occurrences.start_night()
	_feedback_key = FEEDBACK_DONE if result.ok else FEEDBACK_ERROR
	return result


## Yapılandırmadaki bulmaca için oturum açar (CableRepairSystem.start_session); oturum sonuçtadır.
func start_repair(puzzle_id: StringName) -> CablePuzzleStartResultScript:
	if not _is_ready() or not _config.has_repair_puzzle(puzzle_id):
		_feedback_key = FEEDBACK_ERROR
		return null
	var result: CablePuzzleStartResultScript = _cable.start_session(puzzle_id)
	_feedback_key = &"" if result.is_started() else _failure_feedback(result.failure, NORMAL_START_FAILURES)
	return result


## Bitmiş oturumun sonucunu uygular (CableRepairSystem.apply_result).
func finish_repair(session: CablePuzzleSessionScript) -> CableRepairResultScript:
	if not _is_ready() or session == null or not _config.has_repair_puzzle(session.get_puzzle_id()):
		_feedback_key = FEEDBACK_ERROR
		return null
	var result: CableRepairResultScript = _cable.apply_result(session)
	_feedback_key = FEEDBACK_DONE if result.ok else _failure_feedback(result.failure, NORMAL_REPAIR_FAILURES)
	return result


# --- Yardımcılar ---

func _is_ready() -> bool:
	return get_configuration_errors().is_empty()


func _failure_feedback(failure: StringName, normal: Array[StringName]) -> StringName:
	return FEEDBACK_UNAVAILABLE if normal.has(failure) else FEEDBACK_ERROR


func _is_night_active() -> bool:
	return _state.get_night() > 0 and not _state.is_night_ended()


# TimeSystem gece uzunluğunu dışarı vermez: etkin gecede kalan süre yan etkisiz önizlemeyle bulunur; bitmiş gecede
# süre gece uzunluğuna eşittir (TimeSystem doğrular); ilk geceden önce bilinmez (0).
func _night_length(active: bool) -> int:
	if active:
		return _state.get_elapsed_units() + _time.plan_advance(NIGHT_REMAINDER_PROBE_UNITS).result.applied_units
	if _state.is_night_ended():
		return _state.get_elapsed_units()
	return 0


static func _sorted_ids(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: Variant in ids:
		result.append(StringName(id))
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return result
