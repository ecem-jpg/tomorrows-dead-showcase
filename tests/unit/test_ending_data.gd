extends "res://tests/framework/test_case.gd"
## EndingData'nın yüklenmesi ve doğrulanması (K-030).

const EndingDataScript := preload("res://scripts/data/ending_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/endings"


func test_defaults_are_empty() -> void:
	var ending: EndingDataScript = EndingDataScript.new()
	assert_eq([ending.id, ending.priority, ending.conditions.size()], ["", 0, 0])
	assert_eq(ending.conditions.get_typed_script(), ConditionDataScript)
	var names: Array[String] = []
	for property in ending.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(property["name"])
	assert_eq(names, ["id", "priority", "conditions"] as Array[String])


func test_ending_fixtures_load_with_typed_conditions() -> void:
	var conditional: EndingDataScript = ResourceLoader.load(FIXTURE_DIR + "/ending_a.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE) as EndingDataScript
	var fallback: EndingDataScript = ResourceLoader.load(FIXTURE_DIR + "/ending_b.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE) as EndingDataScript
	assert_true(conditional != null and fallback != null, "Son dosyaları yüklenemedi.")
	if conditional == null or fallback == null:
		return
	assert_eq([conditional.id, conditional.priority, conditional.conditions.size()], ["ending_a", 1, 1])
	assert_eq(conditional.conditions.get_typed_script(), ConditionDataScript)
	var condition: ConditionDataScript = conditional.conditions[0]
	assert_true(condition.get_script() == ConditionDataScript)
	assert_eq([condition.kind, condition.flag_id, condition.flag_value], [&"flag", "flag_a", true])
	assert_eq([fallback.id, fallback.priority, fallback.conditions.size()], ["ending_b", 2, 0])


func test_ending_fixtures_pass_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
