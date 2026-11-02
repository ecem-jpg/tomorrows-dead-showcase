extends "res://tests/framework/test_case.gd"
## CableBoard: açık taraf verisiyle bağlantı noktası, çizgi sayısı, boyut değişimi, geçersiz uç ve taraf kayıtları,
## tek tip görünüm ve modelin değişmemesi (K-033).

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const CableBoardScript := preload("res://scripts/ui/cable_board.gd")
const CableTerminalDataScript := preload("res://scripts/data/cable_terminal_data.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

const BOARD_PATH: String = "res://scripts/ui/cable_board.gd"
const ANCHOR_SIZE: Vector2 = Vector2(100, 40)

var _viewport: SubViewport
var _board: CableBoardScript


func test_side_constants_match_terminal_data() -> void:
	assert_eq(CableBoardScript.SIDE_LEFT, CableTerminalDataScript.SIDE_LEFT)
	assert_eq(CableBoardScript.SIDE_RIGHT, CableTerminalDataScript.SIDE_RIGHT)


func test_explicit_side_picks_edge_regardless_of_screen_position() -> void:
	_mount_board()
	# Görsel konumlar bilerek ters: left taraflı uç ekranın sağında, right taraflı uç solunda.
	var left_anchor: Control = _anchor(Vector2(600, 100))
	var right_anchor: Control = _anchor(Vector2(50, 300))
	var anchors: Dictionary[StringName, Control] = _anchors_of({&"p": left_anchor, &"q": right_anchor})
	_board.show_cables(anchors, _sides_of({&"p": &"left", &"q": &"right"}), [[&"p", &"q"]])
	var segments: Array[PackedVector2Array] = _board.get_segments()
	assert_eq(segments.size(), 1)
	if segments.size() == 1:
		assert_eq(segments[0][0], Vector2(700, 120), "left → düğmenin sağ kenar ortası.")
		assert_eq(segments[0][1], Vector2(50, 320), "right → düğmenin sol kenar ortası.")
	# Taraflar değişince yalnızca kenar değişir; düğüm konumu ve adı tarafı belirlemez.
	_board.show_cables(anchors, _sides_of({&"p": &"right", &"q": &"left"}), [[&"p", &"q"]])
	segments = _board.get_segments()
	assert_eq(segments.size(), 1)
	if segments.size() == 1:
		assert_eq(segments[0][0], Vector2(600, 120))
		assert_eq(segments[0][1], Vector2(150, 320))
	await _finish()


func test_missing_or_invalid_side_is_skipped_silently() -> void:
	_mount_board()
	var anchors: Dictionary[StringName, Control] = {
		&"p": _anchor(Vector2(0, 0)), &"q": _anchor(Vector2(300, 0)), &"r": _anchor(Vector2(0, 100)),
		&"s": _anchor(Vector2(300, 100)),
	}
	var connections: Array = [[&"p", &"q"], [&"r", &"s"]]
	var sides: Dictionary[StringName, StringName] = {&"p": &"left", &"q": &"right", &"r": &"up"}
	_board.show_cables(anchors, sides, connections)
	assert_eq(_board.get_segments().size(), 1, "Eksik (s) ve geçersiz (r) taraflı kablo atlanmalı.")
	assert_eq(_board.get_port_points().size(), 2)
	_board.queue_redraw()
	await UiFixtures.settle()
	assert_eq(connections, [[&"p", &"q"], [&"r", &"s"]], "Girdi değişmemeli.")
	assert_eq(sides.size(), 3)
	await _finish()


func test_segment_count_matches_connections_and_inputs_are_copied() -> void:
	_mount_board()
	var anchors: Dictionary[StringName, Control] = {
		&"p": _anchor(Vector2(0, 0)), &"q": _anchor(Vector2(300, 0)), &"r": _anchor(Vector2(0, 100)),
		&"s": _anchor(Vector2(300, 100)),
	}
	var sides: Dictionary[StringName, StringName] = {&"p": &"left", &"r": &"left", &"q": &"right", &"s": &"right"}
	var connections: Array = [[&"p", &"s"], [&"q", &"r"]]
	_board.show_cables(anchors, sides, connections)
	assert_eq(_board.get_segments().size(), 2)
	connections.append([&"x", &"y"])
	sides.clear()
	assert_eq(_board.get_segments().size(), 2, "Board girdilerin kopyasıyla çalışmalı.")
	var connected: Array[bool] = []
	for port: Dictionary in _board.get_port_points():
		connected.append(port["connected"])
	assert_eq(connected, [true, true, true, true])
	_board.show_cables(anchors, _sides_of({&"p": &"left", &"q": &"right"}), [])
	assert_eq(_board.get_segments().size(), 0)
	assert_eq(_board.get_port_points().map(func(port: Dictionary) -> bool: return port["connected"]), [false, false])
	_board.clear()
	assert_eq(_board.get_segments().size(), 0)
	assert_eq(_board.get_port_points().size(), 0)
	await _finish()


func test_freed_or_detached_anchor_is_skipped_without_errors() -> void:
	_mount_board()
	var p: Control = _anchor(Vector2(0, 0))
	var q: Control = _anchor(Vector2(300, 0))
	var r: Control = _anchor(Vector2(0, 100))
	var s: Control = _anchor(Vector2(300, 100))
	_board.show_cables(_anchors_of({&"p": p, &"q": q, &"r": r, &"s": s}),
			_sides_of({&"p": &"left", &"q": &"right", &"r": &"left", &"s": &"right"}), [[&"p", &"q"], [&"r", &"s"]])
	q.free()
	_board.remove_child(s)
	assert_eq(_board.get_segments().size(), 0)
	assert_eq(_board.get_port_points().size(), 2)
	_board.queue_redraw()
	await UiFixtures.settle()
	assert_eq(take_engine_errors(), PackedStringArray(), "Serbest bırakılmış uç hata üretmemeli.")
	s.free()
	await _finish()


func test_resize_updates_port_coordinates_in_scene() -> void:
	_viewport = UiFixtures.make_viewport()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	var view: CablePuzzleViewScript = UiFixtures.mount(_viewport, session)
	await UiFixtures.settle()
	UiFixtures.click(_viewport, view.get_terminal_button(&"terminal_a"))
	UiFixtures.click(_viewport, view.get_terminal_button(&"terminal_b"))
	_board = UiFixtures.board(view) as CableBoardScript
	var before: Array[PackedVector2Array] = _board.get_segments()
	_viewport.size = Vector2i(1920, 1080)
	await UiFixtures.settle()
	var after: Array[PackedVector2Array] = _board.get_segments()
	assert_eq(after.size(), 1)
	assert_ne(after, before, "Boyut değişince uç koordinatları güncellenmeli.")
	var left: Rect2 = _local_rect(view.get_terminal_button(&"terminal_a"))
	var right: Rect2 = _local_rect(view.get_terminal_button(&"terminal_b"))
	if after.size() == 1:
		assert_eq(after[0][0], Vector2(left.end.x, left.get_center().y))
		assert_eq(after[0][1], Vector2(right.position.x, right.get_center().y))
	await _finish()


func test_drawing_does_not_change_session_and_uses_one_style() -> void:
	_viewport = UiFixtures.make_viewport()
	var session: CablePuzzleSessionScript = UiFixtures.standard_session()
	var view: CablePuzzleViewScript = UiFixtures.mount(_viewport, session)
	await UiFixtures.settle()
	for terminal: StringName in [&"terminal_a", &"terminal_d", &"terminal_c", &"terminal_b"]:
		UiFixtures.click(_viewport, view.get_terminal_button(terminal))
	var before: Array = UiFixtures.snapshot(session)
	_board = UiFixtures.board(view) as CableBoardScript
	for i in 3:
		_board.queue_redraw()
		_board.get_segments()
		_board.get_port_points()
		await UiFixtures.settle()
	_viewport.size = Vector2i(1600, 900)
	await UiFixtures.settle()
	assert_eq(UiFixtures.snapshot(session), before, "Çizim modeli değiştirmemeli.")
	# Taraf yalnızca geometri içindir; board doğruluk, sonuç veya durum bilmez ve tek kablo rengi kullanır.
	var source: String = FileAccess.get_file_as_string(BOARD_PATH)
	for token: String in ["correct", "incorrect", "solved", "failed", "required", "status", "session"]:
		assert_false(_code_of(source).to_lower().contains(token), "Board '%s' izi taşımamalı." % token)
	assert_eq(_code_of(source).count("Color("), 1, "Board tek bir kablo rengi tanımlamalı.")
	await _finish()


func _mount_board() -> void:
	_viewport = UiFixtures.make_viewport()
	_board = CableBoardScript.new()
	_board.position = Vector2.ZERO
	_board.size = Vector2(UiFixtures.DEFAULT_SIZE)
	_viewport.add_child(_board)


func _anchor(position: Vector2) -> Control:
	var anchor: Control = Control.new()
	anchor.position = position
	anchor.size = ANCHOR_SIZE
	_board.add_child(anchor)
	return anchor


static func _anchors_of(source: Dictionary) -> Dictionary[StringName, Control]:
	var result: Dictionary[StringName, Control] = {}
	for terminal: StringName in source:
		result[terminal] = source[terminal]
	return result


static func _sides_of(source: Dictionary) -> Dictionary[StringName, StringName]:
	var result: Dictionary[StringName, StringName] = {}
	for terminal: StringName in source:
		result[terminal] = source[terminal]
	return result


func _local_rect(control: Control) -> Rect2:
	return _board.get_global_transform().affine_inverse() * control.get_global_rect()


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


## Yorumları ayıklanmış kaynak (dizgi içindeki # korunur).
static func _code_of(source: String) -> String:
	var lines: PackedStringArray = []
	for line: String in source.split("\n"):
		var in_string: bool = false
		var cut: int = line.length()
		for i in line.length():
			if line[i] == "\"":
				in_string = not in_string
			elif line[i] == "#" and not in_string:
				cut = i
				break
		lines.append(line.substr(0, cut))
	return "\n".join(lines)
