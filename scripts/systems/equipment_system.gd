class_name EquipmentSystem
extends RefCounted
## Ekipman durumunun sorgulanması ve zamanla geri sayımın yan etkisiz planlanması (K-031).
##
## - Durum yazmaz: değişiklikler yalnızca etkiler (EffectPlanner) ve TaskCompletionSystem.plan_time üzerinden
##   tek GameStateChange paketine girer. Hikâye, ekipman adları, arayüz veya mini oyun kuralları bilmez.
## - Görünür durum ve kullanılabilirlik EquipmentState'ten gelir: broken > disabled > operational; yalnızca
##   çalışır ve süresiz ekipman kullanılabilir. Süre bitmesi kullanılabilir olmak demek değildir.
## - plan_countdown süreyi ortak oyun saatinde, verilen zaman parçası kadar azaltır; TimeSystem ekipmanı bilmez.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const EquipmentViewScript := preload("res://scripts/systems/equipment_view.gd")
const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

var _state: GameStateScript


func _init(state: GameStateScript) -> void:
	if state == null:
		push_error("EquipmentSystem: oyun durumu verilmelidir.")
	_state = state


## Görünür durum. Tanımsız ekipmanda GameState hata verir; boş döner.
func get_status(equipment_id: StringName) -> StringName:
	var equipment: EquipmentStateScript = _state.get_equipment(equipment_id)
	return &"" if equipment == null else equipment.get_status()


## Tanımsız ekipmanda GameState hata verir; false döner.
func is_usable(equipment_id: StringName) -> bool:
	var equipment: EquipmentStateScript = _state.get_equipment(equipment_id)
	return equipment != null and equipment.is_usable()


## Arayüz için bütün ekipmanlar, kimlik sırasıyla; her çağrıda yeni görünümler.
func get_views() -> Array[EquipmentViewScript]:
	var views: Array[EquipmentViewScript] = []
	for equipment in _state.get_equipment_snapshot():
		var view: EquipmentViewScript = EquipmentViewScript.new()
		view.equipment_id = equipment.equipment_id
		view.condition = equipment.condition
		view.status = equipment.get_status()
		view.disabled_units = equipment.disabled_units
		view.usable = equipment.is_usable()
		views.append(view)
	return views


## Zaman parçası [from_units, to_units) boyunca bütün geçici süreleri azaltır ve yeni mutlak değerleri change'e
## yazar. Mevcut değer önce change'ten, yoksa durumdan okunur. Süresi r > 0 ve r ≤ parça uzunluğu olan her
## ekipman için tam bitiş anıyla bir kayıt döner; kayıtlar (at_units, equipment_id) sırasıyla. Kalıcı durum
## değişmez. Yazmaz, sinyal yaymaz, hata basmaz. Yalnızca TaskCompletionSystem.plan_time tarafından çağrılır.
static func plan_countdown(state: GameStateScript, change: GameStateChangeScript, night: int, from_units: int,
		to_units: int) -> Array[EquipmentDisableExpirationScript]:
	var expirations: Array[EquipmentDisableExpirationScript] = []
	var span: int = to_units - from_units
	if span <= 0:
		return expirations
	for equipment in state.get_equipment_snapshot():
		var current: EquipmentStateScript = current_in(state, change, equipment.equipment_id)
		var remaining: int = current.disabled_units
		if remaining <= 0:
			continue
		if remaining <= span:
			expirations.append(EquipmentDisableExpirationScript.new(current.equipment_id, night, from_units + remaining))
		current.disabled_units = maxi(0, remaining - span)
		write_into(change, current)
	expirations.sort_custom(func(a: EquipmentDisableExpirationScript, b: EquipmentDisableExpirationScript) -> bool:
		if a.at_units != b.at_units:
			return a.at_units < b.at_units
		return String(a.equipment_id) < String(b.equipment_id))
	return expirations


## Ekipmanın paketteki değerinin, yoksa durumdaki değerinin bağımsız kopyası. Tanımsızsa null.
static func current_in(state: GameStateScript, change: GameStateChangeScript, equipment_id: StringName) -> EquipmentStateScript:
	for entry in change.equipment_values:
		if entry.equipment_id == equipment_id:
			return entry.copy()
	return state.get_equipment(equipment_id) if state.has_equipment(equipment_id) else null


## Değerin bağımsız kopyasını pakete yazar; pakette aynı ekipman varsa yerinde günceller (iki kez bulunamaz).
static func write_into(change: GameStateChangeScript, value: EquipmentStateScript) -> void:
	for i in change.equipment_values.size():
		if change.equipment_values[i].equipment_id == value.equipment_id:
			change.equipment_values[i] = value.copy()
			return
	change.equipment_values.append(value.copy())
