extends "res://tests/framework/test_case.gd"
## Kablo bulmacası verisinin yüklenmesi, kopyalanması ve doğrulanması (K-019). Yalnızca tarafsız kimlikler.

const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CableTerminalDataScript := preload("res://scripts/data/cable_terminal_data.gd")
const CableConnectionDataScript := preload("res://scripts/data/cable_connection_data.gd")
const CablePuzzleRulesDataScript := preload("res://scripts/data/cable_puzzle_rules_data.gd")
const CablePuzzleOutcomeDataScript := preload("res://scripts/data/cable_puzzle_outcome_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CableFixtures := preload("res://tests/fixtures/cable_fixtures.gd")
const DecisionFixtures := preload("res://tests/fixtures/decision_fixtures.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/cable"
const FIXTURE_PATH: String = "res://tests/fixtures/cable/puzzle_a.tres"


# --- Tanım ve yükleme ---

func test_defaults_are_empty_typed_and_fields_are_fixed() -> void:
	var puzzle: CablePuzzleDataScript = CablePuzzleDataScript.new()
	assert_eq([puzzle.id, puzzle.terminals.size(), puzzle.required_connections.size(), puzzle.rules,
			puzzle.start_conditions.size(), puzzle.success, puzzle.failure], ["", 0, 0, null, 0, null, null])
	assert_eq(puzzle.terminals.get_typed_script(), CableTerminalDataScript)
	assert_eq(puzzle.required_connections.get_typed_script(), CableConnectionDataScript)
	assert_eq(puzzle.start_conditions.get_typed_script(), ConditionDataScript)
	var rules: CablePuzzleRulesDataScript = CablePuzzleRulesDataScript.new()
	assert_eq([rules.equipment_id, rules.max_submissions, rules.max_resolutions], ["", 0, 0])
	var outcome: CablePuzzleOutcomeDataScript = CablePuzzleOutcomeDataScript.new()
	assert_eq([outcome.effects.size(), outcome.action_id], [0, ""])
	assert_eq(outcome.effects.get_typed_script(), EffectDataScript)
	# Alan listeleri sabitlenir: yeni bir alan eklenirse copy() ve bu test birlikte güncellenmelidir.
	assert_eq(_stored_fields(puzzle), ["id", "terminals", "required_connections", "rules", "start_conditions",
			"success", "failure"] as Array[String])
	assert_eq(_stored_fields(CableTerminalDataScript.new()), ["id", "side"] as Array[String])
	assert_eq(_stored_fields(CableConnectionDataScript.new()), ["terminal_a", "terminal_b"] as Array[String])
	assert_eq(_stored_fields(rules), ["equipment_id", "max_submissions", "max_resolutions"] as Array[String])
	assert_eq(_stored_fields(outcome), ["effects", "action_id"] as Array[String])


func test_fixture_loads_with_typed_sub_resources() -> void:
	var puzzle: CablePuzzleDataScript = _load_fixture()
	assert_true(puzzle != null, "Bulmaca dosyası yüklenemedi.")
	if puzzle == null:
		return
	assert_eq(puzzle.id, "puzzle_a")
	assert_eq(_describe_terminals(puzzle), [["terminal_a", &"left"], ["terminal_b", &"right"]])
	assert_true(puzzle.terminals[0].get_script() == CableTerminalDataScript)
	assert_eq(_describe_connections(puzzle), [["terminal_a", "terminal_b"]])
	assert_true(puzzle.required_connections[0].get_script() == CableConnectionDataScript)
	assert_true(puzzle.rules.get_script() == CablePuzzleRulesDataScript)
	assert_eq([puzzle.rules.equipment_id, puzzle.rules.max_submissions, puzzle.rules.max_resolutions],
			["equipment_a", 2, 1])
	assert_eq(puzzle.start_conditions.size(), 1)
	assert_true(puzzle.start_conditions[0].get_script() == ConditionDataScript)
	assert_eq([puzzle.start_conditions[0].kind, puzzle.start_conditions[0].equipment_id,
			puzzle.start_conditions[0].equipment_status], [&"equipment", "equipment_a", &"broken"])
	assert_true(puzzle.success.get_script() == CablePuzzleOutcomeDataScript)
	assert_true(puzzle.failure.get_script() == CablePuzzleOutcomeDataScript)
	assert_eq([puzzle.success.effects.size(), puzzle.success.effects[0].kind, puzzle.success.action_id],
			[1, &"equipment_repair", ""])
	assert_eq([puzzle.failure.effects.size(), puzzle.failure.effects[0].kind, puzzle.failure.effects[0].amount],
			[1, &"equipment_disable", 2])


func test_fixture_passes_data_and_puzzle_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(_load_fixture()), PackedStringArray())


# --- Kopyalama ---

func test_copy_keeps_every_value_in_new_instances() -> void:
	var source: CablePuzzleDataScript = _load_fixture()
	var copy: CablePuzzleDataScript = source.copy()
	assert_true(copy != null and copy.get_script() == CablePuzzleDataScript)
	assert_eq(_describe(copy), _describe(source))
	assert_eq(copy.terminals.get_typed_script(), CableTerminalDataScript)
	assert_eq(copy.required_connections.get_typed_script(), CableConnectionDataScript)
	assert_eq(copy.start_conditions.get_typed_script(), ConditionDataScript)
	assert_eq(copy.success.effects.get_typed_script(), EffectDataScript)
	var pairs: Array = [[copy, source], [copy.terminals, source.terminals], [copy.terminals[0], source.terminals[0]],
			[copy.required_connections, source.required_connections],
			[copy.required_connections[0], source.required_connections[0]], [copy.rules, source.rules],
			[copy.start_conditions, source.start_conditions], [copy.start_conditions[0], source.start_conditions[0]],
			[copy.success, source.success], [copy.success.effects, source.success.effects],
			[copy.success.effects[0], source.success.effects[0]], [copy.failure, source.failure],
			[copy.failure.effects[0], source.failure.effects[0]]]
	for i in pairs.size():
		assert_false(is_same(pairs[i][0], pairs[i][1]), "Paylaşılan örnek (#%d)" % i)


func test_later_changes_to_the_source_never_reach_the_copy() -> void:
	var source: CablePuzzleDataScript = _load_fixture()
	var copy: CablePuzzleDataScript = source.copy()
	var before: Array = _describe(copy)
	_corrupt(source)
	assert_eq(_describe(copy), before)
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(copy), PackedStringArray())


func test_later_changes_to_the_copy_never_reach_the_source() -> void:
	var source: CablePuzzleDataScript = _load_fixture()
	var before: Array = _describe(source)
	_corrupt(source.copy())
	assert_eq(_describe(source), before)
	assert_eq(_describe(_load_fixture()), before)


func test_copy_keeps_empty_records_in_place() -> void:
	var source: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a",
			[null, CableFixtures.make_terminal("terminal_a", &"left")], [null])
	source.start_conditions.append(null)
	source.success.effects.append(null)
	source.failure = null
	source.rules = null
	var copy: CablePuzzleDataScript = source.copy()
	assert_eq([copy.terminals.size(), copy.terminals[0], copy.terminals[1].id], [2, null, "terminal_a"])
	assert_eq([copy.required_connections.size(), copy.required_connections[0]], [1, null])
	assert_eq([copy.start_conditions.size(), copy.start_conditions[0]], [1, null])
	assert_eq([copy.success.effects.size(), copy.success.effects[0]], [1, null])
	assert_eq([copy.rules, copy.failure], [null, null])
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(copy), CablePuzzleSessionScript.get_puzzle_errors(source))


# --- Doğrulama ---

func test_null_puzzle_is_reported() -> void:
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(null), PackedStringArray(["Tanımsız bulmaca"]))


func test_standard_puzzle_is_valid() -> void:
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(CableFixtures.make_standard()), PackedStringArray())


func test_empty_puzzle_and_equipment_ids() -> void:
	var puzzle: CablePuzzleDataScript = CableFixtures.make_standard()
	puzzle.id = ""
	puzzle.rules.equipment_id = ""
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle),
			PackedStringArray(["Boş bulmaca kimliği", "Boş ekipman kimliği"]))


func test_empty_and_duplicate_terminal_ids() -> void:
	var terminals: Array = CableFixtures.standard_terminals()
	terminals.append(CableFixtures.make_terminal("", &"left"))
	terminals.append(CableFixtures.make_terminal("terminal_b", &"left"))
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", terminals,
			CableFixtures.standard_connections())
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle),
			PackedStringArray(["Boş terminal kimliği (#4)", "Tekrarlanan terminal kimliği: 'terminal_b'"]))


func test_invalid_side() -> void:
	var terminals: Array = CableFixtures.standard_terminals()
	terminals[3].side = &"top"
	terminals[1].side = &""
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", terminals,
			CableFixtures.standard_connections())
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle),
			PackedStringArray(["Terminal #1: geçersiz taraf ''", "Terminal #3: geçersiz taraf 'top'"]))


func test_undefined_terminal_in_connection() -> void:
	var connections: Array = [CableFixtures.make_connection("terminal_a", "terminal_x"),
			CableFixtures.make_connection("", "terminal_d"), CableFixtures.make_connection("terminal_c", "terminal_b")]
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", CableFixtures.standard_terminals(),
			connections)
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"Bağlantı #0: tanımsız terminal 'terminal_x'",
			"Bağlantı #1: tanımsız terminal ''",
			"'terminal_a': hiçbir zorunlu bağlantıda kullanılmıyor",
			"'terminal_d': hiçbir zorunlu bağlantıda kullanılmıyor"]))


func test_self_connection() -> void:
	var connections: Array = [CableFixtures.make_connection("terminal_a", "terminal_a")]
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a",
			[CableFixtures.make_terminal("terminal_a", &"left")], connections)
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"Bağlantı #0: terminal kendisine bağlanamaz ('terminal_a')",
			"'terminal_a': hiçbir zorunlu bağlantıda kullanılmıyor"]))


func test_same_side_connection() -> void:
	var connections: Array = [CableFixtures.make_connection("terminal_a", "terminal_c"),
			CableFixtures.make_connection("terminal_b", "terminal_d")]
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", CableFixtures.standard_terminals(),
			connections)
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"Bağlantı #0: aynı taraftaki terminaller ('terminal_a', 'terminal_c')",
			"Bağlantı #1: aynı taraftaki terminaller ('terminal_b', 'terminal_d')",
			"'terminal_a': hiçbir zorunlu bağlantıda kullanılmıyor",
			"'terminal_c': hiçbir zorunlu bağlantıda kullanılmıyor",
			"'terminal_b': hiçbir zorunlu bağlantıda kullanılmıyor",
			"'terminal_d': hiçbir zorunlu bağlantıda kullanılmıyor"]))


func test_duplicate_connection_including_reversed() -> void:
	var connections: Array = CableFixtures.standard_connections()
	connections.append(CableFixtures.make_connection("terminal_b", "terminal_a"))
	connections.append(CableFixtures.make_connection("terminal_c", "terminal_d"))
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", CableFixtures.standard_terminals(),
			connections)
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"Bağlantı #2: tekrarlanan bağlantı ('terminal_a', 'terminal_b')",
			"Bağlantı #3: tekrarlanan bağlantı ('terminal_c', 'terminal_d')"]))


func test_no_required_connection() -> void:
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a",
			[CableFixtures.make_terminal("terminal_a", &"left"), CableFixtures.make_terminal("terminal_b", &"right")], [])
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"Zorunlu bağlantı yok",
			"'terminal_a': hiçbir zorunlu bağlantıda kullanılmıyor",
			"'terminal_b': hiçbir zorunlu bağlantıda kullanılmıyor"]))
	var empty: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", [], [])
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(empty), PackedStringArray(["Zorunlu bağlantı yok"]))


func test_unused_terminal() -> void:
	var terminals: Array = CableFixtures.standard_terminals()
	terminals.append(CableFixtures.make_terminal("terminal_e", &"left"))
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", terminals,
			CableFixtures.standard_connections())
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle),
			PackedStringArray(["'terminal_e': hiçbir zorunlu bağlantıda kullanılmıyor"]))


func test_terminal_in_more_than_one_required_connection() -> void:
	var terminals: Array = CableFixtures.standard_terminals()
	var connections: Array = [CableFixtures.make_connection("terminal_a", "terminal_b"),
			CableFixtures.make_connection("terminal_d", "terminal_a"), CableFixtures.make_connection("terminal_c", "terminal_b")]
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", terminals, connections)
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"Bağlantı #1: 'terminal_a' birden fazla zorunlu bağlantıda (#0 ile)",
			"Bağlantı #2: 'terminal_b' birden fazla zorunlu bağlantıda (#0 ile)"]))


func test_limits_below_one() -> void:
	var puzzle: CablePuzzleDataScript = CableFixtures.make_standard()
	puzzle.rules.max_submissions = 0
	puzzle.rules.max_resolutions = -1
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"max_submissions 1 veya daha büyük olmalı (0)",
			"max_resolutions 1 veya daha büyük olmalı (-1)"]))
	puzzle.rules.max_submissions = 1
	puzzle.rules.max_resolutions = 1
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray())


func test_empty_records() -> void:
	var terminals: Array = CableFixtures.standard_terminals()
	terminals.insert(1, null)
	var connections: Array = CableFixtures.standard_connections()
	connections.append(null)
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", terminals, connections)
	puzzle.rules = null
	puzzle.start_conditions.append(DecisionFixtures.cond_flag("flag_a", true))
	puzzle.start_conditions.append(null)
	puzzle.success.effects.append(null)
	puzzle.failure.effects.append(DecisionFixtures.eff_add("res_a", 1))
	puzzle.failure.effects.append(null)
	assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), PackedStringArray([
			"Tanımsız terminal kaydı (#1)",
			"Tanımsız bağlantı kaydı (#2)",
			"Kural kaydı yok",
			"Tanımsız başlangıç koşulu kaydı (#1)",
			"Başarı etkisi #0 tanımsız",
			"Başarısızlık etkisi #1 tanımsız"]))
	puzzle.success = null
	puzzle.failure = null
	var errors: PackedStringArray = CablePuzzleSessionScript.get_puzzle_errors(puzzle)
	assert_eq(errors.slice(errors.size() - 2), PackedStringArray(["Başarı sonucu yok", "Başarısızlık sonucu yok"]))


func test_errors_are_deterministic_and_in_fixed_section_order() -> void:
	var expected: PackedStringArray = PackedStringArray([
			"Boş bulmaca kimliği",
			"Tekrarlanan terminal kimliği: 'terminal_a'",
			"Bağlantı #0: terminal kendisine bağlanamaz ('terminal_c')",
			"'terminal_c': hiçbir zorunlu bağlantıda kullanılmıyor",
			"'terminal_d': hiçbir zorunlu bağlantıda kullanılmıyor",
			"max_submissions 1 veya daha büyük olmalı (0)",
			"Tanımsız başlangıç koşulu kaydı (#0)",
			"Başarısızlık sonucu yok"])
	for attempt in 3:
		var terminals: Array = CableFixtures.standard_terminals()
		terminals.append(CableFixtures.make_terminal("terminal_a", &"right"))
		var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("", terminals,
				[CableFixtures.make_connection("terminal_c", "terminal_c"),
				CableFixtures.make_connection("terminal_b", "terminal_a")])
		puzzle.rules.max_submissions = 0
		puzzle.start_conditions.append(null)
		puzzle.failure = null
		assert_eq(CablePuzzleSessionScript.get_puzzle_errors(puzzle), expected, "Deneme #%d" % attempt)
	assert_eq(take_engine_errors().size(), 0)


# --- Yardımcılar ---

func _load_fixture() -> CablePuzzleDataScript:
	return ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as CablePuzzleDataScript


func _stored_fields(resource: Resource) -> Array[String]:
	var names: Array[String] = []
	for property in resource.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_true(property["usage"] & PROPERTY_USAGE_STORAGE, "Saklanmayan alan: %s" % property["name"])
			names.append(property["name"])
	return names


func _describe_terminals(puzzle: CablePuzzleDataScript) -> Array:
	var result: Array = []
	for terminal in puzzle.terminals:
		result.append([terminal.id, terminal.side])
	return result


func _describe_connections(puzzle: CablePuzzleDataScript) -> Array:
	var result: Array = []
	for connection in puzzle.required_connections:
		result.append([connection.terminal_a, connection.terminal_b])
	return result


func _describe_outcome(outcome: CablePuzzleOutcomeDataScript) -> Array:
	var effects: Array = []
	for effect in outcome.effects:
		effects.append([effect.kind, effect.equipment_id, effect.amount])
	return [effects, outcome.action_id]


func _describe(puzzle: CablePuzzleDataScript) -> Array:
	var conditions: Array = []
	for condition in puzzle.start_conditions:
		conditions.append([condition.kind, condition.equipment_id, condition.equipment_status])
	return [puzzle.id, _describe_terminals(puzzle), _describe_connections(puzzle),
			[puzzle.rules.equipment_id, puzzle.rules.max_submissions, puzzle.rules.max_resolutions], conditions,
			_describe_outcome(puzzle.success), _describe_outcome(puzzle.failure)]


# Bütün iç içe kayıtları yerinde bozar ve listelere öğe ekler; kopya bağımsızsa hiçbir etkisi görülmez.
func _corrupt(puzzle: CablePuzzleDataScript) -> void:
	puzzle.id = "puzzle_z"
	puzzle.terminals[0].id = "terminal_z"
	puzzle.terminals[1].side = &"left"
	puzzle.terminals.append(CableFixtures.make_terminal("terminal_y", &"right"))
	puzzle.required_connections[0].terminal_b = "terminal_a"
	puzzle.required_connections.append(null)
	puzzle.rules.equipment_id = "equipment_z"
	puzzle.rules.max_submissions = 0
	puzzle.rules.max_resolutions = 0
	puzzle.start_conditions[0].equipment_status = &"operational"
	puzzle.start_conditions.append(null)
	puzzle.success.effects[0].equipment_id = "equipment_z"
	puzzle.success.effects.append(null)
	puzzle.success.action_id = "action_z"
	puzzle.failure.effects[0].amount = 99
