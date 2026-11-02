class_name ResourceSystem
extends RefCounted
## Kaynak değerlerini veriyle tanımlı alt/üst sınırlara uyarak değiştirir.
## Değerleri saklamaz; GameState üzerinden okur ve yazar. Normal oyun akışında kaynak
## değişiklikleri bu sınıf üzerinden yapılır, GameState.set_resource doğrudan çağrılmaz.
## Sınırı yazılmamış yön sınırsızdır. Kendi sinyali yoktur; değişiklikler
## GameState.state_changed ile bildirilir.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const ResourceLimitsDataScript := preload("res://scripts/data/resource_limits_data.gd")

var _state: GameStateScript
var _min_values: Dictionary[StringName, int] = {}
var _max_values: Dictionary[StringName, int] = {}


func _init(state: GameStateScript, limits: ResourceLimitsDataScript) -> void:
	if state == null or limits == null:
		push_error("ResourceSystem: durum ve sınır verisi verilmelidir.")
	_state = state
	if limits != null:
		_min_values = limits.min_values.duplicate()
		_max_values = limits.max_values.duplicate()


## Değeri artırır, üst sınırda keser ve gerçekten eklenen miktarı döndürür.
## Tanımsız kaynak veya negatif miktarda hata verir ve 0 döner.
func add(resource_id: StringName, amount: int) -> int:
	if not _is_valid_request(resource_id, amount, "ekleme"):
		return 0
	var current: int = _state.get_resource(resource_id)
	var target: int = compute_add(resource_id, amount, current)
	_state.set_resource(resource_id, target)
	return target - current


## Harcama alt sınırı ihlal etmiyorsa true. Durumu değiştirmez.
## Tanımsız kaynak veya negatif miktarda hata verir ve false döner.
func can_spend(resource_id: StringName, amount: int) -> bool:
	if not _is_valid_request(resource_id, amount, "harcama"):
		return false
	return can_spend_from(resource_id, amount, _state.get_resource(resource_id))


## Yan etkisiz: verilen değere amount eklendiğinde add'in yazacağı yeni değer (K-025).
## Doğrulama yapmaz ve hata basmaz; kimlik ve miktar çağıran tarafından doğrulanmış olmalıdır.
func compute_add(resource_id: StringName, amount: int, current: int) -> int:
	var target: int = current + amount
	if _max_values.has(resource_id):
		target = mini(target, _max_values[resource_id])
	# Değer zaten üst sınırın üstündeyse ekleme onu düşürmemeli.
	return maxi(target, current)


## Yan etkisiz: verilen değerden amount harcamak alt sınırı ihlal etmiyorsa true (K-025).
## Doğrulama yapmaz ve hata basmaz; kimlik ve miktar çağıran tarafından doğrulanmış olmalıdır.
func can_spend_from(resource_id: StringName, amount: int, current: int) -> bool:
	if not _min_values.has(resource_id):
		return true
	return current - amount >= _min_values[resource_id]


## Ya tamamen harcar ya hiç. Yetersizlik hata değildir; yalnızca false döner.
func spend(resource_id: StringName, amount: int) -> bool:
	if not can_spend(resource_id, amount):
		return false
	if amount > 0:
		_state.set_resource(resource_id, _state.get_resource(resource_id) - amount)
	return true


## Sınır verisindeki tutarsızlıkları kimliğe göre sıralı döndürür; durumu değiştirmez.
func get_configuration_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	var ids: PackedStringArray = []
	for resource_id in _min_values.keys() + _max_values.keys():
		if not ids.has(String(resource_id)):
			ids.append(String(resource_id))
	ids.sort()

	for id_text in ids:
		var resource_id: StringName = StringName(id_text)
		if not _state.has_resource(resource_id):
			errors.append("Tanımsız kaynak için sınır: '%s'" % id_text)
			continue
		var has_min: bool = _min_values.has(resource_id)
		var has_max: bool = _max_values.has(resource_id)
		if has_min and has_max and _min_values[resource_id] > _max_values[resource_id]:
			errors.append("Alt sınır üst sınırdan büyük: '%s' (alt %d, üst %d)"
					% [id_text, _min_values[resource_id], _max_values[resource_id]])
			continue
		var value: int = _state.get_resource(resource_id)
		if has_min and value < _min_values[resource_id]:
			errors.append("Değer alt sınırın altında: '%s' (değer %d, alt %d)"
					% [id_text, value, _min_values[resource_id]])
		if has_max and value > _max_values[resource_id]:
			errors.append("Değer üst sınırın üstünde: '%s' (değer %d, üst %d)"
					% [id_text, value, _max_values[resource_id]])
	return errors


func _is_valid_request(resource_id: StringName, amount: int, action: String) -> bool:
	if not _state.has_resource(resource_id):
		push_error("ResourceSystem: tanımsız kaynakta %s yapılamaz: '%s'" % [action, resource_id])
		return false
	if amount < 0:
		push_error("ResourceSystem: negatif miktarla %s yapılamaz: '%s' (%d)" % [action, resource_id, amount])
		return false
	return true
