class_name CablePuzzleView
extends CanvasLayer
## Kablo bulmacasının bağımsız arayüzü (K-033). Yalnızca setup ile verilen mevcut bir oturumu gösterir ve oyuncu
## girdisini o oturuma iletir.
##
## - Oturum açmaz, sonucu uygulamaz; hak sayacı, bağlantı kopyası veya doğru bağlantı bilgisi tutmaz. Bağlantı, sökme
##   ve kontrol kararlarının tek kaynağı oturumun dönüş değerleri ve okuyucularıdır.
## - puzzle_finished yalnızca bu görünümdeki kontrol oturumu solved veya failed yaptığında, kurulum başına en fazla bir
##   kez ve aynı oturumla yayılır. Görünüm önce kilitlenir; yayma son işlemdir. Bitmiş oturumla kurulum sinyal yaymaz.
## - Kilitli görünümde terminaller ve Kontrol devre dışıdır ve odak almaz; Kapat düğmesi kilitten muaftır. Oturum bu
##   görünümde bitince odak Kapat düğmesine geçer (puzzle_finished'den önce). setup ile kurulumda otomatik odak yalnızca
##   aktif oturumda ilk sol terminale verilir.
## - Kapat yalnızca close_requested yayar; oturuma, bağlantılara ve sayaçlara dokunmaz. Esc'yi bu görünüm ele almaz.
## - Terminal kimlikleri veri kimliğidir: düğüm adı veya düğüm yolu olarak kullanılmaz.

signal puzzle_finished(session: CablePuzzleSessionScript)
signal close_requested

const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CableBoardScript := preload("res://scripts/ui/cable_board.gd")

const LEFT_NODE_PREFIX: String = "LeftTerminal"
const RIGHT_NODE_PREFIX: String = "RightTerminal"
const TERMINAL_META: StringName = &"cable_terminal_id"
const TERMINAL_MIN_SIZE: Vector2 = Vector2(300, 72)
## Seçili terminalin renkten bağımsız metin işareti (yalnızca noktalama, çeviri gerektirmez).
const SELECTED_TEXT_FORMAT: String = "[ %s ]"
const SELECTED_BORDER_WIDTH: int = 6
const SELECTED_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0)
const SELECTED_STYLE_NAMES: Array[StringName] = [&"normal", &"hover", &"pressed"]

const TEXT_INCOMPLETE: StringName = &"UI_CABLE_INCOMPLETE"
const TEXT_INCORRECT: StringName = &"UI_CABLE_INCORRECT"
const TEXT_SOLVED: StringName = &"UI_CABLE_SOLVED"
const TEXT_FAILED: StringName = &"UI_CABLE_FAILED"

var _session: CablePuzzleSessionScript = null
var _buttons: Dictionary[StringName, Button] = {}
# Tab sırası: sol terminaller, sonra sağ terminaller (veri sırasıyla).
var _left_order: Array[StringName] = []
var _right_order: Array[StringName] = []
var _selected: StringName = &""
var _locked: bool = true
var _finish_emitted: bool = false
var _feedback_key: StringName = &""
var _selected_style: StyleBox = null

@onready var _left_terminals: VBoxContainer = %LeftTerminals
@onready var _right_terminals: VBoxContainer = %RightTerminals
@onready var _board: CableBoardScript = %Board
@onready var _remaining_value: Label = %RemainingValue
@onready var _feedback: Label = %Feedback
@onready var _check: Button = %Check
@onready var _close: Button = %Close


func _ready() -> void:
	_selected_style = _make_selected_style()
	_check.pressed.connect(_on_check_pressed)
	_close.pressed.connect(_on_close_pressed)
	# Container yeniden yerleşince uçlar kayar; board yeniden çizilir.
	for container: Container in [%Layout as Container, _left_terminals, _right_terminals]:
		container.sort_children.connect(_board.queue_redraw)
	_rebuild()


## Görünümü verilen oturumla baştan kurar; aynı veya farklı oturumla tekrar çağrılabilir. null akış hatasıdır: görünüm
## boş ve kilitli kalır. Ağaca girmeden çağrılırsa kurulum _ready'de yapılır.
func setup(session: CablePuzzleSessionScript) -> void:
	if session == null:
		push_error("CablePuzzleView.setup: tanımsız oturum; görünüm boş ve kilitli kalır")
	_session = session
	_selected = &""
	_finish_emitted = false
	_feedback_key = &""
	if is_node_ready():
		_rebuild()


func get_session() -> CablePuzzleSessionScript:
	return _session


func get_selected_terminal() -> StringName:
	return _selected


## Terminalin düğmesi; bu kurulumda yoksa null.
func get_terminal_button(terminal: StringName) -> Button:
	return _buttons.get(terminal)


func is_locked() -> bool:
	return _locked


## İlk uygun denetime odak verir: aktif oturumda zincirin ilk denetimi (ilk sol terminal), kilitli görünümde Kapat.
## Görünüm ağaçta değilse false.
func focus_first_available_control() -> bool:
	if not is_node_ready() or not is_inside_tree():
		return false
	if not _locked and not _left_order.is_empty():
		_buttons[_left_order[0]].grab_focus()
	else:
		_close.grab_focus()
	return true


# --- Kurulum ---

func _rebuild() -> void:
	_release_own_focus()
	_board.clear()
	_clear_terminals()
	_locked = _session == null or _session.is_finished()
	if _session != null:
		_build_column(_left_terminals, CableBoardScript.SIDE_LEFT, LEFT_NODE_PREFIX, _left_order)
		_build_column(_right_terminals, CableBoardScript.SIDE_RIGHT, RIGHT_NODE_PREFIX, _right_order)
	# Odak yolları _refresh sonunda, bütün yeni düğmeler ağaca eklendikten sonra kurulur.
	_refresh()
	if not _locked and is_inside_tree():
		_focus_first_terminal.call_deferred()


func _clear_terminals() -> void:
	for column: VBoxContainer in [_left_terminals, _right_terminals]:
		for child: Node in column.get_children():
			var button: Button = child as Button
			if button != null:
				for connection: Dictionary in button.pressed.get_connections():
					button.pressed.disconnect(connection["callable"])
			column.remove_child(child)
			child.queue_free()
	_buttons.clear()
	_left_order.clear()
	_right_order.clear()


func _build_column(column: VBoxContainer, side: StringName, prefix: String, order: Array[StringName]) -> void:
	var terminals: Array[StringName] = _session.get_terminal_ids(side)
	for i in terminals.size():
		var terminal: StringName = terminals[i]
		var button: Button = Button.new()
		button.name = "%s%d" % [prefix, i]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.custom_minimum_size = TERMINAL_MIN_SIZE
		button.set_meta(TERMINAL_META, terminal)
		button.pressed.connect(_on_terminal_pressed.bind(terminal))
		column.add_child(button)
		_buttons[terminal] = button
		order.append(terminal)


## Tab: sol → sağ → Kontrol → Kapat → başa; kilitli görünümde yalnızca Kapat (kendisine döner) ve terminallerin ve
## Kontrol'ün yolları boşaltılır. Oklar: sütun içinde yukarı/aşağı, son terminalden Kontrol'e; sol/sağ karşı sütunun
## aynı sırasına (karşı sütun kısaysa son öğeye); Kontrol sağ → Kapat, Kapat sol → Kontrol. Gidilecek yer yoksa düğüm
## kendisini gösterir.
func _link_focus() -> void:
	var left: Array[Button] = _buttons_of(_left_order)
	var right: Array[Button] = _buttons_of(_right_order)
	var chain: Array[Control] = []
	if not _locked:
		chain.append_array(left)
		chain.append_array(right)
		chain.append(_check)
	chain.append(_close)
	for i in chain.size():
		var control: Control = chain[i]
		control.focus_next = control.get_path_to(chain[(i + 1) % chain.size()])
		control.focus_previous = control.get_path_to(chain[(i - 1 + chain.size()) % chain.size()])
	for side: Side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
		_close.set_focus_neighbor(side, _close.get_path_to(_close))
	if _locked:
		var inactive: Array[Control] = [_check]
		inactive.append_array(left)
		inactive.append_array(right)
		for control in inactive:
			control.focus_next = NodePath()
			control.focus_previous = NodePath()
			for side: Side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
				control.set_focus_neighbor(side, NodePath())
		return
	_link_column(left, right, SIDE_RIGHT)
	_link_column(right, left, SIDE_LEFT)
	_check.focus_neighbor_top = _check.get_path_to(left.back() if not left.is_empty() else _check)
	for side: Side in [SIDE_BOTTOM, SIDE_LEFT]:
		_check.set_focus_neighbor(side, _check.get_path_to(_check))
	_check.focus_neighbor_right = _check.get_path_to(_close)
	_close.focus_neighbor_left = _close.get_path_to(_check)
	_close.focus_neighbor_top = _close.get_path_to(left.back() if not left.is_empty() else _close)


func _link_column(column: Array[Button], other: Array[Button], toward_other: Side) -> void:
	var away: Side = SIDE_LEFT if toward_other == SIDE_RIGHT else SIDE_RIGHT
	for i in column.size():
		var button: Button = column[i]
		button.focus_neighbor_top = button.get_path_to(column[i - 1] if i > 0 else button)
		button.focus_neighbor_bottom = button.get_path_to(column[i + 1] if i + 1 < column.size() else _check)
		var across: Control = other[mini(i, other.size() - 1)] if not other.is_empty() else button
		button.set_focus_neighbor(toward_other, button.get_path_to(across))
		button.set_focus_neighbor(away, button.get_path_to(button))


func _buttons_of(order: Array[StringName]) -> Array[Button]:
	var result: Array[Button] = []
	for terminal: StringName in order:
		result.append(_buttons[terminal])
	return result


# --- Girdi ---

func _on_terminal_pressed(terminal: StringName) -> void:
	if _locked or _session == null or not _buttons.has(terminal):
		return
	_feedback_key = &""
	if not _session.get_partner(terminal).is_empty():
		_session.disconnect_terminal(terminal)
	elif _selected.is_empty():
		_selected = terminal
	elif _selected == terminal:
		_selected = &""
	else:
		# Aynı taraf seçimi devralır; diğer her sonuçta seçim temizlenir.
		var result: StringName = _session.connect_terminals(_selected, terminal)
		_selected = terminal if result == CablePuzzleSessionScript.MOVE_SAME_SIDE else &""
	_refresh()


func _on_check_pressed() -> void:
	if _locked or _session == null:
		return
	var session: CablePuzzleSessionScript = _session
	var result: StringName = session.submit()
	match result:
		CablePuzzleSessionScript.SUBMIT_INCOMPLETE:
			_feedback_key = TEXT_INCOMPLETE
		CablePuzzleSessionScript.SUBMIT_INCORRECT:
			_feedback_key = TEXT_INCORRECT
	_refresh()
	if result != CablePuzzleSessionScript.SUBMIT_SOLVED and result != CablePuzzleSessionScript.SUBMIT_FAILED:
		return
	if _finish_emitted:
		return
	_finish_emitted = true
	# Dinleyici burada setup çağırabilir veya görünümü silebilir; sonrasında hiçbir duruma dokunulmaz.
	puzzle_finished.emit(session)


## Yalnızca kapatma isteğini bildirir; oturuma, bağlantılara, sayaçlara ve kilide dokunmaz.
func _on_close_pressed() -> void:
	close_requested.emit()


# --- Görünüm ---

## Her şeyi oturumdan yeniden okur; dışarıda bitmiş oturum da sinyalsiz kilitlenir. Kilide geçiş anında odak Kapat'a
## verilir.
func _refresh() -> void:
	var lock_started: bool = false
	if _session != null and _session.is_finished():
		_feedback_key = TEXT_SOLVED if _session.get_status() == CablePuzzleSessionScript.STATUS_SOLVED else TEXT_FAILED
		if not _locked:
			_locked = true
			lock_started = true
			_release_own_focus()
	if _locked or (not _selected.is_empty() and not _session.get_partner(_selected).is_empty()):
		_selected = &""

	var focus_mode_value: Control.FocusMode = Control.FOCUS_NONE if _locked else Control.FOCUS_ALL
	var anchors: Dictionary[StringName, Control] = {}
	var sides: Dictionary[StringName, StringName] = {}
	for terminal: StringName in _buttons:
		var button: Button = _buttons[terminal]
		var selected: bool = terminal == _selected
		button.text = SELECTED_TEXT_FORMAT % terminal if selected else String(terminal)
		button.disabled = _locked
		button.focus_mode = focus_mode_value
		for style_name: StringName in SELECTED_STYLE_NAMES:
			if selected:
				button.add_theme_stylebox_override(style_name, _selected_style)
			else:
				button.remove_theme_stylebox_override(style_name)
		anchors[terminal] = button
		sides[terminal] = _session.get_terminal_side(terminal)
	_check.disabled = _locked
	_check.focus_mode = focus_mode_value

	_remaining_value.text = str(_session.get_remaining_submissions()) if _session != null else ""
	_feedback.text = tr(_feedback_key) if not _feedback_key.is_empty() else ""
	if _session == null:
		_board.clear()
	else:
		_board.show_cables(anchors, sides, _session.get_connections())
	_link_focus()
	if lock_started and is_inside_tree():
		_close.grab_focus()


func _focus_first_terminal() -> void:
	if _locked or not is_inside_tree() or _left_order.is_empty():
		return
	var button: Button = _buttons.get(_left_order[0])
	if button != null and not button.disabled and button.is_inside_tree():
		button.grab_focus()


func _release_own_focus() -> void:
	if not is_inside_tree():
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()


## Temanın düğme stilinden türetilir; yalnızca çerçeve kalınlaşır ve açılır.
func _make_selected_style() -> StyleBox:
	var style: StyleBoxFlat = _check.get_theme_stylebox(&"normal").duplicate() as StyleBoxFlat
	if style == null:
		style = StyleBoxFlat.new()
	style.set_border_width_all(SELECTED_BORDER_WIDTH)
	style.border_color = SELECTED_BORDER_COLOR
	return style
