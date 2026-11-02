extends RefCounted
## Son belirleyici testleri için tarafsız veri ve sistem kurucuları (K-018). Oyun içeriği değildir.
## Dünya occurrence_fixtures ile aynıdır (2 gece × 10 birim; varsayılan görünüm kataloğu).

const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const EndingDataScript := preload("res://scripts/data/ending_data.gd")
const EndingResolverScript := preload("res://scripts/systems/ending_resolver.gd")


## conditions içindeki null değerler boş kayıt olarak eklenir. Boş liste koşulsuz yedek sondur.
static func make_ending(id: String, priority: int, conditions: Array = []) -> EndingDataScript:
	var ending: EndingDataScript = EndingDataScript.new()
	ending.id = id
	ending.priority = priority
	for condition in conditions:
		ending.conditions.append(condition)
	return ending


static func make_resolver(world: DecisionFixtures.World, endings: Array) -> EndingResolverScript:
	var typed: Array[EndingDataScript] = []
	for ending in endings:
		typed.append(ending)
	return EndingResolverScript.new(world.state, world.trust, world.time, typed)
