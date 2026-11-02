extends "res://tests/framework/test_case.gd"
## Duman testi: kablo bulmacası sahnesi tek başına yüklenir, örneklenir, ağaca girer, kareler boyunca ve farklı
## boyutlarda hatasız çalışır ve temizlenir (K-033).

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const CablePuzzleViewScript := preload("res://scripts/ui/cable_puzzle_view.gd")

const FRAMES_TO_RUN: int = 3
const RESIZE_STEPS: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(1024, 600), Vector2i(1280, 720)]


func test_scene_opens_runs_and_frees_headless() -> void:
	var tree: SceneTree = UiFixtures.tree()
	var packed: PackedScene = ResourceLoader.load(UiFixtures.SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_assert_stage_clean("yükleme/ayrıştırma")
	assert_true(packed != null and packed.can_instantiate(), "Sahne örneklenebilir PackedScene olarak yüklenemedi.")
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	_assert_stage_clean("örnekleme")
	assert_true(instance != null, "Sahne örneklenemedi.")
	if instance == null:
		return
	tree.root.add_child(instance)
	_assert_stage_clean("ağaca girme / _ready")
	assert_true(instance.is_inside_tree() and instance.is_node_ready(), "Örnek ağaca girmedi veya _ready bitmedi.")
	for frame in FRAMES_TO_RUN:
		await tree.process_frame
	await tree.physics_frame
	_assert_stage_clean("%d kare çalışma" % FRAMES_TO_RUN)
	instance.queue_free()
	await tree.process_frame
	_assert_stage_clean("temizleme")
	assert_false(is_instance_valid(instance), "Sahne örneği temizlenmedi.")


func test_root_is_canvas_layer_with_full_rect_control() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var view: Node = UiFixtures.mount(viewport)
	await UiFixtures.settle()
	assert_true(view is CanvasLayer, "Kök CanvasLayer olmalı.")
	var root: Control = view.get_node_or_null("Root") as Control
	assert_true(root != null, "Kökün altında Root (Control) olmalı.")
	if root != null:
		assert_eq(root.get_child_count() > 0, true)
		assert_eq(Vector2i(root.size), UiFixtures.DEFAULT_SIZE, "Root tam ekran olmalı.")
		assert_eq([root.anchor_left, root.anchor_top, root.anchor_right, root.anchor_bottom], [0.0, 0.0, 1.0, 1.0])
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(viewport)


func test_unconfigured_view_is_empty_locked_and_clean() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport()
	var view: CablePuzzleViewScript = UiFixtures.mount(viewport)
	await UiFixtures.settle()
	assert_true(view.is_locked())
	assert_true(view.get_session() == null)
	assert_eq(UiFixtures.column_buttons(view, &"left").size() + UiFixtures.column_buttons(view, &"right").size(), 0)
	assert_true(UiFixtures.check_button(view).disabled)
	assert_eq(UiFixtures.feedback_text(view), "")
	assert_false(UiFixtures.owns_focus(view, viewport))
	assert_eq(take_engine_errors(), PackedStringArray(), "Kurulumsuz görünüm hata üretmemeli.")
	await UiFixtures.dispose(viewport)


func test_resizes_without_errors_or_warnings() -> void:
	var warnings: UiFixtures.WarningCapture = UiFixtures.WarningCapture.new()
	OS.add_logger(warnings)
	var viewport: SubViewport = UiFixtures.make_viewport()
	var view: Node = UiFixtures.mount(viewport, UiFixtures.standard_session())
	await UiFixtures.settle()
	var root: Control = view.get_node("Root") as Control
	for size: Vector2i in RESIZE_STEPS:
		viewport.size = size
		await UiFixtures.settle()
		assert_eq(Vector2i(root.size), size, "Root yeni boyutu almalı: %s" % size)
		_assert_stage_clean("boyut %s" % size)
	OS.remove_logger(warnings)
	assert_eq(warnings.take_warnings(), PackedStringArray(), "Boyut değişiminde uyarı olmamalı.")
	await UiFixtures.dispose(viewport)


func test_scene_does_not_reference_main_or_project_settings() -> void:
	var text: String = FileAccess.get_file_as_string(UiFixtures.SCENE_PATH)
	assert_false(text.is_empty(), "Sahne metni okunamadı.")
	for token: String in ["res://scenes/main", "res://scripts/main", "project.godot"]:
		assert_false(text.contains(token), "Sahne '%s' izine başvurmamalı." % token)


func _assert_stage_clean(stage: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.is_empty(), "%s aşamasında motor hatası: %s" % [stage, " | ".join(errors)])
