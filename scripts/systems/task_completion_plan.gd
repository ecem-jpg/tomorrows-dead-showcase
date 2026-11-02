class_name TaskCompletionPlan
extends RefCounted
## TaskCompletionSystem.plan_time sonucu (K-027): zaman planı ve tamamlanan görevlerin sonuçları.
## Hiçbir şey yazılmamıştır. Tamamlanma etkileri verilen pakete eklenmiştir; zaman alanlarını pakete
## yazmak çağıranın işidir (ör. görev atama, yeni görevi plana ekledikten sonra yazar).
## plan_time hata basmaz; geçersiz istekte failure ve error_message doldurulur.

const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")
const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"
const FAILURE_NEGATIVE_AMOUNT: StringName = TimeAdvancePlanScript.FAILURE_NEGATIVE_AMOUNT
const FAILURE_NIGHT_NOT_ACTIVE: StringName = TimeAdvancePlanScript.FAILURE_NIGHT_NOT_ACTIVE

## Boşsa plan geçerlidir.
var failure: StringName = &""
var error_message: String = ""
## Geçerli planda TimeSystem.plan_advance sonucu; geçersizse null olabilir.
var time_plan: TimeAdvancePlanScript = null
## Kronolojik sırayla tamamlanan görevler.
var completions: Array[TaskCompletionOutcomeScript] = []
## Plan geceyi bitiriyorsa, gece sonunda death_permanent yapılan görünümler (kimlik sırasıyla; K-029).
var permanent_occurrence_ids: Array[StringName] = []
## Bu ilerlemede biten geçici ekipman süreleri, (night, at_units, equipment_id) sırasıyla (K-031).
var equipment_disable_expirations: Array[EquipmentDisableExpirationScript] = []


func is_valid() -> bool:
	return failure.is_empty()
