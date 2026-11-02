extends "res://tests/framework/test_case.gd"
## Duman testi: ana arayüz sahnesi tek başına yüklenir, örneklenir, ağaca girer, oturumsuz başlar, kareler boyunca
## hatasız çalışır ve temizlenir.

const SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")
const FRAMES_TO_RUN: int = 3


func test_scene_loads_and_instantiates() -> void:
	var packed: PackedScene = ResourceLoader.load(SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_assert_clean("yükleme")
	assert_true(packed != null and packed.can_instantiate(), "Sahne örneklenebilir olmalı.")
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	_assert_clean("örnekleme")
	assert_true(instance is MainHudViewScript, "Kök MainHudView olmalı.")
	instance.free()


func test_scene_has_single_root_structure() -> void:
	var instance: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	assert_eq(instance.get_class(), "Node", "Kök düz Node olmalı.")
	assert_eq(instance.get_children().map(func(child: Node) -> String: return String(child.name)),
			["HudLayer", "MiniGameHost"], "Kökün çocukları HudLayer ve MiniGameHost olmalı.")
	var layer: CanvasLayer = instance.get_node_or_null("HudLayer") as CanvasLayer
	assert_true(layer != null and layer.layer == 1, "HudLayer CanvasLayer (layer 1) olmalı.")
	var root: Control = instance.get_node_or_null("HudLayer/Root") as Control
	assert_true(root != null, "HudLayer/Root Control olmalı.")
	if root != null:
		assert_eq([root.anchor_left, root.anchor_top, root.anchor_right, root.anchor_bottom], [0.0, 0.0, 1.0, 1.0])
	var host: Node = instance.get_node_or_null("MiniGameHost")
	assert_true(host != null and host.get_class() == "Node" and not (host is CanvasLayer),
			"MiniGameHost düz Node olmalı.")
	assert_true(host != null and host.get_child_count() == 0, "Başlangıçta mini oyun örneklenmemiş olmalı.")
	instance.free()


func test_scene_enters_tree_and_starts_without_session() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var instance: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(instance)
	_assert_clean("ağaca girme / _ready")
	assert_true(instance.is_inside_tree() and instance.is_node_ready())
	assert_eq((instance.get_node("%FeedbackLabel") as Label).text, "UI_HUD_NO_SESSION")
	assert_true((instance.get_node("%WaitButton") as Button).disabled)
	assert_true((instance.get_node("%NextNightButton") as Button).disabled)
	assert_false((instance.get_node("%EndingPanel") as Control).visible)
	instance.queue_free()
	await tree.process_frame
	_assert_clean("temizleme")


func test_scene_runs_frames_and_frees_cleanly() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var instance: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(instance)
	for frame in FRAMES_TO_RUN:
		await tree.process_frame
	await tree.physics_frame
	_assert_clean("%d kare çalışma" % FRAMES_TO_RUN)
	assert_true(is_instance_valid(instance) and instance.is_inside_tree())
	instance.queue_free()
	await tree.process_frame
	_assert_clean("temizleme")
	assert_false(is_instance_valid(instance), "Sahne örneği temizlenmeli.")


func _assert_clean(stage: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.is_empty(), "%s aşamasında motor hatası: %s" % [stage, " | ".join(errors)])
