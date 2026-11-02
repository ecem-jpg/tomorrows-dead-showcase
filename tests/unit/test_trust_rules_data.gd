extends "res://tests/framework/test_case.gd"
## TrustRulesData'nın tipli alt kaynak dizisiyle birlikte veri dosyasından yüklenmesi ve doğrulanması.

const TrustRulesDataScript := preload("res://scripts/data/trust_rules_data.gd")
const TrustRelationshipDataScript := preload("res://scripts/data/trust_relationship_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/trust"
const FIXTURE_PATH: String = "res://tests/fixtures/trust/trust_rules_a.tres"


func test_rules_fixture_loads_with_typed_relationships() -> void:
	var resource: Resource = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null, "Örnek dosya yüklenemedi.")
	if resource == null:
		return
	assert_true(resource.get_script() == TrustRulesDataScript, "Kaynak TrustRulesData değil.")
	var rules: TrustRulesDataScript = resource as TrustRulesDataScript
	assert_eq(rules.id, "trust_rules_a")
	assert_eq(rules.min_value, 0)
	assert_eq(rules.max_value, 100)
	assert_eq(rules.relationships.size(), 4)
	assert_eq(rules.relationships.get_typed_script(), TrustRelationshipDataScript)
	var rows: Array = []
	for relationship in rules.relationships:
		assert_true(relationship.get_script() == TrustRelationshipDataScript, "Alt kaynak türü yanlış.")
		rows.append([relationship.source_actor_id, relationship.target_actor_id, relationship.starting_value])
	assert_eq(rows, [
		["actor_a", "actor_b", 60],
		["actor_b", "actor_a", 30],
		["actor_a", "actor_c", 0],
		["actor_c", "actor_a", 100],
	])


func test_fixture_passes_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
