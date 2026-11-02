class_name InitialEquipmentData
extends Resource
## Yeni oyunun başlangıcındaki tek bir ekipman kaydı; InitialStateData.starting_equipment içinde alt kaynak (K-031).
## Ekipman adı veya içerik taşımaz. Geçersiz kayıtları GameState kurucusu hata basarak tek tek yok sayar.

@export var id: String = ""
## operational veya broken (EquipmentState.CONDITIONS).
@export var condition: StringName = &""
## 0 veya daha büyük; başlangıçta geçici devre dışı kurulumu destekler.
@export var disabled_units: int = 0
