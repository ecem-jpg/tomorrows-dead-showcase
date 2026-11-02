extends "res://tests/framework/test_case.gd"
## Mini oyun katmanının mimari sınırı (kaynak taraması; davranış testlerinin yerine geçmez) ve çalışma zamanında iç içe
## CanvasLayer olmaması: host ve kablo görünümünde sistem, presenter veya oyun durumu bağımlılığı, doğrudan yazma,
## _process ve hikâye adı yoktur; host yalnızca kablo sahnesini ve görünüm betiğini yükler. Yorumlar ayıklanır.

const UiFixtures := preload("res://tests/fixtures/cable_ui_fixtures.gd")
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")
const MiniGameHostScript := preload("res://scripts/ui/mini_game_host.gd")

const HOST_PATH: String = "res://scripts/ui/mini_game_host.gd"
const CABLE_VIEW_PATH: String = "res://scripts/ui/cable_puzzle_view.gd"
const CABLE_SCENE_PATH: String = "res://scenes/ui/cable_puzzle.tscn"
const HUD_VIEW_PATH: String = "res://scripts/ui/main_hud_view.gd"
const HUD_SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"

const FORBIDDEN_DEPENDENCIES: Array[String] = ["GameState", "GameStateChange", "MainHudPresenter", "MainHudConfig",
		"TimeSystem", "TaskCompletionSystem", "TaskSystem", "DecisionSystem", "AdviceSystem", "OccurrenceSystem",
		"EquipmentSystem", "CableRepairSystem", "EndingResolver", "ResourceSystem", "TrustSystem", "apply_result",
		"start_session"]
const FORBIDDEN_WRITES: Array[String] = ["apply_changes", "set_resource", "set_flag", "set_time_state",
		"set_trust_state", "_process", "_physics_process"]
const STORY_TERMS: Array[String] = ["story_name_a", "story_name_b", "story_place_a", "story_place_b"]


func test_host_and_views_have_no_system_dependency() -> void:
	for path: String in [HOST_PATH, CABLE_VIEW_PATH, HUD_VIEW_PATH]:
		var code: String = _code(path)
		for token: String in FORBIDDEN_DEPENDENCIES:
			assert_false(_has_identifier(code, token), "%s '%s' bağımlılığı taşımamalı." % [path, token])
	for fragment: String in ["res://scripts/systems", "res://scripts/core", "res://scripts/data",
			"res://scripts/presentation"]:
		assert_false(_code(HOST_PATH).contains(fragment), "Host '%s' yoluna başvurmamalı." % fragment)


func test_no_direct_writes_or_process() -> void:
	for path: String in [HOST_PATH, CABLE_VIEW_PATH, HUD_VIEW_PATH]:
		var code: String = _code(path)
		for token: String in FORBIDDEN_WRITES:
			assert_false(_has_identifier(code, token), "%s '%s' içermemeli." % [path, token])
		assert_false(code.contains("get(\"_"), "%s özel alan okumamalı." % path)


func test_host_loads_only_cable_scene_and_view() -> void:
	var loads: Array[String] = []
	for match_result: RegExMatch in RegEx.create_from_string("(?:pre)?load\\(\\s*\"([^\"]+)\"").search_all(_code(HOST_PATH)):
		loads.append(match_result.get_string(1))
	loads.sort()
	assert_eq(loads, [CABLE_SCENE_PATH, CABLE_VIEW_PATH] as Array[String])
	assert_true(_code(HOST_PATH).contains("ui_cancel"), "Esc sorumluluğu host'ta olmalı.")
	assert_false(_code(CABLE_VIEW_PATH).contains("ui_cancel"), "Kablo görünümü Esc'yi ele almamalı.")


func test_no_story_terms() -> void:
	for path: String in [HOST_PATH, CABLE_VIEW_PATH, CABLE_SCENE_PATH, HUD_VIEW_PATH, HUD_SCENE_PATH]:
		var lower: String = FileAccess.get_file_as_string(path).to_lower()
		assert_false(lower.is_empty(), "%s okunamadı." % path)
		for term: String in STORY_TERMS:
			assert_false(_has_identifier(lower, term), "%s hikâye terimi '%s' içermemeli." % [path, term])


func test_no_nested_canvas_layer_at_runtime() -> void:
	var viewport: SubViewport = UiFixtures.make_viewport(Vector2i(1920, 1080))
	var hud: MainHudViewScript = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as MainHudViewScript
	viewport.add_child(hud)
	await UiFixtures.settle()
	var host_node: Node = hud.get_node("%MiniGameHost")
	assert_true(host_node.get_parent() == hud and host_node.get_class() == "Node", "Host MainHud altında düz Node olmalı.")
	var host: MiniGameHostScript = host_node as MiniGameHostScript
	assert_true(hud.open_mini_game(UiFixtures.standard_session()))
	var layers: Array[CanvasLayer] = []
	var stack: Array[Node] = [hud]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CanvasLayer:
			layers.append(node)
			var ancestor: Node = node.get_parent()
			while ancestor != null and ancestor != viewport:
				assert_false(ancestor is CanvasLayer, "%s başka bir CanvasLayer altında olmamalı." % node.name)
				ancestor = ancestor.get_parent()
		stack.append_array(node.get_children())
	assert_eq(layers.map(func(layer: CanvasLayer) -> int: return layer.layer).size(), 2)
	assert_true((host.get_view() as CanvasLayer).layer == 10 and (hud.get_node("HudLayer") as CanvasLayer).layer == 1)
	hud.close_mini_game()
	assert_eq(take_engine_errors(), PackedStringArray())
	await UiFixtures.dispose(viewport)


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
