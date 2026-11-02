extends "res://tests/framework/test_case.gd"
## MainHudView düzeni: 1920×1080 ve 1280×720 mantıksal boyutta, çok satırlı dolu modelle Root'un alanı doldurması,
## panellerin taşmaması, liste taşmasının yalnızca ScrollContainer içinde kalması, asgari yazı ve düğme boyutları ve
## mevcut proje ölçeğiyle 720p pencerede etkili boyutlar. Piksel karşılaştırması yapılmaz.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")
const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")

const SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"
const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1280, 720)]
const ROWS: int = 24
const MIN_FONT: int = 30
const MIN_BUTTON_HEIGHT: float = 72.0
const MIN_EFFECTIVE_FONT: float = 20.0
const MIN_EFFECTIVE_BUTTON_HEIGHT: float = 48.0
## Kayan nokta ölçek çarpımı için tolerans.
const EPSILON: float = 0.01
const MAIN_PANELS: Array[String] = ["Margin", "Margin/Layout", "Margin/Layout/TopBar", "Margin/Layout/Body",
		"Margin/Layout/StatusBar", "Margin/Layout/Body/LeftColumn", "Margin/Layout/Body/CenterColumn",
		"Margin/Layout/Body/RightColumn", "Margin/Layout/Body/LeftColumn/BodiesPanel",
		"Margin/Layout/Body/LeftColumn/EquipmentPanel", "Margin/Layout/Body/CenterColumn/DecisionPanel",
		"Margin/Layout/Body/RightColumn/TasksPanel", "Margin/Layout/Body/RightColumn/ActionsPanel"]

var _viewport: SubViewport
var _view: MainHudViewScript


func test_layout_fits_1920x1080() -> void:
	await _assert_layout(SIZES[0])


func test_layout_fits_1280x720() -> void:
	await _assert_layout(SIZES[1])


func test_ending_panel_fits_both_sizes() -> void:
	for size: Vector2i in SIZES:
		var model: MainHudModelScript = _model(ROWS)
		model.ending_id = &"ending_a"
		await _mount(size, model)
		var panel: Control = _view.get_node("%EndingPanel") as Control
		assert_true(panel.visible)
		assert_true(_inside(panel.get_global_rect(), size), "%s: son paneli taşmamalı (%s)" % [size, panel.get_global_rect()])
		await _finish()


func test_effective_sizes_under_project_scale() -> void:
	# canvas_items ölçeklemesinde mantıksal tasarım boyutu pencereye ölçeklenir; 720p pencerede ölçek ~0,667.
	var design: Vector2 = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	var window: Vector2 = Vector2(ProjectSettings.get_setting("display/window/size/window_width_override"),
			ProjectSettings.get_setting("display/window/size/window_height_override"))
	var scale: float = minf(window.x / design.x, window.y / design.y)
	assert_true(scale > 0.0 and scale <= 1.0, "Ölçek: %f" % scale)
	await _mount(Vector2i(design), _model(ROWS))
	var measures: Dictionary = _measure()
	var effective_font: float = measures["min_font"] * scale
	var effective_button: float = measures["min_button_height"] * scale
	assert_true(effective_font >= MIN_EFFECTIVE_FONT - EPSILON, "Etkili yazı %.2f px" % effective_font)
	assert_true(effective_button >= MIN_EFFECTIVE_BUTTON_HEIGHT - EPSILON, "Etkili düğme yüksekliği %.2f px" % effective_button)
	print("    ölçüm: ölçek %.4f, etkili yazı %.2f px, etkili düğme %.2f px" % [scale, effective_font, effective_button])
	await _finish()


func _assert_layout(size: Vector2i) -> void:
	await _mount(size, _model(ROWS))
	var root: Control = _view.get_node("HudLayer/Root") as Control
	assert_eq(Vector2i(root.size), size, "Root görünüm alanını doldurmalı.")
	var margin: Control = root.get_node("Margin") as Control
	var minimum: Vector2 = margin.get_combined_minimum_size()
	assert_true(minimum.x <= size.x and minimum.y <= size.y, "%s: en küçük boyut %s alanı aşmamalı." % [size, minimum])
	for path: String in MAIN_PANELS:
		var panel: Control = root.get_node(path) as Control
		assert_true(_inside(panel.get_global_rect(), size), "%s: %s taşmamalı (%s)" % [size, path, panel.get_global_rect()])
	# Kaydırma içindekiler dışında görünür her denetim alan içinde; kaydırma kapları da alan içinde.
	for control: Control in _visible_controls(root):
		if _scroll_ancestor(control, root) == null:
			assert_true(_inside(control.get_global_rect(), size), "%s: %s taşmamalı (%s)"
					% [size, root.get_path_to(control), control.get_global_rect()])
	var measures: Dictionary = _measure()
	assert_true(measures["min_font"] >= MIN_FONT, "%s: en küçük yazı %d" % [size, measures["min_font"]])
	assert_true(measures["min_button_height"] >= MIN_BUTTON_HEIGHT, "%s: en kısa düğme %.1f" % [size, measures["min_button_height"]])
	assert_true(measures["scrolling_lists"] > 0, "Çok satırlı listeler kaydırma içinde taşmalı.")
	print("    ölçüm %s: en küçük yazı %d px, en kısa düğme %.1f px, en küçük boyut %s, taşan liste %d"
			% [size, measures["min_font"], measures["min_button_height"], minimum, measures["scrolling_lists"]])
	await _finish()


## Görünür etiket ve düğmelerin en küçük yazı boyutu, görünür düğmelerin en küçük yüksekliği, içeriği taşan kaydırma
## kabı sayısı.
func _measure() -> Dictionary:
	var root: Control = _view.get_node("HudLayer/Root") as Control
	var min_font: int = 1 << 20
	var min_button: float = INF
	var scrolling: int = 0
	for control: Control in _visible_controls(root):
		if control is Label or control is Button:
			min_font = mini(min_font, control.get_theme_font_size(&"font_size"))
		if control is Button:
			min_button = minf(min_button, control.size.y)
		if control is ScrollContainer and control.get_child_count() > 0:
			var content: Control = control.get_child(0) as Control
			if content != null and content.size.y > control.size.y:
				scrolling += 1
	return {"min_font": min_font, "min_button_height": min_button, "scrolling_lists": scrolling}


func _visible_controls(root: Control) -> Array[Control]:
	var result: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var control: Control = node as Control
		if control != null and not control.is_visible_in_tree():
			continue
		if control != null:
			result.append(control)
		for child: Node in node.get_children():
			stack.append(child)
	return result


func _scroll_ancestor(control: Control, root: Control) -> ScrollContainer:
	var node: Node = control.get_parent()
	while node != null and node != root:
		if node is ScrollContainer:
			return node
		node = node.get_parent()
	return null


func _inside(rect: Rect2, size: Vector2i) -> bool:
	return rect.position.x >= -EPSILON and rect.position.y >= -EPSILON \
			and rect.end.x <= size.x + EPSILON and rect.end.y <= size.y + EPSILON


func _mount(size: Vector2i, model: MainHudModelScript) -> void:
	_viewport = UiFixtures.make_viewport(size)
	_view = (load(SCENE_PATH) as PackedScene).instantiate() as MainHudViewScript
	_viewport.add_child(_view)
	_view.show_model(model)
	await UiFixtures.settle(3)


func _finish() -> void:
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(_viewport)


## Her listede rows satırlı, tarafsız ve uzun kimlikli dolu model.
static func _model(rows: int) -> MainHudModelScript:
	var model: MainHudModelScript = MainHudModelScript.new()
	model.has_session = true
	model.night = 1
	model.night_count = 2
	model.elapsed_units = 3
	model.night_length_units = 10
	model.decision_id = &"decision_a"
	model.advice_offered = true
	model.advisor_actor_id = &"actor_b"
	model.recommended_choice_id = &"choice_a_with_a_long_neutral_identifier"
	model.can_wait = true
	model.can_start_night = true
	model.feedback_key = &"UI_HUD_UNAVAILABLE"
	for i in rows:
		var resource: MainHudModelScript.ResourceRow = MainHudModelScript.ResourceRow.new()
		resource.resource_id = StringName("resource_%d" % i)
		resource.value = i
		model.resources.append(resource)
		var task: MainHudModelScript.TaskRow = MainHudModelScript.TaskRow.new()
		task.task_id = StringName("task_%d_long_neutral_identifier" % i)
		task.assigned_actor_id = &"actor_b"
		task.remaining_units = i
		model.tasks.append(task)
		var assignable: MainHudModelScript.AssignableRow = MainHudModelScript.AssignableRow.new()
		assignable.task_id = StringName("task_%d_long_neutral_identifier" % i)
		assignable.active_actor_id = &"actor_a"
		assignable.assigned_actor_id = &"actor_b"
		assignable.available = i % 2 == 0
		model.assignable.append(assignable)
		var equipment: MainHudModelScript.EquipmentRow = MainHudModelScript.EquipmentRow.new()
		equipment.equipment_id = StringName("equipment_%d" % i)
		equipment.status = &"disabled"
		equipment.disabled_units = i
		model.equipment.append(equipment)
		var repair: MainHudModelScript.RepairRow = MainHudModelScript.RepairRow.new()
		repair.puzzle_id = StringName("puzzle_%d" % i)
		repair.available = true
		model.repairs.append(repair)
		var body: MainHudModelScript.BodyRow = MainHudModelScript.BodyRow.new()
		body.occurrence_id = StringName("occurrence_%d" % i)
		body.subject_id = StringName("subject_%d" % i)
		body.night = 1
		body.presence = &"present"
		model.bodies.append(body)
		var choice: MainHudModelScript.ChoiceRow = MainHudModelScript.ChoiceRow.new()
		choice.choice_id = StringName("choice_%d_with_a_long_neutral_identifier" % i)
		choice.available = true
		model.choices.append(choice)
	return model
