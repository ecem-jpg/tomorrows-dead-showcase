class_name OccurrenceSystem
extends RefCounted
## Gelecek ceset görünümlerinin kataloğu, gece başındaki varışları ve arayüze verilebilir ceset görünümü (K-029).
##
## - Her görünüm veride açıkça tanımlı ayrı bir kayıttır; kod görünüm üretmez ve rastgelelik kullanmaz.
## - Gece sınırı: Oyun akışında geceler yalnızca start_night ile başlar; gece başlangıcı ve o gecenin varışları
##   tek GameStateChange ile yazılır. TimeSystem.start_night düşük seviyeli bir uyumluluk yöntemidir.
## - Varış (inactive → pending) yalnızca görünümün kendi gecesinin başında denenir ve kaçırılırsa tekrar
##   denenmez. Kişinin kalıcı ölümü varsa (subject_dead) veya bekleyen başka görünümü varsa (subject_busy)
##   görünüm etkinleşmez; bunlar normal iç sonuçlardır.
## - Sonuçlanma (pending → death_prevented / death_permanent) etki türleriyle (EffectPlanner) ve gece sonunda
##   plan_night_end ile yapılır; kesin sonuçlar değiştirilemez (OccurrenceStatus, GameState.apply_changes).
## - Arayüz yalnızca get_visible_bodies kullanır. get_status ve NightStartResult.internal_skip_reasons iç
##   sistem verisidir; iç durum adları, varış koşulları ve gelecekteki görünümler arayüze verilmez.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")
const ConditionEvaluatorScript := preload("res://scripts/systems/condition_evaluator.gd")
const NightStartResultScript := preload("res://scripts/systems/night_start_result.gd")
const BodyViewScript := preload("res://scripts/systems/body_view.gd")
const SubjectDataScript := preload("res://scripts/data/subject_data.gd")
const OccurrenceDataScript := preload("res://scripts/data/occurrence_data.gd")

var _state: GameStateScript
var _trust: TrustSystemScript
var _time: TimeSystemScript
var _conditions: ConditionEvaluatorScript
# Katalogların bağımsız derin kopyaları; boş kayıtlar hata raporu için yerinde tutulur.
var _subjects: Array[SubjectDataScript] = []
var _occurrences: Array[OccurrenceDataScript] = []


func _init(state: GameStateScript, trust_system: TrustSystemScript, time_system: TimeSystemScript,
		subjects: Array[SubjectDataScript], occurrences: Array[OccurrenceDataScript]) -> void:
	if state == null or trust_system == null or time_system == null:
		push_error("OccurrenceSystem: oyun durumu ve bütün bağımlı sistemler verilmelidir.")
	_state = state
	_trust = trust_system
	_time = time_system
	_conditions = ConditionEvaluatorScript.new(state, trust_system)
	for subject in subjects:
		_subjects.append(null if subject == null else _copy_subject(subject))
	for occurrence in occurrences:
		_occurrences.append(null if occurrence == null else _copy_occurrence(occurrence))


## Bağımlı sistemlerin, kişi ve görünüm kataloğunun ve durumdaki görünüm kaydının tutarsızlıklarını
## deterministik sırayla döndürür; hiçbir değeri düzeltmez ve motor hatası üretmez.
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
	if _state == null or _trust == null or _time == null:
		return errors

	var subject_ids: Array[String] = []
	for i in _subjects.size():
		var subject: SubjectDataScript = _subjects[i]
		if subject == null:
			errors.append("Tanımsız kişi kaydı (#%d)" % i)
		elif subject.id.is_empty():
			errors.append("Boş kişi kimliği (#%d)" % i)
		elif subject_ids.has(subject.id):
			errors.append("Tekrarlanan kişi kimliği: '%s'" % subject.id)
		else:
			subject_ids.append(subject.id)

	var night_count: int = _time.get_night_count()
	var occurrence_ids: Array[String] = []
	for i in _occurrences.size():
		var occurrence: OccurrenceDataScript = _occurrences[i]
		if occurrence == null:
			errors.append("Tanımsız görünüm kaydı (#%d)" % i)
			continue
		if occurrence.id.is_empty():
			errors.append("Boş görünüm kimliği (#%d)" % i)
		elif occurrence_ids.has(occurrence.id):
			errors.append("Tekrarlanan görünüm kimliği: '%s'" % occurrence.id)
		else:
			occurrence_ids.append(occurrence.id)
		var p: String = "'%s': " % occurrence.id
		if occurrence.subject_id.is_empty():
			errors.append(p + "eksik alan 'subject_id'")
		elif not subject_ids.has(occurrence.subject_id):
			errors.append(p + "tanımsız kişi '%s'" % occurrence.subject_id)
		if occurrence.night < 1 or occurrence.night > night_count:
			errors.append(p + "gece aralık dışında (%d, 1..%d)" % [occurrence.night, night_count])
		for j in i:
			var other: OccurrenceDataScript = _occurrences[j]
			if other != null and not occurrence.subject_id.is_empty() and other.subject_id == occurrence.subject_id \
					and other.night == occurrence.night:
				errors.append(p + "aynı kişinin aynı gecede ikinci görünümü ('%s' ile)" % other.id)
				break
		for k in occurrence.arrival_conditions.size():
			errors.append_array(_conditions.get_errors("'%s' varış koşulu #%d: " % [occurrence.id, k],
					occurrence.arrival_conditions[k]))

	errors.append_array(_state_errors(occurrence_ids))
	return errors


func has_occurrence(occurrence_id: StringName) -> bool:
	return _find_occurrence(occurrence_id) != null


## Oyun akışında gecelerin tek başlangıç noktası: TimeSystem.plan_start_night ile yeni gece ve o gecenin
## varışları tek apply_changes ile yazılır. Hatalı yapılandırma, sürmekte olan gece, son geceden sonrası,
## başlatılmamış güven (güven koşullu varışta) ve başarısız yazma hata verir ve hiçbir şeyi değiştirmez.
func start_night() -> NightStartResultScript:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	var result: NightStartResultScript = _plan_start(change)
	if not result.ok:
		return result
	if not _state.apply_changes(change):
		push_error("OccurrenceSystem: durum yazılamadı; gece başlatılmadı.")
		return _failed(NightStartResultScript.FAILURE_WRITE_FAILED)
	return result


## start_night'ın yapacağını yazmadan hesaplar. Hatalar start_night ile aynı biçimde basılır.
## Sonuçtaki iç atlanma nedenleri arayüze verilmez.
func preview_start_night() -> NightStartResultScript:
	return _plan_start(GameStateChangeScript.new())


## Arayüzün kullanacağı tek görünüm: morgda gerçekten görünen cesetler, (night, occurrence_id) sırasıyla.
## pending → present, death_permanent → permanent. Ölümü engellenen görünüm (ceset kayboldu) ve henüz
## gerçekleşmemiş (inactive) görünümler döndürülmez. Hata basmaz.
func get_visible_bodies() -> Array[BodyViewScript]:
	var bodies: Array[BodyViewScript] = []
	if _state == null:
		return bodies
	for occurrence in _occurrences:
		if occurrence == null or occurrence.id.is_empty() or not _state.has_occurrence(StringName(occurrence.id)):
			continue
		var status: StringName = _state.get_occurrence_status(StringName(occurrence.id))
		var presence: StringName = &""
		if status == OccurrenceStatusScript.STATUS_PENDING:
			presence = BodyViewScript.PRESENCE_PRESENT
		elif status == OccurrenceStatusScript.STATUS_DEATH_PERMANENT:
			presence = BodyViewScript.PRESENCE_PERMANENT
		else:
			continue
		var body: BodyViewScript = BodyViewScript.new()
		body.occurrence_id = StringName(occurrence.id)
		body.subject_id = StringName(occurrence.subject_id)
		body.night = occurrence.night
		body.presence = presence
		bodies.append(body)
	bodies.sort_custom(func(a: BodyViewScript, b: BodyViewScript) -> bool:
		if a.night != b.night:
			return a.night < b.night
		return String(a.occurrence_id) < String(b.occurrence_id))
	return bodies


## İç sistem API'si (sonlar, analiz, testler): görünümün iç durumu. Arayüze verilmez.
func get_status(occurrence_id: StringName) -> StringName:
	return _state.get_occurrence_status(occurrence_id)


## Gece sonu kesinleşmesi (K-029): hâlâ pending olan bütün görünümleri change içinde death_permanent yapar ve
## bunların kimliklerini sırayla döndürür. change'te önceden bulunan değerler (seçim ve tamamlanma etkileri)
## esas alınır; böylece aynı pakette ölümü engellenen görünüm kalıcı yapılmaz. Yazmaz, hata basmaz.
## Yalnızca zaman planı geceyi bitirdiğinde TaskCompletionSystem.plan_time tarafından çağrılır.
static func plan_night_end(state: GameStateScript, change: GameStateChangeScript) -> Array[StringName]:
	var finalized: Array[StringName] = []
	var snapshot: Dictionary[StringName, StringName] = state.get_occurrences_snapshot()
	var ids: Array[StringName] = []
	for occurrence_id in snapshot:
		ids.append(occurrence_id)
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for occurrence_id in ids:
		var current: StringName = change.occurrence_statuses[occurrence_id] \
				if change.occurrence_statuses.has(occurrence_id) else snapshot[occurrence_id]
		if current == OccurrenceStatusScript.STATUS_PENDING:
			change.occurrence_statuses[occurrence_id] = OccurrenceStatusScript.STATUS_DEATH_PERMANENT
			finalized.append(occurrence_id)
	return finalized


# --- Planlama ---

# Sıra: yapılandırma → zaman planı → adaylar kimlik sırasıyla: inactive mi → subject_dead → subject_busy →
# güven hazır mı (yalnızca koşullar gerçekten değerlendirilecekse) → varış koşulları → pending.
# Varışlar ancak bütün adaylar başarıyla değerlendirildikten sonra change'e yazılır; başarısız planda change değişmez.
func _plan_start(change: GameStateChangeScript) -> NightStartResultScript:
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		push_error("OccurrenceSystem: geçersiz yapılandırma; gece başlatılamaz: %s" % " | ".join(errors))
		return _failed(NightStartResultScript.FAILURE_INVALID_CONFIGURATION)
	var time_plan: TimeAdvancePlanScript = _time.plan_start_night()
	if not time_plan.is_valid():
		push_error(time_plan.error_message)
		match time_plan.failure:
			TimeAdvancePlanScript.FAILURE_NIGHT_ALREADY_ACTIVE:
				return _failed(NightStartResultScript.FAILURE_NIGHT_ALREADY_ACTIVE)
			TimeAdvancePlanScript.FAILURE_NO_NEXT_NIGHT:
				return _failed(NightStartResultScript.FAILURE_NO_NEXT_NIGHT)
		return _failed(NightStartResultScript.FAILURE_INVALID_CONFIGURATION)

	var night: int = time_plan.night
	var candidates: Array[OccurrenceDataScript] = []
	for occurrence in _occurrences:
		if occurrence.night == night:
			candidates.append(occurrence)
	candidates.sort_custom(func(a: OccurrenceDataScript, b: OccurrenceDataScript) -> bool: return a.id < b.id)

	# Aynı kişinin aynı gecede iki görünümü olamadığı için adaylar birbirinin kişi denetimini etkilemez.
	var result: NightStartResultScript = NightStartResultScript.new()
	for candidate in candidates:
		var occurrence_id: StringName = StringName(candidate.id)
		if _status(occurrence_id, change) != OccurrenceStatusScript.STATUS_INACTIVE:
			continue
		if _subject_has_status(candidate, OccurrenceStatusScript.STATUS_DEATH_PERMANENT, change):
			result.internal_skip_reasons[occurrence_id] = NightStartResultScript.SKIP_SUBJECT_DEAD
			continue
		if _subject_has_status(candidate, OccurrenceStatusScript.STATUS_PENDING, change):
			result.internal_skip_reasons[occurrence_id] = NightStartResultScript.SKIP_SUBJECT_BUSY
			continue
		if _conditions.uses_trust(candidate.arrival_conditions) and not _trust.is_initialized():
			push_error("OccurrenceSystem: güven başlatılmadı; güven koşullu görünüm değerlendirilemez: '%s'" % candidate.id)
			return _failed(NightStartResultScript.FAILURE_SYSTEM_NOT_READY)
		if not _conditions.get_failed_indexes(candidate.arrival_conditions).is_empty():
			result.internal_skip_reasons[occurrence_id] = NightStartResultScript.SKIP_CONDITIONS_NOT_MET
			continue
		result.arrived_ids.append(occurrence_id)
	for occurrence_id in result.arrived_ids:
		change.occurrence_statuses[occurrence_id] = OccurrenceStatusScript.STATUS_PENDING
	change.set_time_state(time_plan.night, time_plan.elapsed_units, time_plan.night_ended, time_plan.tasks)
	result.ok = true
	result.night = night
	return result


func _status(occurrence_id: StringName, change: GameStateChangeScript) -> StringName:
	if change.occurrence_statuses.has(occurrence_id):
		return change.occurrence_statuses[occurrence_id]
	return _state.get_occurrence_status(occurrence_id)


# Aynı kişinin başka bir görünümü verilen durumda mı (adayın kendisi hariç).
func _subject_has_status(candidate: OccurrenceDataScript, status: StringName, change: GameStateChangeScript) -> bool:
	for occurrence in _occurrences:
		if occurrence == candidate or occurrence.subject_id != candidate.subject_id:
			continue
		if _status(StringName(occurrence.id), change) == status:
			return true
	return false


func _find_occurrence(occurrence_id: StringName) -> OccurrenceDataScript:
	for occurrence in _occurrences:
		if occurrence != null and StringName(occurrence.id) == occurrence_id:
			return occurrence
	return null


func _failed(failure: StringName) -> NightStartResultScript:
	var result: NightStartResultScript = NightStartResultScript.new()
	result.failure = failure
	return result


# --- Doğrulama ---

# Durumdaki görünüm kaydı katalogla birebir aynı olmalı; gelecek gecelerin görünümleri etkin olamaz.
func _state_errors(catalog_ids: Array[String]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var sorted_catalog: Array[String] = catalog_ids.duplicate()
	sorted_catalog.sort()
	for occurrence_id in sorted_catalog:
		if not _state.has_occurrence(StringName(occurrence_id)):
			errors.append("Başlangıç durumunda görünüm yok: '%s'" % occurrence_id)
	var state_ids: Array[String] = []
	for occurrence_id in _state.get_occurrences_snapshot():
		state_ids.append(String(occurrence_id))
	state_ids.sort()
	for occurrence_id in state_ids:
		if not catalog_ids.has(occurrence_id):
			errors.append("Katalogda tanımsız görünüm: '%s'" % occurrence_id)
	var night: int = _state.get_night()
	for occurrence in _occurrences:
		if occurrence == null or occurrence.id.is_empty() or not _state.has_occurrence(StringName(occurrence.id)):
			continue
		if occurrence.night > night and _state.get_occurrence_status(StringName(occurrence.id)) != OccurrenceStatusScript.STATUS_INACTIVE:
			errors.append("Gelecek gecenin görünümü etkin: '%s' (gece %d)" % [occurrence.id, occurrence.night])
	return errors


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result


# --- Kopyalama ---

func _copy_subject(subject: SubjectDataScript) -> SubjectDataScript:
	var copy: SubjectDataScript = SubjectDataScript.new()
	copy.id = subject.id
	return copy


func _copy_occurrence(occurrence: OccurrenceDataScript) -> OccurrenceDataScript:
	var copy: OccurrenceDataScript = OccurrenceDataScript.new()
	copy.id = occurrence.id
	copy.subject_id = occurrence.subject_id
	copy.night = occurrence.night
	for condition in occurrence.arrival_conditions:
		copy.arrival_conditions.append(null if condition == null else condition.copy())
	return copy
