extends "res://tests/framework/test_case.gd"
## CablePuzzleSession testleri: saf kablo birleştirme mantığı (K-019). Yalnızca tarafsız kimlikler.
## Standart düzen (CableFixtures): solda terminal_a ve terminal_c, sağda terminal_b ve terminal_d; doğrusu a–b, c–d.

const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CableFixtures := preload("res://tests/fixtures/cable_fixtures.gd")

const A: StringName = &"terminal_a"
const B: StringName = &"terminal_b"
const C: StringName = &"terminal_c"
const D: StringName = &"terminal_d"


# --- Oluşturma ---

func test_create_starts_in_progress_with_no_connections() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start(3)
	assert_true(session != null)
	assert_eq([session.get_puzzle_id(), session.get_status(), session.is_finished(), session.get_connections()],
			[&"puzzle_a", &"in_progress", false, []])
	assert_eq([session.get_max_submissions(), session.get_incorrect_submissions(), session.get_remaining_submissions()],
			[3, 0, 3])
	assert_false(session.is_fully_connected())
	assert_eq(take_engine_errors().size(), 0)


func test_create_with_an_invalid_puzzle_is_a_flow_error() -> void:
	assert_true(CablePuzzleSessionScript.create(null) == null)
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.size() == 1 and errors[0].contains("Tanımsız bulmaca"), " | ".join(errors))
	var puzzle: CablePuzzleDataScript = CableFixtures.make_standard()
	puzzle.rules.max_submissions = 0
	assert_true(CablePuzzleSessionScript.create(puzzle) == null)
	errors = take_engine_errors()
	assert_true(errors.size() == 1 and errors[0].contains("max_submissions 1 veya daha büyük olmalı (0)"),
			" | ".join(errors))


func test_terminals_are_listed_by_side_in_data_order() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	assert_eq(session.get_terminal_ids(&"left"), [A, C] as Array[StringName])
	assert_eq(session.get_terminal_ids(&"right"), [B, D] as Array[StringName])
	assert_eq(session.get_terminal_ids(&"top"), [] as Array[StringName])
	assert_eq([session.get_terminal_side(A), session.get_terminal_side(D)], [&"left", &"right"])
	assert_eq([session.has_terminal(A), session.has_terminal(&"terminal_x")], [true, false])
	assert_eq(take_engine_errors().size(), 0)


func test_canonical_pair_is_order_independent() -> void:
	assert_eq(CablePuzzleSessionScript.canonical_pair(B, A), [A, B])
	assert_eq(CablePuzzleSessionScript.canonical_pair(A, B), [A, B])
	assert_eq(CablePuzzleSessionScript.canonical_pair(D, A), [A, D])


# --- Bağlantılar ---

func test_connections_are_undirected_and_canonical() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	assert_eq(session.connect_terminals(D, C), &"connected")
	assert_eq(session.connect_terminals(B, A), &"connected")
	assert_eq(session.get_connections(), [[A, B], [C, D]])
	assert_eq([session.get_partner(A), session.get_partner(B), session.get_partner(C), session.get_partner(D)],
			[B, A, D, C])
	assert_true(session.is_fully_connected())


func test_connect_and_disconnect() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	assert_eq(session.connect_terminals(A, D), &"connected")
	assert_eq(session.disconnect_terminal(D), &"disconnected")
	assert_eq([session.get_connections(), session.get_partner(A), session.get_partner(D)], [[], &"", &""])
	assert_eq(session.connect_terminals(A, B), &"connected")
	assert_eq(session.disconnect_terminal(A), &"disconnected")
	assert_eq(session.get_connections(), [])
	assert_eq(take_engine_errors().size(), 0)


func test_disconnecting_an_unconnected_terminal_is_a_normal_rejection() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	session.connect_terminals(A, B)
	assert_eq(session.disconnect_terminal(C), &"not_connected")
	assert_eq(session.get_connections(), [[A, B]])
	assert_eq(take_engine_errors().size(), 0)


func test_occupied_terminal_is_rejected() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	assert_eq(session.connect_terminals(A, B), &"connected")
	assert_eq(session.connect_terminals(C, B), &"terminal_occupied")
	assert_eq(session.connect_terminals(A, D), &"terminal_occupied")
	assert_eq(session.connect_terminals(B, A), &"terminal_occupied")
	assert_eq(session.get_connections(), [[A, B]])
	assert_eq(take_engine_errors().size(), 0)


func test_same_side_and_self_connection_are_normal_rejections() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	assert_eq(session.connect_terminals(A, C), &"same_side")
	assert_eq(session.connect_terminals(D, B), &"same_side")
	assert_eq(session.connect_terminals(A, A), &"self_connection")
	assert_eq(session.get_connections(), [])
	# Ret, dolu terminalden önce gelir: bağlı bir terminalle aynı taraf yine same_side.
	session.connect_terminals(A, B)
	assert_eq(session.connect_terminals(C, A), &"same_side")
	assert_eq(session.connect_terminals(B, B), &"self_connection")
	assert_eq(session.get_connections(), [[A, B]])
	assert_eq(take_engine_errors().size(), 0)


func test_unknown_terminal_is_a_flow_error_and_changes_nothing() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	session.connect_terminals(A, B)
	assert_eq(session.connect_terminals(&"terminal_x", D), &"unknown_terminal")
	assert_eq(session.connect_terminals(C, &"terminal_x"), &"unknown_terminal")
	assert_eq(session.disconnect_terminal(&"terminal_x"), &"unknown_terminal")
	assert_eq(session.get_partner(&"terminal_x"), &"")
	assert_eq(session.get_terminal_side(&""), &"")
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 5, " | ".join(errors))
	for error in errors:
		assert_true(error.contains("tanımsız terminal"), error)
	assert_true(errors[0].contains("connect_terminals") and errors[0].contains("'terminal_x'"), errors[0])
	assert_eq(session.get_connections(), [[A, B]])
	assert_eq([session.get_status(), session.get_incorrect_submissions()], [&"in_progress", 0])


func test_wrong_connections_can_be_made_and_fixed_before_submitting() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start(1)
	assert_eq(session.connect_terminals(A, D), &"connected")
	assert_eq(session.connect_terminals(C, B), &"connected")
	assert_eq(session.get_connections(), [[A, D], [B, C]])
	session.disconnect_terminal(A)
	session.disconnect_terminal(B)
	session.connect_terminals(A, B)
	session.connect_terminals(C, D)
	assert_eq(session.submit(), &"solved")
	assert_eq(session.get_incorrect_submissions(), 0)


# --- Kontrol ---

func test_incomplete_submission_uses_no_submission() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start(1)
	assert_eq(session.submit(), &"incomplete")
	session.connect_terminals(A, D)
	assert_eq(session.submit(), &"incomplete")
	session.connect_terminals(C, D) # dolu; düzen hâlâ eksik
	assert_eq(session.submit(), &"incomplete")
	assert_eq([session.get_status(), session.get_incorrect_submissions(), session.get_remaining_submissions()],
			[&"in_progress", 0, 1])


func test_wrong_complete_submission_uses_a_submission() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start(3)
	session.connect_terminals(A, D)
	session.connect_terminals(C, B)
	assert_eq(session.submit(), &"incorrect")
	assert_eq([session.get_status(), session.get_incorrect_submissions(), session.get_remaining_submissions()],
			[&"in_progress", 1, 2])
	# Bağlantılar kontrol sonrasında olduğu gibi kalır ve düzenlenebilir.
	assert_eq(session.get_connections(), [[A, D], [B, C]])
	assert_eq(session.disconnect_terminal(A), &"disconnected")


func test_partially_correct_complete_layout_is_incorrect() -> void:
	var puzzle: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", [
			CableFixtures.make_terminal("terminal_a", &"left"), CableFixtures.make_terminal("terminal_c", &"left"),
			CableFixtures.make_terminal("terminal_e", &"left"), CableFixtures.make_terminal("terminal_b", &"right"),
			CableFixtures.make_terminal("terminal_d", &"right"), CableFixtures.make_terminal("terminal_f", &"right")],
			[CableFixtures.make_connection("terminal_a", "terminal_b"), CableFixtures.make_connection("terminal_c", "terminal_d"),
			CableFixtures.make_connection("terminal_e", "terminal_f")])
	var session: CablePuzzleSessionScript = CablePuzzleSessionScript.create(puzzle)
	session.connect_terminals(A, B)
	session.connect_terminals(C, &"terminal_f")
	session.connect_terminals(&"terminal_e", D)
	assert_eq(session.submit(), &"incorrect")
	assert_eq(session.get_incorrect_submissions(), 1)


func test_correct_submission_solves() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	session.connect_terminals(B, A)
	session.connect_terminals(C, D)
	assert_eq(session.submit(), &"solved")
	assert_eq([session.get_status(), session.is_finished(), session.get_incorrect_submissions()],
			[&"solved", true, 0])


func test_correct_submission_after_wrong_ones_solves() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start(2)
	session.connect_terminals(A, D)
	session.connect_terminals(C, B)
	assert_eq(session.submit(), &"incorrect")
	session.disconnect_terminal(A)
	session.disconnect_terminal(C)
	session.connect_terminals(A, B)
	session.connect_terminals(C, D)
	assert_eq(session.submit(), &"solved")
	assert_eq([session.get_status(), session.get_incorrect_submissions(), session.get_remaining_submissions()],
			[&"solved", 1, 1])


func test_last_wrong_submission_fails() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start(2)
	session.connect_terminals(A, D)
	session.connect_terminals(C, B)
	assert_eq(session.submit(), &"incorrect")
	assert_eq(session.submit(), &"failed")
	assert_eq([session.get_status(), session.is_finished(), session.get_incorrect_submissions(),
			session.get_remaining_submissions()], [&"failed", true, 2, 0])


func test_single_submission_puzzle_fails_on_the_first_wrong_complete_submission() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start(1)
	session.connect_terminals(A, D)
	assert_eq(session.submit(), &"incomplete")
	session.connect_terminals(C, B)
	assert_eq(session.submit(), &"failed")
	assert_eq(session.get_status(), &"failed")


func test_finished_session_never_changes() -> void:
	var solved: CablePuzzleSessionScript = CableFixtures.start()
	solved.connect_terminals(A, B)
	solved.connect_terminals(C, D)
	solved.submit()
	var failed: CablePuzzleSessionScript = CableFixtures.start(1)
	failed.connect_terminals(A, D)
	failed.connect_terminals(C, B)
	failed.submit()
	for session: CablePuzzleSessionScript in [solved, failed]:
		var before: Array = _snapshot(session)
		assert_eq(session.disconnect_terminal(A), &"finished")
		assert_eq(session.disconnect_terminal(C), &"finished")
		assert_eq(session.connect_terminals(A, C), &"finished")
		assert_eq(session.connect_terminals(A, A), &"finished")
		assert_eq(session.submit(), &"finished")
		assert_eq(session.submit(), &"finished")
		assert_eq(_snapshot(session), before)
	assert_eq([solved.get_status(), failed.get_status()], [&"solved", &"failed"])
	assert_eq(take_engine_errors().size(), 0)


# --- Bağımsızlık ve determinizm ---

func test_returned_arrays_are_independent_copies() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	session.connect_terminals(A, B)
	var connections: Array = session.get_connections()
	connections[0][1] = D
	connections.append([C, D])
	var left: Array[StringName] = session.get_terminal_ids(&"left")
	left.clear()
	assert_eq(session.get_connections(), [[A, B]])
	assert_eq(session.get_terminal_ids(&"left"), [A, C] as Array[StringName])
	assert_false(is_same(session.get_connections(), session.get_connections()))


func test_session_is_unaffected_by_later_puzzle_changes() -> void:
	var puzzle: CablePuzzleDataScript = CableFixtures.make_standard(1)
	var session: CablePuzzleSessionScript = CablePuzzleSessionScript.create(puzzle)
	puzzle.id = "puzzle_z"
	puzzle.terminals[1].side = &"right"
	puzzle.terminals.append(CableFixtures.make_terminal("terminal_e", &"left"))
	puzzle.required_connections[0].terminal_b = "terminal_d"
	puzzle.required_connections[1].terminal_b = "terminal_b"
	puzzle.rules.max_submissions = 5
	assert_eq([session.get_puzzle_id(), session.get_max_submissions(), session.has_terminal(&"terminal_e")],
			[&"puzzle_a", 1, false])
	assert_eq(session.connect_terminals(A, C), &"same_side")
	session.connect_terminals(A, B)
	session.connect_terminals(C, D)
	assert_eq(session.submit(), &"solved")


func test_data_order_does_not_change_results() -> void:
	var shuffled: CablePuzzleDataScript = CableFixtures.make_puzzle("puzzle_a", [
			CableFixtures.make_terminal("terminal_d", &"right"), CableFixtures.make_terminal("terminal_c", &"left"),
			CableFixtures.make_terminal("terminal_b", &"right"), CableFixtures.make_terminal("terminal_a", &"left")],
			[CableFixtures.make_connection("terminal_d", "terminal_c"), CableFixtures.make_connection("terminal_b", "terminal_a")])
	var log_standard: Array = _play_script(CablePuzzleSessionScript.create(CableFixtures.make_standard()))
	var log_shuffled: Array = _play_script(CablePuzzleSessionScript.create(shuffled))
	assert_eq(log_shuffled, log_standard)


func test_same_moves_produce_same_results() -> void:
	var first: Array = _play_script(CableFixtures.start())
	var second: Array = _play_script(CableFixtures.start())
	assert_eq(first, second)
	assert_eq(first[first.size() - 1], [&"solved", [[A, B], [C, D]], 1])


func test_session_is_pure_logic_without_signals_or_scene_dependencies() -> void:
	var session: CablePuzzleSessionScript = CableFixtures.start()
	var script: GDScript = session.get_script() as GDScript
	assert_eq(script.get_instance_base_type(), &"RefCounted")
	assert_eq(script.get_script_signal_list().size(), 0)
	# Yüklenen bütün betikler yalnızca bulmaca verisi ve oturumun kendisidir.
	var allowed: Array[String] = ["res://scripts/systems/cable_puzzle_session.gd", "res://scripts/data/cable_puzzle_data.gd",
			"res://scripts/data/cable_puzzle_outcome_data.gd", "res://scripts/data/cable_terminal_data.gd",
			"res://scripts/data/cable_connection_data.gd"]
	var constants: Dictionary = script.get_script_constant_map()
	for constant_name: String in constants:
		var value: Variant = constants[constant_name]
		if value is Script:
			assert_true(allowed.has((value as Script).resource_path), "Beklenmeyen bağımlılık: %s" % constant_name)


# --- Yardımcılar ---

func _snapshot(session: CablePuzzleSessionScript) -> Array:
	return [session.get_status(), session.get_connections(), session.get_incorrect_submissions(),
			session.get_remaining_submissions(), session.is_fully_connected()]


# Sabit bir hamle dizisi; her adımın sonucu ve son durum kaydedilir.
func _play_script(session: CablePuzzleSessionScript) -> Array:
	var moves: Array = []
	moves.append(session.connect_terminals(A, C))
	moves.append(session.connect_terminals(D, A))
	moves.append(session.submit())
	moves.append(session.connect_terminals(B, C))
	moves.append(session.get_connections())
	moves.append(session.submit())
	moves.append(session.disconnect_terminal(B))
	moves.append(session.disconnect_terminal(B))
	moves.append(session.disconnect_terminal(D))
	moves.append(session.connect_terminals(A, B))
	moves.append(session.connect_terminals(D, C))
	moves.append(session.submit())
	moves.append(session.connect_terminals(A, D))
	moves.append([session.get_status(), session.get_connections(), session.get_incorrect_submissions()])
	return moves
