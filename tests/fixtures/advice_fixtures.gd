extends RefCounted
## Öneri testleri için tarafsız veri ve sistem kurucuları (K-018). Oyun içeriği değildir.
## Dünya decision_fixtures ile aynıdır: res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30;
## zaman 2 gece × 10 birim. Varsayılan karar: decision_a → choice_a, choice_b (koşulsuz, etkisiz).
## Bilgi bayraklarla temsil edilir (information_a, information_b).

const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const AdviceDataScript := preload("res://scripts/data/advice_data.gd")
const AdviceContextDataScript := preload("res://scripts/data/advice_context_data.gd")
const AdviceVariantDataScript := preload("res://scripts/data/advice_variant_data.gd")
const AdviceSystemScript := preload("res://scripts/systems/advice_system.gd")
const DecisionSystemScript := preload("res://scripts/systems/decision_system.gd")


## conditions içindeki null değerler boş kayıt olarak eklenir.
static func make_variant(id: String, accuracy: StringName, conditions: Array = [],
		recommended_choice_id: String = "") -> AdviceVariantDataScript:
	var variant: AdviceVariantDataScript = AdviceVariantDataScript.new()
	variant.id = id
	variant.accuracy = accuracy
	variant.recommended_choice_id = recommended_choice_id
	for condition in conditions:
		variant.conditions.append(condition)
	return variant


static func make_advice(id: String, advisor_actor_id: String, recipient_actor_id: String, decision_id: String,
		variants: Array, presentation_conditions: Array = []) -> AdviceDataScript:
	var context: AdviceContextDataScript = AdviceContextDataScript.new()
	context.advisor_actor_id = advisor_actor_id
	context.recipient_actor_id = recipient_actor_id
	context.decision_id = decision_id
	var advice: AdviceDataScript = AdviceDataScript.new()
	advice.id = id
	advice.context = context
	for condition in presentation_conditions:
		advice.presentation_conditions.append(condition)
	for variant in variants:
		advice.variants.append(variant)
	return advice


static func make_default_decisions(world: DecisionFixtures.World) -> DecisionSystemScript:
	return DecisionFixtures.make_system(world, [DecisionFixtures.make_decision("decision_a", [
		DecisionFixtures.make_choice("choice_a"),
		DecisionFixtures.make_choice("choice_b"),
	])])


## decisions verilmezse varsayılan karar sistemi kurulur.
static func make_system(world: DecisionFixtures.World, advices: Array,
		decisions: DecisionSystemScript = null) -> AdviceSystemScript:
	var typed: Array[AdviceDataScript] = []
	for advice in advices:
		typed.append(advice)
	var decision_system: DecisionSystemScript = decisions if decisions != null else make_default_decisions(world)
	return AdviceSystemScript.new(world.state, world.trust, decision_system, typed)
