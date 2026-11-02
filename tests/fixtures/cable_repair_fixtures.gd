extends RefCounted
## Kablo bulmacası sonuç sistemi testleri için tarafsız veri ve sistem kurucuları (K-018, K-032). Oyun içeriği değildir.
## Dünya equipment_fixtures ile aynıdır (res_a = 5 (0..10), res_b = 0; güven actor_a→actor_b 60, actor_b→actor_a 30;
## 2 gece × 10 birim, action_a = 2, action_b = 0; equipment_a çalışıyor, equipment_b arızalı, equipment_c çalışıyor)
## ve ek olarak kablo bulmacası kimlikleri taşır. Varsayılan bulmaca: standart düzen (CableFixtures), tek gönderim
## hakkı, iki oyun geneli çözüm hakkı, equipment_b, boş sonuç dalları.

const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const EquipmentFixtures := preload("res://tests/fixtures/equipment_fixtures.gd")
const CableFixtures := preload("res://tests/fixtures/cable_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CableRepairSystemScript := preload("res://scripts/systems/cable_repair_system.gd")
const TaskDataScript := preload("res://scripts/data/task_data.gd")

const A: StringName = &"terminal_a"
const B: StringName = &"terminal_b"
const C: StringName = &"terminal_c"
const D: StringName = &"terminal_d"


static func make_setup(puzzle_ids: Array = ["puzzle_a"]) -> InitialStateDataScript:
	var setup: InitialStateDataScript = EquipmentFixtures.make_setup(EquipmentFixtures.default_equipment())
	for puzzle_id in puzzle_ids:
		setup.cable_puzzle_ids.append(puzzle_id)
	return setup


## state verilmezse puzzle_ids ile yeni bir GameState kurulur (test ikizleri için verilebilir).
static func make_world(puzzle_ids: Array = ["puzzle_a"], state: GameStateScript = null) -> DecisionFixtures.World:
	return DecisionFixtures.make_world(state if state != null else GameStateScript.new(make_setup(puzzle_ids)))


## Güveni başlatır ve ilk geceyi açar (düşük seviyeli start_night; yalnızca test kurulumu).
static func start(world: DecisionFixtures.World) -> void:
	world.trust.initialize_relationships()
	world.time.start_night()


static func make_puzzle(id: String = "puzzle_a", success_effects: Array = [], failure_effects: Array = [],
		success_action: String = "", failure_action: String = "") -> CablePuzzleDataScript:
	var puzzle: CablePuzzleDataScript = CableFixtures.make_standard(1)
	puzzle.id = id
	puzzle.rules.equipment_id = "equipment_b"
	puzzle.rules.max_resolutions = 2
	puzzle.success = CableFixtures.make_outcome(success_effects, success_action)
	puzzle.failure = CableFixtures.make_outcome(failure_effects, failure_action)
	return puzzle


static func make_system(world: DecisionFixtures.World, puzzles: Array, tasks: Array = []) -> CableRepairSystemScript:
	var typed: Array[CablePuzzleDataScript] = []
	for puzzle in puzzles:
		typed.append(puzzle)
	return CableRepairSystemScript.new(world.state, world.resources, world.trust, world.time,
			DecisionFixtures.make_completion_system(world, tasks), typed)


## Standart düzeni doğru bağlar ve gönderir; oturum solved olur.
static func solve(session: CablePuzzleSessionScript) -> void:
	session.connect_terminals(A, B)
	session.connect_terminals(C, D)
	session.submit()


## Standart düzeni yanlış bağlar ve hak bitene kadar gönderir; oturum failed olur.
static func fail(session: CablePuzzleSessionScript) -> void:
	session.connect_terminals(A, D)
	session.connect_terminals(C, B)
	while not session.is_finished():
		session.submit()


## İlerleme anlık görüntüsü: [[kimlik, çözüm sayısı, çözüldü], ...] kimlik sırasıyla.
static func progress_rows(state: GameStateScript) -> Array:
	var result: Array = []
	for entry in state.get_cable_puzzle_progress_snapshot():
		result.append([String(entry.puzzle_id), entry.resolutions_used, entry.solved])
	return result


## Durumun karşılaştırılabilir tam özeti: kaynaklar, bayraklar, güven, zaman, görevler, ekipman, görünümler, ilerleme.
static func describe_state(state: GameStateScript) -> Array:
	var trust: Array = []
	for entry in state.get_trust_snapshot():
		trust.append([String(entry.source_actor_id), String(entry.target_actor_id), entry.value])
	var tasks: Array = []
	for task in state.get_tasks_snapshot():
		tasks.append([String(task.task_id), String(task.assigned_actor_id), task.remaining_units])
	return [state.get_resources_snapshot(), state.get_flags_snapshot(), trust,
			[state.get_night(), state.get_elapsed_units(), state.is_night_ended()], tasks,
			EquipmentFixtures.rows(state), state.get_occurrences_snapshot(), progress_rows(state)]


## Görev tanımları için kısa yol.
static func make_task(id: String, completion_effects: Array = []) -> TaskDataScript:
	return DecisionFixtures.make_task_definition(id, completion_effects)
