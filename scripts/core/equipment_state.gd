class_name EquipmentState
extends RefCounted
## Bir ekipmanın çalışma zamanı durumu (K-031): kalıcı durum ile geçici devre dışı süresi ayrı tutulur.
## Görünür durum ve kullanılabilirlik bu iki alandan hesaplanır, ayrıca saklanmaz; tek kaynak bu sınıftır.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")

## Kalıcı durumlar.
const CONDITION_OPERATIONAL: StringName = &"operational"
const CONDITION_BROKEN: StringName = &"broken"
const CONDITIONS: Array[StringName] = [CONDITION_OPERATIONAL, CONDITION_BROKEN]

## Görünür durumlar; öncelik broken > disabled > operational.
const STATUS_OPERATIONAL: StringName = &"operational"
const STATUS_BROKEN: StringName = &"broken"
const STATUS_DISABLED: StringName = &"disabled"
const STATUSES: Array[StringName] = [STATUS_OPERATIONAL, STATUS_BROKEN, STATUS_DISABLED]

var equipment_id: StringName = &""
var condition: StringName = &""
## Geçici devre dışı süresi (ortak oyun saati birimi); 0 devre dışı değil demektir.
var disabled_units: int = 0


func _init(p_equipment_id: StringName = &"", p_condition: StringName = &"", p_disabled_units: int = 0) -> void:
	equipment_id = p_equipment_id
	condition = p_condition
	disabled_units = p_disabled_units


## Bağımsız kopya.
func copy() -> EquipmentStateScript:
	return EquipmentStateScript.new(equipment_id, condition, disabled_units)


func equals(other: EquipmentStateScript) -> bool:
	return other != null \
			and equipment_id == other.equipment_id \
			and condition == other.condition \
			and disabled_units == other.disabled_units


## broken > disabled > operational. Süresi süren arızalı ekipman broken görünür.
func get_status() -> StringName:
	if condition == CONDITION_BROKEN:
		return STATUS_BROKEN
	if disabled_units > 0:
		return STATUS_DISABLED
	return STATUS_OPERATIONAL


## Yalnızca çalışır durumda ve süresiz iken kullanılabilir.
func is_usable() -> bool:
	return condition == CONDITION_OPERATIONAL and disabled_units == 0


static func is_valid_condition(value: StringName) -> bool:
	return CONDITIONS.has(value)
