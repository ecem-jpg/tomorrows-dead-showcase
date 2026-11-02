extends "res://tests/framework/test_case.gd"
## AdviceData'nın iç içe tipli alt kaynaklarla (bağlam, sunulma koşulları, biçimler → koşullar) yüklenmesi.

const AdviceDataScript := preload("res://scripts/data/advice_data.gd")
const AdviceContextDataScript := preload("res://scripts/data/advice_context_data.gd")
const AdviceVariantDataScript := preload("res://scripts/data/advice_variant_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/advice"
const FIXTURE_PATH: String = "res://tests/fixtures/advice/advice_a.tres"


func test_defaults_are_empty_and_accuracy_values_are_fixed() -> void:
	var advice: AdviceDataScript = AdviceDataScript.new()
	assert_eq(advice.id, "")
	assert_eq(advice.context, null)
	assert_eq([advice.presentation_conditions.size(), advice.variants.size()], [0, 0])
	assert_eq(advice.variants.get_typed_script(), AdviceVariantDataScript)
	var context: AdviceContextDataScript = AdviceContextDataScript.new()
	assert_eq([context.advisor_actor_id, context.recipient_actor_id, context.decision_id], ["", "", ""])
	var variant: AdviceVariantDataScript = AdviceVariantDataScript.new()
	assert_eq([variant.id, variant.accuracy, variant.recommended_choice_id], ["", &"", ""])
	assert_eq(variant.conditions.get_typed_script(), ConditionDataScript)
	assert_eq(AdviceVariantDataScript.ACCURACIES, [&"correct", &"incomplete", &"incorrect"] as Array[StringName])


func test_advice_fixture_loads_nested_typed_sub_resources() -> void:
	var resource: Resource = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null and resource.get_script() == AdviceDataScript, "Örnek dosya AdviceData olarak yüklenemedi.")
	if resource == null:
		return
	var advice: AdviceDataScript = resource as AdviceDataScript
	assert_eq(advice.id, "advice_a")
	assert_true(advice.context != null and advice.context.get_script() == AdviceContextDataScript)
	if advice.context == null:
		return
	assert_eq([advice.context.advisor_actor_id, advice.context.recipient_actor_id, advice.context.decision_id],
			["actor_b", "actor_a", "decision_a"])
	assert_eq(advice.presentation_conditions.get_typed_script(), ConditionDataScript)
	var presentation: ConditionDataScript = advice.presentation_conditions[0]
	assert_eq([presentation.kind, presentation.source_actor_id, presentation.target_actor_id, presentation.value],
			[&"trust", "actor_b", "actor_a", 20])
	assert_eq(advice.variants.size(), 3)
	var described: Array = []
	for variant in advice.variants:
		assert_true(variant.get_script() == AdviceVariantDataScript)
		assert_eq(variant.conditions.get_typed_script(), ConditionDataScript)
		described.append([variant.id, variant.accuracy, variant.conditions.size(), variant.recommended_choice_id])
	assert_eq(described, [["variant_a", &"correct", 2, "choice_a"], ["variant_b", &"incomplete", 1, ""],
			["variant_c", &"incorrect", 0, "choice_b"]])
	var information: ConditionDataScript = advice.variants[1].conditions[0]
	assert_eq([information.kind, information.flag_id, information.flag_value], [&"flag", "information_a", true])


func test_advice_fixture_passes_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
