extends "res://tests/framework/test_case.gd"
## ConditionData.copy() testleri: koşul kopyalamanın tek kaynağı (teknik temizlik). Yalnızca tarafsız kimlikler.
## Kopya, motorun Resource.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) yöntemiyle üretilir.

const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const CopyProbeScript := preload("res://tests/fixtures/copy_probe_data.gd")
const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const TaskFixtures := preload("res://tests/fixtures/task_fixtures.gd")
const AdviceFixtures := preload("res://tests/fixtures/advice_fixtures.gd")
const OccurrenceFixtures := preload("res://tests/fixtures/occurrence_fixtures.gd")
const EndingFixtures := preload("res://tests/fixtures/ending_fixtures.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")
const TaskSystemScript := preload("res://scripts/systems/task_system.gd")
const AdviceSystemScript := preload("res://scripts/systems/advice_system.gd")
const AdviceEvaluationScript := preload("res://scripts/systems/advice_evaluation.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")
const EndingResolverScript := preload("res://scripts/systems/ending_resolver.gd")
const NightStartResultScript := preload("res://scripts/systems/night_start_result.gd")

const FIXTURE_PATH: String = "res://tests/fixtures/decisions/decision_a.tres"


# --- ConditionData.copy() ---

func test_copy_is_a_condition_with_every_current_field() -> void:
	var source: ConditionDataScript = _filled_condition()
	var copy: ConditionDataScript = source.copy()
	assert_true(copy != null and copy != source)
	assert_true(copy.get_script() == ConditionDataScript)
	assert_eq(_describe(copy), _describe(source))
	assert_eq(_describe(copy), [&"occurrence", "res_a", "actor_a", "actor_b", "flag_a", &"ge", 7, true,
			"occurrence_a", &"pending"])


func test_changing_the_copy_never_changes_the_source() -> void:
	var source: ConditionDataScript = _filled_condition()
	var before: Array = _describe(source)
	var copy: ConditionDataScript = source.copy()
	_overwrite(copy)
	assert_eq(_describe(source), before)


func test_changing_the_source_never_changes_the_copy() -> void:
	var source: ConditionDataScript = _filled_condition()
	var copy: ConditionDataScript = source.copy()
	var before: Array = _describe(copy)
	_overwrite(source)
	assert_eq(_describe(copy), before)


func test_every_stored_field_is_copied_and_no_unstored_field_exists() -> void:
	# Alan listesi elle tekrarlanmaz: saklanan betik alanları yansımayla bulunur. Yeni bir alan eklendiğinde ya
	# otomatik olarak sınanır ya da tanınmayan türü için bu test açık bir mesajla başarısız olur.
	var source: ConditionDataScript = ConditionDataScript.new()
	var fields: Array[Dictionary] = []
	for property in source.get_property_list():
		if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		assert_true(property["usage"] & PROPERTY_USAGE_STORAGE,
				"ConditionData'da saklanmayan (@export olmayan) betik alanı var; kopyalanmaz: %s" % property["name"])
		fields.append(property)
	assert_true(fields.size() > 0, "ConditionData'da saklanan alan bulunamadı.")
	for property in fields:
		var sample: Variant = _sample_for(property)
		assert_true(sample != null, "Yeni alan türü için koruma testi güncellenmeli: %s (tür %d)"
				% [property["name"], property["type"]])
		if sample == null:
			return
		assert_ne(source.get(property["name"]), sample, "Örnek değer varsayılandan farklı olmalı: %s" % property["name"])
		source.set(property["name"], sample)
	var copy: ConditionDataScript = source.copy()
	for property in fields:
		var field: String = property["name"]
		assert_eq(copy.get(field), source.get(field), "Alan kopyalanmadı: %s" % field)
		if typeof(source.get(field)) in [TYPE_ARRAY, TYPE_DICTIONARY, TYPE_OBJECT]:
			assert_false(is_same(copy.get(field), source.get(field)), "Değiştirilebilir alan paylaşılıyor: %s" % field)


func test_copy_is_deep_for_sub_resources_and_collections() -> void:
	# Kanıt, ConditionData.copy()'nin kendisi üzerinden: sonda ConditionData'yı koleksiyon alanlarıyla genişletir.
	var probe: CopyProbeScript = CopyProbeScript.new()
	probe.flag_id = "flag_a"
	probe.child = _numbered(1)
	probe.children = [_numbered(2)] as Array[Resource]
	probe.keyed = {"key_a": _numbered(3)}
	probe.numbers = [1, 2] as Array[int]
	probe.labels = {"label_a": "value_a"}
	var copy: CopyProbeScript = probe.copy() as CopyProbeScript
	assert_true(copy != null and copy.get_script() == CopyProbeScript, "Kopya sonda türünde değil.")
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
	assert_eq(_nested_values(copy), [1, 2, 3])
	assert_eq([copy.numbers, copy.labels], [[1, 2], {"label_a": "value_a"}])
	assert_eq(copy.children.get_typed_script(), probe.children.get_typed_script())
	# Kopyada yapılan hiçbir değişiklik kaynağa ulaşmaz.
	_set_nested_values(copy, [91, 92, 93])
	copy.children.append(_numbered(94))
	copy.keyed["key_b"] = _numbered(95)
	copy.numbers.append(96)
	copy.labels["label_b"] = "value_b"
	assert_eq(_nested_values(probe), [1, 2, 3])
	assert_eq([probe.children.size(), probe.keyed.size(), probe.numbers, probe.labels],
			[1, 1, [1, 2], {"label_a": "value_a"}])
	# Kaynakta yapılan hiçbir değişiklik kopyaya ulaşmaz.
	_set_nested_values(probe, [81, 82, 83])
	assert_eq(_nested_values(copy), [91, 92, 93])


func test_copy_of_a_loaded_resource_is_a_new_independent_instance() -> void:
	var decision: DecisionDataScript = ResourceLoader.load(FIXTURE_PATH) as DecisionDataScript
	var source: ConditionDataScript = decision.choices[0].conditions[0]
	var copy: ConditionDataScript = source.copy()
	assert_false(is_same(copy, source))
	assert_eq(copy.resource_path, "")
	copy.value = 99
	assert_eq((ResourceLoader.load(FIXTURE_PATH) as DecisionDataScript).choices[0].conditions[0].value, 1)
	assert_eq(source.value, 1)


# --- Beş sistemde alan düzeyinde bağımsızlık ---

func test_decision_system_is_unaffected_by_later_condition_changes() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	DecisionFixtures.start(world)
	var condition: ConditionDataScript = DecisionFixtures.cond_flag("flag_a", false)
	var system: DecisionSystemScript = DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a",
			[DecisionFixtures.make_choice("choice_a", [condition])])])
	_corrupt(condition)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_true(system.is_choice_available(&"decision_a", &"choice_a"))


func test_task_system_is_unaffected_by_later_condition_changes() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	DecisionFixtures.start(world)
	var condition: ConditionDataScript = DecisionFixtures.cond_resource("res_a", &"ge", 1)
	var system: TaskSystemScript = TaskFixtures.make_system(world, [TaskFixtures.make_task("task_a", 4, "actor_a", "actor_b", [condition])])
	_corrupt(condition)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_true(system.assign_task(&"task_a", &"actor_a", &"actor_b").is_accepted())


func test_advice_system_is_unaffected_by_later_condition_changes() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	DecisionFixtures.start(world)
	world.state.set_flag(&"information_a", true)
	var presentation: ConditionDataScript = DecisionFixtures.cond_trust("actor_b", "actor_a", &"ge", 20)
	var information: ConditionDataScript = DecisionFixtures.cond_flag("information_a", true)
	var system: AdviceSystemScript = AdviceFixtures.make_system(world, [AdviceFixtures.make_advice("advice_a", "actor_b", "actor_a",
			"", [AdviceFixtures.make_variant("variant_a", &"correct", [information]), AdviceFixtures.make_variant("variant_b", &"incorrect")],
			[presentation])])
	_corrupt(presentation)
	_corrupt(information)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	var evaluation: AdviceEvaluationScript = system.evaluate(&"advice_a")
	assert_eq([evaluation.result.status, evaluation.variant_id], [&"offered", &"variant_a"])


func test_occurrence_system_is_unaffected_by_later_condition_changes() -> void:
	var world: DecisionFixtures.World = OccurrenceFixtures.make_world(["occurrence_x"])
	world.trust.initialize_relationships()
	var condition: ConditionDataScript = DecisionFixtures.cond_flag("flag_a", false)
	var system: OccurrenceSystemScript = OccurrenceFixtures.make_system(world, [OccurrenceFixtures.make_subject("subject_a")],
			[OccurrenceFixtures.make_occurrence("occurrence_x", "subject_a", 1, [condition])])
	_corrupt(condition)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	var result: NightStartResultScript = system.start_night()
	assert_eq(result.arrived_ids, [&"occurrence_x"] as Array[StringName])


func test_ending_resolver_is_unaffected_by_later_condition_changes() -> void:
	var world: DecisionFixtures.World = DecisionFixtures.make_world()
	world.trust.initialize_relationships()
	var condition: ConditionDataScript = DecisionFixtures.cond_resource("res_a", &"ge", 1)
	var resolver: EndingResolverScript = EndingFixtures.make_resolver(world, [EndingFixtures.make_ending("ending_a", 1, [condition]),
			EndingFixtures.make_ending("ending_z", 2)])
	_corrupt(condition)
	assert_eq(resolver.get_configuration_errors(), PackedStringArray())
	for i in 2:
		world.time.start_night()
		world.time.advance(10)
	assert_eq(resolver.resolve().ending_id, &"ending_a")


# --- Yardımcılar ---

func _filled_condition() -> ConditionDataScript:
	var condition: ConditionDataScript = ConditionDataScript.new()
	condition.kind = &"occurrence"
	condition.resource_id = "res_a"
	condition.source_actor_id = "actor_a"
	condition.target_actor_id = "actor_b"
	condition.flag_id = "flag_a"
	condition.comparison = &"ge"
	condition.value = 7
	condition.flag_value = true
	condition.occurrence_id = "occurrence_a"
	condition.occurrence_status = &"pending"
	return condition


func _overwrite(condition: ConditionDataScript) -> void:
	condition.kind = &"flag"
	condition.resource_id = "res_z"
	condition.source_actor_id = "actor_z"
	condition.target_actor_id = "actor_y"
	condition.flag_id = "flag_z"
	condition.comparison = &"lt"
	condition.value = -3
	condition.flag_value = false
	condition.occurrence_id = "occurrence_z"
	condition.occurrence_status = &"death_permanent"


# Özgün koşulu bütün alanlarıyla bozar; sistem kendi kopyasını kullanıyorsa hiçbir etkisi olmamalıdır.
func _corrupt(condition: ConditionDataScript) -> void:
	condition.kind = &"unknown"
	condition.comparison = &"zz"
	condition.value = 999
	condition.flag_value = not condition.flag_value
	condition.occurrence_id = "missing_id"
	condition.occurrence_status = &"lost"


func _describe(condition: ConditionDataScript) -> Array:
	return [condition.kind, condition.resource_id, condition.source_actor_id, condition.target_actor_id, condition.flag_id,
			condition.comparison, condition.value, condition.flag_value, condition.occurrence_id, condition.occurrence_status]


# Sondanın iç içe üç kaynağındaki value alanları: [child, children[0], keyed["key_a"]].
func _nested_values(probe: CopyProbeScript) -> Array:
	return [probe.child.get("value"), probe.children[0].get("value"), (probe.keyed["key_a"] as Resource).get("value")]


func _set_nested_values(probe: CopyProbeScript, values: Array) -> void:
	probe.child.set("value", values[0])
	probe.children[0].set("value", values[1])
	(probe.keyed["key_a"] as Resource).set("value", values[2])


func _numbered(number: int) -> ConditionDataScript:
	var condition: ConditionDataScript = ConditionDataScript.new()
	condition.value = number
	return condition


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
