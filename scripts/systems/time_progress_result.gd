class_name TimeProgressResult
extends RefCounted
## TaskCompletionSystem.preview_advance ve advance sonucu (K-027). Her çağrıda yeni oluşturulur;
## değiştirilmesi oyun durumunu etkilemez. Başarısız sonuçta time_result null ve completions boştur.
## Bütün başarısızlıklar kurulum/akış hatasıdır ve push_error ile birlikte gelir; yetersiz harcama gibi
## normal sonuçlar completions içindeki görev kayıtlarında görünür.

const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")
const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"
const FAILURE_NEGATIVE_AMOUNT: StringName = &"negative_amount"
const FAILURE_NIGHT_NOT_ACTIVE: StringName = &"night_not_active"
const FAILURE_WRITE_FAILED: StringName = &"write_failed"

var ok: bool = false
## ok = true ise boş.
var failure: StringName = &""
## Zaman oluşumları, uygulanan ve taşan birimler.
var time_result: TimeAdvanceResultScript = null
## Kronolojik sırayla tamamlanan görevler.
var completions: Array[TaskCompletionOutcomeScript] = []
## İlerleme geceyi bitirdiyse, gece sonunda death_permanent yapılan görünümler (kimlik sırasıyla; K-029).
var permanent_occurrence_ids: Array[StringName] = []
## Bu ilerlemede biten geçici ekipman süreleri, (night, at_units, equipment_id) sırasıyla; bağımsız kopyalar.
## Süre bitmesi kullanılabilir olmak demek değildir (K-031).
var equipment_disable_expirations: Array[EquipmentDisableExpirationScript] = []


func completed_task_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for completion in completions:
		ids.append(completion.task_id)
	return ids
