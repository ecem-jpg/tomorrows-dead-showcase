class_name MiniGameHost
extends Node
## Ana arayüzün üzerinde kablo mini oyununu açan ve kapatan katman (K-033).
##
## - Düz bir Node'dur; kablo görünümü kendi CanvasLayer'ıyla bunun altında örneklenir (layer 10); CanvasLayer iç içe
##   geçmez. Oyun sistemlerini, presenter'ı ve oyun durumunu bilmez; oturumu yalnızca görünüme iletir, sonuç uygulamaz.
## - Açıkken kilitlenen Root'un focus_behavior_recursive ve mouse_behavior_recursive değerleri DISABLED yapılır; kapanışta
##   önceki gerçek değerler aynen geri yüklenir. Kaydedilen odak sahibi hâlâ geçerli ve etkinse ona dönülür.
## - puzzle_finished açılış başına en fazla bir kez finished olarak iletilir; görünüm otomatik kapanmaz. Kapatma (Esc,
##   Kapat veya close) oturumu değiştirmez ve sonuç sinyali yaymaz. Bağlantılar kapanışta koparılır; eski görünümden gelen
##   gecikmiş sinyaller etkisizdir. Kapandıktan sonra görünüm ve oturum başvurusu tutulmaz.
## - Esc yalnızca açıkken dinlenir ve işlenmiş olarak işaretlenir; _process yoktur.

signal finished(session: RefCounted)
signal closed

const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")
const MINI_GAME_SCENE: PackedScene = preload("res://scenes/ui/cable_puzzle.tscn")
const MINI_GAME_LAYER: int = 10
const CANCEL_ACTION: StringName = &"ui_cancel"

var _root: Control = null
var _view: CablePuzzleViewScript = null
var _forwarded: bool = false
var _saved_focus: WeakRef = null
var _saved_focus_behavior: Control.FocusBehaviorRecursive = Control.FOCUS_BEHAVIOR_INHERITED
var _saved_mouse_behavior: Control.MouseBehaviorRecursive = Control.MOUSE_BEHAVIOR_INHERITED


func _ready() -> void:
	set_process_unhandled_input(false)


func _exit_tree() -> void:
	# Ağaçtan çıkarken açık kalan kilit sinyal ve odak işlemi olmadan geri yüklenir.
	if _view != null:
		_dismiss(false)


func _unhandled_input(event: InputEvent) -> void:
	if _view != null and event.is_action_pressed(CANCEL_ACTION):
		get_viewport().set_input_as_handled()
		close()


## Kilitlenecek Root'u belirler. Mini oyun açıkken reddedilir (false); null kapalıyken kabul edilir.
func set_locked_root(root: Control) -> bool:
	if is_open():
		return false
	_root = root
	return true


## Oturumla mini oyunu açar. Oturum, Root ve durum doğrulanmadan hiçbir şey kilitlenmez; geçersiz oturum, verilmemiş
## Root, ağaç dışı veya zaten açık durumda false.
func open(session: Variant) -> bool:
	if is_open() or not is_inside_tree() or _root == null or not is_instance_valid(_root) or not _root.is_inside_tree():
		return false
	# Görünümün beklediği oturum türü görünümden alınır; başka değer setup'a hiç verilmez.
	if not (session is RefCounted) or (session as RefCounted).get_script() != CablePuzzleViewScript.CablePuzzleSessionScript:
		return false
	var view: CablePuzzleViewScript = MINI_GAME_SCENE.instantiate() as CablePuzzleViewScript
	if view == null:
		return false

	var focused: Control = get_viewport().gui_get_focus_owner()
	_saved_focus = weakref(focused) if focused != null and _root.is_ancestor_of(focused) else null
	_saved_focus_behavior = _root.focus_behavior_recursive
	_saved_mouse_behavior = _root.mouse_behavior_recursive
	_root.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_root.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	if _saved_focus != null:
		focused.release_focus()

	view.layer = MINI_GAME_LAYER
	_view = view
	_forwarded = false
	add_child(view)
	view.puzzle_finished.connect(_on_view_finished.bind(view))
	view.close_requested.connect(_on_view_close_requested.bind(view))
	view.setup(session)
	set_process_unhandled_input(true)
	_focus_entry.call_deferred(view)
	return true


## Açık mini oyunu kapatır; açık değilse false.
func close() -> bool:
	if _view == null:
		return false
	_dismiss(true)
	return true


func is_open() -> bool:
	return _view != null


## Yalnızca gözlem içindir (testler); üretim akışı buna dayanmaz. Açık değilse null.
func get_view() -> CanvasLayer:
	return _view


# Görünümü koparır ve siler, kilidi geri yükler. notify: odak dönüşü ve closed sinyali.
func _dismiss(notify: bool) -> void:
	var view: CablePuzzleViewScript = _view
	_view = null
	_forwarded = false
	set_process_unhandled_input(false)
	for connection: Dictionary in view.puzzle_finished.get_connections():
		view.puzzle_finished.disconnect(connection["callable"])
	for connection: Dictionary in view.close_requested.get_connections():
		view.close_requested.disconnect(connection["callable"])
	# Ağaçtan çıkış sırasında ebeveyn çocuk çıkaramaz; görünüm yalnızca silinmek üzere bırakılır.
	if notify and view.get_parent() == self:
		remove_child(view)
	view.queue_free()
	var previous: Control = null if _saved_focus == null else _saved_focus.get_ref() as Control
	_saved_focus = null
	if _root != null and is_instance_valid(_root):
		_root.focus_behavior_recursive = _saved_focus_behavior
		_root.mouse_behavior_recursive = _saved_mouse_behavior
	if not notify:
		return
	if _can_restore(previous):
		previous.grab_focus()
	closed.emit()


func _can_restore(control: Control) -> bool:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree() or not control.is_visible_in_tree():
		return false
	if control.get_focus_mode_with_override() == Control.FOCUS_NONE:
		return false
	return not (control is BaseButton and (control as BaseButton).disabled)


func _focus_entry(view: CablePuzzleViewScript) -> void:
	if view == _view and is_instance_valid(view):
		view.focus_first_available_control()


func _on_view_finished(session: RefCounted, view: CablePuzzleViewScript) -> void:
	if view != _view or _forwarded:
		return
	_forwarded = true
	finished.emit(session)


func _on_view_close_requested(view: CablePuzzleViewScript) -> void:
	if view == _view:
		close()
