extends "res://tests/framework/test_case.gd"
## CablePuzzleViewScript kurulumu: null reddi, düğme üretimi ve sırası, güvenli düğüm adları, yeniden kurulum, bitmiş oturum,
## ağaca girmeden kurulum (K-033).

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const CableFixtures := preload("res://tests/fixtures/cable_fixtures.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CableBoardScript := preload("res://scripts/ui/cable_board.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

const LEFT: StringName = &"left"
const RIGHT: StringName = &"right"
const FOCUS_SIDES: Array[Side] = [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]


func test_null_setup_is_one_flow_error_and_leaves_empty_locked_view() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var view: CablePuzzleViewScript = UiFixtures.mount(viewport, UiFixtures.standard_session())
	await UiFixtures.settle()
	var emitted: Array = []
	view.puzzle_finished.connect(func(session: CablePuzzleSessionScript) -> void: emitted.append(session))
	view.setup(null)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, "null kurulum tam bir akış hatası üretmeli: %s" % " | ".join(errors))
	await UiFixtures.settle()
	assert_true(view.is_locked())
	assert_true(view.get_session() == null)
	assert_eq(UiFixtures.all_buttons(view).size(), 0)
	assert_true(UiFixtures.check_button(view).disabled)
	assert_eq(UiFixtures.feedback_text(view), "")
	assert_eq(UiFixtures.remaining_text(view), "")
	assert_eq((UiFixtures.board(view) as CableBoardScript).get_segments().size(), 0)
	assert_false(UiFixtures.owns_focus(view, viewport), "null kurulumda odak görünümde kalmamalı.")
	assert_eq(emitted.size(), 0)
	await UiFixtures.dispose(viewport)


func test_buttons_follow_session_terminals_and_data_order() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	var view: CablePuzzleViewScript = UiFixtures.mount(viewport, session)
	await UiFixtures.settle()
	for side: StringName in [LEFT, RIGHT]:
		var buttons: Array[Button] = UiFixtures.column_buttons(view, side)
		var shown: Array[StringName] = []
		for button: Button in buttons:
			shown.append(UiFixtures.terminal_of(button))
			assert_eq(button.text, String(UiFixtures.terminal_of(button)), "Etiket kimliğin kendisi olmalı.")
			assert_eq(button.auto_translate_mode, Node.AUTO_TRANSLATE_MODE_DISABLED)
			assert_true(view.get_terminal_button(UiFixtures.terminal_of(button)) == button)
		assert_eq(shown, session.get_terminal_ids(side), "%s sütunu oturumun veri sırasını izlemeli." % side)
	assert_true(view.get_terminal_button(&"terminal_x") == null, "Oturumda olmayan terminalin düğmesi olmamalı.")
	assert_eq(UiFixtures.remaining_text(view), str(session.get_remaining_submissions()))
	assert_false(view.is_locked())
	await UiFixtures.dispose(viewport)


func test_node_names_are_generated_and_odd_ids_are_safe() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var session: CablePuzzleSessionScript = UiFixtures.odd_session()
	var view: CablePuzzleViewScript = UiFixtures.mount(viewport, session)
	await UiFixtures.settle()
	assert_eq(take_engine_errors(), PackedStringArray(), "Özel karakterli kimlikler kurulumu bozmamalı.")
	var expected: Dictionary = {LEFT: ["LeftTerminal0", "LeftTerminal1"], RIGHT: ["RightTerminal0", "RightTerminal1"]}
	for side: StringName in [LEFT, RIGHT]:
		var names: Array[String] = []
		var buttons: Array[Button] = UiFixtures.column_buttons(view, side)
		for i in buttons.size():
			names.append(String(buttons[i].name))
			var terminal: StringName = session.get_terminal_ids(side)[i]
			assert_true(view.get_terminal_button(terminal) == buttons[i], "Düğme kimlikle bulunmalı: %s" % terminal)
			assert_eq(buttons[i].text, String(terminal), "Etiket gerçek kimliği korumalı.")
		assert_eq(names, expected[side])
	_assert_focus_paths_resolve(view, [])
	# Bağlama ve sökme doğru terminale uygulanır.
	UiFixtures.click(viewport, view.get_terminal_button(UiFixtures.ODD_LEFT_B))
	UiFixtures.click(viewport, view.get_terminal_button(UiFixtures.ODD_RIGHT_A))
	assert_eq(session.get_partner(UiFixtures.ODD_LEFT_B), UiFixtures.ODD_RIGHT_A)
	UiFixtures.click(viewport, view.get_terminal_button(UiFixtures.ODD_RIGHT_A))
	assert_eq(session.get_connections(), [])
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(viewport)


func test_resetup_replaces_nodes_selection_paths_and_board_anchors() -> void:
	var warnings: UiFixtures.WarningCapture = UiFixtures.WarningCapture.new()
	OS.add_logger(warnings)
	var viewport: SubViewport = UiFixtures.make_viewport()
	var first: CablePuzzleSessionScript = UiFixtures.standard_session()
	var view: CablePuzzleViewScript = UiFixtures.mount(viewport, first)
	await UiFixtures.settle()
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_a"))
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_d"))
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_c"))
	assert_eq(view.get_selected_terminal(), &"terminal_c")
	assert_true(UiFixtures.owns_focus(view, viewport))
	var old_ids: Array[int] = _button_ids(view)

	var second: CablePuzzleSessionScript = UiFixtures.odd_session()
	view.setup(second)
	assert_eq(view.get_selected_terminal(), &"", "Seçim sıfırlanmalı.")
	assert_false(UiFixtures.owns_focus(view, viewport) and old_ids.has(UiFixtures.focus_owner(viewport).get_instance_id()),
			"Odak eski düğümde kalmamalı.")
	var new_buttons: Array[Button] = UiFixtures.all_buttons(view)
	assert_eq(new_buttons.size(), 4, "Eski düğmeler container'dan hemen çıkarılmalı.")
	for button: Button in new_buttons:
		assert_false(old_ids.has(button.get_instance_id()))
	_assert_focus_paths_resolve(view, old_ids)
	await UiFixtures.settle()
	for id: int in old_ids:
		assert_true(instance_from_id(id) == null, "Eski düğme silinmeli.")
	# Board yalnızca yeni düğmeleri tanır: eski oturumun bağlantısı çizilmez.
	var board: CableBoardScript = UiFixtures.board(view) as CableBoardScript
	assert_eq(board.get_segments().size(), 0)
	assert_eq(board.get_port_points().size(), 4)
	for port: Dictionary in board.get_port_points():
		assert_true(second.has_terminal(port["terminal"]))
	assert_eq(first.get_connections(), [[&"terminal_a", &"terminal_d"]], "Yeniden kurulum eski oturumu değiştirmemeli.")
	OS.remove_logger(warnings)
	assert_eq(warnings.take_warnings(), PackedStringArray(), "Yeniden kurulumda uyarı olmamalı.")
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(viewport)


func test_resetup_with_same_session_is_safe_and_resets_signal_guard() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	var view: CablePuzzleViewScript = UiFixtures.mount(viewport, session)
	await UiFixtures.settle()
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_a"))
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_b"))
	view.setup(session)
	await UiFixtures.settle()
	assert_eq(session.get_connections(), [[&"terminal_a", &"terminal_b"]], "Mevcut bağlantılar oturumda kalır.")
	assert_eq((UiFixtures.board(view) as CableBoardScript).get_segments().size(), 1, "Bağlantı yeniden çizilmeli.")
	_assert_focus_paths_resolve(view, [])

	# Bir kurulumda bitiş sinyali yayan görünüm, yeni oturumla kurulunca yeniden yayabilir.
	var emitted: Array = []
	view.puzzle_finished.connect(func(finished: CablePuzzleSessionScript) -> void: emitted.append(finished))
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_c"))
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_d"))
	UiFixtures.click(viewport, UiFixtures.check_button(view))
	assert_true(view.is_locked())
	var next:CablePuzzleSessionScript = UiFixtures.standard_session()
	view.setup(next)
	await UiFixtures.settle()
	assert_false(view.is_locked())
	_solve(viewport, view)
	assert_eq(emitted.size(), 2)
	assert_true(emitted.size() == 2 and emitted[0] == session and emitted[1] == next)
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(viewport)


func test_solved_session_setup_is_locked_without_signal_or_focus() -> void:
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	session.connect_terminals(&"terminal_a", &"terminal_b")
	session.connect_terminals(&"terminal_c", &"terminal_d")
	assert_eq(session.submit(), CablePuzzleSessionScript.SUBMIT_SOLVED)
	await _assert_finished_setup(session, "UI_CABLE_SOLVED")


func test_failed_session_setup_is_locked_without_signal_or_focus() -> void:
	var session: CablePuzzleSessionScript = UiFixtures.standard_session(1)
	session.connect_terminals(&"terminal_a", &"terminal_d")
	session.connect_terminals(&"terminal_c", &"terminal_b")
	assert_eq(session.submit(), CablePuzzleSessionScript.SUBMIT_FAILED)
	await _assert_finished_setup(session, "UI_CABLE_FAILED")


func test_setup_before_entering_tree_builds_on_ready() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var view: CablePuzzleViewScript = (load(UiFixtures.SCENE_PATH) as PackedScene).instantiate() as CablePuzzleViewScript
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	view.setup(session)
	assert_true(view.get_session() == session)
	assert_true(view.get_terminal_button(&"terminal_a") == null, "Ağaca girmeden düğme kurulmaz.")
	viewport.add_child(view)
	await UiFixtures.settle()
	assert_eq(UiFixtures.column_buttons(view, LEFT).size(), 2)
	assert_eq(UiFixtures.column_buttons(view, RIGHT).size(), 2)
	assert_false(view.is_locked())
	assert_true(UiFixtures.focus_owner(viewport) == view.get_terminal_button(&"terminal_a"))
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(viewport)


func _assert_finished_setup(session: CablePuzzleSessionScript, expected_feedback: String) -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var view: CablePuzzleViewScript = UiFixtures.mount(viewport)
	var emitted: Array = []
	view.puzzle_finished.connect(func(finished: CablePuzzleSessionScript) -> void: emitted.append(finished))
	var before: Array = UiFixtures.snapshot(session)
	view.setup(session)
	await UiFixtures.settle()
	assert_true(view.is_locked())
	assert_eq(emitted.size(), 0, "Geçmiş sonuç için sinyal yayılmamalı.")
	assert_eq(UiFixtures.feedback_text(view), expected_feedback)
	assert_eq(UiFixtures.all_buttons(view).size(), 4)
	for button: Button in UiFixtures.all_buttons(view):
		assert_true(button.disabled and button.focus_mode == Control.FOCUS_NONE)
	assert_true(UiFixtures.check_button(view).disabled)
	assert_false(UiFixtures.owns_focus(view, viewport), "Bitmiş kurulumda odak verilmemeli.")
	assert_eq((UiFixtures.board(view) as CableBoardScript).get_segments().size(), 2, "Mevcut bağlantılar gösterilir.")
	UiFixtures.click(viewport, view.get_terminal_button(&"terminal_a"))
	UiFixtures.click(viewport, UiFixtures.check_button(view))
	assert_eq(UiFixtures.snapshot(session), before)
	assert_eq(emitted.size(), 0)
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(viewport)


func _solve(viewport: SubViewport, view: CablePuzzleViewScript) -> void:
	for terminal: StringName in [&"terminal_a", &"terminal_b", &"terminal_c", &"terminal_d"]:
		UiFixtures.click(viewport, view.get_terminal_button(terminal))
	UiFixtures.click(viewport, UiFixtures.check_button(view))


func _button_ids(view: CablePuzzleViewScript) -> Array[int]:
	var result: Array[int] = []
	for button: Button in UiFixtures.all_buttons(view):
		result.append(button.get_instance_id())
	return result


## Bütün odak yolları bu kurulumun düğmelerine veya Kontrol'e çözülür; eski düğümlere hiçbiri ulaşmaz.
func _assert_focus_paths_resolve(view: CablePuzzleViewScript, old_ids: Array[int]) -> void:
	var check: Button = UiFixtures.check_button(view)
	# Kapat düğmesi de odak zincirinin parçasıdır.
	var allowed: Array[Control] = [check, view.get_node("%Close") as Control]
	allowed.append_array(UiFixtures.all_buttons(view))
	for control: Control in allowed:
		var paths: Array[NodePath] = [control.focus_next, control.focus_previous]
		for side: Side in FOCUS_SIDES:
			paths.append(control.get_focus_neighbor(side))
		for path: NodePath in paths:
			var target: Node = control.get_node_or_null(path)
			assert_true(target != null and allowed.has(target), "%s: odak yolu geçersiz: %s" % [control.name, path])
			assert_false(target != null and old_ids.has(target.get_instance_id()), "Odak yolu eski düğüme gidiyor.")
