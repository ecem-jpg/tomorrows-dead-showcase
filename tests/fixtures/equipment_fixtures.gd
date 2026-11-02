extends RefCounted
## Ekipman testleri için tarafsız veri ve sistem kurucuları (K-018). Oyun içeriği değildir.
## Dünya decision_fixtures ile aynıdır (res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30;
## 2 gece × 10 birim, action_a = 2, action_b = 0) ve ek olarak başlangıç ekipmanları taşır.
## Varsayılan ekipmanlar: equipment_a çalışıyor, equipment_b arızalı, equipment_c çalışıyor; hiçbiri devre dışı değil.

const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const InitialEquipmentDataScript := preload("res://scripts/data/initial_equipment_data.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const EquipmentSystemScript := preload("res://scripts/systems/equipment_system.gd")


static func make_initial(id: String, condition: StringName, disabled_units: int = 0) -> InitialEquipmentDataScript:
	var entry: InitialEquipmentDataScript = InitialEquipmentDataScript.new()
	entry.id = id
	entry.condition = condition
	entry.disabled_units = disabled_units
	return entry


static func default_equipment() -> Array:
	return [
		make_initial("equipment_a", EquipmentStateScript.CONDITION_OPERATIONAL),
		make_initial("equipment_b", EquipmentStateScript.CONDITION_BROKEN),
		make_initial("equipment_c", EquipmentStateScript.CONDITION_OPERATIONAL),
	]


## entries içindeki null değerler boş kayıt olarak eklenir.
static func make_setup(entries: Array) -> InitialStateDataScript:
	var setup: InitialStateDataScript = DecisionFixtures.make_state_setup()
	for entry in entries:
		setup.starting_equipment.append(entry)
	return setup


## state verilmezse entries ile yeni bir GameState kurulur.
static func make_world(entries: Array, state: GameStateScript = null) -> DecisionFixtures.World:
	return DecisionFixtures.make_world(state if state != null else GameStateScript.new(make_setup(entries)))


## Güveni başlatır ve ilk geceyi açar (yalnızca ekipman testleri için düşük seviyeli start_night).
static func start(world: DecisionFixtures.World) -> void:
	world.trust.initialize_relationships()
	world.time.start_night()


static func make_system(world: DecisionFixtures.World) -> EquipmentSystemScript:
	return EquipmentSystemScript.new(world.state)


static func cond_equipment(equipment_id: String, status: StringName) -> ConditionDataScript:
	return DecisionFixtures.make_condition(&"equipment", {"equipment_id": equipment_id, "equipment_status": status})


static func eff_break(equipment_id: String) -> EffectDataScript:
	return DecisionFixtures.make_effect(&"equipment_break", {"equipment_id": equipment_id})


static func eff_repair(equipment_id: String) -> EffectDataScript:
	return DecisionFixtures.make_effect(&"equipment_repair", {"equipment_id": equipment_id})


static func eff_disable(equipment_id: String, units: int) -> EffectDataScript:
	return DecisionFixtures.make_effect(&"equipment_disable", {"equipment_id": equipment_id, "amount": units})


## Ekipman anlık görüntüsü: [[kimlik, kalıcı durum, kalan süre], ...] kimlik sırasıyla.
static func rows(state: GameStateScript) -> Array:
	var result: Array = []
	for entry in state.get_equipment_snapshot():
		result.append([String(entry.equipment_id), entry.condition, entry.disabled_units])
	return result


## Süre bitiş kayıtları: [[kimlik, gece, an], ...].
static func expiration_rows(expirations: Array) -> Array:
	var result: Array = []
	for expiration in expirations:
		result.append([String(expiration.equipment_id), expiration.night, expiration.at_units])
	return result
