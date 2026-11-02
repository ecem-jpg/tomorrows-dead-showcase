class_name TimeAdvanceResult
extends RefCounted
## Bir TimeSystem.advance çağrısının sonucu. Her çağrıda yeni oluşturulur ve sistem buna
## referans tutmaz; değiştirilmesi oyun durumunu etkilemez. Geçersiz işlemde ok = false,
## süreler 0 ve oluşum listesi boştur.

const TimeOccurrenceScript := preload("res://scripts/systems/time_occurrence.gd")

var ok: bool = false
## Gerçekten uygulanan süre.
var applied_units: int = 0
## Gece sonunu aşan, kullanılmamış miktar.
var overflow_units: int = 0
## Kronolojik sıralı birleşik oluşum listesi.
var occurrences: Array[TimeOccurrenceScript] = []


## Gece sonu bu çağrıda gerçekleştiyse true. occurrences listesinden türetilir.
func night_ended() -> bool:
	for occurrence in occurrences:
		if occurrence.kind == TimeOccurrenceScript.Kind.NIGHT_ENDED:
			return true
	return false


## Tetiklenen olay kimlikleri, kronolojik sırayla. occurrences listesinden türetilir.
func triggered_event_ids() -> Array[StringName]:
	return _ids_of(TimeOccurrenceScript.Kind.EVENT_TRIGGERED)


## Tamamlanan görev kimlikleri, kronolojik sırayla. occurrences listesinden türetilir.
func completed_task_ids() -> Array[StringName]:
	return _ids_of(TimeOccurrenceScript.Kind.TASK_COMPLETED)


func _ids_of(kind: TimeOccurrenceScript.Kind) -> Array[StringName]:
	var ids: Array[StringName] = []
	for occurrence in occurrences:
		if occurrence.kind == kind:
			ids.append(occurrence.id)
	return ids
