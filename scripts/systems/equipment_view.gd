class_name EquipmentView
extends RefCounted
## Bir ekipmanın arayüze verilebilir görünümü (K-031). Her çağrıda yeni oluşturulur; değiştirilmesi durumu etkilemez.

var equipment_id: StringName = &""
## Kalıcı durum: operational veya broken.
var condition: StringName = &""
## Görünür durum: broken > disabled > operational.
var status: StringName = &""
## Kalan geçici devre dışı süresi.
var disabled_units: int = 0
var usable: bool = false
