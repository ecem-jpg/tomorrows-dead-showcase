class_name TimeOccurrence
extends RefCounted
## Bir TimeSystem.advance çağrısında gerçekleşen tek bir zaman oluşumu.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const TimeOccurrenceScript := preload("res://scripts/systems/time_occurrence.gd")

enum Kind { TASK_COMPLETED, EVENT_TRIGGERED, NIGHT_ENDED }

## Aynı anda gerçekleşen oluşumların açık önceliği; enum'un sayısal değerine bağlı değildir.
const KIND_PRIORITY: Dictionary[int, int] = {
	Kind.TASK_COMPLETED: 0,
	Kind.EVENT_TRIGGERED: 1,
	Kind.NIGHT_ENDED: 2,
}

var night: int = 0
## Gece içindeki gerçekleşme anı.
var at_units: int = 0
var kind: Kind = Kind.TASK_COMPLETED
## Görev veya olay kimliği; gece sonunda boş.
var id: StringName = &""
## Olaylarda ScheduledEventData.order; diğerlerinde 0.
var order: int = 0
## Yalnızca görev tamamlanmasında dolu.
var assigned_actor_id: StringName = &""


func _init(p_night: int = 0, p_at_units: int = 0, p_kind: Kind = Kind.TASK_COMPLETED, p_id: StringName = &"",
		p_order: int = 0, p_assigned_actor_id: StringName = &"") -> void:
	night = p_night
	at_units = p_at_units
	kind = p_kind
	id = p_id
	order = p_order
	assigned_actor_id = p_assigned_actor_id


## Kronolojik sıra: an, tür önceliği, order, id.
static func comes_before(a: TimeOccurrenceScript, b: TimeOccurrenceScript) -> bool:
	if a.at_units != b.at_units:
		return a.at_units < b.at_units
	var a_priority: int = KIND_PRIORITY[a.kind]
	var b_priority: int = KIND_PRIORITY[b.kind]
	if a_priority != b_priority:
		return a_priority < b_priority
	if a.order != b.order:
		return a.order < b.order
	return String(a.id) < String(b.id)
