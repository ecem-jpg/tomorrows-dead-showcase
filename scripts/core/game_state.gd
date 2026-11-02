class_name GameState
extends RefCounted
## Oyun durumunun tek gerçek kaynağı. Sahne ağacından bağımsızdır; değerler yalnızca
## kontrollü yöntemlerle değişir. Kaynak sınırları burada değil, ResourceSystem'de uygulanır.

## Bir değer gerçekten değiştiğinde bir kez yayılır.
signal state_changed

# Sınıf önbelleğine bağımlı kalmamak için tip, yol ile yüklenir.
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const InitialEquipmentDataScript := preload("res://scripts/data/initial_equipment_data.gd")
const CablePuzzleProgressStateScript := preload("res://scripts/core/cable_puzzle_progress_state.gd")


## Başlangıç verisinin tek değerlendirmesi: kabul edilecek kayıtlar ve yok sayılacak kayıtların hata metinleri, kural
## sırasıyla. _init ve get_setup_errors aynı planı kullanır; böylece kurallar tek yerde durur.
class SetupPlan extends RefCounted:
	var errors: PackedStringArray = []
	var occurrence_ids: Array[StringName] = []
	var equipment: Array[EquipmentStateScript] = []
	var cable_puzzle_ids: Array[StringName] = []


var _resources: Dictionary[StringName, int] = {}
var _flags: Dictionary[StringName, bool] = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Zaman durumu. Gece 0, henüz gece başlamadı demektir. Gece/süre sınırları TimeSystem'de denetlenir.
var _night: int = 0
var _elapsed_units: int = 0
var _night_ended: bool = false
var _tasks: Array[TimedTaskStateScript] = []
# Yönlü güven ilişkileri; (kaynak, hedef) sırasına göre sıralı. Boş liste, güven henüz başlatılmadı demektir.
var _trust: Array[TrustRelationshipStateScript] = []
# Gelecek ceset görünümlerinin iç durumları (K-029). Kayıt kümesi başlangıçta sabitlenir; durumlar yalnızca
# apply_changes ile ve yalnızca izinli geçişlerle değişir. Doğrudan yazma yöntemi bilerek yoktur.
var _occurrences: Dictionary[StringName, StringName] = {}
# Ekipman durumları (K-031), kimlik sırasıyla. Kayıt kümesi başlangıçta sabitlenir; değerler yalnızca apply_changes
# ile değişir. Doğrudan yazma yöntemi bilerek yoktur.
var _equipment: Array[EquipmentStateScript] = []
# Kablo bulmacası ilerlemeleri (K-032), kimlik sırasıyla. Kayıt kümesi başlangıçta sabitlenir; değerler yalnızca
# apply_changes ile ve yalnızca izinli geçişlerle değişir. Doğrudan yazma yöntemi bilerek yoktur.
var _cable_puzzles: Array[CablePuzzleProgressStateScript] = []


func _init(setup: InitialStateDataScript) -> void:
	# Davranış get_setup_errors ile aynı plandan gelir: geçersiz kayıtlar aynı metinle ve aynı sırayla hata basılarak
	# tek tek yok sayılır; geçerliler korunur, kaynak veri değiştirilmez.
	var plan: SetupPlan = _plan_setup(setup)
	for message in plan.errors:
		push_error(message)
	if setup == null:
		return
	for resource_id in setup.starting_resources:
		_resources[resource_id] = setup.starting_resources[resource_id]
	for flag_id in setup.starting_flags:
		_flags[StringName(flag_id)] = true
	_rng.seed = setup.rng_seed
	for occurrence_id in plan.occurrence_ids:
		_occurrences[occurrence_id] = OccurrenceStatusScript.STATUS_INACTIVE
	_equipment = plan.equipment
	_equipment.sort_custom(_equipment_sorts_before)
	for puzzle_id in plan.cable_puzzle_ids:
		_cable_puzzles.append(CablePuzzleProgressStateScript.new(puzzle_id))
	_cable_puzzles.sort_custom(_cable_puzzle_sorts_before)


## Başlangıç verisinde GameState'in yok sayacağı her kaydın hata metni, kural sırasıyla: setup yoksa tek hata; görünüm
## kimlikleri (boş veya tekrarlanan); ekipman kayıtları (kayıt başına ilk sağlanmayan kural: boş kayıt, boş kimlik,
## tekrarlanan kimlik, geçersiz durum, negatif süre); kablo bulmacası kimlikleri (boş veya tekrarlanan). Tekrar, daha
## önce kabul edilmiş kayda göre değerlendirilir. Salt okunurdur: örnek oluşturmaz, hata basmaz, setup'ı değiştirmez.
## Geçerli setup için boş liste.
static func get_setup_errors(setup: InitialStateDataScript) -> PackedStringArray:
	return _plan_setup(setup).errors.duplicate()


static func _plan_setup(setup: InitialStateDataScript) -> SetupPlan:
	var plan: SetupPlan = SetupPlan.new()
	if setup == null:
		plan.errors.append("GameState: başlangıç verisi verilmedi.")
		return plan
	for occurrence_text in setup.occurrence_ids:
		var occurrence_id: StringName = StringName(occurrence_text)
		if occurrence_id.is_empty() or plan.occurrence_ids.has(occurrence_id):
			plan.errors.append("GameState: boş veya tekrarlanan görünüm kimliği yok sayıldı: '%s'" % occurrence_text)
			continue
		plan.occurrence_ids.append(occurrence_id)
	var equipment_ids: Array[StringName] = []
	for i in setup.starting_equipment.size():
		var entry: InitialEquipmentDataScript = setup.starting_equipment[i]
		if entry == null:
			plan.errors.append("GameState: boş başlangıç ekipmanı kaydı yok sayıldı (#%d)." % i)
			continue
		var equipment_id: StringName = StringName(entry.id)
		var condition: StringName = entry.condition
		var disabled_units: int = entry.disabled_units
		if equipment_id.is_empty():
			plan.errors.append("GameState: boş ekipman kimliği yok sayıldı (#%d)." % i)
		elif equipment_ids.has(equipment_id):
			plan.errors.append("GameState: tekrarlanan ekipman kimliği yok sayıldı: '%s'" % equipment_id)
		elif not EquipmentStateScript.is_valid_condition(condition):
			plan.errors.append("GameState: geçersiz ekipman durumu yok sayıldı: '%s' (%s)" % [equipment_id, condition])
		elif disabled_units < 0:
			plan.errors.append("GameState: negatif ekipman süresi yok sayıldı: '%s' (%d)" % [equipment_id, disabled_units])
		else:
			equipment_ids.append(equipment_id)
			plan.equipment.append(EquipmentStateScript.new(equipment_id, condition, disabled_units))
	for puzzle_text in setup.cable_puzzle_ids:
		var puzzle_id: StringName = StringName(puzzle_text)
		if puzzle_id.is_empty() or plan.cable_puzzle_ids.has(puzzle_id):
			plan.errors.append("GameState: boş veya tekrarlanan kablo bulmacası kimliği yok sayıldı: '%s'" % puzzle_text)
			continue
		plan.cable_puzzle_ids.append(puzzle_id)
	return plan


func has_resource(resource_id: StringName) -> bool:
	return _resources.has(resource_id)


## Tanımsız kaynakta hata verir ve 0 döner.
func get_resource(resource_id: StringName) -> int:
	if not _resources.has(resource_id):
		push_error("GameState: tanımsız kaynak okunamaz: '%s'" % resource_id)
		return 0
	return _resources[resource_id]


## Tanımsız kaynakta hata verir, durumu değiştirmez ve false döner.
func set_resource(resource_id: StringName, value: int) -> bool:
	if not _resources.has(resource_id):
		push_error("GameState: tanımsız kaynağa yazılamaz: '%s'" % resource_id)
		return false
	if _resources[resource_id] != value:
		_resources[resource_id] = value
		state_changed.emit()
	return true


## Tanımsız bayrak false sayılır.
func get_flag(flag_id: StringName) -> bool:
	return _flags.get(flag_id, false)


func set_flag(flag_id: StringName, value: bool) -> bool:
	if get_flag(flag_id) != value:
		_flags[flag_id] = value
		state_changed.emit()
	return true


## [from, to] aralığında (ikisi dahil) tohumlu rastgele tam sayı.
func random_int(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## İç durumun kopyası; üzerinde yapılan değişiklikler durumu etkilemez.
func get_resources_snapshot() -> Dictionary[StringName, int]:
	return _resources.duplicate()


## İç durumun kopyası; üzerinde yapılan değişiklikler durumu etkilemez.
func get_flags_snapshot() -> Dictionary[StringName, bool]:
	return _flags.duplicate()


func get_night() -> int:
	return _night


func get_elapsed_units() -> int:
	return _elapsed_units


func is_night_ended() -> bool:
	return _night_ended


## Görevlerin task_id'ye göre sıralı, bağımsız kopyaları.
func get_tasks_snapshot() -> Array[TimedTaskStateScript]:
	var result: Array[TimedTaskStateScript] = []
	for task in _tasks:
		result.append(task.copy())
	return result


## Zaman durumunu tek seferde yazar. Geçersiz değerde hata verir, durumu değiştirmez ve false döner.
## Bir değer gerçekten değiştiyse state_changed bir kez yayılır.
func set_time_state(night: int, elapsed_units: int, night_ended: bool, tasks: Array[TimedTaskStateScript]) -> bool:
	var copies: Array[TimedTaskStateScript] = []
	if not _copy_valid_time_state(night, elapsed_units, tasks, copies):
		return false

	var changed: bool = night != _night or elapsed_units != _elapsed_units \
			or night_ended != _night_ended or not _tasks_equal(copies)
	if changed:
		_night = night
		_elapsed_units = elapsed_units
		_night_ended = night_ended
		_tasks = copies
		state_changed.emit()
	return true


func has_trust(source_actor_id: StringName, target_actor_id: StringName) -> bool:
	return _find_trust_index(source_actor_id, target_actor_id) >= 0


## Tanımsız ilişkide hata verir ve 0 döner.
func get_trust(source_actor_id: StringName, target_actor_id: StringName) -> int:
	var index: int = _find_trust_index(source_actor_id, target_actor_id)
	if index < 0:
		push_error("GameState: tanımsız güven ilişkisi okunamaz: '%s' -> '%s'" % [source_actor_id, target_actor_id])
		return 0
	return _trust[index].value


func has_occurrence(occurrence_id: StringName) -> bool:
	return _occurrences.has(occurrence_id)


## İç durum (OccurrenceStatus). Tanımsız görünümde hata verir ve boş döner.
func get_occurrence_status(occurrence_id: StringName) -> StringName:
	if not _occurrences.has(occurrence_id):
		push_error("GameState: tanımsız görünüm okunamaz: '%s'" % occurrence_id)
		return &""
	return _occurrences[occurrence_id]


## İç durumun kopyası; üzerinde yapılan değişiklikler durumu etkilemez.
func get_occurrences_snapshot() -> Dictionary[StringName, StringName]:
	return _occurrences.duplicate()


func has_equipment(equipment_id: StringName) -> bool:
	return _find_equipment_index(equipment_id) >= 0


## Bağımsız kopya. Tanımsız ekipmanda hata verir ve null döner.
func get_equipment(equipment_id: StringName) -> EquipmentStateScript:
	var index: int = _find_equipment_index(equipment_id)
	if index < 0:
		push_error("GameState: tanımsız ekipman okunamaz: '%s'" % equipment_id)
		return null
	return _equipment[index].copy()


## Ekipmanların kimlik sırasına göre sıralı, bağımsız kopyaları.
func get_equipment_snapshot() -> Array[EquipmentStateScript]:
	var result: Array[EquipmentStateScript] = []
	for entry in _equipment:
		result.append(entry.copy())
	return result


func has_cable_puzzle(puzzle_id: StringName) -> bool:
	return _find_cable_puzzle_index(puzzle_id) >= 0


## Bağımsız kopya. Tanımsız bulmacada hata verir ve null döner.
func get_cable_puzzle_progress(puzzle_id: StringName) -> CablePuzzleProgressStateScript:
	var index: int = _find_cable_puzzle_index(puzzle_id)
	if index < 0:
		push_error("GameState: tanımsız kablo bulmacası okunamaz: '%s'" % puzzle_id)
		return null
	return _cable_puzzles[index].copy()


## Kablo bulmacası ilerlemelerinin kimlik sırasına göre sıralı, bağımsız kopyaları.
func get_cable_puzzle_progress_snapshot() -> Array[CablePuzzleProgressStateScript]:
	var result: Array[CablePuzzleProgressStateScript] = []
	for entry in _cable_puzzles:
		result.append(entry.copy())
	return result


## Güven ilişkilerinin (kaynak, hedef) sırasına göre sıralı, bağımsız kopyaları.
func get_trust_snapshot() -> Array[TrustRelationshipStateScript]:
	var result: Array[TrustRelationshipStateScript] = []
	for entry in _trust:
		result.append(entry.copy())
	return result


## Güven ilişkilerini tek seferde yazar. Boş kimlik, kendine güven veya tekrarlanan ilişkide
## hata verir, durumu değiştirmez ve false döner. Sınırlar TrustSystem'de denetlenir.
## Bir değer gerçekten değiştiyse state_changed bir kez yayılır.
func set_trust_state(entries: Array[TrustRelationshipStateScript]) -> bool:
	var copies: Array[TrustRelationshipStateScript] = []
	for entry in entries:
		if not _is_valid_trust_entry(entry):
			return false
		for existing in copies:
			if existing.source_actor_id == entry.source_actor_id and existing.target_actor_id == entry.target_actor_id:
				push_error("GameState: tekrarlanan güven ilişkisi: '%s' -> '%s'"
						% [entry.source_actor_id, entry.target_actor_id])
				return false
		copies.append(entry.copy())
	copies.sort_custom(_trust_sorts_before)

	if not _trust_equal(copies):
		_trust = copies
		state_changed.emit()
	return true


## Birden fazla kategoriyi tek seferde yazar (K-025). Önce paketin bütün alanları doğrulanır ve bağımsız
## kopyalar hazırlanır; tek bir geçersiz alan varsa hiçbir iç alan değişmez, hata verilir ve false döner.
## Doğrulama bittikten sonra doğrudan atama yapılır; gerçek değişiklik varsa state_changed bir kez yayılır.
## Boş paket başarılı ve etkisizdir. Mevcut kategori yazma yöntemleri bundan bağımsız olarak geçerlidir.
func apply_changes(change: GameStateChangeScript) -> bool:
	if change == null:
		push_error("GameState: değişiklik paketi verilmedi.")
		return false

	var new_resources: Dictionary[StringName, int] = _resources.duplicate()
	for resource_id in change.resource_values:
		if not _resources.has(resource_id):
			push_error("GameState: pakette tanımsız kaynak: '%s'" % resource_id)
			return false
		new_resources[resource_id] = change.resource_values[resource_id]

	var new_flags: Dictionary[StringName, bool] = _flags.duplicate()
	for flag_id in change.flag_values:
		if flag_id.is_empty():
			push_error("GameState: pakette boş bayrak kimliği.")
			return false
		# Tanımsız bayrak false okunduğu için false yazmak değişiklik sayılmaz.
		if get_flag(flag_id) != change.flag_values[flag_id]:
			new_flags[flag_id] = change.flag_values[flag_id]

	var new_trust: Array[TrustRelationshipStateScript] = get_trust_snapshot()
	var updated_pairs: Array[TrustRelationshipStateScript] = []
	for entry in change.trust_values:
		if not _is_valid_trust_entry(entry):
			return false
		for updated in updated_pairs:
			if updated.source_actor_id == entry.source_actor_id and updated.target_actor_id == entry.target_actor_id:
				push_error("GameState: pakette tekrarlanan güven ilişkisi: '%s' -> '%s'"
						% [entry.source_actor_id, entry.target_actor_id])
				return false
		var index: int = _find_trust_index(entry.source_actor_id, entry.target_actor_id)
		if index < 0:
			push_error("GameState: pakette tanımsız güven ilişkisi: '%s' -> '%s'"
					% [entry.source_actor_id, entry.target_actor_id])
			return false
		new_trust[index] = entry.copy()
		updated_pairs.append(entry)

	# Görünüm geçişleri yazma düzeyinde yeniden doğrulanır; kesin sonuçlar değiştirilemez (K-029).
	var new_occurrences: Dictionary[StringName, StringName] = _occurrences.duplicate()
	for occurrence_id in change.occurrence_statuses:
		if not _occurrences.has(occurrence_id):
			push_error("GameState: pakette tanımsız görünüm: '%s'" % occurrence_id)
			return false
		var status: StringName = change.occurrence_statuses[occurrence_id]
		var current: StringName = _occurrences[occurrence_id]
		if status == current:
			continue
		if not OccurrenceStatusScript.is_valid(status) or not OccurrenceStatusScript.can_transition(current, status):
			push_error("GameState: geçersiz görünüm geçişi: '%s' (%s -> %s)" % [occurrence_id, current, status])
			return false
		new_occurrences[occurrence_id] = status

	# Ekipman: tanımlı kimlik, geçerli durum, negatif olmayan süre; pakette aynı ekipman iki kez olamaz (K-031).
	var new_equipment: Array[EquipmentStateScript] = get_equipment_snapshot()
	var updated_equipment: Array[StringName] = []
	for entry in change.equipment_values:
		if entry == null or entry.equipment_id.is_empty():
			push_error("GameState: pakette geçersiz ekipman kaydı (boş kayıt veya kimlik).")
			return false
		if updated_equipment.has(entry.equipment_id):
			push_error("GameState: pakette tekrarlanan ekipman: '%s'" % entry.equipment_id)
			return false
		var equipment_index: int = _find_equipment_index(entry.equipment_id)
		if equipment_index < 0:
			push_error("GameState: pakette tanımsız ekipman: '%s'" % entry.equipment_id)
			return false
		if not EquipmentStateScript.is_valid_condition(entry.condition):
			push_error("GameState: pakette geçersiz ekipman durumu: '%s' (%s)" % [entry.equipment_id, entry.condition])
			return false
		if entry.disabled_units < 0:
			push_error("GameState: pakette negatif ekipman süresi: '%s' (%d)" % [entry.equipment_id, entry.disabled_units])
			return false
		new_equipment[equipment_index] = entry.copy()
		updated_equipment.append(entry.equipment_id)

	# Kablo bulmacası ilerlemesi (K-032): sayaç negatif olamaz, geri gidemez ve bir uygulamada en fazla bir artar;
	# çözülme yalnızca false → true ve sayaç artışıyla birlikte olur; çözülmüş kayıt değişmez. Aynı değer etkisizdir.
	var new_cable_puzzles: Array[CablePuzzleProgressStateScript] = get_cable_puzzle_progress_snapshot()
	var updated_puzzles: Array[StringName] = []
	for entry in change.cable_puzzle_progress:
		if entry == null or entry.puzzle_id.is_empty():
			push_error("GameState: pakette geçersiz kablo bulmacası kaydı (boş kayıt veya kimlik).")
			return false
		if updated_puzzles.has(entry.puzzle_id):
			push_error("GameState: pakette tekrarlanan kablo bulmacası: '%s'" % entry.puzzle_id)
			return false
		var puzzle_index: int = _find_cable_puzzle_index(entry.puzzle_id)
		if puzzle_index < 0:
			push_error("GameState: pakette tanımsız kablo bulmacası: '%s'" % entry.puzzle_id)
			return false
		if entry.resolutions_used < 0:
			push_error("GameState: pakette negatif çözüm sayısı: '%s' (%d)" % [entry.puzzle_id, entry.resolutions_used])
			return false
		updated_puzzles.append(entry.puzzle_id)
		var current_progress: CablePuzzleProgressStateScript = _cable_puzzles[puzzle_index]
		if entry.equals(current_progress):
			continue
		if current_progress.solved:
			push_error("GameState: çözülmüş kablo bulmacası değiştirilemez: '%s'" % entry.puzzle_id)
			return false
		if entry.resolutions_used < current_progress.resolutions_used:
			push_error("GameState: kablo bulmacası çözüm sayısı geri gidemez: '%s' (%d -> %d)"
					% [entry.puzzle_id, current_progress.resolutions_used, entry.resolutions_used])
			return false
		if entry.resolutions_used > current_progress.resolutions_used + 1:
			push_error("GameState: kablo bulmacası çözüm sayısı bir uygulamada en fazla bir artar: '%s' (%d -> %d)"
					% [entry.puzzle_id, current_progress.resolutions_used, entry.resolutions_used])
			return false
		if entry.solved and entry.resolutions_used == current_progress.resolutions_used:
			push_error("GameState: kablo bulmacası çözüm sayısı artmadan çözülmüş olamaz: '%s'" % entry.puzzle_id)
			return false
		new_cable_puzzles[puzzle_index] = entry.copy()

	var new_night: int = _night
	var new_elapsed_units: int = _elapsed_units
	var new_night_ended: bool = _night_ended
	var new_tasks: Array[TimedTaskStateScript] = get_tasks_snapshot()
	if change.has_time_state:
		new_tasks = []
		if not _copy_valid_time_state(change.night, change.elapsed_units, change.tasks, new_tasks):
			return false
		new_night = change.night
		new_elapsed_units = change.elapsed_units
		new_night_ended = change.night_ended

	var changed: bool = new_resources != _resources or new_flags != _flags or not _trust_equal(new_trust) \
			or new_night != _night or new_elapsed_units != _elapsed_units or new_night_ended != _night_ended \
			or not _tasks_equal(new_tasks) or new_occurrences != _occurrences or not _equipment_equal(new_equipment) \
			or not _cable_puzzles_equal(new_cable_puzzles)
	if not changed:
		return true
	_resources = new_resources
	_flags = new_flags
	_trust = new_trust
	_occurrences = new_occurrences
	_equipment = new_equipment
	_cable_puzzles = new_cable_puzzles
	_night = new_night
	_elapsed_units = new_elapsed_units
	_night_ended = new_night_ended
	_tasks = new_tasks
	state_changed.emit()
	return true


# Zaman değerlerini doğrular; geçerliyse görevlerin sıralı bağımsız kopyalarını out_tasks'a ekler.
func _copy_valid_time_state(night: int, elapsed_units: int, tasks: Array[TimedTaskStateScript],
		out_tasks: Array[TimedTaskStateScript]) -> bool:
	if night < 0 or elapsed_units < 0:
		push_error("GameState: gece ve süre negatif olamaz: gece %d, süre %d" % [night, elapsed_units])
		return false
	var seen_ids: Dictionary[StringName, bool] = {}
	for task in tasks:
		if task == null or task.task_id.is_empty() or task.assigned_actor_id.is_empty() or task.remaining_units <= 0:
			push_error("GameState: geçersiz görev durumu (boş kimlik/aktör veya pozitif olmayan süre).")
			return false
		if seen_ids.has(task.task_id):
			push_error("GameState: tekrarlanan görev kimliği: '%s'" % task.task_id)
			return false
		seen_ids[task.task_id] = true
		out_tasks.append(task.copy())
	out_tasks.sort_custom(func(a: TimedTaskStateScript, b: TimedTaskStateScript) -> bool:
		return String(a.task_id) < String(b.task_id))
	return true


func _is_valid_trust_entry(entry: TrustRelationshipStateScript) -> bool:
	if entry == null or entry.source_actor_id.is_empty() or entry.target_actor_id.is_empty():
		push_error("GameState: geçersiz güven ilişkisi (boş kayıt veya aktör kimliği).")
		return false
	if entry.source_actor_id == entry.target_actor_id:
		push_error("GameState: kendine güven ilişkisi geçersiz: '%s'" % entry.source_actor_id)
		return false
	return true


func _find_trust_index(source_actor_id: StringName, target_actor_id: StringName) -> int:
	for i in _trust.size():
		if _trust[i].source_actor_id == source_actor_id and _trust[i].target_actor_id == target_actor_id:
			return i
	return -1


func _trust_sorts_before(a: TrustRelationshipStateScript, b: TrustRelationshipStateScript) -> bool:
	if a.source_actor_id != b.source_actor_id:
		return String(a.source_actor_id) < String(b.source_actor_id)
	return String(a.target_actor_id) < String(b.target_actor_id)


func _trust_equal(other: Array[TrustRelationshipStateScript]) -> bool:
	if other.size() != _trust.size():
		return false
	for i in _trust.size():
		if not _trust[i].equals(other[i]):
			return false
	return true


func _find_equipment_index(equipment_id: StringName) -> int:
	for i in _equipment.size():
		if _equipment[i].equipment_id == equipment_id:
			return i
	return -1


func _equipment_sorts_before(a: EquipmentStateScript, b: EquipmentStateScript) -> bool:
	return String(a.equipment_id) < String(b.equipment_id)


func _equipment_equal(other: Array[EquipmentStateScript]) -> bool:
	if other.size() != _equipment.size():
		return false
	for i in _equipment.size():
		if not _equipment[i].equals(other[i]):
			return false
	return true


func _find_cable_puzzle_index(puzzle_id: StringName) -> int:
	for i in _cable_puzzles.size():
		if _cable_puzzles[i].puzzle_id == puzzle_id:
			return i
	return -1


func _cable_puzzle_sorts_before(a: CablePuzzleProgressStateScript, b: CablePuzzleProgressStateScript) -> bool:
	return String(a.puzzle_id) < String(b.puzzle_id)


func _cable_puzzles_equal(other: Array[CablePuzzleProgressStateScript]) -> bool:
	if other.size() != _cable_puzzles.size():
		return false
	for i in _cable_puzzles.size():
		if not _cable_puzzles[i].equals(other[i]):
			return false
	return true


func _tasks_equal(other: Array[TimedTaskStateScript]) -> bool:
	if other.size() != _tasks.size():
		return false
	for i in _tasks.size():
		if not _tasks[i].equals(other[i]):
			return false
	return true
