class_name AdviceSystem
extends RefCounted
## Bir aktörün başka bir aktöre sunduğu öneriyi veriden ve mevcut oyun durumundan hesaplar (K-021, K-028).
##
## - Salt okunurdur: durum yazmaz, sinyal yaymaz, zaman harcamaz, rastgele sayı üreteci kullanmaz. Öneri
##   oyuncunun seçimini değiştiremez; karar ve görev sistemleri bu sınıftan habersizdir.
## - Biçimler veri sırasıyla değerlendirilir; koşulları sağlanan ilk biçim seçilir. Aynı durum her zaman aynı
##   öneriyi verir. Bilgi mevcut bayrak koşullarıyla temsil edilir.
## - Güven yalnızca sunulma koşullarında kullanılabilir; biçim koşullarında güven yapılandırma hatasıdır.
##   Böylece güven bir önerinin sunulup sunulmayacağını etkileyebilir, hangi biçimin seçildiğini etkileyemez.
## - Arayüz yalnızca get_advice kullanır. evaluate iç sistem API'sidir; yazarın tanımladığı gizli
##   sınıflandırmayı (accuracy) döndürür ve oyuncuya verilmez.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const ConditionEvaluatorScript := preload("res://scripts/systems/condition_evaluator.gd")
const AdviceResultScript := preload("res://scripts/systems/advice_result.gd")
const AdviceEvaluationScript := preload("res://scripts/systems/advice_evaluation.gd")
const AdviceDataScript := preload("res://scripts/data/advice_data.gd")
const AdviceContextDataScript := preload("res://scripts/data/advice_context_data.gd")
const AdviceVariantDataScript := preload("res://scripts/data/advice_variant_data.gd")

var _state: GameStateScript
var _trust: TrustSystemScript
# Yalnızca karar ve seçenek kimliklerini doğrulamak için okunur; hiçbir yazma yöntemi çağrılmaz.
var _decisions: DecisionSystemScript
var _conditions: ConditionEvaluatorScript
# Önerilerin bağımsız derin kopyaları; boş kayıtlar hata raporu için yerinde tutulur.
var _advices: Array[AdviceDataScript] = []


func _init(state: GameStateScript, trust_system: TrustSystemScript, decision_system: DecisionSystemScript,
		advices: Array[AdviceDataScript]) -> void:
	if state == null or trust_system == null or decision_system == null:
		push_error("AdviceSystem: oyun durumu ve bütün bağımlı sistemler verilmelidir.")
	_state = state
	_trust = trust_system
	_decisions = decision_system
	_conditions = ConditionEvaluatorScript.new(state, trust_system)
	for advice in advices:
		_advices.append(null if advice == null else _copy_advice(advice))


## Bağımlı sistemlerin ve önerilerin tutarsızlıklarını deterministik sırayla döndürür; hiçbir değeri
## düzeltmez ve motor hatası üretmez. DecisionSystem'in kendi hataları burada tekrarlanmaz.
func get_configuration_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if _state == null:
		errors.append("Oyun durumu verilmedi")
	if _trust == null:
		errors.append("Güven sistemi verilmedi")
	else:
		errors.append_array(_prefixed("TrustSystem: ", _trust.get_configuration_errors()))
	if _decisions == null:
		errors.append("Karar sistemi verilmedi")
	if _state == null or _trust == null or _decisions == null:
		return errors

	var seen_ids: Array[String] = []
	for i in _advices.size():
		var advice: AdviceDataScript = _advices[i]
		if advice == null:
			errors.append("Tanımsız öneri kaydı (#%d)" % i)
			continue
		if advice.id.is_empty():
			errors.append("Boş öneri kimliği (#%d)" % i)
		elif seen_ids.has(advice.id):
			errors.append("Tekrarlanan öneri kimliği: '%s'" % advice.id)
		else:
			seen_ids.append(advice.id)
		if advice.context == null:
			errors.append("'%s': eksik bağlam" % advice.id)
		if advice.variants.is_empty():
			errors.append("'%s': öneride biçim yok" % advice.id)
		if advice.context != null:
			errors.append_array(_context_errors(advice.id, advice.context))
		for j in advice.presentation_conditions.size():
			errors.append_array(_conditions.get_errors("'%s' sunulma koşulu #%d: " % [advice.id, j],
					advice.presentation_conditions[j]))
		errors.append_array(_variant_errors(advice))
	return errors


func has_advice(advice_id: StringName) -> bool:
	return _find_advice(advice_id) != null


## Arayüzün kullanacağı tek yöntem. Öneriyi yan etkisiz hesaplar; gizli sınıflandırmayı içermez.
func get_advice(advice_id: StringName) -> AdviceResultScript:
	return _evaluate(advice_id).result


## İç sistem API'si: get_advice ile aynı değerlendirmeyi yapar ve ek olarak seçilen biçimi ve gizli
## sınıflandırmayı döndürür. Sonlar, analizler ve testler içindir; arayüze veya oyuncuya verilmez.
func evaluate(advice_id: StringName) -> AdviceEvaluationScript:
	return _evaluate(advice_id)


# --- Değerlendirme ---

# Sıra: yapılandırma → öneri → güven hazır mı (yalnızca sunulma koşulunda güven varsa) → sunulma →
# biçimler (veri sırasıyla ilk uygun olan).
func _evaluate(advice_id: StringName) -> AdviceEvaluationScript:
	var evaluation: AdviceEvaluationScript = AdviceEvaluationScript.new()
	var result: AdviceResultScript = evaluation.result
	result.advice_id = advice_id
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		push_error("AdviceSystem: geçersiz yapılandırma; öneri değerlendirilemez: %s" % " | ".join(errors))
		result.failure = AdviceResultScript.FAILURE_INVALID_CONFIGURATION
		return evaluation
	var advice: AdviceDataScript = _find_advice(advice_id)
	if advice == null:
		push_error("AdviceSystem: tanımsız öneri: '%s'" % advice_id)
		result.failure = AdviceResultScript.FAILURE_UNKNOWN_ADVICE
		return evaluation
	result.advisor_actor_id = StringName(advice.context.advisor_actor_id)
	result.recipient_actor_id = StringName(advice.context.recipient_actor_id)
	result.decision_id = StringName(advice.context.decision_id)
	if _conditions.uses_trust(advice.presentation_conditions) and not _trust.is_initialized():
		push_error("AdviceSystem: güven başlatılmadı; güven koşullu öneri değerlendirilemez: '%s'" % advice_id)
		result.failure = AdviceResultScript.FAILURE_SYSTEM_NOT_READY
		return evaluation

	if not _conditions.get_failed_indexes(advice.presentation_conditions).is_empty():
		result.status = AdviceResultScript.STATUS_NOT_OFFERED
		return evaluation
	for variant in advice.variants:
		if _conditions.get_failed_indexes(variant.conditions).is_empty():
			result.status = AdviceResultScript.STATUS_OFFERED
			result.recommended_choice_id = StringName(variant.recommended_choice_id)
			evaluation.variant_id = StringName(variant.id)
			evaluation.accuracy = variant.accuracy
			return evaluation
	result.status = AdviceResultScript.STATUS_NO_APPLICABLE_VARIANT
	return evaluation


func _find_advice(advice_id: StringName) -> AdviceDataScript:
	for advice in _advices:
		if advice != null and StringName(advice.id) == advice_id:
			return advice
	return null


# --- Doğrulama ---

func _context_errors(advice_id: String, context: AdviceContextDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	var p: String = "'%s' bağlam: " % advice_id
	if context.advisor_actor_id.is_empty():
		errors.append(p + "eksik alan 'advisor_actor_id'")
	if context.recipient_actor_id.is_empty():
		errors.append(p + "eksik alan 'recipient_actor_id'")
	if not context.advisor_actor_id.is_empty() and context.advisor_actor_id == context.recipient_actor_id:
		errors.append(p + "kendine öneri '%s'" % context.advisor_actor_id)
	if not context.decision_id.is_empty() and _decisions.get_choice_ids(StringName(context.decision_id)).is_empty():
		errors.append(p + "tanımsız karar '%s'" % context.decision_id)
	return errors


func _variant_errors(advice: AdviceDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	var decision_id: String = "" if advice.context == null else advice.context.decision_id
	var seen_ids: Array[String] = []
	var unconditional_index: int = -1
	var last: int = advice.variants.size() - 1
	for i in advice.variants.size():
		var variant: AdviceVariantDataScript = advice.variants[i]
		var p: String = "'%s' biçim #%d: " % [advice.id, i]
		if variant == null:
			errors.append(p + "tanımsız kayıt")
			continue
		if variant.id.is_empty():
			errors.append(p + "boş biçim kimliği")
		elif seen_ids.has(variant.id):
			errors.append(p + "tekrarlanan biçim kimliği '%s'" % variant.id)
		else:
			seen_ids.append(variant.id)
		if variant.accuracy.is_empty():
			errors.append(p + "eksik alan 'accuracy'")
		elif not AdviceVariantDataScript.ACCURACIES.has(variant.accuracy):
			errors.append(p + "tanımsız doğruluk sınıfı '%s'" % variant.accuracy)
		for j in variant.conditions.size():
			errors.append_array(_conditions.get_errors("%skoşul #%d: " % [p, j], variant.conditions[j]))
		if _conditions.uses_trust(variant.conditions):
			errors.append(p + "biçim koşulunda güven kullanılamaz")
		# Koşulsuz biçim isteğe bağlıdır; en fazla bir tane olabilir ve son biçim olmalıdır.
		if variant.conditions.is_empty():
			if unconditional_index >= 0:
				errors.append(p + "birden fazla koşulsuz biçim (#%d ile)" % unconditional_index)
			else:
				unconditional_index = i
			if i != last:
				errors.append(p + "koşulsuz biçim son biçim olmalı")
		if not variant.recommended_choice_id.is_empty():
			if decision_id.is_empty():
				errors.append(p + "karar yokken önerilen seçenek '%s'" % variant.recommended_choice_id)
			elif not _decisions.has_choice(StringName(decision_id), StringName(variant.recommended_choice_id)):
				errors.append(p + "tanımsız seçenek '%s'" % variant.recommended_choice_id)
	return errors


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result


# --- Kopyalama ---

func _copy_advice(advice: AdviceDataScript) -> AdviceDataScript:
	var copy: AdviceDataScript = AdviceDataScript.new()
	copy.id = advice.id
	if advice.context != null:
		var context: AdviceContextDataScript = AdviceContextDataScript.new()
		context.advisor_actor_id = advice.context.advisor_actor_id
		context.recipient_actor_id = advice.context.recipient_actor_id
		context.decision_id = advice.context.decision_id
		copy.context = context
	for condition in advice.presentation_conditions:
		copy.presentation_conditions.append(null if condition == null else condition.copy())
	for variant in advice.variants:
		copy.variants.append(null if variant == null else _copy_variant(variant))
	return copy


func _copy_variant(variant: AdviceVariantDataScript) -> AdviceVariantDataScript:
	var copy: AdviceVariantDataScript = AdviceVariantDataScript.new()
	copy.id = variant.id
	copy.accuracy = variant.accuracy
	copy.recommended_choice_id = variant.recommended_choice_id
	for condition in variant.conditions:
		copy.conditions.append(null if condition == null else condition.copy())
	return copy
