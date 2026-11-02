extends "res://tests/framework/test_case.gd"
## Duman testi: ana sahne başsız modda yüklenir, örneklenir, ağaca girer, kareler
## boyunca hatasız çalışır ve temizlenir. Sahne içeriğine dair varsayım yapmaz.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const FRAMES_TO_RUN: int = 2


func test_main_scene_opens_headless() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	assert_true(tree != null, "SceneTree bulunamadı.")
	if tree == null:
		return

	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_assert_stage_clean("yükleme/ayrıştırma")
	assert_true(packed != null, "Sahne PackedScene olarak yüklenemedi.")
	if packed == null:
		return
	assert_true(packed.can_instantiate(), "Sahne örneklenemez durumda.")

	var instance: Node = packed.instantiate()
	_assert_stage_clean("örnekleme")
	assert_true(instance != null, "Sahne örneklenemedi.")
	if instance == null:
		return

	# add_child, _enter_tree ve _ready'yi eşzamanlı çalıştırır.
	tree.root.add_child(instance)
	_assert_stage_clean("ağaca girme / _ready")
	assert_true(instance.is_inside_tree(), "Örnek sahne ağacına girmedi.")
	assert_true(instance.is_node_ready(), "_ready tamamlanmadı.")

	for frame in FRAMES_TO_RUN:
		await tree.process_frame
	await tree.physics_frame
	_assert_stage_clean("%d kare çalışma" % FRAMES_TO_RUN)
	assert_true(is_instance_valid(instance) and instance.is_inside_tree(), "Örnek kareler sırasında ağaçtan çıktı.")

	instance.queue_free()
	await tree.process_frame
	_assert_stage_clean("temizleme")
	assert_false(is_instance_valid(instance), "Sahne örneği temizlenmedi.")


# Aşamaya özgü mesaj için hataları burada alır; hata varsa test başarısız olur.
func _assert_stage_clean(stage: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.is_empty(), "%s aşamasında motor hatası: %s" % [stage, " | ".join(errors)])
