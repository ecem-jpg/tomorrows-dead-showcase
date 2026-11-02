class_name CableRepairSystem
extends RefCounted
## Kablo bulmacası oturumlarını açar ve kesin sonuçlarını, veri tanımlı etkileri, zaman maliyeti ve oyun geneli
## ilerleme kaydıyla birlikte tek atomik GameStateChange olarak uygular (K-019, K-032).
##
## - Oturum yalnızca start_session ile açılır. Açılışta kesin retler (çözülmüş, hak bitmiş), güven hazırlığı ve
##   başlangıç koşulları denetlenir; ardından başarı ve başarısızlık dallarının ikisi de mevcut durumda, ayrı
##   geçici paketlerde yan etkisiz olarak planlanır. Dallardan biri uygulanamıyorsa oturum açılmaz; böylece
##   uygulanamayan bir başarısızlık hak tüketmeden yeniden denenemez.
## - Oturum açmak, yarım bırakmak veya hiç göndermemek durum yazmaz ve hak tüketmez.
## - Sistem açtığı her oturumu kaydeder (zayıf referans, nesne kimliği, bulmaca, beklenen çözüm sayısı). Yalnızca
##   bu kayıtlı oturumlar kabul edilir; ilerleme açılıştan sonra değiştiyse sonuç stale_session olur. Oturum
##   yalnızca başarılı yazmadan sonra tüketilir ve bir daha uygulanamaz.
## - Başlangıç koşulları uygulama anında yeniden değerlendirilmez; yapılandırma, ilerleme sürümü, etkiler ve zaman
##   ise yeniden planlanır. Başka dala geçilmez, kısmi yazma yapılmaz.
## - Zaman yalnızca TaskCompletionSystem.plan_time ile planlanır; tamamlanan görevler, ekipman sayaçları ve gece
##   sonu aynı pakete girer. Sistem son belirlemez; zaman maliyetinin geceyi bitirmesi zaman sisteminin normal
##   sonucudur.
## - Rastgele sayı üreteci kullanılmaz.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const CablePuzzleProgressStateScript := preload("res://scripts/core/cable_puzzle_progress_state.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TaskCompletionPlanScript := preload("res://scripts/systems/task_completion_plan.gd")
const ConditionEvaluatorScript := preload("res://scripts/systems/condition_evaluator.gd")
const EffectPlannerScript := preload("res://scripts/systems/effect_planner.gd")
const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CablePuzzleStartResultScript := preload("res://scripts/systems/cable_puzzle_start_result.gd")
const CableRepairResultScript := preload("res://scripts/systems/cable_repair_result.gd")
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CablePuzzleOutcomeDataScript := preload("res://scripts/data/cable_puzzle_outcome_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")


# Bu sistemin açtığı bir oturum. Zayıf referans oturumu canlı tutmaz; kimlik, gerçek nesne eşitliğiyle birlikte
# denetlenir.
class SessionRecord:
	var session_ref: WeakRef
	var instance_id: int = 0
	var puzzle_id: StringName = &""
	var expected_resolutions: int = 0
	var consumed: bool = false


var _state: GameStateScript
var _resources: ResourceSystemScript
var _trust: TrustSystemScript
var _time: TimeSystemScript
var _completions: TaskCompletionSystemScript
var _conditions: ConditionEvaluatorScript
var _effects: EffectPlannerScript
# Bulmacaların bağımsız kopyaları; boş kayıtlar hata raporu için yerinde tutulur.
var _puzzles: Array[CablePuzzleDataScript] = []
var _records: Array[SessionRecord] = []


## task_completion_system zorunludur; aynı oyun durumu ve sistemlerle kurulmuş olmalıdır.
func _init(state: GameStateScript, resource_system: ResourceSystemScript, trust_system: TrustSystemScript,
		time_system: TimeSystemScript, task_completion_system: TaskCompletionSystemScript,
		puzzles: Array[CablePuzzleDataScript]) -> void:
	if state == null or resource_system == null or trust_system == null or time_system == null \
			or task_completion_system == null:
		push_error("CableRepairSystem: oyun durumu ve bütün bağımlı sistemler verilmelidir.")
	_state = state
	_resources = resource_system
	_trust = trust_system
	_time = time_system
	_completions = task_completion_system
	_conditions = ConditionEvaluatorScript.new(state, trust_system)
	_effects = EffectPlannerScript.new(state, resource_system, trust_system)
	for puzzle in puzzles:
		_puzzles.append(null if puzzle == null else puzzle.copy())


## Bağımlı sistemlerin, bulmaca kataloğunun ve durumdaki ilerleme kayıtlarının tutarsızlıklarını deterministik
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

	var catalog_ids: Array[String] = []
	for i in _puzzles.size():
		var puzzle: CablePuzzleDataScript = _puzzles[i]
		if puzzle == null:
			errors.append("Tanımsız bulmaca kaydı (#%d)" % i)
			continue
		if not puzzle.id.is_empty():
			if catalog_ids.has(puzzle.id):
				errors.append("Tekrarlanan bulmaca kimliği: '%s'" % puzzle.id)
			else:
				catalog_ids.append(puzzle.id)
		var p: String = "'%s': " % puzzle.id
		errors.append_array(_prefixed(p, CablePuzzleSessionScript.get_puzzle_errors(puzzle)))
		if puzzle.rules != null and not puzzle.rules.equipment_id.is_empty() \
				and not _state.has_equipment(StringName(puzzle.rules.equipment_id)):
			errors.append(p + "tanımsız ekipman '%s'" % puzzle.rules.equipment_id)
		# Boş kayıtlar get_puzzle_errors tarafından zaten raporlanır.
		for k in puzzle.start_conditions.size():
			if puzzle.start_conditions[k] != null:
				errors.append_array(_conditions.get_errors("'%s' başlangıç koşulu #%d: " % [puzzle.id, k],
						puzzle.start_conditions[k]))
		errors.append_array(_outcome_errors("'%s' başarı" % puzzle.id, puzzle.success))
		errors.append_array(_outcome_errors("'%s' başarısızlık" % puzzle.id, puzzle.failure))

	errors.append_array(_state_errors(catalog_ids))
	return errors


func has_puzzle(puzzle_id: StringName) -> bool:
	return _find_puzzle(puzzle_id) != null


## Katalogdaki bulmaca kimlikleri, kimlik sırasıyla.
func get_puzzle_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for puzzle in _puzzles:
		if puzzle != null and not puzzle.id.is_empty() and not ids.has(StringName(puzzle.id)):
			ids.append(StringName(puzzle.id))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids


## Yeni bir oturum açar. Sıra: yapılandırma → bulmaca → çözülmüş mü → hak bitti mi → güven hazırlığı →
## başlangıç koşulları → iki dalın yan etkisiz ön planlaması → oturum ve kayıt. Durum yazmaz, sinyal yaymaz.
func start_session(puzzle_id: StringName) -> CablePuzzleStartResultScript:
	var result: CablePuzzleStartResultScript = CablePuzzleStartResultScript.new()
	result.puzzle_id = puzzle_id
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		push_error("CableRepairSystem: geçersiz yapılandırma; oturum açılamaz: %s" % " | ".join(errors))
		result.failure = CablePuzzleStartResultScript.FAILURE_INVALID_CONFIGURATION
		return result
	var puzzle: CablePuzzleDataScript = _find_puzzle(puzzle_id)
	if puzzle == null:
		push_error("CableRepairSystem: tanımsız kablo bulmacası: '%s'" % puzzle_id)
		result.failure = CablePuzzleStartResultScript.FAILURE_UNKNOWN_PUZZLE
		return result
	var progress: CablePuzzleProgressStateScript = _state.get_cable_puzzle_progress(puzzle_id)
	if progress.solved:
		result.failure = CablePuzzleStartResultScript.FAILURE_ALREADY_SOLVED
		return result
	if progress.resolutions_used >= puzzle.rules.max_resolutions:
		result.failure = CablePuzzleStartResultScript.FAILURE_RESOLUTION_LIMIT_REACHED
		return result
	if _start_uses_trust(puzzle) and not _trust.is_initialized():
		push_error("CableRepairSystem: güven başlatılmadı; güven kullanan bulmaca açılamaz: '%s'" % puzzle_id)
		result.failure = CablePuzzleStartResultScript.FAILURE_SYSTEM_NOT_READY
		return result
	var failed_conditions: PackedInt32Array = _conditions.get_failed_indexes(puzzle.start_conditions)
	if not failed_conditions.is_empty():
		result.failure = CablePuzzleStartResultScript.FAILURE_CONDITIONS_NOT_MET
		result.failed_condition_indexes = failed_conditions
		return result

	# Her dal ayrı ve yeni bir geçici pakette planlanır; paketler atılır.
	for outcome: CablePuzzleOutcomeDataScript in [puzzle.success, puzzle.failure]:
		var probe: CableRepairResultScript = CableRepairResultScript.new()
		if _plan_outcome(outcome, GameStateChangeScript.new(), probe):
			continue
		match probe.failure:
			CableRepairResultScript.FAILURE_SYSTEM_NOT_READY:
				result.failure = CablePuzzleStartResultScript.FAILURE_SYSTEM_NOT_READY
			CableRepairResultScript.FAILURE_INVALID_CONFIGURATION:
				result.failure = CablePuzzleStartResultScript.FAILURE_INVALID_CONFIGURATION
			_:
				result.failure = CablePuzzleStartResultScript.FAILURE_OUTCOME_UNAVAILABLE
		return result

	var session: CablePuzzleSessionScript = CablePuzzleSessionScript.create(puzzle)
	_prune_records()
	var record: SessionRecord = SessionRecord.new()
	record.session_ref = weakref(session)
	record.instance_id = session.get_instance_id()
	record.puzzle_id = puzzle_id
	record.expected_resolutions = progress.resolutions_used
	_records.append(record)
	result.status = CablePuzzleStartResultScript.STATUS_STARTED
	result.session = session
	return result


## Sonucu yan etkisiz değerlendirir: hiçbir şey yazmaz, sinyal yaymaz ve oturumu tüketmez. apply_result ile aynı
## sonuç biçimi; tekrar çağrılabilir.
func preview_result(session: CablePuzzleSessionScript) -> CableRepairResultScript:
	return _evaluate(session, GameStateChangeScript.new())


## Oturumun kesin sonucunu taze bir planla tek apply_changes içinde yazar. Oturum yalnızca başarılı yazmadan sonra
## tüketilir; herhangi bir başarısızlıkta hiçbir şey değişmez.
func apply_result(session: CablePuzzleSessionScript) -> CableRepairResultScript:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var result: CableRepairResultScript = _evaluate(session, change)
	if not result.ok:
		return result
	if not _state.apply_changes(change):
		push_error("CableRepairSystem: durum yazılamadı; sonuç uygulanmadı: '%s'" % result.puzzle_id)
		var failed: CableRepairResultScript = _failed(result.puzzle_id, CableRepairResultScript.FAILURE_WRITE_FAILED)
		failed.outcome = result.outcome
		return failed
	_find_record(session).consumed = true
	return result


# --- Planlama ---

# Sıra: yapılandırma → sahiplik ve gerçek nesne → tüketilmiş mi → kesin durum → ilerleme sürümü → dal →
# güven hazırlığı → etkiler → zaman → ilerleme kaydı. Geçerliyse yazılacak değerleri change'e ekler.
func _evaluate(session: CablePuzzleSessionScript, change: GameStateChangeScript) -> CableRepairResultScript:
	var puzzle_id: StringName = &"" if session == null else session.get_puzzle_id()
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		push_error("CableRepairSystem: geçersiz yapılandırma; sonuç değerlendirilemez: %s" % " | ".join(errors))
		return _failed(puzzle_id, CableRepairResultScript.FAILURE_INVALID_CONFIGURATION)
	var record: SessionRecord = _find_record(session)
	if record == null:
		push_error("CableRepairSystem: bu sistemin açmadığı oturum: '%s'" % puzzle_id)
		return _failed(puzzle_id, CableRepairResultScript.FAILURE_FOREIGN_SESSION)
	if record.consumed:
		push_error("CableRepairSystem: oturumun sonucu zaten uygulandı: '%s'" % puzzle_id)
		return _failed(puzzle_id, CableRepairResultScript.FAILURE_ALREADY_APPLIED)
	if not session.is_finished():
		push_error("CableRepairSystem: oturum henüz bitmedi: '%s'" % puzzle_id)
		return _failed(puzzle_id, CableRepairResultScript.FAILURE_SESSION_NOT_FINISHED)
	var outcome: StringName = session.get_status()
	var progress: CablePuzzleProgressStateScript = _state.get_cable_puzzle_progress(record.puzzle_id)
	if progress.resolutions_used != record.expected_resolutions:
		var stale: CableRepairResultScript = _failed(puzzle_id, CableRepairResultScript.FAILURE_STALE_SESSION)
		stale.outcome = outcome
		return stale

	var solved: bool = outcome == CablePuzzleSessionScript.STATUS_SOLVED
	var puzzle: CablePuzzleDataScript = _find_puzzle(record.puzzle_id)
	var branch: CablePuzzleOutcomeDataScript = puzzle.success if solved else puzzle.failure
	var result: CableRepairResultScript = CableRepairResultScript.new()
	result.puzzle_id = puzzle_id
	result.outcome = outcome
	if _effects.uses_trust(branch.effects) and not _trust.is_initialized():
		push_error("CableRepairSystem: güven başlatılmadı; güven etkili sonuç uygulanamaz: '%s'" % puzzle_id)
		result.failure = CableRepairResultScript.FAILURE_SYSTEM_NOT_READY
		return result
	if not _plan_outcome(branch, change, result):
		return result
	change.cable_puzzle_progress.append(CablePuzzleProgressStateScript.new(record.puzzle_id,
			record.expected_resolutions + 1, solved))
	result.ok = true
	return result


# Dalın etkilerini veri sırasıyla, ardından varsa eylem süresini change üzerinde planlar ve sonucu result'a yazar.
# Başarısızlıkta result.failure dolar ve false döner; change'in kullanılmaması çağıranın işidir. Yalnızca akış
# hatalarında (zaman planlanamadı, görev tamamlanırken güven hazır değil) tek push_error üretir.
func _plan_outcome(outcome: CablePuzzleOutcomeDataScript, change: GameStateChangeScript,
		result: CableRepairResultScript) -> bool:
	var outcomes: Array[DecisionEffectOutcomeScript] = []
	for i in outcome.effects.size():
		var effect_outcome: DecisionEffectOutcomeScript = _effects.plan(i, outcome.effects[i], change)
		if effect_outcome == null:
			result.failure = CableRepairResultScript.FAILURE_EFFECT_NOT_APPLICABLE
			result.blocking_effect_index = i
			return false
		outcomes.append(effect_outcome)
	if not outcome.action_id.is_empty():
		# Tamamlanma etkileri dalın etkilerinden sonra, aynı pakete birikerek eklenir.
		var plan: TaskCompletionPlanScript = _completions.plan_time(_time.cost_of(StringName(outcome.action_id)), change)
		if plan.failure == TaskCompletionPlanScript.FAILURE_NIGHT_NOT_ACTIVE:
			result.failure = CableRepairResultScript.FAILURE_TIME_UNAVAILABLE
			return false
		if plan.failure == TaskCompletionPlanScript.FAILURE_SYSTEM_NOT_READY:
			push_error(plan.error_message)
			result.failure = CableRepairResultScript.FAILURE_SYSTEM_NOT_READY
			return false
		if not plan.is_valid():
			push_error("CableRepairSystem: zaman planlanamadı: %s" % plan.error_message)
			result.failure = CableRepairResultScript.FAILURE_INVALID_CONFIGURATION
			return false
		var time_plan: TimeAdvancePlanScript = plan.time_plan
		change.set_time_state(time_plan.night, time_plan.elapsed_units, time_plan.night_ended, time_plan.tasks)
		result.applied_units = time_plan.result.applied_units
		result.overflow_units = time_plan.result.overflow_units
		result.night_ended = time_plan.night_ended
		for completion in plan.completions:
			result.completed_task_ids.append(completion.task_id)
		result.permanent_occurrence_ids = plan.permanent_occurrence_ids.duplicate()
		result.equipment_disable_expirations = TaskCompletionSystemScript.copy_expirations(
				plan.equipment_disable_expirations)
	result.effect_outcomes = outcomes
	return true


func _start_uses_trust(puzzle: CablePuzzleDataScript) -> bool:
	return _conditions.uses_trust(puzzle.start_conditions) or _effects.uses_trust(puzzle.success.effects) \
			or _effects.uses_trust(puzzle.failure.effects)


func _failed(puzzle_id: StringName, failure: StringName) -> CableRepairResultScript:
	var result: CableRepairResultScript = CableRepairResultScript.new()
	result.puzzle_id = puzzle_id
	result.failure = failure
	return result


# --- Oturum kayıtları ---

# Nesne kimliği, zayıf referansın gösterdiği gerçek nesne ve bulmaca kimliği birlikte eşleşmelidir.
func _find_record(session: CablePuzzleSessionScript) -> SessionRecord:
	if session == null:
		return null
	for record in _records:
		if record.instance_id == session.get_instance_id() and record.session_ref.get_ref() == session \
				and record.puzzle_id == session.get_puzzle_id():
			return record
	return null


# Oturumu artık var olmayan kayıtlar atılır; böylece terk edilen oturumlar kayıt listesini büyütmez.
func _prune_records() -> void:
	var alive: Array[SessionRecord] = []
	for record in _records:
		if record.session_ref.get_ref() != null:
			alive.append(record)
	_records = alive


func _find_puzzle(puzzle_id: StringName) -> CablePuzzleDataScript:
	for puzzle in _puzzles:
		if puzzle != null and StringName(puzzle.id) == puzzle_id:
			return puzzle
	return null


# --- Doğrulama ---

func _outcome_errors(prefix: String, outcome: CablePuzzleOutcomeDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	# Boş dal ve boş etki kayıtları get_puzzle_errors tarafından zaten raporlanır.
	if outcome == null:
		return errors
	for j in outcome.effects.size():
		var effect: EffectDataScript = outcome.effects[j]
		if effect == null:
			continue
		var effect_prefix: String = "%s etkisi #%d: " % [prefix, j]
		errors.append_array(_effects.get_errors(effect_prefix, effect))
		for i in j:
			if _effects.is_same_target(outcome.effects[i], effect):
				errors.append(effect_prefix + "aynı hedefe birden fazla etki (#%d ile)" % i)
				break
	if not outcome.action_id.is_empty() and not _time.has_action_cost(StringName(outcome.action_id)):
		errors.append("%s: tanımsız eylem '%s'" % [prefix, outcome.action_id])
	return errors


# Durumdaki ilerleme kayıtları katalogla birebir aynı olmalı; sayaç sınırı aşamaz, çözülmüş kayıt en az bir
# çözüm taşır.
func _state_errors(catalog_ids: Array[String]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var sorted_catalog: Array[String] = catalog_ids.duplicate()
	sorted_catalog.sort()
	for puzzle_id in sorted_catalog:
		if not _state.has_cable_puzzle(StringName(puzzle_id)):
			errors.append("Başlangıç durumunda kablo bulmacası yok: '%s'" % puzzle_id)
	for progress in _state.get_cable_puzzle_progress_snapshot():
		var puzzle_id: String = String(progress.puzzle_id)
		if not catalog_ids.has(puzzle_id):
			errors.append("Katalogda tanımsız kablo bulmacası: '%s'" % puzzle_id)
			continue
		var puzzle: CablePuzzleDataScript = _find_puzzle(progress.puzzle_id)
		if puzzle.rules != null and progress.resolutions_used > puzzle.rules.max_resolutions:
			errors.append("'%s': çözüm sayısı sınırı aşıyor (%d > %d)"
					% [puzzle_id, progress.resolutions_used, puzzle.rules.max_resolutions])
		if progress.solved and progress.resolutions_used == 0:
			errors.append("'%s': çözülmüş ama çözüm sayısı 0" % puzzle_id)
	return errors


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result
