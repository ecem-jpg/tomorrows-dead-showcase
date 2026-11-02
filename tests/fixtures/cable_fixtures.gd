extends RefCounted
## Kablo bulmacası testleri için tarafsız veri kurucuları (K-018, K-019). Oyun içeriği değildir.
## Standart düzen: solda terminal_a ve terminal_c, sağda terminal_b ve terminal_d; doğru bağlantılar a–b ve c–d.

const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CableTerminalDataScript := preload("res://scripts/data/cable_terminal_data.gd")
const CableConnectionDataScript := preload("res://scripts/data/cable_connection_data.gd")
const CablePuzzleRulesDataScript := preload("res://scripts/data/cable_puzzle_rules_data.gd")
const CablePuzzleOutcomeDataScript := preload("res://scripts/data/cable_puzzle_outcome_data.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

const LEFT: StringName = &"left"
const RIGHT: StringName = &"right"


static func make_terminal(id: String, side: StringName) -> CableTerminalDataScript:
	var terminal: CableTerminalDataScript = CableTerminalDataScript.new()
	terminal.id = id
	terminal.side = side
	return terminal


static func make_connection(terminal_a: String, terminal_b: String) -> CableConnectionDataScript:
	var connection: CableConnectionDataScript = CableConnectionDataScript.new()
	connection.terminal_a = terminal_a
	connection.terminal_b = terminal_b
	return connection


static func make_rules(max_submissions: int, max_resolutions: int = 1,
		equipment_id: String = "equipment_a") -> CablePuzzleRulesDataScript:
	var rules: CablePuzzleRulesDataScript = CablePuzzleRulesDataScript.new()
	rules.equipment_id = equipment_id
	rules.max_submissions = max_submissions
	rules.max_resolutions = max_resolutions
	return rules


## effects içindeki null değerler boş kayıt olarak eklenir.
static func make_outcome(effects: Array = [], action_id: String = "") -> CablePuzzleOutcomeDataScript:
	var outcome: CablePuzzleOutcomeDataScript = CablePuzzleOutcomeDataScript.new()
	for effect in effects:
		outcome.effects.append(effect)
	outcome.action_id = action_id
	return outcome


## terminals ve connections içindeki null değerler boş kayıt olarak eklenir. Sonuç dalları boş ama tanımlıdır.
## max_submissions 2 olan kurallar varsayılandır.
static func make_puzzle(id: String, terminals: Array, connections: Array) -> CablePuzzleDataScript:
	var puzzle: CablePuzzleDataScript = CablePuzzleDataScript.new()
	puzzle.id = id
	for terminal in terminals:
		puzzle.terminals.append(terminal)
	for connection in connections:
		puzzle.required_connections.append(connection)
	puzzle.rules = make_rules(2)
	puzzle.success = make_outcome()
	puzzle.failure = make_outcome()
	return puzzle


static func standard_terminals() -> Array:
	return [make_terminal("terminal_a", LEFT), make_terminal("terminal_c", LEFT),
			make_terminal("terminal_b", RIGHT), make_terminal("terminal_d", RIGHT)]


static func standard_connections() -> Array:
	return [make_connection("terminal_a", "terminal_b"), make_connection("terminal_c", "terminal_d")]


static func make_standard(max_submissions: int = 2) -> CablePuzzleDataScript:
	var puzzle: CablePuzzleDataScript = make_puzzle("puzzle_a", standard_terminals(), standard_connections())
	puzzle.rules.max_submissions = max_submissions
	return puzzle


static func start(max_submissions: int = 2) -> CablePuzzleSessionScript:
	return CablePuzzleSessionScript.create(make_standard(max_submissions))
