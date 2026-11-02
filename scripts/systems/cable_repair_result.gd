class_name CableRepairResult
extends RefCounted
## CableRepairSystem.preview_result ve apply_result sonucu (K-032). Her çağrıda yeni oluşturulur; değiştirilmesi
## oyun durumunu veya oturumu etkilemez. Görev tamamlanma ayrıntıları ve zaman oluşumları gibi iç sistem verileri
## yalnızca kimlik ve birim olarak raporlanır. Başarısız sonuçta etki ve zaman alanları boş kalır.

const DecisionEffectOutcomeScript := preload("res://scripts/systems/decision_effect_outcome.gd")
const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

## Kurulum/akış hataları (push_error ile birlikte):
const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_FOREIGN_SESSION: StringName = &"foreign_session"
const FAILURE_SESSION_NOT_FINISHED: StringName = &"session_not_finished"
const FAILURE_ALREADY_APPLIED: StringName = &"already_applied"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"
const FAILURE_WRITE_FAILED: StringName = &"write_failed"
## Normal oyun sonuçları (hata basılmaz):
## Oturum açıldıktan sonra bulmacanın ilerlemesi değişti; sonuç artık uygulanamaz.
const FAILURE_STALE_SESSION: StringName = &"stale_session"
const FAILURE_EFFECT_NOT_APPLICABLE: StringName = &"effect_not_applicable"
const FAILURE_TIME_UNAVAILABLE: StringName = &"time_unavailable"

var ok: bool = false
## ok = true ise boş.
var failure: StringName = &""
var puzzle_id: StringName = &""
## Oturumun kesin sonucu (solved / failed); oturum bitmemişse veya tanınmıyorsa boş.
var outcome: StringName = &""
## effect_not_applicable: uygulanamayan etkinin dal içindeki konumu; diğer durumlarda -1.
var blocking_effect_index: int = -1
## Seçilen dalın etki sonuçları, veri sırasıyla.
var effect_outcomes: Array[DecisionEffectOutcomeScript] = []
## Dalda eylem yoksa 0.
var applied_units: int = 0
var overflow_units: int = 0
var night_ended: bool = false
## Eylem süresinde tamamlanan görevler, kronolojik sırayla.
var completed_task_ids: Array[StringName] = []
## Eylem geceyi bitirdiyse kalıcılaşan görünümler, kimlik sırasıyla.
var permanent_occurrence_ids: Array[StringName] = []
## Eylem süresinde biten geçici ekipman süreleri; bağımsız kopyalar.
var equipment_disable_expirations: Array[EquipmentDisableExpirationScript] = []
