class_name DecisionEffectOutcome
extends RefCounted
## Bir etkinin (seçim veya görev tamamlanma etkisi) istenen ve gerçekten uygulanan değeri (K-024, K-027).
## Sınırda kesme burada görünür.

var index: int = -1
var kind: StringName = &""
var resource_id: StringName = &""
var source_actor_id: StringName = &""
var target_actor_id: StringName = &""
var flag_id: StringName = &""
## Kaynak/güven: verideki miktar. Harcamada pozitif miktar.
var requested: int = 0
## Kaynak/güven: etkiden önceki değer.
var previous: int = 0
## Kaynak/güven: gerçekten uygulanan işaretli değişim (harcamada negatif).
var applied: int = 0
## Bayrak: etkiden önceki ve yazılan değer.
var previous_flag: bool = false
var flag_value: bool = false
## Görünüm (K-029): hedef, etkiden önceki ve yazılan iç durum. İç sistem verisidir.
var occurrence_id: StringName = &""
var previous_occurrence_status: StringName = &""
var occurrence_status: StringName = &""
## Ekipman (K-031): hedef, etkiden önceki ve yazılan kalıcı durum ile kalan süre.
var equipment_id: StringName = &""
var previous_equipment_condition: StringName = &""
var equipment_condition: StringName = &""
var previous_disabled_units: int = 0
var disabled_units: int = 0
