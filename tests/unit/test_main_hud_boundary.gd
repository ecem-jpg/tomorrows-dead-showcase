extends "res://tests/framework/test_case.gd"
## Ana arayüz görünümünün mimari sınırı (kaynak taraması; davranış testlerinin yerine geçmez): oyun durumu, presenter
## veya sistem bağımlılığı, doğrudan yazma, özel alan okuma, _process, gizli öneri alanları, hikâye adları, kimlikten
## düğüm adı/yolu üretimi ve main / kablo sahnesine başvuru yoktur. Yorumlar ayıklanır.

const VIEW_PATH: String = "res://scripts/ui/main_hud_view.gd"
const SCENE_PATH: String = "res://scenes/ui/main_hud.tscn"
const HOST_PATH: String = "res://scripts/ui/mini_game_host.gd"

const FORBIDDEN_DEPENDENCIES: Array[String] = ["GameState", "GameStateChange", "MainHudPresenter", "MainHudConfig",
		"TimeSystem", "TaskCompletionSystem", "TaskSystem", "DecisionSystem", "AdviceSystem", "OccurrenceSystem",
		"EquipmentSystem", "CableRepairSystem", "EndingResolver", "ResourceSystem", "TrustSystem", "CablePuzzleSession",
		"CablePuzzleView"]
const FORBIDDEN_WRITES: Array[String] = ["apply_changes", "set_resource", "set_flag", "set_time_state",
		"set_trust_state", "_process", "_physics_process"]
const FORBIDDEN_HIDDEN: Array[String] = ["accuracy", "variant_id", "variant", "failed_condition_indexes", "condition"]
const STORY_TERMS: Array[String] = ["story_name_a", "story_name_b", "story_place_a", "story_place_b",
		"story_family_a", "story_family_b"]
const FORBIDDEN_PATHS: Array[String] = ["res://scenes/main", "res://scripts/main", "cable_puzzle", "cable_board",
		"res://scripts/systems", "res://scripts/core", "res://scripts/data", "full_scenario", "res://tests/"]


func test_view_has_no_state_presenter_or_system_dependency() -> void:
	var code: String = _code(VIEW_PATH)
	for token: String in FORBIDDEN_DEPENDENCIES:
		assert_false(_has_identifier(code, token), "Görünüm '%s' bağımlılığı taşımamalı." % token)
	var loads: Array[String] = []
	for match_result: RegExMatch in RegEx.create_from_string("(?:pre)?load\\(\\s*\"([^\"]+)\"").search_all(code):
		loads.append(match_result.get_string(1))
	assert_eq(loads, ["res://scripts/presentation/main_hud_model.gd", HOST_PATH] as Array[String],
			"Görünüm yalnız modeli ve mini oyun katmanını yükler.")


func test_view_has_no_writes_private_reads_or_process() -> void:
	var code: String = _code(VIEW_PATH)
	for token: String in FORBIDDEN_WRITES:
		assert_false(_has_identifier(code, token), "Görünüm '%s' içermemeli." % token)
	assert_false(code.contains("get(\"_"), "Özel alan okuması olmamalı.")


func test_no_hidden_advice_or_internal_fields() -> void:
	for path: String in [VIEW_PATH, SCENE_PATH]:
		var code: String = _code(path) if path.ends_with(".gd") else FileAccess.get_file_as_string(path)
		for token: String in FORBIDDEN_HIDDEN:
			assert_false(_has_identifier(code, token), "%s '%s' içermemeli." % [path, token])


func test_no_story_terms_or_foreign_scene_references() -> void:
	for path: String in [VIEW_PATH, SCENE_PATH]:
		var text: String = FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s okunamadı." % path)
		var lower: String = text.to_lower()
		for term: String in STORY_TERMS:
			assert_false(_has_identifier(lower, term), "%s hikâye terimi '%s' içermemeli." % [path, term])
		for fragment: String in FORBIDDEN_PATHS:
			assert_false(text.contains(fragment), "%s '%s' yoluna başvurmamalı." % [path, fragment])
	var scene: String = FileAccess.get_file_as_string(SCENE_PATH)
	var ext_paths: Array[String] = []
	for match_result: RegExMatch in RegEx.create_from_string("\\[ext_resource[^\\]]*path=\"([^\"]+)\"").search_all(scene):
		ext_paths.append(match_result.get_string(1))
	assert_eq(ext_paths, [VIEW_PATH, HOST_PATH] as Array[String], "Sahne yalnız görünüm ve mini oyun katmanı betiklerine başvurur.")


func test_node_names_and_paths_never_come_from_model_ids() -> void:
	var code: String = _code(VIEW_PATH)
	# Düğüm adı yalnızca önek + sayaçtan veya sabit "EmptyRow"dan gelir.
	for match_result: RegExMatch in RegEx.create_from_string("\\.name\\s*=(?!=)\\s*(.+)").search_all(code):
		var value: String = match_result.get_string(1).strip_edges()
		assert_true(value in ["\"%s%d\" % [prefix, i]", "node_name"], "Beklenmeyen düğüm adı ataması: %s" % value)
	for match_result: RegExMatch in RegEx.create_from_string("_make_label\\(\\s*([^,]+),").search_all(code):
		var argument: String = match_result.get_string(1).strip_edges()
		# Desen ilk virgülde durur: önek + sayaç biçimi "[prefix" ile kesilmiş görünür.
		assert_true(argument in ["\"EmptyRow\"", "\"%s%d\" % [prefix", "node_name: String"],
				"Beklenmeyen etiket adı: %s" % argument)
	# Düğüm yolu yalnızca düğümlerin kendisinden (get_path_to) veya boş olarak kurulur.
	for match_result: RegExMatch in RegEx.create_from_string("NodePath\\(([^)]*)\\)").search_all(code):
		assert_eq(match_result.get_string(1).strip_edges(), "", "Düğüm yolu metinden kurulmamalı.")
	for token: String in ["get_node(", "get_node_or_null(", "find_child("]:
		assert_false(code.contains(token), "Görünüm kimlikle düğüm aramamalı: %s" % token)


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
