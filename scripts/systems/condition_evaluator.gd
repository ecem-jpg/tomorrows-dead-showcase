class_name ConditionEvaluator
extends RefCounted
## ConditionData değerlendirmesinin ve doğrulamasının tek kaynağı (K-024, K-026, K-029). Karar ve görev sistemleri
## kendi örneklerini oluşturur; böylece aynı koşul her yerde aynı sonucu ve aynı hata metnini üretir.
## Yalnızca okur: durum yazmaz, sinyal yaymaz, motor hatası basmaz ve rastgele sayı üreteci kullanmaz.
## Yalnızca koşullardan sorumludur; etki doğrulaması kullanan sistemin işidir.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")

const COMPARISONS: Array[StringName] = [
	ConditionDataScript.COMPARISON_EQ, ConditionDataScript.COMPARISON_NE, ConditionDataScript.COMPARISON_LT,
	ConditionDataScript.COMPARISON_LE, ConditionDataScript.COMPARISON_GT, ConditionDataScript.COMPARISON_GE,
]

var _state: GameStateScript
var _trust: TrustSystemScript


func _init(state: GameStateScript, trust_system: TrustSystemScript) -> void:
	_state = state
	_trust = trust_system


## Koşul mevcut durumda sağlanıyor mu. Koşulun önceden get_errors ile doğrulanmış olması beklenir.
func is_met(condition: ConditionDataScript) -> bool:
	match condition.kind:
		ConditionDataScript.KIND_RESOURCE:
			return _compare(_state.get_resource(StringName(condition.resource_id)), condition.comparison, condition.value)
		ConditionDataScript.KIND_TRUST:
			var trust: int = _state.get_trust(StringName(condition.source_actor_id), StringName(condition.target_actor_id))
			return _compare(trust, condition.comparison, condition.value)
		ConditionDataScript.KIND_FLAG:
			# Tanımsız bayrak GameState kuralına göre false okunur.
			return _state.get_flag(StringName(condition.flag_id)) == condition.flag_value
		ConditionDataScript.KIND_OCCURRENCE:
			return _state.get_occurrence_status(StringName(condition.occurrence_id)) == condition.occurrence_status
		ConditionDataScript.KIND_EQUIPMENT:
			var equipment: EquipmentStateScript = _state.get_equipment(StringName(condition.equipment_id))
			return equipment != null and equipment.get_status() == condition.equipment_status
	return false


## Sağlanmayan koşulların veri sırasındaki konumları.
func get_failed_indexes(conditions: Array[ConditionDataScript]) -> PackedInt32Array:
	var failed: PackedInt32Array = []
	for i in conditions.size():
		if not is_met(conditions[i]):
			failed.append(i)
	return failed


## Listede güven koşulu var mı (güvenin başlatılmış olması gerekip gerekmediğini belirler).
func uses_trust(conditions: Array[ConditionDataScript]) -> bool:
	for condition in conditions:
		if condition != null and condition.kind == ConditionDataScript.KIND_TRUST:
			return true
	return false


## Koşulun yapılandırma hataları; her satır prefix ile başlar. Sabit sırayla döner, hiçbir değeri düzeltmez.
func get_errors(prefix: String, condition: ConditionDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	var p: String = prefix
	if condition == null:
		errors.append(p + "tanımsız kayıt")
		return errors
	match condition.kind:
		ConditionDataScript.KIND_RESOURCE:
			_require(errors, p, "resource_id", condition.resource_id)
			_forbid_text(errors, p, "source_actor_id", condition.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", condition.target_actor_id)
			_forbid_text(errors, p, "flag_id", condition.flag_id)
			_forbid_bool(errors, p, "flag_value", condition.flag_value)
			_check_comparison(errors, p, condition.comparison)
			_check_resource(errors, p, condition.resource_id)
			_forbid_occurrence_fields(errors, p, condition)
			_forbid_equipment_fields(errors, p, condition)
		ConditionDataScript.KIND_TRUST:
			_require(errors, p, "source_actor_id", condition.source_actor_id)
			_require(errors, p, "target_actor_id", condition.target_actor_id)
			_forbid_text(errors, p, "resource_id", condition.resource_id)
			_forbid_text(errors, p, "flag_id", condition.flag_id)
			_forbid_bool(errors, p, "flag_value", condition.flag_value)
			_check_comparison(errors, p, condition.comparison)
			_check_trust_pair(errors, p, condition.source_actor_id, condition.target_actor_id)
			if not _trust.is_threshold_in_range(condition.value):
				errors.append(p + "güven eşiği aralık dışında: %d" % condition.value)
			_forbid_occurrence_fields(errors, p, condition)
			_forbid_equipment_fields(errors, p, condition)
		ConditionDataScript.KIND_FLAG:
			_require(errors, p, "flag_id", condition.flag_id)
			_forbid_text(errors, p, "resource_id", condition.resource_id)
			_forbid_text(errors, p, "source_actor_id", condition.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", condition.target_actor_id)
			if not condition.comparison.is_empty():
				errors.append(p + "ilgisiz alan dolu 'comparison'")
			if condition.value != 0:
				errors.append(p + "ilgisiz alan dolu 'value'")
			_forbid_occurrence_fields(errors, p, condition)
			_forbid_equipment_fields(errors, p, condition)
		ConditionDataScript.KIND_OCCURRENCE:
			_require(errors, p, "occurrence_id", condition.occurrence_id)
			_forbid_text(errors, p, "resource_id", condition.resource_id)
			_forbid_text(errors, p, "source_actor_id", condition.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", condition.target_actor_id)
			_forbid_text(errors, p, "flag_id", condition.flag_id)
			_forbid_bool(errors, p, "flag_value", condition.flag_value)
			if not condition.comparison.is_empty():
				errors.append(p + "ilgisiz alan dolu 'comparison'")
			if condition.value != 0:
				errors.append(p + "ilgisiz alan dolu 'value'")
			if condition.occurrence_status.is_empty():
				errors.append(p + "eksik alan 'occurrence_status'")
			elif not OccurrenceStatusScript.is_valid(condition.occurrence_status):
				errors.append(p + "tanımsız görünüm durumu '%s'" % condition.occurrence_status)
			if not condition.occurrence_id.is_empty() and not _state.has_occurrence(StringName(condition.occurrence_id)):
				errors.append(p + "tanımsız görünüm '%s'" % condition.occurrence_id)
			_forbid_equipment_fields(errors, p, condition)
		ConditionDataScript.KIND_EQUIPMENT:
			_require(errors, p, "equipment_id", condition.equipment_id)
			_forbid_text(errors, p, "resource_id", condition.resource_id)
			_forbid_text(errors, p, "source_actor_id", condition.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", condition.target_actor_id)
			_forbid_text(errors, p, "flag_id", condition.flag_id)
			_forbid_bool(errors, p, "flag_value", condition.flag_value)
			if not condition.comparison.is_empty():
				errors.append(p + "ilgisiz alan dolu 'comparison'")
			if condition.value != 0:
				errors.append(p + "ilgisiz alan dolu 'value'")
			_forbid_occurrence_fields(errors, p, condition)
			if condition.equipment_status.is_empty():
				errors.append(p + "eksik alan 'equipment_status'")
			elif not EquipmentStateScript.STATUSES.has(condition.equipment_status):
				errors.append(p + "tanımsız ekipman durumu '%s'" % condition.equipment_status)
			if not condition.equipment_id.is_empty() and not _state.has_equipment(StringName(condition.equipment_id)):
				errors.append(p + "tanımsız ekipman '%s'" % condition.equipment_id)
		_:
			errors.append(p + "tanımsız tür '%s'" % condition.kind)
	return errors


func _compare(actual: int, comparison: StringName, expected: int) -> bool:
	match comparison:
		ConditionDataScript.COMPARISON_EQ:
			return actual == expected
		ConditionDataScript.COMPARISON_NE:
			return actual != expected
		ConditionDataScript.COMPARISON_LT:
			return actual < expected
		ConditionDataScript.COMPARISON_LE:
			return actual <= expected
		ConditionDataScript.COMPARISON_GT:
			return actual > expected
		ConditionDataScript.COMPARISON_GE:
			return actual >= expected
	return false


func _require(errors: PackedStringArray, p: String, field: String, value: String) -> void:
	if value.is_empty():
		errors.append(p + "eksik alan '%s'" % field)


func _forbid_text(errors: PackedStringArray, p: String, field: String, value: String) -> void:
	if not value.is_empty():
		errors.append(p + "ilgisiz alan dolu '%s'" % field)


func _forbid_bool(errors: PackedStringArray, p: String, field: String, value: bool) -> void:
	if value:
		errors.append(p + "ilgisiz alan dolu '%s'" % field)


# Görünüm türü dışındaki koşullarda görünüm alanları boş kalmalıdır.
func _forbid_occurrence_fields(errors: PackedStringArray, p: String, condition: ConditionDataScript) -> void:
	_forbid_text(errors, p, "occurrence_id", condition.occurrence_id)
	if not condition.occurrence_status.is_empty():
		errors.append(p + "ilgisiz alan dolu 'occurrence_status'")


# Ekipman türü dışındaki koşullarda ekipman alanları boş kalmalıdır.
func _forbid_equipment_fields(errors: PackedStringArray, p: String, condition: ConditionDataScript) -> void:
	_forbid_text(errors, p, "equipment_id", condition.equipment_id)
	if not condition.equipment_status.is_empty():
		errors.append(p + "ilgisiz alan dolu 'equipment_status'")


func _check_comparison(errors: PackedStringArray, p: String, comparison: StringName) -> void:
	if comparison.is_empty():
		errors.append(p + "eksik alan 'comparison'")
	elif not COMPARISONS.has(comparison):
		errors.append(p + "tanımsız karşılaştırma '%s'" % comparison)


func _check_resource(errors: PackedStringArray, p: String, resource_id: String) -> void:
	if not resource_id.is_empty() and not _state.has_resource(StringName(resource_id)):
		errors.append(p + "tanımsız kaynak '%s'" % resource_id)


func _check_trust_pair(errors: PackedStringArray, p: String, source: String, target: String) -> void:
	if source.is_empty() or target.is_empty():
		return
	if source == target:
		errors.append(p + "kendine güven ilişkisi '%s'" % source)
	elif not _trust.has_relationship(StringName(source), StringName(target)):
		errors.append(p + "tanımsız güven ilişkisi '%s' -> '%s'" % [source, target])
