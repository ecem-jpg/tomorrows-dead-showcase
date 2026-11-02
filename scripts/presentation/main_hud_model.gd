class_name MainHudModel
extends RefCounted
## Ana arayüzün göstereceği salt veri anlık görüntüsü. MainHudPresenter.build_model her çağrıda yeni ve bağımsız bir
## model kurar; modeli değiştirmek oyun durumunu veya başka bir modeli etkilemez.
##
## - Yalnızca gösterilebilir bilgiler: önerinin gizli doğruluk sınıfı, biçim kimliği, koşul konumları, görünümlerin
##   iç durum adları ve güven değerleri bulunmaz.
## - Hikâye metni veya karakter adı taşımaz; satırlar veri kimlikleriyle kurulur.
## - Bütün koleksiyonlar isimli alanlı satır nesneleridir.

const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")


class ResourceRow extends RefCounted:
	var resource_id: StringName = &""
	var value: int = 0

	func copy() -> ResourceRow:
		var row: ResourceRow = ResourceRow.new()
		row.resource_id = resource_id
		row.value = value
		return row

	func to_dict() -> Dictionary:
		return {"resource_id": resource_id, "value": value}


## Etkin (sürmekte olan) görev.
class TaskRow extends RefCounted:
	var task_id: StringName = &""
	var assigned_actor_id: StringName = &""
	var remaining_units: int = 0

	func copy() -> TaskRow:
		var row: TaskRow = TaskRow.new()
		row.task_id = task_id
		row.assigned_actor_id = assigned_actor_id
		row.remaining_units = remaining_units
		return row

	func to_dict() -> Dictionary:
		return {"task_id": task_id, "assigned_actor_id": assigned_actor_id, "remaining_units": remaining_units}


## Sunulan görev ataması. available, denemenin şu an yapılabilir olup olmadığıdır; kabul edilip edilmeyeceğini
## (gizli kabul koşullarını) göstermez.
class AssignableRow extends RefCounted:
	var task_id: StringName = &""
	var active_actor_id: StringName = &""
	var assigned_actor_id: StringName = &""
	var available: bool = false

	func copy() -> AssignableRow:
		var row: AssignableRow = AssignableRow.new()
		row.task_id = task_id
		row.active_actor_id = active_actor_id
		row.assigned_actor_id = assigned_actor_id
		row.available = available
		return row

	func to_dict() -> Dictionary:
		return {"task_id": task_id, "active_actor_id": active_actor_id, "assigned_actor_id": assigned_actor_id,
				"available": available}


class EquipmentRow extends RefCounted:
	var equipment_id: StringName = &""
	## Görünür durum: operational / broken / disabled.
	var status: StringName = &""
	var disabled_units: int = 0
	var usable: bool = false

	func copy() -> EquipmentRow:
		var row: EquipmentRow = EquipmentRow.new()
		row.equipment_id = equipment_id
		row.status = status
		row.disabled_units = disabled_units
		row.usable = usable
		return row

	func to_dict() -> Dictionary:
		return {"equipment_id": equipment_id, "status": status, "disabled_units": disabled_units, "usable": usable}


## Sunulan tamir bulmacası. available yalnızca etkin gecede denenebilirliktir; sonucu sistem belirler.
class RepairRow extends RefCounted:
	var puzzle_id: StringName = &""
	var available: bool = false

	func copy() -> RepairRow:
		var row: RepairRow = RepairRow.new()
		row.puzzle_id = puzzle_id
		row.available = available
		return row

	func to_dict() -> Dictionary:
		return {"puzzle_id": puzzle_id, "available": available}


## Morgda görünen ceset (BodyView alanları): present / permanent.
class BodyRow extends RefCounted:
	var occurrence_id: StringName = &""
	var subject_id: StringName = &""
	var night: int = 0
	var presence: StringName = &""

	func copy() -> BodyRow:
		var row: BodyRow = BodyRow.new()
		row.occurrence_id = occurrence_id
		row.subject_id = subject_id
		row.night = night
		row.presence = presence
		return row

	func to_dict() -> Dictionary:
		return {"occurrence_id": occurrence_id, "subject_id": subject_id, "night": night, "presence": presence}


class ChoiceRow extends RefCounted:
	var choice_id: StringName = &""
	var available: bool = false

	func copy() -> ChoiceRow:
		var row: ChoiceRow = ChoiceRow.new()
		row.choice_id = choice_id
		row.available = available
		return row

	func to_dict() -> Dictionary:
		return {"choice_id": choice_id, "available": available}


var has_session: bool = false
var night: int = 0
var night_count: int = 0
var elapsed_units: int = 0
## Bilinmiyorsa (ilk geceden önce) 0.
var night_length_units: int = 0
var night_ended: bool = false
var resources: Array[ResourceRow] = []
var tasks: Array[TaskRow] = []
var assignable: Array[AssignableRow] = []
var equipment: Array[EquipmentRow] = []
var repairs: Array[RepairRow] = []
var bodies: Array[BodyRow] = []
## Sunulan karar yoksa boş.
var decision_id: StringName = &""
var choices: Array[ChoiceRow] = []
## Önerinin yalnızca gösterilebilir alanları.
var advice_offered: bool = false
var advisor_actor_id: StringName = &""
var recommended_choice_id: StringName = &""
var can_wait: bool = false
var can_start_night: bool = false
## Son çözüldüyse kimliği, yoksa boş.
var ending_id: StringName = &""
var feedback_key: StringName = &""


## Oturumsuz model: hiçbir sistem çağrılmadan kurulur; bütün eylemler kapalı.
static func empty(p_feedback_key: StringName = &"") -> MainHudModelScript:
	var model: MainHudModelScript = MainHudModelScript.new()
	model.feedback_key = p_feedback_key
	return model


## Bütün satırları kopyalanmış bağımsız model.
func copy() -> MainHudModelScript:
	var model: MainHudModelScript = MainHudModelScript.new()
	model.has_session = has_session
	model.night = night
	model.night_count = night_count
	model.elapsed_units = elapsed_units
	model.night_length_units = night_length_units
	model.night_ended = night_ended
	for row in resources:
		model.resources.append(row.copy())
	for row in tasks:
		model.tasks.append(row.copy())
	for row in assignable:
		model.assignable.append(row.copy())
	for row in equipment:
		model.equipment.append(row.copy())
	for row in repairs:
		model.repairs.append(row.copy())
	for row in bodies:
		model.bodies.append(row.copy())
	model.decision_id = decision_id
	for row in choices:
		model.choices.append(row.copy())
	model.advice_offered = advice_offered
	model.advisor_actor_id = advisor_actor_id
	model.recommended_choice_id = recommended_choice_id
	model.can_wait = can_wait
	model.can_start_night = can_start_night
	model.ending_id = ending_id
	model.feedback_key = feedback_key
	return model


## İçeriğin isimli alanlı bağımsız gösterimi (karşılaştırma ve denetim için).
func to_dict() -> Dictionary:
	return {
		"has_session": has_session,
		"night": night,
		"night_count": night_count,
		"elapsed_units": elapsed_units,
		"night_length_units": night_length_units,
		"night_ended": night_ended,
		"resources": resources.map(func(row: ResourceRow) -> Dictionary: return row.to_dict()),
		"tasks": tasks.map(func(row: TaskRow) -> Dictionary: return row.to_dict()),
		"assignable": assignable.map(func(row: AssignableRow) -> Dictionary: return row.to_dict()),
		"equipment": equipment.map(func(row: EquipmentRow) -> Dictionary: return row.to_dict()),
		"repairs": repairs.map(func(row: RepairRow) -> Dictionary: return row.to_dict()),
		"bodies": bodies.map(func(row: BodyRow) -> Dictionary: return row.to_dict()),
		"decision_id": decision_id,
		"choices": choices.map(func(row: ChoiceRow) -> Dictionary: return row.to_dict()),
		"advice_offered": advice_offered,
		"advisor_actor_id": advisor_actor_id,
		"recommended_choice_id": recommended_choice_id,
		"can_wait": can_wait,
		"can_start_night": can_start_night,
		"ending_id": ending_id,
		"feedback_key": feedback_key,
	}


func equals(other: MainHudModelScript) -> bool:
	return other != null and to_dict() == other.to_dict()
