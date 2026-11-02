class_name EquipmentDisableExpiration
extends RefCounted
## Bir ekipmanın geçici devre dışı süresinin bittiği an (K-031). Yalnızca "süre bitti" anlamı taşır; ekipmanın
## kullanılabilir olduğu anlamına gelmez (süresi biten arızalı ekipman arızalı kalır).

const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

var equipment_id: StringName = &""
var night: int = 0
var at_units: int = 0


func _init(p_equipment_id: StringName = &"", p_night: int = 0, p_at_units: int = 0) -> void:
	equipment_id = p_equipment_id
	night = p_night
	at_units = p_at_units


func copy() -> EquipmentDisableExpirationScript:
	return EquipmentDisableExpirationScript.new(equipment_id, night, at_units)
