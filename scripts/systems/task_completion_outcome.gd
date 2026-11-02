class_name TaskCompletionOutcome
extends RefCounted
## Bir zaman ilerlemesinde tamamlanan tek görevin sonucu (K-027). Kayıtlar TimeOccurrence kronolojik
## sırasıyla dizilir. İç sistem verisidir; oyuncuya nasıl gösterileceği arayüz aşamasında kararlaştırılır.

const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")

## Bütün tamamlanma etkileri uygulandı (etkisiz görevde liste boştur).
const STATUS_APPLIED: StringName = &"applied"
## Bir etki uygulanamadı (yetersiz harcama); görev tamamlandı ama hiçbir etkisi uygulanmadı. Hata değildir.
const STATUS_EFFECTS_NOT_APPLICABLE: StringName = &"effects_not_applicable"

var task_id: StringName = &""
var assigned_actor_id: StringName = &""
var night: int = 0
var at_units: int = 0
var status: StringName = &""
## Yalnızca applied: veri sırasıyla etki sonuçları; sınırda kesilen etkide applied, requested'dan farklıdır.
var effect_outcomes: Array[DecisionEffectOutcomeScript] = []
## Yalnızca effects_not_applicable: uygulanamayan etkinin veri sırasındaki konumu; diğer durumlarda -1.
var blocking_effect_index: int = -1
