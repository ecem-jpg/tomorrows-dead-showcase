class_name ChoiceData
extends Resource
## Bir kararın seçeneği; DecisionData içinde alt kaynak olarak tutulur (K-024).

const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")

## Karar içinde benzersiz.
@export var id: String = ""
@export var conditions: Array[ConditionDataScript] = []
## Aynı hedefe birden fazla etki olamaz.
@export var effects: Array[EffectDataScript] = []
## İsteğe bağlı; doluysa seçimle aynı atomik pakette zaman bu eylemin maliyeti kadar ilerler (K-025).
@export var action_id: String = ""
