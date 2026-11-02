class_name TaskSystem
extends RefCounted
## Oyuncunun yönettiği aktörün (active_actor_id) başka bir aktöre (assigned_actor_id) görev vermesini
## değerlendirir ve sonucu tek bir atomik GameStateChange olarak yazar (K-020, K-025, K-026).
##
## - Kabul/ret kodda değil, verideki kabul koşullarıyla belirlenir; güven koşullardan yalnızca biri olabilir.
## - İstenen görev ve aktör çifti asla değiştirilmez: ret veya uygun olmama durumunda başka bir göreve,
##   başka bir aktöre veya başka bir çifte geçilmez.
## - Denemenin zamanı (kabul ve ret için aynı) ve kabul edilen görev aynı pakette, tek apply_changes ile yazılır.
## - Bir aktör aynı anda yalnızca bir etkin görev taşıyabilir. Tamamlanan görev yeniden verilebilir.
## - Tamamlanma etkileri TaskCompletionSystem'in işidir. Deneme zamanı yalnızca TaskCompletionSystem.plan_time
##   ile planlanır; deneme süresinde biten diğer görevlerin etkileri aynı pakete yazılır (K-027). Bu sınıfın
##   başlatabildiği her görevin tamamlanma sisteminde tanımı olmalıdır.
## - Rastgele sayı üreteci kullanılmaz.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TaskCompletionPlanScript := preload("res://scripts/systems/task_completion_plan.gd")
const ConditionEvaluatorScript := preload("res://scripts/systems/condition_evaluator.gd")
const TaskAssignmentResultScript := preload("res://scripts/systems/task_assignment_result.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const TaskAssignmentDataScript := preload("res://scripts/data/task_assignment_data.gd")

var _state: GameStateScript
var _trust: TrustSystemScript
var _time: TimeSystemScript
var _completions: TaskCompletionSystemScript
var _conditions: ConditionEvaluatorScript
# Görevlerin bağımsız derin kopyaları; boş kayıtlar hata raporu için yerinde tutulur.
var _tasks: Array[TaskDataScript] = []


## task_completion_system zorunludur; aynı oyun durumu ve sistemlerle kurulmuş olmalıdır.
func _init(state: GameStateScript, trust_system: TrustSystemScript, time_system: TimeSystemScript,
		task_completion_system: TaskCompletionSystemScript, tasks: Array[TaskDataScript]) -> void:
	if state == null or trust_system == null or time_system == null or task_completion_system == null:
		push_error("TaskSystem: oyun durumu ve bütün bağımlı sistemler verilmelidir.")
	_state = state
	_trust = trust_system
	_time = time_system
	_completions = task_completion_system
	_conditions = ConditionEvaluatorScript.new(state, trust_system)
	for task in tasks:
		_tasks.append(null if task == null else _copy_task(task))


## Bağımlı sistemlerin, görevlerin, atamaların ve kabul koşullarının tutarsızlıklarını deterministik
## sırayla döndürür; hiçbir değeri düzeltmez ve motor hatası üretmez.
func get_configuration_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if _state == null:
		errors.append("Oyun durumu verilmedi")
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
	if _state == null or _trust == null or _time == null or _completions == null:
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
		if task.duration_units <= 0:
			errors.append("'%s': görev süresi pozitif olmalı (%d)" % [task.id, task.duration_units])
		if not task.id.is_empty() and not _completions.has_definition(StringName(task.id)):
			errors.append("'%s': tamamlanma sisteminde tanımı yok" % task.id)
		if task.assignment == null:
			errors.append("'%s': eksik atama" % task.id)
			continue
		errors.append_array(_assignment_errors(task.id, task.assignment))
	return errors


func has_task(task_id: StringName) -> bool:
	return _find_task(task_id) != null


## Atamayı yan etkisiz değerlendirir: hiçbir şey yazmaz, sinyal yaymaz. assign_task ile aynı sonuç biçimi.
## Sınır: sonuç gizli kabul koşullarını içerir. Oyuncuya kabul/ret sonucunu deneme maliyeti ödenmeden
## açıklamak için kullanılmamalıdır; oyuncuya gösterilecek sonuç yalnızca assign_task'tan gelir.
func preview_assignment(task_id: StringName, active_actor_id: StringName,
		assigned_actor_id: StringName) -> TaskAssignmentResultScript:
	return _plan(task_id, active_actor_id, assigned_actor_id, GameStateChangeScript.new())


## Yalnızca istenen görevi istenen aktör çiftiyle dener. Mevcut durumu yeniden değerlendirip taze bir plan
## kurar (önceden alınmış önizleme kullanılmaz). Kabulde görev ve deneme zamanı, retde yalnızca deneme
## zamanı tek apply_changes ile yazılır.
func assign_task(task_id: StringName, active_actor_id: StringName,
		assigned_actor_id: StringName) -> TaskAssignmentResultScript:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var result: TaskAssignmentResultScript = _plan(task_id, active_actor_id, assigned_actor_id, change)
	if result.is_failed():
		return result
	if not _state.apply_changes(change):
		push_error("TaskSystem: durum yazılamadı; görev ataması uygulanmadı: '%s'" % task_id)
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_WRITE_FAILED)
	return result


# --- Planlama ---

# Atamayı değerlendirir ve yazılacak yeni değerleri change'e ekler; hiçbir şey yazmaz.
# Sıra: yapılandırma → görev → aktör çifti → güven hazır mı → zaman → görev/aktör meşgul mü → koşullar.
# Uygun olmama denetimleri koşullardan önce gelir; böylece gizli kabul koşulları bedelsiz öğrenilemez.
func _plan(task_id: StringName, active_actor_id: StringName, assigned_actor_id: StringName,
		change: GameStateChangeScript) -> TaskAssignmentResultScript:
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		push_error("TaskSystem: geçersiz yapılandırma; görev ataması değerlendirilemez: %s" % " | ".join(errors))
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_INVALID_CONFIGURATION)
	var task: TaskDataScript = _find_task(task_id)
	if task == null:
		push_error("TaskSystem: tanımsız görev: '%s'" % task_id)
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_UNKNOWN_TASK)
	var assignment: TaskAssignmentDataScript = task.assignment
	if StringName(assignment.active_actor_id) != active_actor_id \
			or StringName(assignment.assigned_actor_id) != assigned_actor_id:
		push_error("TaskSystem: görev bu aktör çiftine tanımlı değil: '%s' ('%s' -> '%s')"
				% [task_id, active_actor_id, assigned_actor_id])
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_UNKNOWN_ASSIGNMENT)
	if _conditions.uses_trust(assignment.acceptance_conditions) and not _trust.is_initialized():
		push_error("TaskSystem: güven başlatılmadı; güven koşullu görev değerlendirilemez: '%s'" % task_id)
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_SYSTEM_NOT_READY)

	var has_action: bool = not assignment.action_id.is_empty()
	var cost: int = _time.cost_of(StringName(assignment.action_id)) if has_action else 0
	# Tamamlanma etkileri geçici bir pakette hesaplanır; deneme uygun olmazsa hiçbiri yazılmaz.
	var pending: GameStateChangeScript = GameStateChangeScript.new()
	var completion_plan: TaskCompletionPlanScript = _completions.plan_time(cost, pending)
	# Etkin gece yoksa ya da deneme geceyi bitirecekse hiçbir şey yazılmaz (K-026).
	if completion_plan.failure == TaskCompletionPlanScript.FAILURE_NIGHT_NOT_ACTIVE \
			or (completion_plan.is_valid() and completion_plan.time_plan.night_ended):
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_TIME_UNAVAILABLE)
	if completion_plan.failure == TaskCompletionPlanScript.FAILURE_SYSTEM_NOT_READY:
		push_error(completion_plan.error_message)
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_SYSTEM_NOT_READY)
	if not completion_plan.is_valid():
		push_error("TaskSystem: zaman planlanamadı: %s" % completion_plan.error_message)
		return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_INVALID_CONFIGURATION)
	var plan: TimeAdvancePlanScript = completion_plan.time_plan

	# Meşguliyet denemenin başladığı andaki duruma göre değerlendirilir.
	for active_task in _state.get_tasks_snapshot():
		if active_task.task_id == task_id:
			return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_TASK_ALREADY_ACTIVE)
	for active_task in _state.get_tasks_snapshot():
		if active_task.assigned_actor_id == assigned_actor_id:
			return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_ACTOR_BUSY)

	var result: TaskAssignmentResultScript = _failed(task_id, active_actor_id, assigned_actor_id, &"")
	var failed_conditions: PackedInt32Array = _conditions.get_failed_indexes(assignment.acceptance_conditions)
	if failed_conditions.is_empty():
		var task_failure: StringName = _time.plan_add_task(plan, task_id, assigned_actor_id, task.duration_units)
		if not task_failure.is_empty():
			push_error("TaskSystem: görev zamana eklenemedi: '%s' (%s)" % [task_id, task_failure])
			return _failed(task_id, active_actor_id, assigned_actor_id, TaskAssignmentResultScript.FAILURE_INVALID_CONFIGURATION)
		result.status = TaskAssignmentResultScript.STATUS_ACCEPTED
		result.started_task = TimedTaskStateScript.new(task_id, assigned_actor_id, task.duration_units)
	else:
		result.status = TaskAssignmentResultScript.STATUS_REJECTED
		result.failed_condition_indexes = failed_conditions

	if has_action or result.is_accepted():
		change.resource_values = pending.resource_values
		change.flag_values = pending.flag_values
		change.trust_values = pending.trust_values
		change.occurrence_statuses = pending.occurrence_statuses
		change.equipment_values = pending.equipment_values
		change.set_time_state(plan.night, plan.elapsed_units, plan.night_ended, plan.tasks)
	if has_action:
		result.time_result = plan.result
		result.task_completions = completion_plan.completions
		result.equipment_disable_expirations = TaskCompletionSystemScript.copy_expirations(
				completion_plan.equipment_disable_expirations)
	return result


func _find_task(task_id: StringName) -> TaskDataScript:
	for task in _tasks:
		if task != null and StringName(task.id) == task_id:
			return task
	return null


func _failed(task_id: StringName, active_actor_id: StringName, assigned_actor_id: StringName,
		failure: StringName) -> TaskAssignmentResultScript:
	var result: TaskAssignmentResultScript = TaskAssignmentResultScript.new()
	result.task_id = task_id
	result.active_actor_id = active_actor_id
	result.assigned_actor_id = assigned_actor_id
	result.failure = failure
	return result


# --- Doğrulama ---

func _assignment_errors(task_id: String, assignment: TaskAssignmentDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	var p: String = "'%s' atama: " % task_id
	if assignment.active_actor_id.is_empty():
		errors.append(p + "eksik alan 'active_actor_id'")
	if assignment.assigned_actor_id.is_empty():
		errors.append(p + "eksik alan 'assigned_actor_id'")
	if not assignment.active_actor_id.is_empty() and assignment.active_actor_id == assignment.assigned_actor_id:
		errors.append(p + "kendine görev atama '%s'" % assignment.active_actor_id)
	if not assignment.action_id.is_empty() and not _time.has_action_cost(StringName(assignment.action_id)):
		errors.append(p + "tanımsız eylem '%s'" % assignment.action_id)
	for i in assignment.acceptance_conditions.size():
		errors.append_array(_conditions.get_errors("'%s' koşul #%d: " % [task_id, i], assignment.acceptance_conditions[i]))
	return errors


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result


# --- Kopyalama ---

func _copy_task(task: TaskDataScript) -> TaskDataScript:
	var copy: TaskDataScript = TaskDataScript.new()
	copy.id = task.id
	copy.duration_units = task.duration_units
	if task.assignment != null:
		var source: TaskAssignmentDataScript = task.assignment
		var assignment: TaskAssignmentDataScript = TaskAssignmentDataScript.new()
		assignment.active_actor_id = source.active_actor_id
		assignment.assigned_actor_id = source.assigned_actor_id
		assignment.action_id = source.action_id
		for condition in source.acceptance_conditions:
			assignment.acceptance_conditions.append(null if condition == null else condition.copy())
		copy.assignment = assignment
	return copy
