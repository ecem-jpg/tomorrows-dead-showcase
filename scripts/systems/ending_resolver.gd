class_name EndingResolver
extends RefCounted
## Oyun sonunda veriye ve mevcut duruma bakarak sonu seçer (K-030).
##
## - Salt okunurdur: durum yazmaz, sinyal yaymaz, zaman ilerletmez, rastgele sayı üreteci kullanmaz. Ayrı bir
##   önizleme yöntemi yoktur; resolve'un kendisi yan etkisizdir.
## - Son yalnızca son gece gerçekten bittiğinde belirlenir (is_game_over).
## - Sonlar priority sırasıyla (küçük sayı önce) değerlendirilir; giriş sırası sonucu etkilemez. Koşullar
##   ConditionEvaluator ile değerlendirilir. Güven hazırlığı yalnızca gerçekten değerlendirilen aday için denetlenir;
##   daha öncelikli bir son eşleşirse sonraki adaylara hiç bakılmaz.
## - Tam olarak bir koşulsuz yedek son zorunludur; bu yüzden geçerli yapılandırmada oyun bittiğinde her zaman
##   bir son seçilir. Seçilemezse bu bir iç tutarlılık hatasıdır, normal sonuç değildir.
## - Arayüz yalnızca resolve ve EndingResult kullanır; gizli koşullar sonuca girmez.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const TimeSystemScript := preload("res://scripts/systems/time_system.gd")
const ConditionEvaluatorScript := preload("res://scripts/systems/condition_evaluator.gd")
const EndingResultScript := preload("res://scripts/systems/ending_result.gd")
const EndingDataScript := preload("res://scripts/data/ending_data.gd")

var _state: GameStateScript
var _trust: TrustSystemScript
var _time: TimeSystemScript
var _conditions: ConditionEvaluatorScript
# Sonların bağımsız derin kopyaları, verildiği sırayla; boş kayıtlar hata raporu için yerinde tutulur.
var _endings: Array[EndingDataScript] = []


func _init(state: GameStateScript, trust_system: TrustSystemScript, time_system: TimeSystemScript,
		endings: Array[EndingDataScript]) -> void:
	if state == null or trust_system == null or time_system == null:
		push_error("EndingResolver: oyun durumu ve bütün bağımlı sistemler verilmelidir.")
	_state = state
	_trust = trust_system
	_time = time_system
	_conditions = ConditionEvaluatorScript.new(state, trust_system)
	for ending in endings:
		_endings.append(null if ending == null else _copy_ending(ending))


## Bağımlı sistemlerin ve son kataloğunun tutarsızlıklarını deterministik sırayla döndürür; hiçbir değeri
## düzeltmez ve motor hatası üretmez.
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

	var seen_ids: Array[String] = []
	for i in _endings.size():
		var ending: EndingDataScript = _endings[i]
		if ending == null:
			errors.append("Tanımsız son kaydı (#%d)" % i)
			continue
		if ending.id.is_empty():
			errors.append("Boş son kimliği (#%d)" % i)
		elif seen_ids.has(ending.id):
			errors.append("Tekrarlanan son kimliği: '%s'" % ending.id)
		else:
			seen_ids.append(ending.id)
		if ending.priority < 1:
			errors.append("'%s': öncelik 1 veya daha büyük olmalı (%d)" % [ending.id, ending.priority])
		for j in ending.conditions.size():
			errors.append_array(_conditions.get_errors("'%s' koşul #%d: " % [ending.id, j], ending.conditions[j]))
	errors.append_array(_ordering_errors())
	return errors


func has_ending(ending_id: StringName) -> bool:
	for ending in _endings:
		if ending != null and StringName(ending.id) == ending_id:
			return true
	return false


## Son gece gerçekten bitti mi: gece sayısındaki son gece ve bitmiş. Hata basmaz; geçerliliği
## get_configuration_errors denetler.
func is_game_over() -> bool:
	if _state == null or _time == null:
		return false
	var night: int = _state.get_night()
	return night >= 1 and night == _time.get_night_count() and _state.is_night_ended()


## Arayüzün kullanacağı tek yöntem. Sıra: yapılandırma → oyun bitti mi → adaylar priority sırasıyla
## (yalnızca değerlendirilen adayda güven hazır mı → koşullar). Yan etkisizdir.
func resolve() -> EndingResultScript:
	var result: EndingResultScript = EndingResultScript.new()
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		push_error("EndingResolver: geçersiz yapılandırma; son belirlenemez: %s" % " | ".join(errors))
		result.failure = EndingResultScript.FAILURE_INVALID_CONFIGURATION
		return result
	if not is_game_over():
		result.status = EndingResultScript.STATUS_GAME_NOT_OVER
		return result
	for ending in _sorted_endings():
		if _conditions.uses_trust(ending.conditions) and not _trust.is_initialized():
			push_error("EndingResolver: güven başlatılmadı; güven koşullu son değerlendirilemez: '%s'" % ending.id)
			result.failure = EndingResultScript.FAILURE_SYSTEM_NOT_READY
			return result
		if _conditions.get_failed_indexes(ending.conditions).is_empty():
			result.status = EndingResultScript.STATUS_RESOLVED
			result.ending_id = StringName(ending.id)
			return result
	# Zorunlu koşulsuz yedek son yapılandırmada doğrulandığı için buraya ulaşılmamalı.
	push_error("EndingResolver: iç tutarlılık hatası; bütün sonlar değerlendirildi ama hiçbiri seçilemedi.")
	result.failure = EndingResultScript.FAILURE_INVALID_CONFIGURATION
	return result


# --- Doğrulama ---

# Eşit öncelik ve koşulsuz yedek son kuralları; adaylar (priority, veri sırası) ile sıralanır.
func _ordering_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	var sorted: Array[EndingDataScript] = _sorted_endings()
	for i in range(1, sorted.size()):
		if sorted[i].priority == sorted[i - 1].priority:
			errors.append("'%s': aynı öncelik ('%s' ile, %d)" % [sorted[i].id, sorted[i - 1].id, sorted[i].priority])
	var fallbacks: Array[EndingDataScript] = []
	for ending in sorted:
		if ending.conditions.is_empty():
			fallbacks.append(ending)
	if fallbacks.is_empty():
		errors.append("Koşulsuz yedek son yok")
		return errors
	for i in range(1, fallbacks.size()):
		errors.append("'%s': birden fazla koşulsuz son ('%s' ile)" % [fallbacks[i].id, fallbacks[0].id])
	var fallback: EndingDataScript = fallbacks[0]
	for ending in sorted:
		if ending != fallback and ending.priority >= fallback.priority:
			errors.append("'%s': koşulsuz son en düşük öncelikte olmalı" % fallback.id)
			break
	return errors


# Boş olmayan kayıtlar, (priority, veri sırası) ile sıralı; eşit öncelik ayrıca yapılandırma hatasıdır.
func _sorted_endings() -> Array[EndingDataScript]:
	var indexed: Array = []
	for i in _endings.size():
		if _endings[i] != null:
			indexed.append([_endings[i].priority, i])
	indexed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])
	var sorted: Array[EndingDataScript] = []
	for entry in indexed:
		sorted.append(_endings[entry[1]])
	return sorted


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result


# --- Kopyalama ---

func _copy_ending(ending: EndingDataScript) -> EndingDataScript:
	var copy: EndingDataScript = EndingDataScript.new()
	copy.id = ending.id
	copy.priority = ending.priority
	for condition in ending.conditions:
		copy.conditions.append(null if condition == null else condition.copy())
	return copy
