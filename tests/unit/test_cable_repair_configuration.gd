extends "res://tests/framework/test_case.gd"
## CableRepairSystem yapılandırma doğrulaması (K-032): bağımlılıklar, katalog, durum/katalog eşleşmesi, hata sırası,
## katalog kopyası ve hatalı yapılandırmada hiçbir şeyin değişmemesi. Yalnızca tarafsız kimlikler.

const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const CablePuzzleProgressStateScript := preload("res://scripts/core/cable_puzzle_progress_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CableRepairSystemScript := preload("res://scripts/systems/cable_repair_system.gd")
const CablePuzzleStartResultScript := preload("res://scripts/systems/cable_puzzle_start_result.gd")
const CableRepairResultScript := preload("res://scripts/systems/cable_repair_result.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const EquipmentFixtures := preload("res://tests/fixtures/equipment_fixtures.gd")
const Fixtures := preload("res://tests/fixtures/cable_repair_fixtures.gd")


# Durum kurallarıyla üretilemeyen tutarsız bir kaydı yapılandırma testine sunar.
class ForgedProgressState extends "res://scripts/core/game_state.gd":
	func get_cable_puzzle_progress_snapshot() -> Array[CablePuzzleProgressStateScript]:
		var forged: Array[CablePuzzleProgressStateScript] = [CablePuzzleProgressStateScript.new(&"puzzle_a", 0, true)]
		return forged


func test_valid_configuration_has_no_errors() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle("puzzle_a",
			[EquipmentFixtures.eff_repair("equipment_b")], [EquipmentFixtures.eff_disable("equipment_b", 2)], "action_a",
			"action_b")])
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_eq([system.has_puzzle(&"puzzle_a"), system.has_puzzle(&"puzzle_x")], [true, false])
	assert_eq(system.get_puzzle_ids(), [&"puzzle_a"] as Array[StringName])


func test_missing_dependencies() -> void:
	var no_puzzles: Array[CablePuzzleDataScript] = []
	var system: CableRepairSystemScript = CableRepairSystemScript.new(null, null, null, null, null, no_puzzles)
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.size() == 1 and errors[0].contains("bütün bağımlı sistemler verilmelidir"), " | ".join(errors))
	assert_eq(system.get_configuration_errors(), PackedStringArray(["Oyun durumu verilmedi", "Kaynak sistemi verilmedi",
			"Güven sistemi verilmedi", "Zaman sistemi verilmedi", "Görev tamamlanma sistemi verilmedi"]))


func test_null_and_duplicate_puzzle_records() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var system: CableRepairSystemScript = Fixtures.make_system(world, [null, Fixtures.make_puzzle(), Fixtures.make_puzzle()])
	assert_eq(system.get_configuration_errors(),
			PackedStringArray(["Tanımsız bulmaca kaydı (#0)", "Tekrarlanan bulmaca kimliği: 'puzzle_a'"]))
	assert_eq(system.get_puzzle_ids(), [&"puzzle_a"] as Array[StringName])


func test_puzzle_layout_errors_are_prefixed() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle()
	puzzle.rules.max_submissions = 0
	puzzle.success = null
	var system: CableRepairSystemScript = Fixtures.make_system(world, [puzzle])
	assert_eq(system.get_configuration_errors(), PackedStringArray([
			"'puzzle_a': max_submissions 1 veya daha büyük olmalı (0)", "'puzzle_a': Başarı sonucu yok"]))


func test_undefined_equipment() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle()
	puzzle.rules.equipment_id = "equipment_x"
	assert_eq(Fixtures.make_system(world, [puzzle]).get_configuration_errors(),
			PackedStringArray(["'puzzle_a': tanımsız ekipman 'equipment_x'"]))


func test_start_condition_errors_use_shared_messages() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle()
	puzzle.start_conditions.append(DecisionFixtures.cond_flag("flag_a", true))
	puzzle.start_conditions.append(DecisionFixtures.cond_resource("res_x", &"ge", 1))
	var errors: PackedStringArray = Fixtures.make_system(world, [puzzle]).get_configuration_errors()
	assert_true(errors.size() == 1 and errors[0].begins_with("'puzzle_a' başlangıç koşulu #1: ")
			and errors[0].contains("tanımsız kaynak 'res_x'"), " | ".join(errors))


func test_effect_errors_for_undefined_resource_trust_and_equipment() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_add("res_x", 1)],
			[DecisionFixtures.eff_trust("actor_a", "actor_c", 1), EquipmentFixtures.eff_disable("equipment_x", 1)])
	assert_eq(Fixtures.make_system(world, [puzzle]).get_configuration_errors(), PackedStringArray([
			"'puzzle_a' başarı etkisi #0: tanımsız kaynak 'res_x'",
			"'puzzle_a' başarısızlık etkisi #0: tanımsız güven ilişkisi 'actor_a' -> 'actor_c'",
			"'puzzle_a' başarısızlık etkisi #1: tanımsız ekipman 'equipment_x'"]))


func test_same_target_twice_in_one_branch() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	# Aynı hedef farklı dallarda serbesttir; yalnızca aynı dal içinde hatadır.
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a",
			[DecisionFixtures.eff_add("res_a", 1), DecisionFixtures.eff_spend("res_a", 1)], [DecisionFixtures.eff_add("res_a", 1)])
	assert_eq(Fixtures.make_system(world, [puzzle]).get_configuration_errors(),
			PackedStringArray(["'puzzle_a' başarı etkisi #1: aynı hedefe birden fazla etki (#0 ile)"]))


func test_undefined_action() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a", [], [], "action_x", "action_y")
	assert_eq(Fixtures.make_system(world, [puzzle]).get_configuration_errors(), PackedStringArray([
			"'puzzle_a' başarı: tanımsız eylem 'action_x'", "'puzzle_a' başarısızlık: tanımsız eylem 'action_y'"]))


func test_catalog_and_state_records_must_match_both_ways() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world(["puzzle_c", "puzzle_b"])
	var system: CableRepairSystemScript = Fixtures.make_system(world,
			[Fixtures.make_puzzle("puzzle_b"), Fixtures.make_puzzle("puzzle_a")])
	assert_eq(system.get_configuration_errors(), PackedStringArray([
			"Başlangıç durumunda kablo bulmacası yok: 'puzzle_a'",
			"Katalogda tanımsız kablo bulmacası: 'puzzle_c'"]))


func test_resolutions_above_the_catalog_limit() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	for count in [1, 2]:
		var change: GameStateChangeScript = GameStateChangeScript.new()
		change.cable_puzzle_progress.append(CablePuzzleProgressStateScript.new(&"puzzle_a", count, false))
		assert_true(world.state.apply_changes(change))
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle()
	puzzle.rules.max_resolutions = 1
	assert_eq(Fixtures.make_system(world, [puzzle]).get_configuration_errors(),
			PackedStringArray(["'puzzle_a': çözüm sayısı sınırı aşıyor (2 > 1)"]))


func test_solved_record_with_zero_resolutions() -> void:
	var state: GameStateScript = ForgedProgressState.new(Fixtures.make_setup())
	var world: DecisionFixtures.World = Fixtures.make_world([], state)
	assert_eq(Fixtures.make_system(world, [Fixtures.make_puzzle()]).get_configuration_errors(),
			PackedStringArray(["'puzzle_a': çözülmüş ama çözüm sayısı 0"]))


func test_partial_trust_state_is_a_configuration_error() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	assert_true(world.state.set_trust_state(partial))
	var errors: PackedStringArray = Fixtures.make_system(world, [Fixtures.make_puzzle()]).get_configuration_errors()
	assert_true(errors.size() > 0, "Kısmi güven durumu hata vermedi.")
	for error in errors:
		assert_true(error.begins_with("TrustSystem: "), error)


func test_errors_are_deterministic_in_fixed_order() -> void:
	var expected: PackedStringArray = PackedStringArray([
			"Tanımsız bulmaca kaydı (#1)",
			"'puzzle_b': max_resolutions 1 veya daha büyük olmalı (0)",
			"'puzzle_b': tanımsız ekipman 'equipment_x'",
			"'puzzle_b' başarı etkisi #0: tanımsız kaynak 'res_x'",
			"'puzzle_b' başarısızlık: tanımsız eylem 'action_x'",
			"Tekrarlanan bulmaca kimliği: 'puzzle_a'",
			"Başlangıç durumunda kablo bulmacası yok: 'puzzle_b'",
			"Katalogda tanımsız kablo bulmacası: 'puzzle_c'"])
	for attempt in 3:
		var world: DecisionFixtures.World = Fixtures.make_world(["puzzle_c", "puzzle_a"])
		var broken: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_b", [DecisionFixtures.eff_add("res_x", 1)], [], "",
				"action_x")
		broken.rules.max_resolutions = 0
		broken.rules.equipment_id = "equipment_x"
		var system: CableRepairSystemScript = Fixtures.make_system(world,
				[Fixtures.make_puzzle("puzzle_a"), null, broken, Fixtures.make_puzzle("puzzle_a")])
		assert_eq(system.get_configuration_errors(), expected, "Deneme #%d" % attempt)
	assert_eq(take_engine_errors().size(), 0)


func test_catalog_is_copied_at_construction() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	Fixtures.start(world)
	var puzzle: CablePuzzleDataScript = Fixtures.make_puzzle("puzzle_a", [DecisionFixtures.eff_add("res_b", 1)])
	var system: CableRepairSystemScript = Fixtures.make_system(world, [puzzle])
	puzzle.id = "puzzle_z"
	puzzle.rules.max_resolutions = 0
	puzzle.rules.equipment_id = "equipment_x"
	puzzle.success.effects[0].resource_id = "res_x"
	puzzle.success.effects.append(null)
	puzzle.failure = null
	puzzle.start_conditions.append(DecisionFixtures.cond_flag("flag_x", true))
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	var started: CablePuzzleStartResultScript = system.start_session(&"puzzle_a")
	assert_true(started.is_started())
	Fixtures.solve(started.session)
	assert_true(system.apply_result(started.session).ok)
	assert_eq(world.state.get_resource(&"res_b"), 1)


func test_invalid_configuration_changes_nothing_in_start_preview_and_apply() -> void:
	var world: DecisionFixtures.World = Fixtures.make_world()
	Fixtures.start(world)
	var system: CableRepairSystemScript = Fixtures.make_system(world, [Fixtures.make_puzzle("puzzle_a",
			[DecisionFixtures.eff_add("res_b", 1)], [], "action_a")])
	var session: CablePuzzleSessionScript = system.start_session(&"puzzle_a").session
	Fixtures.solve(session)
	var partial: Array[TrustRelationshipStateScript] = [TrustRelationshipStateScript.new(&"actor_a", &"actor_b", 60)]
	assert_true(world.state.set_trust_state(partial))
	var before: Array = Fixtures.describe_state(world.state)
	var signals: Array = [0]
	world.state.state_changed.connect(func() -> void: signals[0] += 1)
	assert_eq(system.preview_result(session).failure, CableRepairResultScript.FAILURE_INVALID_CONFIGURATION)
	assert_eq(system.apply_result(session).failure, CableRepairResultScript.FAILURE_INVALID_CONFIGURATION)
	assert_eq(system.start_session(&"puzzle_a").failure, CablePuzzleStartResultScript.FAILURE_INVALID_CONFIGURATION)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 3, " | ".join(errors))
	for error in errors:
		assert_true(error.contains("geçersiz yapılandırma"), error)
	assert_eq(Fixtures.describe_state(world.state), before)
	assert_eq(signals[0], 0)
