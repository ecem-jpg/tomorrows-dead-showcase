extends "res://tests/framework/test_case.gd"
## Kablo arayüzünün sorumluluk sınırı (K-033): üretim arayüz betikleri ve sahnesi oyun durumu, sonuç uygulama, diğer
## sistemler, doğru bağlantı kataloğu, rastgelelik, main ve proje ayarlarına bağımlı değildir. Yorumlar ayıklanır.

const VIEW_PATH: String = "res://scripts/ui/cable_puzzle_view.gd"
const BOARD_PATH: String = "res://scripts/ui/cable_board.gd"
const SCENE_PATH: String = "res://scenes/ui/cable_puzzle.tscn"
const SCRIPT_PATHS: Array[String] = [VIEW_PATH, BOARD_PATH]

const FORBIDDEN_SYSTEMS: Array[String] = ["GameState", "GameStateChange", "CableRepairSystem", "CableRepairResult",
		"CablePuzzleStartResult", "TimeSystem", "TaskCompletionSystem", "EquipmentSystem", "ResourceSystem",
		"TrustSystem", "EndingResolver", "EffectPlanner", "ConditionEvaluator", "apply_result", "preview_result",
		"start_session", "apply_changes"]
const FORBIDDEN_CATALOG: Array[String] = ["required_connections", "_required_partners", "_puzzle", "_is_correct",
		"get_puzzle_errors", "CablePuzzleData", "CableConnectionData", "success", "failure"]
const FORBIDDEN_RANDOM: Array[String] = ["RandomNumberGenerator", "randi", "randf", "randi_range", "randf_range",
		"randomize", "seed"]
const FORBIDDEN_PROJECT: Array[String] = ["ProjectSettings", "_process", "_physics_process", "autoload"]
const ALLOWED_PRELOADS: Dictionary = {
	VIEW_PATH: ["res://scripts/systems/cable_puzzle_session.gd", "res://scripts/ui/cable_board.gd"],
	BOARD_PATH: [],
}


func test_no_game_state_or_other_system_dependencies() -> void:
	for path: String in SCRIPT_PATHS:
		_assert_tokens_absent(path, FORBIDDEN_SYSTEMS)


func test_correct_layout_catalog_is_never_read() -> void:
	for path: String in SCRIPT_PATHS:
		_assert_tokens_absent(path, FORBIDDEN_CATALOG)


func test_no_randomness_main_or_project_settings() -> void:
	for path: String in SCRIPT_PATHS:
		_assert_tokens_absent(path, FORBIDDEN_RANDOM + FORBIDDEN_PROJECT)
		var code: String = _code_of(FileAccess.get_file_as_string(path))
		for fragment: String in ["res://scripts/main", "res://scenes/main", "res://scripts/core", "res://data/"]:
			assert_false(code.contains(fragment), "%s: '%s' yoluna başvurmamalı." % [path, fragment])


func test_scripts_preload_only_allowed_files() -> void:
	var load_call: RegEx = RegEx.create_from_string("(?<![A-Za-z0-9_])(?:pre)?load\\(\\s*\"([^\"]+)\"")
	for path: String in SCRIPT_PATHS:
		var code: String = _code_of(FileAccess.get_file_as_string(path))
		var found: Array[String] = []
		for match_result: RegExMatch in load_call.search_all(code):
			found.append(match_result.get_string(1))
		assert_eq(found, Array(ALLOWED_PRELOADS[path], TYPE_STRING, "", null), "%s yüklemeleri" % path)


func test_scene_references_only_the_two_ui_scripts() -> void:
	var text: String = FileAccess.get_file_as_string(SCENE_PATH)
	var ext_path: RegEx = RegEx.create_from_string("\\[ext_resource[^\\]]*path=\"([^\"]+)\"")
	var found: Array[String] = []
	for match_result: RegExMatch in ext_path.search_all(text):
		found.append(match_result.get_string(1))
	found.sort()
	assert_eq(found, [BOARD_PATH, VIEW_PATH] as Array[String])
	for token: String in FORBIDDEN_SYSTEMS + ["res://data/", "res://scenes/main", "res://scripts/main"]:
		assert_false(text.contains(token), "Sahne '%s' izi taşımamalı." % token)


func _assert_tokens_absent(path: String, tokens: Array) -> void:
	var source: String = FileAccess.get_file_as_string(path)
	assert_false(source.is_empty(), "%s okunamadı." % path)
	var code: String = _code_of(source)
	for token: String in tokens:
		var pattern: RegEx = RegEx.create_from_string("(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % token)
		assert_true(pattern.search(code) == null, "%s: yasak iz '%s'." % [path, token])


## Yorumları ayıklanmış kaynak (dizgi içindeki # korunur).
static func _code_of(source: String) -> String:
	var lines: PackedStringArray = []
	for line: String in source.split("\n"):
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
