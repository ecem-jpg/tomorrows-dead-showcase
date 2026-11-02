class_name CablePuzzleOutcomeData
extends Resource
## Kablo bulmacasının bir sonuç dalı (başarı veya başarısızlık); CablePuzzleData içinde alt kaynak olarak tutulur
## (K-019). Sonuçlar tamamen veriden gelir; kod başarıya kendiliğinden onarım eklemez.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const CablePuzzleOutcomeDataScript := preload("res://scripts/data/cable_puzzle_outcome_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")

## Aynı hedefe birden fazla etki olamaz.
@export var effects: Array[EffectDataScript] = []
## İsteğe bağlı; doluysa sonuçla aynı atomik pakette zaman bu eylemin maliyeti kadar ilerler.
@export var action_id: String = ""


## Bağımsız kopya; etkiler EffectData.copy() ile kopyalanır. Boş kayıtlar hata raporu için yerinde kalır.
func copy() -> CablePuzzleOutcomeDataScript:
	var result: CablePuzzleOutcomeDataScript = CablePuzzleOutcomeDataScript.new()
	for effect: EffectDataScript in effects:
		result.effects.append(null if effect == null else effect.copy())
	result.action_id = action_id
	return result
