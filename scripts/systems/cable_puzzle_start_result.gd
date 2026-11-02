class_name CablePuzzleStartResult
extends RefCounted
## CableRepairSystem.start_session sonucu (K-032). Her çağrıda yeni oluşturulur. Oturum yalnızca started
## durumunda doludur. Hangi sonuç dalının uygulanamadığı bilerek raporlanmaz.

const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

const STATUS_STARTED: StringName = &"started"

## Normal oyun sonuçları (hata basılmaz):
const FAILURE_CONDITIONS_NOT_MET: StringName = &"conditions_not_met"
const FAILURE_ALREADY_SOLVED: StringName = &"already_solved"
const FAILURE_RESOLUTION_LIMIT_REACHED: StringName = &"resolution_limit_reached"
## Başarı veya başarısızlık dalı mevcut durumda uygulanamıyor (etki veya zaman); ücretsiz yeniden denemeyi önler.
const FAILURE_OUTCOME_UNAVAILABLE: StringName = &"outcome_unavailable"
## Kurulum/akış hataları (push_error ile birlikte):
const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"
const FAILURE_UNKNOWN_PUZZLE: StringName = &"unknown_puzzle"

## started veya boş.
var status: StringName = &""
## started ise boş.
var failure: StringName = &""
var puzzle_id: StringName = &""
## conditions_not_met: sağlanmayan başlangıç koşullarının veri sırasındaki konumları.
var failed_condition_indexes: PackedInt32Array = []
## Yalnızca started.
var session: CablePuzzleSessionScript = null


func is_started() -> bool:
	return status == STATUS_STARTED
