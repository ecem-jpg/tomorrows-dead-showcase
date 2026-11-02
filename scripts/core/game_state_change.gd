class_name GameStateChange
extends RefCounted
## Birden fazla durum kategorisini tek seferde yazmak için mutlak yeni değerler paketi (K-025).
## GameState.apply_changes ile uygulanır: ya hepsi yazılır ya hiçbiri. Değişim miktarı değil,
## yeni değerler taşır; sınırların hesabı ilgili sistemlerin işidir.

const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const CablePuzzleProgressStateScript := preload("res://scripts/core/cable_puzzle_progress_state.gd")

## Yalnızca tanımlı kaynaklar.
var resource_values: Dictionary[StringName, int] = {}
## Tanımsız bayrak oluşturulabilir; boş kimlik geçersizdir.
var flag_values: Dictionary[StringName, bool] = {}
## Yalnızca durumda mevcut yönlü ilişkiler; kısmi olabilir.
var trust_values: Array[TrustRelationshipStateScript] = []
## Görünüm kimliği → yeni iç durum (K-029). Yalnızca tanımlı görünümler ve izinli geçişler.
var occurrence_statuses: Dictionary[StringName, StringName] = {}
## Ekipmanların mutlak yeni değerleri (K-031); yalnızca tanımlı ekipmanlar, aynı ekipman bir kez; kısmi olabilir.
var equipment_values: Array[EquipmentStateScript] = []
## Kablo bulmacası ilerlemelerinin mutlak yeni değerleri (K-032); yalnızca tanımlı bulmacalar, aynı bulmaca bir kez,
## izinli geçişler; kısmi olabilir.
var cable_puzzle_progress: Array[CablePuzzleProgressStateScript] = []
## Zaman alanları yalnızca has_time_state true ise uygulanır.
var has_time_state: bool = false
var night: int = 0
var elapsed_units: int = 0
var night_ended: bool = false
var tasks: Array[TimedTaskStateScript] = []


func set_time_state(p_night: int, p_elapsed_units: int, p_night_ended: bool, p_tasks: Array[TimedTaskStateScript]) -> void:
	has_time_state = true
	night = p_night
	elapsed_units = p_elapsed_units
	night_ended = p_night_ended
	tasks = p_tasks


func is_empty() -> bool:
	return resource_values.is_empty() and flag_values.is_empty() and trust_values.is_empty() \
			and occurrence_statuses.is_empty() and equipment_values.is_empty() and cable_puzzle_progress.is_empty() \
			and not has_time_state
