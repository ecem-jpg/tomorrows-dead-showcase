class_name MainHudConfig
extends RefCounted
## Ana arayüz presenter'ının yapılandırması: hangi görev atamalarının, hangi kararın ve önerinin, hangi tamir
## bulmacalarının sunulacağı ve bekleme eyleminin kimliği.
##
## - Sistemler bu bilgileri dışarı vermediği için açıkça verilir (görevin aktör çifti, sunulan karar, bulmaca
##   listesi). İleride üretim oturumu sağlar; bugün yalnızca testler kurar.
## - Hikâye metni veya karakter adı taşımaz; yalnızca veri kimlikleri.
## - Kurulumdan sonra değişmez: girdiler kopyalanır, okuyucular kopya döndürür.
## - get_errors yalnızca kendi tutarlılığını deterministik sırayla denetler; kimliklerin sistemlerde tanımlı olması
##   presenter'ın işidir.


## Sunulan bir görev ataması: görev, görevi veren aktör, görevi alan aktör.
class Assignment extends RefCounted:
	var task_id: StringName = &""
	var active_actor_id: StringName = &""
	var assigned_actor_id: StringName = &""

	func _init(p_task_id: StringName = &"", p_active_actor_id: StringName = &"",
			p_assigned_actor_id: StringName = &"") -> void:
		task_id = p_task_id
		active_actor_id = p_active_actor_id
		assigned_actor_id = p_assigned_actor_id

	func copy() -> Assignment:
		return Assignment.new(task_id, active_actor_id, assigned_actor_id)


var _assignments: Array[Assignment] = []
var _decision_id: StringName = &""
var _advice_id: StringName = &""
var _repair_puzzle_ids: Array[StringName] = []
var _wait_action_id: StringName = &""


## assignments: Assignment kayıtları (null veya başka türde kayıt hata raporu için yerinde tutulur); repair_puzzle_ids: bulmaca
## kimlikleri. Bütün girdiler kopyalanır.
func _init(assignments: Array = [], decision_id: StringName = &"", advice_id: StringName = &"",
		repair_puzzle_ids: Array = [], wait_action_id: StringName = &"") -> void:
	for entry: Variant in assignments:
		# Assignment olmayan kayıt tanımsız kayıt olarak raporlanır.
		_assignments.append((entry as Assignment).copy() if entry is Assignment else null)
	_decision_id = decision_id
	_advice_id = advice_id
	for puzzle_id: Variant in repair_puzzle_ids:
		# Metin olmayan kayıt boş kimlik olarak raporlanır.
		_repair_puzzle_ids.append(StringName(puzzle_id) if puzzle_id is String or puzzle_id is StringName else &"")
	_wait_action_id = wait_action_id


## Kısa yol: isimli bir atama kaydı.
static func assignment(task_id: StringName, active_actor_id: StringName, assigned_actor_id: StringName) -> Assignment:
	return Assignment.new(task_id, active_actor_id, assigned_actor_id)


## Tutarsızlıklar, sırayla: atamalar (kayıt sırasıyla), karar/öneri ilişkisi, tamir bulmacaları, bekleme eylemi.
## Hiçbir değeri düzeltmez ve motor hatası üretmez.
func get_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	var seen_tasks: Array[StringName] = []
	for i in _assignments.size():
		var entry: Assignment = _assignments[i]
		var p: String = "Atama #%d: " % i
		if entry == null:
			errors.append(p + "tanımsız kayıt")
			continue
		if entry.task_id.is_empty():
			errors.append(p + "boş görev kimliği")
		elif seen_tasks.has(entry.task_id):
			errors.append(p + "tekrarlanan görev kimliği '%s'" % entry.task_id)
		else:
			seen_tasks.append(entry.task_id)
		if entry.active_actor_id.is_empty():
			errors.append(p + "boş görevi veren aktör")
		if entry.assigned_actor_id.is_empty():
			errors.append(p + "boş görevi alan aktör")
		if not entry.active_actor_id.is_empty() and entry.active_actor_id == entry.assigned_actor_id:
			errors.append(p + "aktör kendisine görev veremez '%s'" % entry.active_actor_id)

	if not _decision_id.is_empty() and _advice_id.is_empty():
		errors.append("Karar '%s' için öneri kimliği yok" % _decision_id)
	if _decision_id.is_empty() and not _advice_id.is_empty():
		errors.append("Öneri '%s' için karar kimliği yok" % _advice_id)

	var seen_puzzles: Array[StringName] = []
	for i in _repair_puzzle_ids.size():
		var puzzle_id: StringName = _repair_puzzle_ids[i]
		if puzzle_id.is_empty():
			errors.append("Tamir #%d: boş bulmaca kimliği" % i)
		elif seen_puzzles.has(puzzle_id):
			errors.append("Tamir #%d: tekrarlanan bulmaca kimliği '%s'" % [i, puzzle_id])
		else:
			seen_puzzles.append(puzzle_id)

	if _wait_action_id.is_empty():
		errors.append("Boş bekleme eylemi kimliği")
	return errors


## Atamaların bağımsız kopyaları, veriliş sırasıyla (null kayıtlar atlanır).
func get_assignments() -> Array[Assignment]:
	var result: Array[Assignment] = []
	for entry in _assignments:
		if entry != null:
			result.append(entry.copy())
	return result


## Görevin atama kaydının kopyası; yoksa null.
func get_assignment(task_id: StringName) -> Assignment:
	for entry in _assignments:
		if entry != null and entry.task_id == task_id:
			return entry.copy()
	return null


func get_decision_id() -> StringName:
	return _decision_id


func get_advice_id() -> StringName:
	return _advice_id


func get_repair_puzzle_ids() -> Array[StringName]:
	return _repair_puzzle_ids.duplicate()


func has_repair_puzzle(puzzle_id: StringName) -> bool:
	return not puzzle_id.is_empty() and _repair_puzzle_ids.has(puzzle_id)


func get_wait_action_id() -> StringName:
	return _wait_action_id
