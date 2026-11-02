class_name DecisionData
extends Resource
## Bir karar ve seçenekleri (K-024). Seçenek, koşul ve etkiler iç içe alt kaynaklardır.

const ChoiceDataScript := preload("res://scripts/data/choice_data.gd")

@export var id: String = ""
## En az bir seçenek gerekir.
@export var choices: Array[ChoiceDataScript] = []
