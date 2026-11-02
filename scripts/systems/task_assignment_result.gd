class_name TaskAssignmentResult
extends RefCounted
## TaskSystem.preview_assignment ve assign_task sonucu (K-026). Her çağrıda yeni oluşturulur; değiştirilmesi
## oyun durumunu veya sonraki çağrıları etkilemez. Kimlikler her zaman istenen değerlerin aynısıdır.
##
## Üç sınıf vardır: kabul (status = accepted), ret (status = rejected) ve başarısızlık (status boş, failure dolu).
## Ret ve uygun olmama normal oyun sonucudur; kurulum/akış hatalarında ayrıca push_error basılır.

const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TaskCompletionOutcomeScript := preload("res://scripts/systems/task_completion_outcome.gd")
const EquipmentDisableExpirationScript := preload("res://scripts/systems/equipment_disable_expiration.gd")

const STATUS_ACCEPTED: StringName = &"accepted"
const STATUS_REJECTED: StringName = &"rejected"

## Kurulum/akış hataları (push_error ile birlikte):
const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_UNKNOWN_TASK: StringName = &"unknown_task"
const FAILURE_UNKNOWN_ASSIGNMENT: StringName = &"unknown_assignment"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"
const FAILURE_WRITE_FAILED: StringName = &"write_failed"
## Normal oyun sonuçları; hiçbir şey yazılmaz ve hata basılmaz:
const FAILURE_TIME_UNAVAILABLE: StringName = &"time_unavailable"
const FAILURE_ACTOR_BUSY: StringName = &"actor_busy"
const FAILURE_TASK_ALREADY_ACTIVE: StringName = &"task_already_active"

## accepted, rejected veya boş (başarısızlık).
var status: StringName = &""
## status doluysa boş.
var failure: StringName = &""
var task_id: StringName = &""
var active_actor_id: StringName = &""
var assigned_actor_id: StringName = &""
## Yalnızca rejected: sağlanmayan kabul koşullarının veri sırasındaki konumları. İç sistem verisidir;
## oyuncuya veya arayüze otomatik gösterilmez.
var failed_condition_indexes: PackedInt32Array = []
## Yalnızca accepted: başlatılan görevin bağımsız kopyası.
var started_task: TimedTaskStateScript = null
## Deneme bir eylem maliyeti taşıyorsa (kabul veya ret) zaman sonucu; aksi hâlde null.
var time_result: TimeAdvanceResultScript = null
## Deneme süresinde tamamlanan diğer görevler, kronolojik sırayla (K-027). İç sistem verisidir.
var task_completions: Array[TaskCompletionOutcomeScript] = []
## Deneme süresinde biten geçici ekipman süreleri (K-031), bağımsız kopyalar. Eylem yoksa veya başarısızsa boş.
var equipment_disable_expirations: Array[EquipmentDisableExpirationScript] = []


func is_accepted() -> bool:
	return status == STATUS_ACCEPTED


func is_rejected() -> bool:
	return status == STATUS_REJECTED


func is_failed() -> bool:
	return status.is_empty()
