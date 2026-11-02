class_name ResourceLimitsData
extends Resource
## Kaynakların alt ve üst sınırları. Sınırı yazılmamış yön sınırsızdır.
## Değerler veri dosyalarında tanımlanır, koda yazılmaz (K-016).

@export var id: String = ""
@export var min_values: Dictionary[StringName, int] = {}
@export var max_values: Dictionary[StringName, int] = {}
