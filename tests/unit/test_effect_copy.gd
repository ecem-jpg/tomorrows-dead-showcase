extends "res://tests/framework/test_case.gd"
## EffectData.copy() testleri: etki kopyalamanın tek kaynağı (teknik temizlik). Yalnızca tarafsız kimlikler.
## Kopya, motorun Resource.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) yöntemiyle üretilir.

const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const EffectCopyProbeScript := preload("res://tests/fixtures/effect_copy_probe_data.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const OccurrenceFixtures := preload("res://tests/fixtures/occurrence_fixtures.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")

const DECISION_FIXTURE_PATH: String = "res://tests/fixtures/decisions/decision_a.tres"
const TASK_FIXTURE_PATH: String = "res://tests/fixtures/tasks/task_b.tres"


# --- EffectData.copy() ---

func test_copy_is_an_effect_with_every_current_field() -> void:
	var source: EffectDataScript = _filled_effect()
	var copy: EffectDataScript = source.copy()
	assert_true(copy != null and copy != source)
	assert_true(copy.get_script() == EffectDataScript)
	assert_eq(_describe(copy), _describe(source))
	assert_eq(_describe(copy), [&"occurrence_prevent_death", "res_a", "actor_a", "actor_b", "flag_a", 7, true, "occurrence_a"])


func test_changing_the_copy_never_changes_the_source() -> void:
	var source: EffectDataScript = _filled_effect()
	var before: Array = _describe(source)
	_overwrite(source.copy())
	assert_eq(_describe(source), before)


func test_changing_the_source_never_changes_the_copy() -> void:
	var source: EffectDataScript = _filled_effect()
	var copy: EffectDataScript = source.copy()
	var before: Array = _describe(copy)
	_overwrite(source)
	assert_eq(_describe(copy), before)


func test_every_stored_field_is_copied_and_no_unstored_field_exists() -> void:
	# Alan listesi elle tekrarlanmaz: saklanan betik alanları yansımayla bulunur. Yeni bir alan eklendiğinde ya
	# otomatik olarak sınanır ya da tanınmayan türü için bu test açık bir mesajla başarısız olur.
	var source: EffectDataScript = EffectDataScript.new()
	var fields: Array[Dictionary] = []
	for property in source.get_property_list():
		if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		assert_true(property["usage"] & PROPERTY_USAGE_STORAGE,
				"EffectData'da saklanmayan (@export olmayan) betik alanı var; kopyalanmaz: %s" % property["name"])
		fields.append(property)
	assert_true(fields.size() > 0, "EffectData'da saklanan alan bulunamadı.")
	for property in fields:
		var sample: Variant = _sample_for(property)
		assert_true(sample != null, "Yeni alan türü için koruma testi güncellenmeli: %s (tür %d)"
				% [property["name"], property["type"]])
		if sample == null:
			return
		assert_ne(source.get(property["name"]), sample, "Örnek değer varsayılandan farklı olmalı: %s" % property["name"])
		source.set(property["name"], sample)
	var copy: EffectDataScript = source.copy()
	for property in fields:
		var field: String = property["name"]
		assert_eq(copy.get(field), source.get(field), "Alan kopyalanmadı: %s" % field)
		if typeof(source.get(field)) in [TYPE_ARRAY, TYPE_DICTIONARY, TYPE_OBJECT]:
			assert_false(is_same(copy.get(field), source.get(field)), "Değiştirilebilir alan paylaşılıyor: %s" % field)


func test_copy_is_deep_for_sub_resources_and_collections() -> void:
	# Kanıt, EffectData.copy()'nin kendisi üzerinden: sonda EffectData'yı koleksiyon alanlarıyla genişletir.
	var probe: EffectCopyProbeScript = EffectCopyProbeScript.new()
	probe.flag_id = "flag_a"
	probe.child = _numbered(1)
	probe.children = [_numbered(2)] as Array[Resource]
	probe.keyed = {"key_a": _numbered(3)}
	probe.numbers = [1, 2] as Array[int]
	probe.labels = {"label_a": "value_a"}
	var copy: EffectCopyProbeScript = probe.copy() as EffectCopyProbeScript
	assert_true(copy != null and copy.get_script() == EffectCopyProbeScript, "Kopya sonda türünde değil.")
	if copy == null:
		return
	assert_eq(copy.flag_id, "flag_a")
	# Örnekler farklı, değerler aynı.
	assert_false(is_same(copy.child, probe.child))
	assert_false(is_same(copy.children, probe.children))
	assert_false(is_same(copy.children[0], probe.children[0]))
	assert_false(is_same(copy.keyed, probe.keyed))
	assert_false(is_same(copy.keyed["key_a"], probe.keyed["key_a"]))
	assert_false(is_same(copy.numbers, probe.numbers))
	assert_false(is_same(copy.labels, probe.labels))
	assert_eq(_nested_amounts(copy), [1, 2, 3])
	assert_eq([copy.numbers, copy.labels], [[1, 2], {"label_a": "value_a"}])
	assert_eq(copy.children.get_typed_script(), probe.children.get_typed_script())
	# Kopyada yapılan hiçbir değişiklik kaynağa ulaşmaz.
	_set_nested_amounts(copy, [91, 92, 93])
	copy.children.append(_numbered(94))
	copy.keyed["key_b"] = _numbered(95)
	copy.numbers.append(96)
	copy.labels["label_b"] = "value_b"
	assert_eq(_nested_amounts(probe), [1, 2, 3])
	assert_eq([probe.children.size(), probe.keyed.size(), probe.numbers, probe.labels],
			[1, 1, [1, 2], {"label_a": "value_a"}])
	# Kaynakta yapılan hiçbir değişiklik kopyaya ulaşmaz.
	_set_nested_amounts(probe, [81, 82, 83])
	assert_eq(_nested_amounts(copy), [91, 92, 93])


func test_copy_of_a_loaded_choice_effect_is_a_new_independent_instance() -> void:
	var source: EffectDataScript = (ResourceLoader.load(DECISION_FIXTURE_PATH) as DecisionDataScript).choices[0].effects[0]
	var copy: EffectDataScript = source.copy()
	assert_false(is_same(copy, source))
	assert_eq(copy.resource_path, "")
	assert_eq([copy.kind, copy.resource_id, copy.amount], [&"resource_spend", "res_a", 1])
	copy.amount = 99
	assert_eq((ResourceLoader.load(DECISION_FIXTURE_PATH) as DecisionDataScript).choices[0].effects[0].amount, 1)
	assert_eq(source.amount, 1)


func test_copy_of_a_loaded_completion_effect_is_a_new_independent_instance() -> void:
	var source: EffectDataScript = (ResourceLoader.load(TASK_FIXTURE_PATH) as TaskDataScript).completion_effects[0]
	var copy: EffectDataScript = source.copy()
	assert_false(is_same(copy, source))
	assert_eq(copy.resource_path, "")
	assert_eq([copy.kind, copy.resource_id, copy.amount], [&"resource_add", "res_a", 2])
	copy.amount = 99
	assert_eq((ResourceLoader.load(TASK_FIXTURE_PATH) as TaskDataScript).completion_effects[0].amount, 2)
	assert_eq(source.amount, 2)


func test_copy_keeps_every_effect_family_intact() -> void:
	var effects: Array = _family_effects()
	var expected: Array = []
	for effect in effects:
		expected.append(_describe(effect))
	var copies: Array = []
	for effect in effects:
		copies.append(_describe((effect as EffectDataScript).copy()))
	assert_eq(copies, expected)
	assert_eq(expected.size(), 5)


# --- İki sistemde alan düzeyinde bağımsızlık ---

func test_decision_system_is_unaffected_by_later_effect_changes() -> void:
	var world: DecisionFixtures.World = _started_occurrence_world()
	var effects: Array = _family_effects()
	var system: DecisionSystemScript = DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a",
			[DecisionFixtures.make_choice("choice_a", [], effects)])])
	for effect in effects:
		_corrupt(effect)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	var result: DecisionResultScript = system.choose(&"decision_a", &"choice_a")
	assert_true(result.ok)
	assert_eq(_describe_outcomes(result.effect_outcomes), _expected_family_outcomes())
	_assert_family_applied(world)


func test_task_completion_system_is_unaffected_by_later_effect_changes() -> void:
	var world: DecisionFixtures.World = _started_occurrence_world()
	var effects: Array = _family_effects()
	var completions: TaskCompletionSystemScript = DecisionFixtures.make_completion_system(world,
			[DecisionFixtures.make_task_definition("task_a", effects)])
	world.time.start_task(&"task_a", &"actor_b", 2)
	for effect in effects:
		_corrupt(effect)
	assert_eq(completions.get_configuration_errors(), PackedStringArray())
	var result: TimeProgressResultScript = completions.advance(2)
	assert_true(result.ok)
	assert_eq(result.completions[0].status, &"applied")
	assert_eq(_describe_outcomes(result.completions[0].effect_outcomes), _expected_family_outcomes())
	_assert_family_applied(world)


func test_null_choice_effect_stays_reported_after_creation() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var choice: Object = DecisionFixtures.make_choice("choice_a", [], [DecisionFixtures.eff_add("res_b", 1), null])
	var system: DecisionSystemScript = DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a", [choice])])
	choice.effects[1] = DecisionFixtures.eff_add("res_a", 1)
	assert_eq(system.get_configuration_errors(), PackedStringArray(["'decision_a' / 'choice_a' etki #1: tanımsız kayıt"]))
	assert_eq(take_engine_errors().size(), 0)


func test_null_completion_effect_stays_reported_after_creation() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	var task: TaskDataScript = DecisionFixtures.make_task_definition("task_a", [null])
	var completions: TaskCompletionSystemScript = DecisionFixtures.make_completion_system(world, [task])
	task.completion_effects[0] = DecisionFixtures.eff_add("res_a", 1)
	assert_eq(completions.get_catalog_errors(), PackedStringArray(["'task_a' tamamlanma etkisi #0: tanımsız kayıt"]))
	assert_eq(take_engine_errors().size(), 0)


# --- Yardımcılar ---

## Dört etki ailesi: kaynak (ekleme ve harcama), yönlü güven, bayrak ve görünüm.
func _family_effects() -> Array:
	return [
		DecisionFixtures.eff_spend("res_a", 2),
		DecisionFixtures.eff_add("res_b", 3),
		DecisionFixtures.eff_trust("actor_a", "actor_b", 5),
		DecisionFixtures.eff_flag("flag_a", true),
		OccurrenceFixtures.eff_prevent("occurrence_a"),
	]


func _expected_family_outcomes() -> Array:
	return [
		"resource_spend:res_a:2:5:-2",
		"resource_add:res_b:3:0:3",
		"trust_change:actor_a>actor_b:5:60:5",
		"flag_set:flag_a:false>true",
		"occurrence_prevent_death:occurrence_a:pending>death_prevented",
	]


func _assert_family_applied(world: DecisionFixtures.World) -> void:
	assert_eq([world.state.get_resource(&"res_a"), world.state.get_resource(&"res_b")], [3, 3])
	assert_eq(world.state.get_trust(&"actor_a", &"actor_b"), 65)
	assert_true(world.state.get_flag(&"flag_a"))
	assert_eq(world.state.get_occurrence_status(&"occurrence_a"), &"death_prevented")


## Güveni başlatılmış, ilk gecesi OccurrenceSystem ile açılmış (occurrence_a pending) dünya.
func _started_occurrence_world() -> DecisionFixtures.World:
	var world: DecisionFixtures.World = OccurrenceFixtures.make_world()
	var occurrences: OccurrenceSystemScript = OccurrenceFixtures.make_default_system(world)
	OccurrenceFixtures.start(world, occurrences)
	return world


func _describe_outcomes(outcomes: Array) -> Array:
	var lines: Array = []
	for outcome in outcomes:
		match outcome.kind:
			&"flag_set":
				lines.append("%s:%s:%s>%s" % [outcome.kind, outcome.flag_id, outcome.previous_flag, outcome.flag_value])
			&"trust_change":
				lines.append("%s:%s>%s:%d:%d:%d" % [outcome.kind, outcome.source_actor_id, outcome.target_actor_id,
						outcome.requested, outcome.previous, outcome.applied])
			&"occurrence_prevent_death", &"occurrence_make_death_permanent":
				lines.append("%s:%s:%s>%s" % [outcome.kind, outcome.occurrence_id, outcome.previous_occurrence_status,
						outcome.occurrence_status])
			_:
				lines.append("%s:%s:%d:%d:%d" % [outcome.kind, outcome.resource_id, outcome.requested,
						outcome.previous, outcome.applied])
	return lines


func _filled_effect() -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.kind = &"occurrence_prevent_death"
	effect.resource_id = "res_a"
	effect.source_actor_id = "actor_a"
	effect.target_actor_id = "actor_b"
	effect.flag_id = "flag_a"
	effect.amount = 7
	effect.flag_value = true
	effect.occurrence_id = "occurrence_a"
	return effect


func _overwrite(effect: EffectDataScript) -> void:
	effect.kind = &"flag_set"
	effect.resource_id = "res_z"
	effect.source_actor_id = "actor_z"
	effect.target_actor_id = "actor_y"
	effect.flag_id = "flag_z"
	effect.amount = -3
	effect.flag_value = false
	effect.occurrence_id = "occurrence_z"


# Özgün etkiyi bütün alanlarıyla bozar; sistem kendi kopyasını kullanıyorsa hiçbir etkisi olmamalıdır.
func _corrupt(effect: EffectDataScript) -> void:
	effect.kind = &"unknown"
	effect.resource_id = "missing_id"
	effect.source_actor_id = "actor_z"
	effect.target_actor_id = "actor_z"
	effect.flag_id = ""
	effect.amount = -999
	effect.flag_value = not effect.flag_value
	effect.occurrence_id = "missing_id"


func _describe(effect: EffectDataScript) -> Array:
	return [effect.kind, effect.resource_id, effect.source_actor_id, effect.target_actor_id, effect.flag_id,
			effect.amount, effect.flag_value, effect.occurrence_id]


# Sondanın iç içe üç kaynağındaki amount alanları: [child, children[0], keyed["key_a"]].
func _nested_amounts(probe: EffectCopyProbeScript) -> Array:
	return [probe.child.get("amount"), probe.children[0].get("amount"), (probe.keyed["key_a"] as Resource).get("amount")]


func _set_nested_amounts(probe: EffectCopyProbeScript, values: Array) -> void:
	probe.child.set("amount", values[0])
	probe.children[0].set("amount", values[1])
	(probe.keyed["key_a"] as Resource).set("amount", values[2])


func _numbered(number: int) -> EffectDataScript:
	var effect: EffectDataScript = EffectDataScript.new()
	effect.amount = number
	return effect


# Desteklenen türler için varsayılan dışı örnek değer; tanınmayan türde null.
func _sample_for(property: Dictionary) -> Variant:
	var field: String = property["name"]
	match property["type"]:
		TYPE_STRING:
			return "sample_" + field
		TYPE_STRING_NAME:
			return StringName("sample_" + field)
		TYPE_INT:
			return 7
		TYPE_FLOAT:
			return 1.5
		TYPE_BOOL:
			return true
	return null
