class_name DecisionResult
extends RefCounted
## DecisionSystem.preview_choice ve choose sonucu (K-024). Her çağrıda yeni oluşturulur; değiştirilmesi
## oyun durumunu veya sonraki seçimleri etkilemez. Başarısız sonuçta effect_outcomes ve task_completions
## boş, time_result null.

const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")
const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")
const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

## Kurulum/akış hataları (push_error ile birlikte):
const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_UNKNOWN_CHOICE: StringName = &"unknown_choice"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"
const FAILURE_WRITE_FAILED: StringName = &"write_failed"
## Normal oyun sonuçları (hata basılmaz):
const FAILURE_CONDITIONS_NOT_MET: StringName = &"conditions_not_met"
const FAILURE_EFFECT_NOT_APPLICABLE: StringName = &"effect_not_applicable"
const FAILURE_TIME_UNAVAILABLE: StringName = &"time_unavailable"

var ok: bool = false
var decision_id: StringName = &""
var choice_id: StringName = &""
## ok = true ise boş.
var failure: StringName = &""
## conditions_not_met: sağlanmayan koşulların veri sırasındaki konumları.
var failed_condition_indexes: PackedInt32Array = []
## effect_not_applicable: uygulanamayan etkinin konumu; diğer durumlarda -1.
var blocking_effect_index: int = -1
## Veri sırasıyla etki sonuçları.
var effect_outcomes: Array[DecisionEffectOutcomeScript] = []
## Seçenekte eylem yoksa null.
var time_result: TimeAdvanceResultScript = null
## Eylem süresinde tamamlanan görevler, kronolojik sırayla (K-027). İç sistem verisidir.
var task_completions: Array[TaskCompletionOutcomeScript] = []
## Eylem süresinde biten geçici ekipman süreleri (K-031), bağımsız kopyalar. Eylem yoksa veya başarısızsa boş.
var equipment_disable_expirations: Array[EquipmentDisableExpirationScript] = []
