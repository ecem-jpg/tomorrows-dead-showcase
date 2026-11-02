class_name TimeRulesData
extends Resource
## Ana gece oynanışının zaman kuralları (K-022). Değerler veri dosyalarında tanımlanır, koda yazılmaz.
## Zaman soyut birimlerle ölçülür; ekranda gösterilecek saat bu verinin konusu değildir.

@export var id: String = ""
## En az 1.
@export var night_count: int = 0
## Bütün geceler için ortak uzunluk; en az 1.
@export var night_length_units: int = 0
## Eylem kimliği → zaman maliyeti. Negatif olamaz; 0'a izin verilir.
@export var action_costs: Dictionary[StringName, int] = {}
