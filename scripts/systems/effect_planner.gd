class_name EffectPlanner
extends RefCounted
## EffectData planlamasının ve doğrulamasının tek kaynağı (K-024, K-027, K-029). Karar ve görev tamamlanma
## sistemleri kendi örneklerini oluşturur; aynı etki her yerde aynı sonucu ve aynı hata metnini üretir.
## Yalnızca hesaplar: durum yazmaz, sinyal yaymaz, motor hatası basmaz ve rastgele sayı üreteci kullanmaz.
##
## Biriken değer: plan bir hedefin mevcut değerini önce verilen pakette arar, yoksa GameState'ten okur;
## yeni mutlak değeri yine pakete yazar. Böylece aynı pakette art arda gelen etkiler, her biri ayrı ayrı
## sınırda kesilerek birbirinin üzerine hesaplanır ve pakette yalnızca nihai değer kalır.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const EquipmentSystemScript := preload("res://scripts/systems/equipment_system.gd")

var _state: GameStateScript
var _resources: ResourceSystemScript
var _trust: TrustSystemScript


func _init(state: GameStateScript, resource_system: ResourceSystemScript, trust_system: TrustSystemScript) -> void:
	_state = state
	_resources = resource_system
	_trust = trust_system


## Etkinin yeni değerini change'e ekler ve sonucunu döndürür. Harcama yetersizse, görünüm geçişi izinli değilse
## (K-029) veya ekipman arızası/onarımı etkisizse (K-031) null döner ve change'e dokunmaz. Etkinin önceden
## get_errors ile doğrulanmış olması beklenir.
func plan(index: int, effect: EffectDataScript, change: GameStateChangeScript) -> DecisionEffectOutcomeScript:
	var outcome: DecisionEffectOutcomeScript = DecisionEffectOutcomeScript.new()
	outcome.index = index
	outcome.kind = effect.kind
	match effect.kind:
		EffectDataScript.KIND_RESOURCE_ADD:
			var resource_id: StringName = StringName(effect.resource_id)
			var current: int = _current_resource(resource_id, change)
			var updated: int = _resources.compute_add(resource_id, effect.amount, current)
			_fill_numeric(outcome, effect.amount, current, updated - current)
			outcome.resource_id = resource_id
			if updated != current:
				change.resource_values[resource_id] = updated
		EffectDataScript.KIND_RESOURCE_SPEND:
			var resource_id: StringName = StringName(effect.resource_id)
			var current: int = _current_resource(resource_id, change)
			if not _resources.can_spend_from(resource_id, effect.amount, current):
				return null
			_fill_numeric(outcome, effect.amount, current, -effect.amount)
			outcome.resource_id = resource_id
			if effect.amount != 0:
				change.resource_values[resource_id] = current - effect.amount
		EffectDataScript.KIND_TRUST_CHANGE:
			var source: StringName = StringName(effect.source_actor_id)
			var target: StringName = StringName(effect.target_actor_id)
			var index_in_change: int = _find_trust(change, source, target)
			var current: int = change.trust_values[index_in_change].value if index_in_change >= 0 \
					else _state.get_trust(source, target)
			var updated: int = _trust.compute_change(current, effect.amount)
			_fill_numeric(outcome, effect.amount, current, updated - current)
			outcome.source_actor_id = source
			outcome.target_actor_id = target
			if updated != current:
				# Pakette aynı ilişki iki kez bulunamaz; varsa yerinde güncellenir.
				var entry: TrustRelationshipStateScript = TrustRelationshipStateScript.new(source, target, updated)
				if index_in_change >= 0:
					change.trust_values[index_in_change] = entry
				else:
					change.trust_values.append(entry)
		EffectDataScript.KIND_FLAG_SET:
			var flag_id: StringName = StringName(effect.flag_id)
			outcome.flag_id = flag_id
			outcome.previous_flag = change.flag_values[flag_id] if change.flag_values.has(flag_id) \
					else _state.get_flag(flag_id)
			outcome.flag_value = effect.flag_value
			change.flag_values[flag_id] = effect.flag_value
		EffectDataScript.KIND_OCCURRENCE_PREVENT_DEATH, EffectDataScript.KIND_OCCURRENCE_MAKE_DEATH_PERMANENT:
			var occurrence_id: StringName = StringName(effect.occurrence_id)
			var current: StringName = change.occurrence_statuses[occurrence_id] \
					if change.occurrence_statuses.has(occurrence_id) else _state.get_occurrence_status(occurrence_id)
			var target: StringName = OccurrenceStatusScript.STATUS_DEATH_PREVENTED \
					if effect.kind == EffectDataScript.KIND_OCCURRENCE_PREVENT_DEATH else OccurrenceStatusScript.STATUS_DEATH_PERMANENT
			if not OccurrenceStatusScript.can_transition(current, target):
				return null
			outcome.occurrence_id = occurrence_id
			outcome.previous_occurrence_status = current
			outcome.occurrence_status = target
			change.occurrence_statuses[occurrence_id] = target
		EffectDataScript.KIND_EQUIPMENT_BREAK, EffectDataScript.KIND_EQUIPMENT_REPAIR, EffectDataScript.KIND_EQUIPMENT_DISABLE:
			var equipment_id: StringName = StringName(effect.equipment_id)
			var current: EquipmentStateScript = EquipmentSystemScript.current_in(_state, change, equipment_id)
			var updated: EquipmentStateScript = current.copy()
			match effect.kind:
				EffectDataScript.KIND_EQUIPMENT_BREAK:
					if current.condition != EquipmentStateScript.CONDITION_OPERATIONAL:
						return null
					updated.condition = EquipmentStateScript.CONDITION_BROKEN
				EffectDataScript.KIND_EQUIPMENT_REPAIR:
					if current.condition != EquipmentStateScript.CONDITION_BROKEN:
						return null
					updated.condition = EquipmentStateScript.CONDITION_OPERATIONAL
				EffectDataScript.KIND_EQUIPMENT_DISABLE:
					# Süre kısalmaz: max(kalan, yeni).
					updated.disabled_units = maxi(current.disabled_units, effect.amount)
			outcome.equipment_id = equipment_id
			outcome.previous_equipment_condition = current.condition
			outcome.equipment_condition = updated.condition
			outcome.previous_disabled_units = current.disabled_units
			outcome.disabled_units = updated.disabled_units
			if not updated.equals(current):
				EquipmentSystemScript.write_into(change, updated)
	return outcome


## Etkinin yapılandırma hataları; her satır prefix ile başlar. Sabit sırayla döner, hiçbir değeri düzeltmez.
func get_errors(prefix: String, effect: EffectDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	var p: String = prefix
	if effect == null:
		errors.append(p + "tanımsız kayıt")
		return errors
	match effect.kind:
		EffectDataScript.KIND_RESOURCE_ADD, EffectDataScript.KIND_RESOURCE_SPEND:
			_require(errors, p, "resource_id", effect.resource_id)
			_forbid_text(errors, p, "source_actor_id", effect.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", effect.target_actor_id)
			_forbid_text(errors, p, "flag_id", effect.flag_id)
			_forbid_bool(errors, p, "flag_value", effect.flag_value)
			if effect.amount < 0:
				errors.append(p + "negatif miktar: %d" % effect.amount)
			_check_resource(errors, p, effect.resource_id)
			_forbid_text(errors, p, "occurrence_id", effect.occurrence_id)
			_forbid_text(errors, p, "equipment_id", effect.equipment_id)
		EffectDataScript.KIND_TRUST_CHANGE:
			_require(errors, p, "source_actor_id", effect.source_actor_id)
			_require(errors, p, "target_actor_id", effect.target_actor_id)
			_forbid_text(errors, p, "resource_id", effect.resource_id)
			_forbid_text(errors, p, "flag_id", effect.flag_id)
			_forbid_bool(errors, p, "flag_value", effect.flag_value)
			_check_trust_pair(errors, p, effect.source_actor_id, effect.target_actor_id)
			_forbid_text(errors, p, "occurrence_id", effect.occurrence_id)
			_forbid_text(errors, p, "equipment_id", effect.equipment_id)
		EffectDataScript.KIND_FLAG_SET:
			_require(errors, p, "flag_id", effect.flag_id)
			_forbid_text(errors, p, "resource_id", effect.resource_id)
			_forbid_text(errors, p, "source_actor_id", effect.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", effect.target_actor_id)
			if effect.amount != 0:
				errors.append(p + "ilgisiz alan dolu 'amount'")
			_forbid_text(errors, p, "occurrence_id", effect.occurrence_id)
			_forbid_text(errors, p, "equipment_id", effect.equipment_id)
		EffectDataScript.KIND_OCCURRENCE_PREVENT_DEATH, EffectDataScript.KIND_OCCURRENCE_MAKE_DEATH_PERMANENT:
			_require(errors, p, "occurrence_id", effect.occurrence_id)
			_forbid_text(errors, p, "resource_id", effect.resource_id)
			_forbid_text(errors, p, "source_actor_id", effect.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", effect.target_actor_id)
			_forbid_text(errors, p, "flag_id", effect.flag_id)
			_forbid_bool(errors, p, "flag_value", effect.flag_value)
			if effect.amount != 0:
				errors.append(p + "ilgisiz alan dolu 'amount'")
			if not effect.occurrence_id.is_empty() and not _state.has_occurrence(StringName(effect.occurrence_id)):
				errors.append(p + "tanımsız görünüm '%s'" % effect.occurrence_id)
			_forbid_text(errors, p, "equipment_id", effect.equipment_id)
		EffectDataScript.KIND_EQUIPMENT_BREAK, EffectDataScript.KIND_EQUIPMENT_REPAIR, EffectDataScript.KIND_EQUIPMENT_DISABLE:
			_require(errors, p, "equipment_id", effect.equipment_id)
			_forbid_text(errors, p, "resource_id", effect.resource_id)
			_forbid_text(errors, p, "source_actor_id", effect.source_actor_id)
			_forbid_text(errors, p, "target_actor_id", effect.target_actor_id)
			_forbid_text(errors, p, "flag_id", effect.flag_id)
			_forbid_bool(errors, p, "flag_value", effect.flag_value)
			_forbid_text(errors, p, "occurrence_id", effect.occurrence_id)
			if effect.kind == EffectDataScript.KIND_EQUIPMENT_DISABLE:
				if effect.amount < 1:
					errors.append(p + "devre dışı süresi en az 1 olmalı: %d" % effect.amount)
			elif effect.amount != 0:
				errors.append(p + "ilgisiz alan dolu 'amount'")
			if not effect.equipment_id.is_empty() and not _state.has_equipment(StringName(effect.equipment_id)):
				errors.append(p + "tanımsız ekipman '%s'" % effect.equipment_id)
		_:
			errors.append(p + "tanımsız tür '%s'" % effect.kind)
	return errors


## Listede güven etkisi var mı (güvenin başlatılmış olması gerekip gerekmediğini belirler).
func uses_trust(effects: Array[EffectDataScript]) -> bool:
	for effect in effects:
		if effect != null and effect.kind == EffectDataScript.KIND_TRUST_CHANGE:
			return true
	return false


## Kaynakta ekleme ve harcama aynı hedeftir; güvende aynı yönlü çift; bayrakta aynı kimlik; görünümde
## (engelleme veya kalıcılaştırma) aynı görünüm; ekipmanda (arıza, onarım, devre dışı) aynı ekipman.
## Ters yönlü güven ilişkileri farklı hedeflerdir.
func is_same_target(a: EffectDataScript, b: EffectDataScript) -> bool:
	if a == null or b == null:
		return false
	var equipment_kinds: Array[StringName] = [EffectDataScript.KIND_EQUIPMENT_BREAK,
			EffectDataScript.KIND_EQUIPMENT_REPAIR, EffectDataScript.KIND_EQUIPMENT_DISABLE]
	if a.kind in equipment_kinds and b.kind in equipment_kinds:
		return not a.equipment_id.is_empty() and a.equipment_id == b.equipment_id
	var occurrence_kinds: Array[StringName] = [EffectDataScript.KIND_OCCURRENCE_PREVENT_DEATH,
			EffectDataScript.KIND_OCCURRENCE_MAKE_DEATH_PERMANENT]
	if a.kind in occurrence_kinds and b.kind in occurrence_kinds:
		return not a.occurrence_id.is_empty() and a.occurrence_id == b.occurrence_id
	var resource_kinds: Array[StringName] = [EffectDataScript.KIND_RESOURCE_ADD, EffectDataScript.KIND_RESOURCE_SPEND]
	if a.kind in resource_kinds and b.kind in resource_kinds:
		return not a.resource_id.is_empty() and a.resource_id == b.resource_id
	if a.kind == EffectDataScript.KIND_TRUST_CHANGE and b.kind == EffectDataScript.KIND_TRUST_CHANGE:
		return not a.source_actor_id.is_empty() and not a.target_actor_id.is_empty() \
				and a.source_actor_id == b.source_actor_id and a.target_actor_id == b.target_actor_id
	if a.kind == EffectDataScript.KIND_FLAG_SET and b.kind == EffectDataScript.KIND_FLAG_SET:
		return not a.flag_id.is_empty() and a.flag_id == b.flag_id
	return false


func _current_resource(resource_id: StringName, change: GameStateChangeScript) -> int:
	if change.resource_values.has(resource_id):
		return change.resource_values[resource_id]
	return _state.get_resource(resource_id)


func _find_trust(change: GameStateChangeScript, source: StringName, target: StringName) -> int:
	for i in change.trust_values.size():
		var entry: TrustRelationshipStateScript = change.trust_values[i]
		if entry.source_actor_id == source and entry.target_actor_id == target:
			return i
	return -1


func _fill_numeric(outcome: DecisionEffectOutcomeScript, requested: int, previous: int, applied: int) -> void:
	outcome.requested = requested
	outcome.previous = previous
	outcome.applied = applied


func _require(errors: PackedStringArray, p: String, field: String, value: String) -> void:
	if value.is_empty():
		errors.append(p + "eksik alan '%s'" % field)


func _forbid_text(errors: PackedStringArray, p: String, field: String, value: String) -> void:
	if not value.is_empty():
		errors.append(p + "ilgisiz alan dolu '%s'" % field)


func _forbid_bool(errors: PackedStringArray, p: String, field: String, value: bool) -> void:
	if value:
		errors.append(p + "ilgisiz alan dolu '%s'" % field)


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
