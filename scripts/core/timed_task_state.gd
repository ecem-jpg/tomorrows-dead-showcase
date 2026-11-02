class_name TimedTaskState
extends RefCounted
## Kabul edilmiş bir görevin çalışma zamanındaki durumu. Görevin kabulü/reddi ve
## sonucu bu sınıfın işi değildir; yalnızca kimlik, atanan aktör ve kalan süre tutulur.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")

var task_id: StringName = &""
var assigned_actor_id: StringName = &""
var remaining_units: int = 0


func _init(p_task_id: StringName = &"", p_assigned_actor_id: StringName = &"", p_remaining_units: int = 0) -> void:
	task_id = p_task_id
	assigned_actor_id = p_assigned_actor_id
	remaining_units = p_remaining_units


## Bağımsız kopya.
func copy() -> TimedTaskStateScript:
	return TimedTaskStateScript.new(task_id, assigned_actor_id, remaining_units)


func equals(other: TimedTaskStateScript) -> bool:
	return other != null \
			and task_id == other.task_id \
			and assigned_actor_id == other.assigned_actor_id \
			and remaining_units == other.remaining_units
