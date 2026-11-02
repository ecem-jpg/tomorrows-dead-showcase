class_name TimeSystem
extends RefCounted
## Ana gece oynanışının ayrık, eylem tabanlı ortak saati (K-022). Zaman yalnızca anlamlı eylemlerle,
## verideki maliyet kadar ilerler; gerçek zamana bağlı değildir. Durum GameState'te tutulur ve
## bu sınıf kendi sinyalini tanımlamaz. Görev kabul/ret kararı, görev sonuçları ve olay
## koşul/etkileri bu sınıfın işi değildir. 60 saniyelik açılış bu sınıfın dışındadır.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")
const TimeOccurrenceScript := preload("res://scripts/systems/time_occurrence.gd")
const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TimeAdvancePlanScript := preload("res://scripts/systems/time_advance_plan.gd")

## plan_add_task sonuçları; boş dizge başarıdır.
const TASK_FAILURE_INVALID_PLAN: StringName = &"invalid_plan"
const TASK_FAILURE_NIGHT_NOT_ACTIVE: StringName = &"night_not_active"
const TASK_FAILURE_EMPTY_ID: StringName = &"empty_id"
const TASK_FAILURE_NON_POSITIVE_DURATION: StringName = &"non_positive_duration"
const TASK_FAILURE_DUPLICATE: StringName = &"duplicate_task"

var _state: GameStateScript
var _night_count: int = 0
var _night_length_units: int = 0
var _action_costs: Dictionary[StringName, int] = {}
# Olayların bağımsız kopyaları; tetiklenme sırasına (gece, an, order, id) göre sıralı.
var _events: Array[ScheduledEventDataScript] = []
var _null_event_count: int = 0


func _init(state: GameStateScript, rules: TimeRulesDataScript, events: Array[ScheduledEventDataScript]) -> void:
	if state == null or rules == null:
		push_error("TimeSystem: oyun durumu ve zaman kuralları verilmelidir.")
	_state = state
	if rules != null:
		_night_count = rules.night_count
		_night_length_units = rules.night_length_units
		_action_costs = rules.action_costs.duplicate(true)
	for event in events:
		if event == null:
			_null_event_count += 1
			continue
		_events.append(_copy_event(event))
	_events.sort_custom(_fires_before)


## Kural, olay ve durum tutarsızlıklarını deterministik sırayla döndürür; hiçbir değeri düzeltmez.
func get_configuration_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if _night_count < 1:
		errors.append("Gece sayısı en az 1 olmalı: %d" % _night_count)
	if _night_length_units < 1:
		errors.append("Gece uzunluğu en az 1 olmalı: %d" % _night_length_units)
	var action_ids: PackedStringArray = []
	for action_id in _action_costs:
		action_ids.append(String(action_id))
	action_ids.sort()
	for action_text in action_ids:
		var cost: int = _action_costs[StringName(action_text)]
		if cost < 0:
			errors.append("Negatif eylem maliyeti: '%s' (%d)" % [action_text, cost])
	errors.append_array(_event_errors())
	errors.append_array(_state_errors())
	return errors


## Eylemin verideki zaman maliyeti. Tanımsız eylemde hata verir ve 0 döner.
func cost_of(action_id: StringName) -> int:
	if not _action_costs.has(action_id):
		push_error("TimeSystem: tanımsız eylem maliyeti: '%s'" % action_id)
		return 0
	return _action_costs[action_id]


## Numara olarak bir sonraki gece var mı. Yeni geceyi açmak oyun akışının işidir.
func has_next_night() -> bool:
	return _state != null and _state.get_night() < _night_count


## Veride tanımlı gece sayısı.
func get_night_count() -> int:
	return _night_count


## Düşük seviyeli uyumluluk ve test yöntemi: oyun akışında geceler OccurrenceSystem.start_night ile başlar
## (K-029), çünkü ceset varışları gece başlangıcıyla aynı pakette yazılmalıdır.
## Hiç gece başlamamışsa ya da mevcut gece bittiyse sonraki geceyi açar. Bitmemiş görevler korunur.
## Gece sürerken, son geceden sonra veya hatalı yapılandırmada hata verir ve durumu değiştirmez.
func start_night() -> bool:
	var plan: TimeAdvancePlanScript = plan_start_night()
	if not plan.is_valid():
		push_error(plan.error_message)
		return false
	return _state.set_time_state(plan.night, plan.elapsed_units, plan.night_ended, plan.tasks)


## start_night'ın yapacağını yazmadan hesaplar. Durumu değiştirmez, sinyal yaymaz ve hata basmaz;
## geçersiz istekte plan.failure ve plan.error_message doldurulur. Plandaki görevler bağımsız kopyalardır.
func plan_start_night() -> TimeAdvancePlanScript:
	var plan: TimeAdvancePlanScript = TimeAdvancePlanScript.new()
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		plan.failure = TimeAdvancePlanScript.FAILURE_INVALID_CONFIGURATION
		plan.error_message = "TimeSystem: geçersiz yapılandırma; gece başlatılamaz: %s" % " | ".join(errors)
		return plan
	var night: int = _state.get_night()
	if night > 0 and not _state.is_night_ended():
		plan.failure = TimeAdvancePlanScript.FAILURE_NIGHT_ALREADY_ACTIVE
		plan.error_message = "TimeSystem: gece sürerken yeni gece başlatılamaz (gece %d)." % night
		return plan
	if night >= _night_count:
		plan.failure = TimeAdvancePlanScript.FAILURE_NO_NEXT_NIGHT
		plan.error_message = "TimeSystem: son gece bitti; başlatılacak gece yok."
		return plan
	plan.night = night + 1
	plan.elapsed_units = 0
	plan.night_ended = false
	plan.tasks = _state.get_tasks_snapshot()
	plan.result.ok = true
	return plan


## Kabul edilmiş bir görevi ortak saate ekler; kabul/ret kararı çağıranındır. Yalnızca etkin gecede.
## Boş görev/aktör kimliği, tekrarlanan görev kimliği veya pozitif olmayan süre reddedilir.
## Aynı aktörün eşzamanlı görev sayısı burada sınırlanmaz. Kurallar plan_add_task ile aynıdır.
func start_task(task_id: StringName, assigned_actor_id: StringName, duration_units: int) -> bool:
	if not _ensure_valid_configuration("görev başlatılamaz"):
		return false
	var plan: TimeAdvancePlanScript = plan_advance(0)
	var failure: StringName = plan_add_task(plan, task_id, assigned_actor_id, duration_units)
	match failure:
		&"":
			return _state.set_time_state(plan.night, plan.elapsed_units, plan.night_ended, plan.tasks)
		TASK_FAILURE_NIGHT_NOT_ACTIVE:
			push_error("TimeSystem: etkin gece yokken görev başlatılamaz: '%s'" % task_id)
		TASK_FAILURE_EMPTY_ID:
			push_error("TimeSystem: görev ve aktör kimliği boş olamaz: '%s' / '%s'" % [task_id, assigned_actor_id])
		TASK_FAILURE_NON_POSITIVE_DURATION:
			push_error("TimeSystem: görev süresi pozitif olmalı: '%s' (%d)" % [task_id, duration_units])
		TASK_FAILURE_DUPLICATE:
			push_error("TimeSystem: görev zaten var: '%s'" % task_id)
		_:
			push_error("TimeSystem: görev planlanamadı: '%s' (%s)" % [task_id, plan.error_message])
	return false


## Kabul edilmiş bir görevi verilen planın görev listesine yazmadan ekler (K-025, K-026). Durumu
## değiştirmez, sinyal yaymaz ve hata basmaz. Plan geçerli olmalı ve gecesi bitmemiş olmalı (ör. bir
## eylemin zamanı geceyi bitirdiyse görev eklenemez). Bütün alanlar doğrulanmadan plan değişmez;
## başarısızlıkta plan tamamen aynı kalır. Görev planın mevcut süresinden itibaren tam süresiyle başlar.
## Boş dizge başarı, aksi hâlde TASK_FAILURE_* döner.
func plan_add_task(plan: TimeAdvancePlanScript, task_id: StringName, assigned_actor_id: StringName,
		duration_units: int) -> StringName:
	if plan == null:
		return TASK_FAILURE_INVALID_PLAN
	if plan.failure == TimeAdvancePlanScript.FAILURE_NIGHT_NOT_ACTIVE or (plan.is_valid() and plan.night_ended):
		return TASK_FAILURE_NIGHT_NOT_ACTIVE
	if not plan.is_valid():
		return TASK_FAILURE_INVALID_PLAN
	if task_id.is_empty() or assigned_actor_id.is_empty():
		return TASK_FAILURE_EMPTY_ID
	if duration_units <= 0:
		return TASK_FAILURE_NON_POSITIVE_DURATION
	for task in plan.tasks:
		if task.task_id == task_id:
			return TASK_FAILURE_DUPLICATE
	plan.tasks.append(TimedTaskStateScript.new(task_id, assigned_actor_id, duration_units))
	return &""


## Etkin gecede zamanı ilerletir; gece sınırında keser ve sonraki geceye geçmez.
## Negatif miktar, etkin olmayan gece (sıfır dahil) veya hatalı yapılandırma geçersiz işlemdir.
## Hesaplama plan_advance ile yapılır; geçerli plan tek seferde yazılır.
func advance(amount: int) -> TimeAdvanceResultScript:
	var plan: TimeAdvancePlanScript = plan_advance(amount)
	if not plan.is_valid():
		push_error(plan.error_message)
		return TimeAdvanceResultScript.new()
	if plan.result.applied_units == 0:
		return plan.result
	# Sonuç yalnızca durum gerçekten yazıldıysa geçerlidir.
	if not _state.set_time_state(plan.night, plan.elapsed_units, plan.night_ended, plan.tasks):
		push_error("TimeSystem: zaman durumu yazılamadı; ilerleme uygulanmadı (gece %d)." % plan.night)
		return TimeAdvanceResultScript.new()
	return plan.result


## Eylem maliyeti veride tanımlı mı. Hata vermez.
func has_action_cost(action_id: StringName) -> bool:
	return _action_costs.has(action_id)


## advance'in yapacağı ilerlemeyi yazmadan hesaplar (K-025). Durumu değiştirmez, sinyal yaymaz ve
## hata basmaz; geçersiz istekte plan.failure ve plan.error_message doldurulur. Plandaki görevler,
## oluşumlar ve sonuç iç durumdan bağımsız kopyalardır. Kurallar advance ile aynıdır: sıfır miktar
## dahil etkin gece gerekir.
func plan_advance(amount: int) -> TimeAdvancePlanScript:
	var plan: TimeAdvancePlanScript = TimeAdvancePlanScript.new()
	var errors: PackedStringArray = get_configuration_errors()
	if not errors.is_empty():
		plan.failure = TimeAdvancePlanScript.FAILURE_INVALID_CONFIGURATION
		plan.error_message = "TimeSystem: geçersiz yapılandırma; zaman ilerletilemez: %s" % " | ".join(errors)
		return plan
	if amount < 0:
		plan.failure = TimeAdvancePlanScript.FAILURE_NEGATIVE_AMOUNT
		plan.error_message = "TimeSystem: negatif zaman ilerlemesi: %d" % amount
		return plan
	if not _is_night_active():
		plan.failure = TimeAdvancePlanScript.FAILURE_NIGHT_NOT_ACTIVE
		plan.error_message = "TimeSystem: etkin gece yokken zaman ilerletilemez (gece %d, bitti: %s)." \
				% [_state.get_night(), _state.is_night_ended()]
		return plan

	var night: int = _state.get_night()
	var previous: int = _state.get_elapsed_units()
	plan.night = night
	plan.elapsed_units = previous
	plan.night_ended = false
	plan.tasks = _state.get_tasks_snapshot()
	plan.result.ok = true
	if amount == 0:
		return plan

	var applied: int = mini(amount, _night_length_units - previous)
	var current: int = previous + applied
	var ended: bool = current == _night_length_units
	var occurrences: Array[TimeOccurrenceScript] = []
	# Görevler yalnızca uygulanan süre kadar ilerler; taşan miktar onları ilerletmez.
	var remaining_tasks: Array[TimedTaskStateScript] = []
	for task in plan.tasks:
		if task.remaining_units <= applied:
			occurrences.append(TimeOccurrenceScript.new(night, previous + task.remaining_units,
					TimeOccurrenceScript.Kind.TASK_COMPLETED, task.task_id, 0, task.assigned_actor_id))
		else:
			task.remaining_units -= applied
			remaining_tasks.append(task)
	for event in _events:
		if event.night == night and event.at_units > previous and event.at_units <= current:
			occurrences.append(TimeOccurrenceScript.new(night, event.at_units,
					TimeOccurrenceScript.Kind.EVENT_TRIGGERED, StringName(event.id), event.order))
	if ended:
		occurrences.append(TimeOccurrenceScript.new(night, current, TimeOccurrenceScript.Kind.NIGHT_ENDED))
	occurrences.sort_custom(func(a: TimeOccurrenceScript, b: TimeOccurrenceScript) -> bool:
		return TimeOccurrenceScript.comes_before(a, b))

	plan.elapsed_units = current
	plan.night_ended = ended
	plan.tasks = remaining_tasks
	plan.result.applied_units = applied
	plan.result.overflow_units = amount - applied
	plan.result.occurrences = occurrences
	return plan


func _is_night_active() -> bool:
	return _state.get_night() > 0 and not _state.is_night_ended()


func _ensure_valid_configuration(action: String) -> bool:
	var errors: PackedStringArray = get_configuration_errors()
	if errors.is_empty():
		return true
	push_error("TimeSystem: geçersiz yapılandırma; %s: %s" % [action, " | ".join(errors)])
	return false


func _event_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	for i in _null_event_count:
		errors.append("Tanımsız olay kaydı")
	var by_id: Array[ScheduledEventDataScript] = _events.duplicate()
	by_id.sort_custom(func(a: ScheduledEventDataScript, b: ScheduledEventDataScript) -> bool:
		if a.id != b.id:
			return a.id < b.id
		if a.night != b.night:
			return a.night < b.night
		return a.at_units < b.at_units)
	var seen_ids: Dictionary[String, bool] = {}
	var reported_duplicates: Dictionary[String, bool] = {}
	for event in by_id:
		if event.id.is_empty():
			errors.append("Boş olay kimliği")
		elif seen_ids.has(event.id):
			if not reported_duplicates.has(event.id):
				errors.append("Tekrarlanan olay kimliği: '%s'" % event.id)
				reported_duplicates[event.id] = true
		else:
			seen_ids[event.id] = true
		if event.night < 1 or event.night > _night_count:
			errors.append("Olay gecesi aralık dışında: '%s' (gece %d, 1..%d)" % [event.id, event.night, _night_count])
		if event.at_units < 1 or event.at_units > _night_length_units:
			errors.append("Olay anı aralık dışında: '%s' (an %d, 1..%d)"
					% [event.id, event.at_units, _night_length_units])
	return errors


func _state_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if _state == null:
		errors.append("Oyun durumu verilmedi")
		return errors
	var night: int = _state.get_night()
	var elapsed: int = _state.get_elapsed_units()
	if night == 0:
		if elapsed != 0:
			errors.append("Gece başlamamışken süre 0 olmalı: %d" % elapsed)
		if _state.is_night_ended():
			errors.append("Gece başlamamışken bitiş işaretli olamaz")
		var task_count: int = _state.get_tasks_snapshot().size()
		if task_count > 0:
			errors.append("Gece başlamamışken görev olamaz: %d" % task_count)
	elif night > _night_count:
		errors.append("Gece sayısı aşıldı: gece %d, gece sayısı %d" % [night, _night_count])
	elif _state.is_night_ended():
		if elapsed != _night_length_units:
			errors.append("Bitmiş gecede süre gece uzunluğuna eşit olmalı: %d / %d" % [elapsed, _night_length_units])
	elif elapsed >= _night_length_units:
		errors.append("Etkin gecede süre gece uzunluğundan küçük olmalı: %d / %d" % [elapsed, _night_length_units])
	return errors


func _copy_event(event: ScheduledEventDataScript) -> ScheduledEventDataScript:
	var copy: ScheduledEventDataScript = ScheduledEventDataScript.new()
	copy.id = event.id
	copy.night = event.night
	copy.at_units = event.at_units
	copy.order = event.order
	return copy


func _fires_before(a: ScheduledEventDataScript, b: ScheduledEventDataScript) -> bool:
	if a.night != b.night:
		return a.night < b.night
	if a.at_units != b.at_units:
		return a.at_units < b.at_units
	if a.order != b.order:
		return a.order < b.order
	return a.id < b.id
