extends RefCounted
## Kablo arayüzü testleri için yardımcılar (K-033). Sahne, deterministik boyutlu bir SubViewport içine kurulur; girdi
## gerçek olaylarla (push_input) verilir. Oyun içeriği değildir.

const CableFixtures := preload("res://tests/fixtures/cable_fixtures.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")

const SCENE_PATH: String = "res://scenes/ui/cable_puzzle.tscn"
const DEFAULT_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_FRAMES: int = 2

## Düğüm adı ve yolu için özel karakterler içeren tarafsız kimlikler; yalnızca test verisi.
const ODD_LEFT_A: StringName = &"left/a:1"
const ODD_LEFT_B: StringName = &"left.b 2"
const ODD_RIGHT_A: StringName = &"right/a:1"
const ODD_RIGHT_B: StringName = &"right.b 2"


## Uyarıları da yakalar; ortak hata yakalayıcı uyarıları bilerek yok sayar.
class WarningCapture extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _warnings: PackedStringArray = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_warnings.append(rationale if not rationale.is_empty() else code)
		_mutex.unlock()

	func take_warnings() -> PackedStringArray:
		_mutex.lock()
		var result: PackedStringArray = _warnings
		_warnings = PackedStringArray()
		_mutex.unlock()
		return result


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func make_viewport(size: Vector2i = DEFAULT_SIZE) -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	tree().root.add_child(viewport)
	return viewport


## Sahneyi verilen görünüm alanına kurar; session verilirse setup ağaca girdikten sonra çağrılır.
static func mount(viewport: SubViewport, session: CablePuzzleSessionScript = null) -> CablePuzzleViewScript:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	var view: CablePuzzleViewScript = packed.instantiate() as CablePuzzleViewScript
	viewport.add_child(view)
	if session != null:
		view.setup(session)
	return view


static func settle(frames: int = SETTLE_FRAMES) -> void:
	for i in frames:
		await tree().process_frame


static func dispose(viewport: SubViewport) -> void:
	if is_instance_valid(viewport):
		viewport.queue_free()
	await tree().process_frame


## Standart düzen: solda terminal_a, terminal_c; sağda terminal_b, terminal_d; doğru a–b, c–d.
static func standard_session(max_submissions: int = 2) -> CablePuzzleSessionScript:
	return CableFixtures.start(max_submissions)


static func odd_session() -> CablePuzzleSessionScript:
	var terminals: Array = [
		CableFixtures.make_terminal(String(ODD_LEFT_A), CableFixtures.LEFT),
		CableFixtures.make_terminal(String(ODD_LEFT_B), CableFixtures.LEFT),
		CableFixtures.make_terminal(String(ODD_RIGHT_A), CableFixtures.RIGHT),
		CableFixtures.make_terminal(String(ODD_RIGHT_B), CableFixtures.RIGHT),
	]
	var connections: Array = [
		CableFixtures.make_connection(String(ODD_LEFT_A), String(ODD_RIGHT_A)),
		CableFixtures.make_connection(String(ODD_LEFT_B), String(ODD_RIGHT_B)),
	]
	return CablePuzzleSessionScript.create(CableFixtures.make_puzzle("puzzle_odd", terminals, connections))


## Düğmenin ortasına sol fare tıklaması (bas + bırak).
static func click(viewport: SubViewport, control: Control) -> void:
	var position: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		viewport.push_input(event)


## Tuşa bas + bırak.
static func key(viewport: SubViewport, keycode: Key, shift: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.shift_pressed = shift
		event.pressed = pressed
		viewport.push_input(event)


static func focus_owner(viewport: SubViewport) -> Control:
	return viewport.gui_get_focus_owner()


## Odak sahibi bu görünüme ait bir düğüm mü?
static func owns_focus(view: Node, viewport: SubViewport) -> bool:
	var focused: Control = viewport.gui_get_focus_owner()
	return focused != null and view.is_ancestor_of(focused)


static func check_button(view: Node) -> Button:
	return view.get_node("%Check") as Button


static func board(view: Node) -> Control:
	return view.get_node("%Board") as Control


static func feedback_text(view: Node) -> String:
	return (view.get_node("%Feedback") as Label).text


static func remaining_text(view: Node) -> String:
	return (view.get_node("%RemainingValue") as Label).text


## Bir taraftaki düğmeler, container sırasıyla.
static func column_buttons(view: Node, side: StringName) -> Array[Button]:
	var column: Node = view.get_node("%LeftTerminals" if side == CableFixtures.LEFT else "%RightTerminals")
	var result: Array[Button] = []
	for child: Node in column.get_children():
		result.append(child as Button)
	return result


## Önce sol, sonra sağ sütunun düğmeleri.
static func all_buttons(view: Node) -> Array[Button]:
	var result: Array[Button] = column_buttons(view, CableFixtures.LEFT)
	result.append_array(column_buttons(view, CableFixtures.RIGHT))
	return result


## Düğmenin taşıdığı terminal kimliği (metaveri).
static func terminal_of(button: Button) -> StringName:
	return button.get_meta(CablePuzzleViewScript.TERMINAL_META, &"")


## Oturumun karşılaştırılabilir özeti.
static func snapshot(session: CablePuzzleSessionScript) -> Array:
	return [session.get_connections(), session.get_status(), session.get_remaining_submissions(),
			session.get_incorrect_submissions()]
