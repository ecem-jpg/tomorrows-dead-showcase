class_name MainHudView
extends Node
## Ana arayüzün görünümü: yalnızca kendisine verilen MainHudModel'i gösterir ve kullanıcı niyetini sinyalle bildirir.
##
## - Presenter'ı, sistemleri veya oyun durumunu bilmez; komut uygulamaz ve kural değerlendirmez.
## - show_model modeli kopyalar, dinamik satırları aynı karede ağaçtan çıkarıp yeniden kurar ve hiçbir sinyal yaymaz.
## - Model kimlikleri düğüm adı veya düğüm yolu yapılmaz: dinamik düğümler sayaçlı ad alır (ChoiceButton0 …); kimlik
##   düğme metaverisinde ve basma geri çağrısının bağlı argümanında taşınır. Kimlikler çevrilmeden ham gösterilir.
## - Odak zinciri yalnızca etkin eylemlerden kurulur: tamir → seçenekler → görev atamaları → Bekle → Sonraki gece →
##   başa. Devre dışı düğmeler odak almaz. Yenileme mevcut geçerli odağı korur; kaybolan dinamik odak aynı kimlikli
##   yeni düğmeye, o yoksa ilk etkin eyleme geçer; etkin eylem yoksa görünüme ait odak bırakılır.
## - Mini oyun MiniGameHost ile açılır; oturum opak olarak iletilir. Açıkken HUD Root'u host kilitler, show_model HUD'a
##   odak vermez. Tamamlanma repair_finished olarak bir kez dışarı verilir. Kapanışta host geçerli eski odağı geri
##   vermediyse ilk etkin eyleme geçilir.

signal assign_requested(task_id: StringName)
signal choice_requested(choice_id: StringName)
signal wait_requested
signal next_night_requested
signal repair_requested(puzzle_id: StringName)
signal repair_finished(session: RefCounted)

const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")
const MiniGameHostScript := preload("res://scripts/ui/mini_game_host.gd")

const ID_META: StringName = &"hud_id"
const ACTION_MIN_HEIGHT: float = 72.0
const SEPARATOR: String = " · "

const TEXT_EMPTY: StringName = &"UI_HUD_EMPTY"
const TEXT_NIGHT: StringName = &"UI_HUD_NIGHT"
const TEXT_TIME: StringName = &"UI_HUD_TIME"
const TEXT_DECISION: StringName = &"UI_HUD_DECISION"
const TEXT_ADVICE: StringName = &"UI_HUD_ADVICE"
const TEXT_ADVICE_NONE: StringName = &"UI_HUD_ADVICE_NONE"
const TEXT_REPAIR: StringName = &"UI_HUD_REPAIR"
const TEXT_ENDING: StringName = &"UI_HUD_ENDING"
const TEXT_NO_SESSION: StringName = &"UI_HUD_NO_SESSION"
## Görünür durumların metin anahtarları; durum yalnızca renkle ifade edilmez.
const STATUS_TEXTS: Dictionary = {
	&"operational": &"UI_HUD_STATUS_OPERATIONAL",
	&"broken": &"UI_HUD_STATUS_BROKEN",
	&"disabled": &"UI_HUD_STATUS_DISABLED",
}
const PRESENCE_TEXTS: Dictionary = {
	&"present": &"UI_HUD_BODY_PRESENT",
	&"permanent": &"UI_HUD_BODY_PERMANENT",
}

var _model: MainHudModelScript = null
# Etkin eylemlerin odak sırası.
var _chain: Array[Button] = []

@onready var _night_label: Label = %NightLabel
@onready var _time_label: Label = %TimeLabel
@onready var _resource_list: HBoxContainer = %ResourceList
@onready var _body_list: VBoxContainer = %BodyList
@onready var _equipment_list: VBoxContainer = %EquipmentList
@onready var _repair_list: VBoxContainer = %RepairList
@onready var _decision_label: Label = %DecisionLabel
@onready var _advice_label: Label = %AdviceLabel
@onready var _choice_list: VBoxContainer = %ChoiceList
@onready var _task_list: VBoxContainer = %TaskList
@onready var _assignment_list: VBoxContainer = %AssignmentList
@onready var _wait_button: Button = %WaitButton
@onready var _next_night_button: Button = %NextNightButton
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _ending_panel: PanelContainer = %EndingPanel
@onready var _ending_label: Label = %EndingLabel
@onready var _root: Control = %Root
@onready var _host: MiniGameHostScript = %MiniGameHost


func _ready() -> void:
	_wait_button.pressed.connect(_on_wait_pressed)
	_next_night_button.pressed.connect(_on_next_night_pressed)
	_host.set_locked_root(_root)
	_host.finished.connect(_on_mini_game_finished)
	_host.closed.connect(_on_mini_game_closed)
	_render(_model if _model != null else MainHudModelScript.empty())


## Modelin bağımsız kopyasını gösterir; null oturumsuz modeldir. Sinyal yaymaz. Ağaca girmeden çağrılırsa _ready'de
## gösterilir.
func show_model(model: MainHudModelScript) -> void:
	_model = MainHudModelScript.empty() if model == null else model.copy()
	if is_node_ready():
		_render(_model)


## Son gösterilen modelin bağımsız kopyası; henüz model verilmediyse null.
func get_last_model() -> MainHudModelScript:
	return null if _model == null else _model.copy()


## İlk etkin eyleme odak verir; etkin eylem yoksa, mini oyun açıksa veya görünüm ağaçta değilse false.
func focus_first_available_action() -> bool:
	if _chain.is_empty() or not is_inside_tree() or is_mini_game_open():
		return false
	_chain[0].grab_focus()
	return true


## Mini oyunu verilen oturumla açar; null, geçersiz oturum veya zaten açıksa false ve hiçbir şey kilitlenmez.
func open_mini_game(session: Variant) -> bool:
	return is_node_ready() and _host.open(session)


## Açık mini oyunu kapatır; oturumu değiştirmez ve sonuç sinyali yaymaz. Açık değilse false.
func close_mini_game() -> bool:
	return is_node_ready() and _host.close()


func is_mini_game_open() -> bool:
	return is_node_ready() and _host.is_open()


# --- Gösterim ---

func _render(model: MainHudModelScript) -> void:
	var previous_focus: Control = _own_focus_owner()
	var focus_key: Array = _focus_key(previous_focus)
	var session: bool = model.has_session

	_night_label.text = "%s %d / %d" % [tr(TEXT_NIGHT), model.night, model.night_count]
	_time_label.text = "%s %d / %d" % [tr(TEXT_TIME), model.elapsed_units, model.night_length_units]
	var resource_texts: Array[String] = []
	for row in model.resources:
		resource_texts.append("%s: %d" % [row.resource_id, row.value])
	# Kaynaklar yatay kayan tek satırdır; etiketler sarılmaz.
	_rebuild_labels(_resource_list, "ResourceRow", resource_texts, false)
	var body_texts: Array[String] = []
	for row in model.bodies:
		body_texts.append(SEPARATOR.join(PackedStringArray([String(row.occurrence_id), String(row.subject_id),
				str(row.night), _text_for(PRESENCE_TEXTS, row.presence)])))
	_rebuild_labels(_body_list, "BodyRow", body_texts)
	var equipment_texts: Array[String] = []
	for row in model.equipment:
		equipment_texts.append(SEPARATOR.join(PackedStringArray([String(row.equipment_id),
				_text_for(STATUS_TEXTS, row.status), str(row.disabled_units)])))
	_rebuild_labels(_equipment_list, "EquipmentRow", equipment_texts)
	var task_texts: Array[String] = []
	for row in model.tasks:
		task_texts.append(SEPARATOR.join(PackedStringArray([String(row.task_id), String(row.assigned_actor_id),
				str(row.remaining_units)])))
	_rebuild_labels(_task_list, "TaskRow", task_texts)

	var repair_entries: Array = []
	for row in model.repairs:
		repair_entries.append([row.puzzle_id, "%s%s%s" % [tr(TEXT_REPAIR), SEPARATOR, row.puzzle_id], session and row.available])
	var repairs: Array[Button] = _rebuild_buttons(_repair_list, "RepairButton", repair_entries, _on_repair_pressed)
	var choice_entries: Array = []
	for row in model.choices:
		choice_entries.append([row.choice_id, String(row.choice_id), session and row.available])
	var choices: Array[Button] = _rebuild_buttons(_choice_list, "ChoiceButton", choice_entries, _on_choice_pressed)
	var assignment_entries: Array = []
	for row in model.assignable:
		assignment_entries.append([row.task_id, "%s%s%s → %s" % [row.task_id, SEPARATOR, row.active_actor_id,
				row.assigned_actor_id], session and row.available])
	var assignments: Array[Button] = _rebuild_buttons(_assignment_list, "AssignmentButton", assignment_entries,
			_on_assign_pressed)

	_decision_label.text = "%s: %s" % [tr(TEXT_DECISION),
			tr(TEXT_EMPTY) if model.decision_id.is_empty() else String(model.decision_id)]
	_advice_label.text = "%s: %s → %s" % [tr(TEXT_ADVICE), model.advisor_actor_id, model.recommended_choice_id] \
			if session and model.advice_offered else tr(TEXT_ADVICE_NONE)
	_set_action(_wait_button, session and model.can_wait)
	_set_action(_next_night_button, session and model.can_start_night)
	if not model.feedback_key.is_empty():
		_feedback_label.text = tr(model.feedback_key)
	else:
		_feedback_label.text = "" if session else tr(TEXT_NO_SESSION)
	_ending_panel.visible = session and not model.ending_id.is_empty()
	_ending_label.text = "%s: %s" % [tr(TEXT_ENDING), model.ending_id] if _ending_panel.visible else ""

	_chain.clear()
	for group: Array[Button] in [repairs, choices, assignments]:
		for button in group:
			if not button.disabled:
				_chain.append(button)
	for button: Button in [_wait_button, _next_night_button]:
		if not button.disabled:
			_chain.append(button)
	_link_focus()
	# Mini oyun açıkken HUD kilitlidir: odak mini oyunda kalır, HUD'a odak verilmez.
	if not is_mini_game_open():
		_restore_focus(previous_focus, focus_key)


## Satırları aynı karede ağaçtan çıkarıp silinmek üzere bırakır; boşsa tarafsız boş durum satırı ekler.
func _rebuild_labels(container: Container, prefix: String, texts: Array[String], wrapped: bool = true) -> void:
	_clear(container)
	if texts.is_empty():
		container.add_child(_make_label("EmptyRow", tr(TEXT_EMPTY), wrapped))
		return
	for i in texts.size():
		container.add_child(_make_label("%s%d" % [prefix, i], texts[i], wrapped))


## entries: [kimlik, metin, etkin mi]. Kimlik metaveride ve bağlı argümanda; düğüm adı sayaçtır.
func _rebuild_buttons(container: Container, prefix: String, entries: Array, callback: Callable) -> Array[Button]:
	_clear(container)
	var buttons: Array[Button] = []
	if entries.is_empty():
		container.add_child(_make_label("EmptyRow", tr(TEXT_EMPTY)))
		return buttons
	for i in entries.size():
		var id: StringName = entries[i][0]
		var button: Button = Button.new()
		button.name = "%s%d" % [prefix, i]
		button.text = entries[i][1]
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(0, ACTION_MIN_HEIGHT)
		button.set_meta(ID_META, id)
		button.pressed.connect(callback.bind(id))
		_set_action(button, entries[i][2])
		container.add_child(button)
		buttons.append(button)
	return buttons


func _clear(container: Container) -> void:
	for child: Node in container.get_children():
		var button: Button = child as Button
		if button != null:
			for connection: Dictionary in button.pressed.get_connections():
				button.pressed.disconnect(connection["callable"])
		container.remove_child(child)
		child.queue_free()


func _make_label(node_name: String, text: String, wrapped: bool = true) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	if wrapped:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _set_action(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if not enabled:
		button.focus_next = NodePath()
		button.focus_previous = NodePath()
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			button.set_focus_neighbor(side, NodePath())


func _text_for(texts: Dictionary, value: StringName) -> String:
	return tr(texts[value]) if texts.has(value) else String(value)


# --- Odak ---

# İleri/geri ve ok komşuları açıkça kurulur; tek düğme kendisine döner.
func _link_focus() -> void:
	var count: int = _chain.size()
	for i in count:
		var button: Button = _chain[i]
		var next_path: NodePath = button.get_path_to(_chain[(i + 1) % count])
		var previous_path: NodePath = button.get_path_to(_chain[(i - 1 + count) % count])
		button.focus_next = next_path
		button.focus_previous = previous_path
		button.focus_neighbor_bottom = next_path
		button.focus_neighbor_right = next_path
		button.focus_neighbor_top = previous_path
		button.focus_neighbor_left = previous_path


# Yalnızca HUD Root altındaki odak; mini oyunun odağı HUD'a ait sayılmaz.
func _own_focus_owner() -> Control:
	if not is_inside_tree():
		return null
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused if focused != null and _root.is_ancestor_of(focused) else null


# Dinamik düğme için [kapsayıcı adı, kimlik]; diğerleri için boş.
func _focus_key(focused: Control) -> Array:
	if focused == null or not focused.has_meta(ID_META) or focused.get_parent() == null:
		return []
	return [focused.get_parent().name, focused.get_meta(ID_META)]


func _restore_focus(previous: Control, key: Array) -> void:
	if previous == null:
		return
	if is_instance_valid(previous) and previous.is_inside_tree() and _chain.has(previous):
		if not previous.has_focus():
			previous.grab_focus()
		return
	if not key.is_empty():
		for button in _chain:
			if button.get_parent().name == key[0] and button.get_meta(ID_META) == key[1]:
				button.grab_focus()
				return
	if not focus_first_available_action():
		var focused: Control = _own_focus_owner()
		if focused != null:
			focused.release_focus()


# --- Girdi ---

func _on_repair_pressed(puzzle_id: StringName) -> void:
	repair_requested.emit(puzzle_id)


func _on_choice_pressed(choice_id: StringName) -> void:
	choice_requested.emit(choice_id)


func _on_assign_pressed(task_id: StringName) -> void:
	assign_requested.emit(task_id)


func _on_wait_pressed() -> void:
	wait_requested.emit()


func _on_mini_game_finished(session: RefCounted) -> void:
	repair_finished.emit(session)


# Host geçerli eski odağı geri verdiyse ona dokunulmaz; HUD'da odak yoksa ilk etkin eyleme geçilir.
func _on_mini_game_closed() -> void:
	if _own_focus_owner() == null:
		focus_first_available_action()


func _on_next_night_pressed() -> void:
	next_night_requested.emit()
