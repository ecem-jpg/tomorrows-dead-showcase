extends "res://tests/framework/test_case.gd"
## Ana sahne arayüz bağlantısı: Main (Node2D) altında tek UI (main_hud.tscn örneği); oturumsuz başlangıç (model,
## geri bildirim, kapalı eylemler, gizli son paneli, kapalı mini oyun); kareler boyunca hatasız çalışma ve temizleme;
## çalışma zamanında sistem/presenter olmaması; main.gd ve main.tscn kaynak sınırları; project.godot ana sahnesi.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const MAIN_SCRIPT_PATH: String = "res://scripts/main.gd"
const HUD_SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"
const HUD_VIEW_PATH: String = "res://scripts/ui/main_hud_view.gd"
const HOST_PATH: String = "res://scripts/ui/mini_game_host.gd"
const MAIN_SCENE_UID: String = "uid://8aj8ysn0mbht"
const FRAMES_TO_RUN: int = 3

const FORBIDDEN_TOKENS: Array[String] = ["GameState", "GameStateChange", "MainHudPresenter", "MainHudConfig",
		"TimeSystem", "TaskCompletionSystem", "TaskSystem", "DecisionSystem", "AdviceSystem", "OccurrenceSystem",
		"EquipmentSystem", "CableRepairSystem", "EndingResolver", "ResourceSystem", "TrustSystem", "CablePuzzleSession",
		"_process", "_physics_process", "connect"]
const FORBIDDEN_PATHS: Array[String] = ["full_scenario", "res://tests/", "res://data/", "res://scripts/systems",
		"res://scripts/core", "res://scripts/data", "main_hud_presenter", "main_hud_config"]
const STORY_TERMS: Array[String] = ["story_name_a", "story_name_b", "story_place_a", "story_place_b"]


func test_scene_structure_has_main_root_and_single_ui_instance() -> void:
	var packed: PackedScene = ResourceLoader.load(MAIN_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	_assert_clean("yükleme")
	assert_true(packed != null and packed.can_instantiate(), "Ana sahne yüklenebilmeli.")
	if packed == null:
		return
	var main: Node = packed.instantiate()
	assert_eq([String(main.name), main.get_class()], ["Main", "Node2D"], "Kök Main (Node2D) olmalı.")
	assert_eq((main.get_script() as Script).resource_path, MAIN_SCRIPT_PATH)
	assert_eq(main.get_children().map(func(child: Node) -> String: return String(child.name)), ["UI"],
			"Kökün tek çocuğu UI olmalı; World eklenmemeli.")
	var ui: Node = main.get_node_or_null("UI")
	assert_true(ui is MainHudViewScript, "UI ana arayüz görünümü olmalı.")
	if ui != null:
		assert_eq(ui.scene_file_path, HUD_SCENE_PATH, "UI main_hud.tscn örneği olmalı.")
		assert_eq(ui.get_children().map(func(child: Node) -> String: return String(child.name)), ["HudLayer", "MiniGameHost"])
		assert_true(ui.get_node("HudLayer") is CanvasLayer, "HudLayer CanvasLayer olmalı.")
		var host: Node = ui.get_node("MiniGameHost")
		assert_true(host.get_class() == "Node" and (host.get_script() as Script).resource_path == HOST_PATH,
				"MiniGameHost düz Node olmalı.")
	main.free()
	_assert_clean("örnekleme")


func test_runs_without_session_and_frees_cleanly() -> void:
	var warnings: UiFixtures.WarningCapture = UiFixtures.WarningCapture.new()
	OS.add_logger(warnings)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main: Node = (ResourceLoader.load(MAIN_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	tree.root.add_child(main)
	_assert_clean("ağaca girme / _ready")
	assert_true(main.is_inside_tree() and main.is_node_ready())
	var ui: MainHudViewScript = main.get_node("UI") as MainHudViewScript
	var model: Variant = ui.get_last_model()
	assert_true(model != null, "Son model boş olmamalı.")
	if model != null:
		assert_false(model.has_session)
		assert_eq(model.feedback_key, &"UI_HUD_NO_SESSION")
	assert_eq((ui.get_node("%FeedbackLabel") as Label).text, "UI_HUD_NO_SESSION")
	assert_true((ui.get_node("%WaitButton") as Button).disabled and (ui.get_node("%NextNightButton") as Button).disabled)
	for list_name: String in ["RepairList", "ChoiceList", "AssignmentList"]:
		for child: Node in ui.get_node("%" + list_name).get_children():
			assert_false(child is Button and not (child as Button).disabled, "%s etkin düğme içermemeli." % list_name)
	assert_false((ui.get_node("%EndingPanel") as Control).visible)
	assert_false(ui.is_mini_game_open())
	assert_false(ui.focus_first_available_action(), "Oturumsuz başlangıçta odaklanacak eylem olmamalı.")
	for frame in FRAMES_TO_RUN:
		await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame
	_assert_clean("%d kare çalışma" % FRAMES_TO_RUN)
	assert_true(is_instance_valid(main) and main.is_inside_tree(), "Sahne kareler boyunca ağaçta kalmalı.")
	main.queue_free()
	await tree.process_frame
	_assert_clean("temizleme")
	assert_false(is_instance_valid(main), "Sahne serbest bırakılmalı.")
	OS.remove_logger(warnings)
	assert_eq(warnings.take_warnings(), PackedStringArray(), "Uyarı olmamalı.")


func test_runtime_tree_contains_only_ui_scripts() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var main: Node = (ResourceLoader.load(MAIN_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var scripts: Array[String] = []
	var stack: Array[Node] = [main]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script() as Script
		if script != null and not scripts.has(script.resource_path):
			scripts.append(script.resource_path)
		stack.append_array(node.get_children())
	scripts.sort()
	assert_eq(scripts, [MAIN_SCRIPT_PATH, HUD_VIEW_PATH, HOST_PATH] as Array[String],
			"Çalışma zamanında yalnızca ana betik, görünüm ve mini oyun katmanı bulunmalı.")
	main.queue_free()
	await tree.process_frame
	_assert_clean("çalışma zamanı ağacı")


func test_main_sources_respect_boundaries() -> void:
	var code: String = _code(MAIN_SCRIPT_PATH)
	assert_true(code.contains("extends Node2D"))
	for token: String in FORBIDDEN_TOKENS:
		assert_false(_has_identifier(code, token), "main.gd '%s' içermemeli." % token)
	var loads: Array[String] = []
	for match_result: RegExMatch in RegEx.create_from_string("(?:pre)?load\\(\\s*\"([^\"]+)\"").search_all(code):
		loads.append(match_result.get_string(1))
	assert_eq(loads, ["res://scripts/presentation/main_hud_model.gd", HUD_VIEW_PATH] as Array[String])
	var scene: String = FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	for path: String in [MAIN_SCRIPT_PATH, MAIN_SCENE_PATH]:
		var text: String = FileAccess.get_file_as_string(path)
		for fragment: String in FORBIDDEN_PATHS:
			assert_false(text.contains(fragment), "%s '%s' yoluna başvurmamalı." % [path, fragment])
		for term: String in STORY_TERMS:
			assert_false(_has_identifier(text.to_lower(), term), "%s hikâye terimi '%s' içermemeli." % [path, term])
	var ext_paths: Array[String] = []
	for match_result: RegExMatch in RegEx.create_from_string("\\[ext_resource[^\\]]*path=\"([^\"]+)\"").search_all(scene):
		ext_paths.append(match_result.get_string(1))
	assert_eq(ext_paths, [MAIN_SCRIPT_PATH, HUD_SCENE_PATH] as Array[String])
	assert_eq(RegEx.create_from_string("instance=ExtResource").search_all(scene).size(), 1, "HUD tam bir kez örneklenmeli.")
	var node_lines: Array[String] = []
	for match_result: RegExMatch in RegEx.create_from_string("\\[node name=\"([^\"]+)\"[^\\]]*\\]").search_all(scene):
		node_lines.append(match_result.get_string(1))
	assert_eq(node_lines, ["Main", "UI"] as Array[String], "HUD iç düğümleri ana sahnede yeniden tanımlanmamalı.")


func test_project_main_scene_is_unchanged() -> void:
	assert_eq(String(ProjectSettings.get_setting("application/run/main_scene")), MAIN_SCENE_UID)
	assert_eq(ResourceUID.get_id_path(ResourceUID.text_to_id(MAIN_SCENE_UID)), MAIN_SCENE_PATH,
			"Proje ana sahnesi hâlâ main.tscn olmalı.")
	assert_true(FileAccess.get_file_as_string(MAIN_SCENE_PATH).begins_with("[gd_scene format=3 uid=\"%s\"]" % MAIN_SCENE_UID),
			"main.tscn UID'si korunmalı.")


func _assert_clean(stage: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_true(errors.is_empty(), "%s aşamasında motor hatası: %s" % [stage, " | ".join(errors)])


func _code(path: String) -> String:
	var lines: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
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


static func _has_identifier(text: String, token: String) -> bool:
	return RegEx.create_from_string("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % token).search(text) != null
