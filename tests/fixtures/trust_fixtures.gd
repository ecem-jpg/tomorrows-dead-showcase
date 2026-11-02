extends RefCounted
## Güven testleri için tarafsız veri kurucuları (K-018). Oyun içeriği değildir.
## Varsayılan: sınırlar 0..100; actor_a→actor_b 60, actor_b→actor_a 30, actor_a→actor_c 0, actor_c→actor_a 100.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const TrustRulesDataScript := preload("res://scripts/data/trust_rules_data.gd")
const TrustRelationshipDataScript := preload("res://scripts/data/trust_relationship_data.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")

const DEFAULT_ROWS: Array = [
	["actor_a", "actor_b", 60],
	["actor_b", "actor_a", 30],
	["actor_a", "actor_c", 0],
	["actor_c", "actor_a", 100],
]


static func make_state_setup() -> InitialStateDataScript:
	var setup: InitialStateDataScript = InitialStateDataScript.new()
	setup.id = "state_setup_a"
	setup.rng_seed = 1
	return setup


static func make_state() -> GameStateScript:
	return GameStateScript.new(make_state_setup())


static func make_relationship(source: String, target: String, starting_value: int) -> TrustRelationshipDataScript:
	var relationship: TrustRelationshipDataScript = TrustRelationshipDataScript.new()
	relationship.source_actor_id = source
	relationship.target_actor_id = target
	relationship.starting_value = starting_value
	return relationship


## rows: [[kaynak, hedef, başlangıç], ...]; null satır boş kayıt olarak eklenir.
static func make_rules(rows: Array = DEFAULT_ROWS, min_value: int = 0, max_value: int = 100) -> TrustRulesDataScript:
	var rules: TrustRulesDataScript = TrustRulesDataScript.new()
	rules.id = "trust_rules_a"
	rules.min_value = min_value
	rules.max_value = max_value
	for row in rows:
		rules.relationships.append(null if row == null else make_relationship(row[0], row[1], row[2]))
	return rules


static func make_system(state: GameStateScript, rules: TrustRulesDataScript = null) -> TrustSystemScript:
	return TrustSystemScript.new(state, rules if rules != null else make_rules())


static func make_initialized_system(state: GameStateScript, rules: TrustRulesDataScript = null) -> TrustSystemScript:
	var system: TrustSystemScript = make_system(state, rules)
	system.initialize_relationships()
	return system
