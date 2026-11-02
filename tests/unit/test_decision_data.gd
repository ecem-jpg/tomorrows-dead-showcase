extends "res://tests/framework/test_case.gd"
## DecisionData'nın iç içe tipli alt kaynaklarla (seçenek → koşul/etki) yüklenmesi ve doğrulanması.

const DecisionDataScript := preload("res://scripts/data/decision_data.gd")
const ChoiceDataScript := preload("res://scripts/data/choice_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/decisions"
const FIXTURE_PATH: String = "res://tests/fixtures/decisions/decision_a.tres"


func test_decision_fixture_loads_nested_typed_sub_resources() -> void:
	var resource: Resource = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null, "Örnek dosya yüklenemedi.")
	if resource == null:
		return
	assert_true(resource.get_script() == DecisionDataScript, "Kaynak DecisionData değil.")
	var decision: DecisionDataScript = resource as DecisionDataScript
	assert_eq(decision.id, "decision_a")
	assert_eq(decision.choices.get_typed_script(), ChoiceDataScript)
	assert_eq(decision.choices.size(), 2)

	var choice_a: ChoiceDataScript = decision.choices[0]
	assert_true(choice_a.get_script() == ChoiceDataScript)
	assert_eq(choice_a.id, "choice_a")
	assert_eq(choice_a.action_id, "action_a")
	assert_eq(choice_a.conditions.get_typed_script(), ConditionDataScript)
	assert_eq(choice_a.effects.get_typed_script(), EffectDataScript)
	assert_eq(choice_a.conditions.size(), 1)
	assert_eq(choice_a.effects.size(), 2)
	var condition: ConditionDataScript = choice_a.conditions[0]
	assert_true(condition.get_script() == ConditionDataScript)
	assert_eq([condition.kind, condition.resource_id, condition.comparison, condition.value],
			[&"resource", "res_a", &"ge", 1])
	var spend: EffectDataScript = choice_a.effects[0]
	var flag: EffectDataScript = choice_a.effects[1]
	assert_true(spend.get_script() == EffectDataScript and flag.get_script() == EffectDataScript)
	assert_eq([spend.kind, spend.resource_id, spend.amount], [&"resource_spend", "res_a", 1])
	assert_eq([flag.kind, flag.flag_id, flag.flag_value], [&"flag_set", "flag_a", true])

	var choice_b: ChoiceDataScript = decision.choices[1]
	assert_eq(choice_b.id, "choice_b")
	assert_eq(choice_b.action_id, "")
	var trust_condition: ConditionDataScript = choice_b.conditions[0]
	assert_eq([trust_condition.kind, trust_condition.source_actor_id, trust_condition.target_actor_id,
			trust_condition.comparison, trust_condition.value], [&"trust", "actor_a", "actor_b", &"ge", 50])
	var trust_effect: EffectDataScript = choice_b.effects[0]
	assert_eq([trust_effect.kind, trust_effect.source_actor_id, trust_effect.target_actor_id, trust_effect.amount],
			[&"trust_change", "actor_a", "actor_b", -5])


func test_decision_fixture_passes_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
