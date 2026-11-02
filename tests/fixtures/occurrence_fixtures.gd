extends RefCounted
## Gelecek ceset görünümü testleri için tarafsız veri ve sistem kurucuları (K-018). Oyun içeriği değildir.
## Dünya decision_fixtures ile aynıdır (res_a = 5, res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30;
## 2 gece × 10 birim, action_a = 2) ve ek olarak görünüm kaydı taşır.
## Varsayılan katalog: occurrence_a (subject_a, gece 1, koşulsuz); occurrence_b (subject_a, gece 2; koşul:
## occurrence_a death_prevented ve condition_a bayrağı false); occurrence_c (subject_b, gece 1, koşulsuz).

const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const SubjectDataScript := preload("res://scripts/data/subject_data.gd")
const OccurrenceDataScript := preload("res://scripts/data/occurrence_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const OccurrenceSystemScript := preload("res://scripts/systems/occurrence_system.gd")
const TaskCompletionSystemScript := preload("res://scripts/systems/task_completion_system.gd")

const DEFAULT_IDS: Array[String] = ["occurrence_a", "occurrence_b", "occurrence_c"]


static func make_setup(occurrence_ids: Array = DEFAULT_IDS) -> InitialStateDataScript:
	var setup: InitialStateDataScript = DecisionFixtures.make_state_setup()
	for occurrence_id in occurrence_ids:
		setup.occurrence_ids.append(occurrence_id)
	return setup


## state verilmezse verilen görünüm kimlikleriyle yeni bir GameState kurulur.
static func make_world(occurrence_ids: Array = DEFAULT_IDS, state: GameStateScript = null) -> DecisionFixtures.World:
	return DecisionFixtures.make_world(state if state != null else GameStateScript.new(make_setup(occurrence_ids)))


## Güveni başlatır ve ilk geceyi görünümlerle birlikte açar.
static func start(world: DecisionFixtures.World, system: OccurrenceSystemScript) -> void:
	world.trust.initialize_relationships()
	system.start_night()


static func make_subject(id: String) -> SubjectDataScript:
	var subject: SubjectDataScript = SubjectDataScript.new()
	subject.id = id
	return subject


## conditions içindeki null değerler boş kayıt olarak eklenir.
static func make_occurrence(id: String, subject_id: String, night: int, conditions: Array = []) -> OccurrenceDataScript:
	var occurrence: OccurrenceDataScript = OccurrenceDataScript.new()
	occurrence.id = id
	occurrence.subject_id = subject_id
	occurrence.night = night
	for condition in conditions:
		occurrence.arrival_conditions.append(condition)
	return occurrence


static func default_subjects() -> Array:
	return [make_subject("subject_a"), make_subject("subject_b")]


static func default_occurrences() -> Array:
	return [
		make_occurrence("occurrence_a", "subject_a", 1),
		make_occurrence("occurrence_b", "subject_a", 2, [
			cond_occurrence("occurrence_a", OccurrenceStatusScript.STATUS_DEATH_PREVENTED),
			DecisionFixtures.cond_flag("condition_a", false),
		]),
		make_occurrence("occurrence_c", "subject_b", 1),
	]


static func make_default_system(world: DecisionFixtures.World) -> OccurrenceSystemScript:
	return make_system(world, default_subjects(), default_occurrences())


static func make_system(world: DecisionFixtures.World, subjects: Array, occurrences: Array) -> OccurrenceSystemScript:
	var typed_subjects: Array[SubjectDataScript] = []
	for subject in subjects:
		typed_subjects.append(subject)
	var typed_occurrences: Array[OccurrenceDataScript] = []
	for occurrence in occurrences:
		typed_occurrences.append(occurrence)
	return OccurrenceSystemScript.new(world.state, world.trust, world.time, typed_subjects, typed_occurrences)


## Görevsiz tamamlanma sistemi; oyun akışında zamanı ve gece sonunu ilerletmek için.
static func make_clock(world: DecisionFixtures.World) -> TaskCompletionSystemScript:
	return DecisionFixtures.make_completion_system(world, [])


static func cond_occurrence(occurrence_id: String, status: StringName) -> ConditionDataScript:
	return DecisionFixtures.make_condition(&"occurrence", {"occurrence_id": occurrence_id, "occurrence_status": status})


static func eff_prevent(occurrence_id: String) -> EffectDataScript:
	return DecisionFixtures.make_effect(&"occurrence_prevent_death", {"occurrence_id": occurrence_id})


static func eff_permanent(occurrence_id: String) -> EffectDataScript:
	return DecisionFixtures.make_effect(&"occurrence_make_death_permanent", {"occurrence_id": occurrence_id})
