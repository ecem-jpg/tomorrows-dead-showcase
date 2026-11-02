extends "res://tests/framework/test_case.gd"
## MainHudConfig: geçerli yapılandırma, boş ve tekrarlanan kimlikler, karar/öneri ilişkisi, deterministik hata sırası,
## girdilerin ve okuyucuların bağımsız kopyalanması.

const MainHudConfigScript := preload("res://scripts/presentation/main_hud_config.gd")


func test_valid_configuration_has_no_errors_and_exposes_values() -> void:
	var config: MainHudConfigScript = _valid()
	assert_eq(config.get_errors(), PackedStringArray())
	var assignments: Array = config.get_assignments()
	assert_eq(assignments.size(), 1)
	if assignments.size() == 1:
		assert_eq([assignments[0].task_id, assignments[0].active_actor_id, assignments[0].assigned_actor_id],
				[&"task_a", &"actor_a", &"actor_b"])
	assert_eq(config.get_assignment(&"task_a").assigned_actor_id, &"actor_b")
	assert_true(config.get_assignment(&"task_x") == null)
	assert_eq([config.get_decision_id(), config.get_advice_id(), config.get_wait_action_id()],
			[&"decision_a", &"advice_a", &"action_b"])
	assert_eq(config.get_repair_puzzle_ids(), [&"puzzle_a"] as Array[StringName])
	assert_true(config.has_repair_puzzle(&"puzzle_a"))
	assert_false(config.has_repair_puzzle(&"puzzle_x"))
	assert_false(config.has_repair_puzzle(&""))


func test_empty_identifiers_are_reported() -> void:
	var config: MainHudConfigScript = MainHudConfigScript.new(
			[MainHudConfigScript.assignment(&"", &"", &"")], &"", &"", [""], &"")
	assert_eq(config.get_errors(), PackedStringArray([
		"Atama #0: boş görev kimliği",
		"Atama #0: boş görevi veren aktör",
		"Atama #0: boş görevi alan aktör",
		"Tamir #0: boş bulmaca kimliği",
		"Boş bekleme eylemi kimliği",
	]))


func test_duplicate_tasks_and_puzzles_are_reported() -> void:
	var config: MainHudConfigScript = MainHudConfigScript.new([
		MainHudConfigScript.assignment(&"task_a", &"actor_a", &"actor_b"),
		MainHudConfigScript.assignment(&"task_a", &"actor_a", &"actor_b"),
	], &"", &"", [&"puzzle_a", &"puzzle_b", &"puzzle_a"], &"action_b")
	assert_eq(config.get_errors(), PackedStringArray([
		"Atama #1: tekrarlanan görev kimliği 'task_a'",
		"Tamir #2: tekrarlanan bulmaca kimliği 'puzzle_a'",
	]))


func test_decision_and_advice_must_come_together() -> void:
	var decision_only: MainHudConfigScript = MainHudConfigScript.new([], &"decision_a", &"", [], &"action_b")
	assert_eq(decision_only.get_errors(), PackedStringArray(["Karar 'decision_a' için öneri kimliği yok"]))
	var advice_only: MainHudConfigScript = MainHudConfigScript.new([], &"", &"advice_a", [], &"action_b")
	assert_eq(advice_only.get_errors(), PackedStringArray(["Öneri 'advice_a' için karar kimliği yok"]))
	var neither: MainHudConfigScript = MainHudConfigScript.new([], &"", &"", [], &"action_b")
	assert_eq(neither.get_errors(), PackedStringArray(), "Karar sunulmaması geçerlidir.")


func test_invalid_records_and_self_assignment_are_reported() -> void:
	var config: MainHudConfigScript = MainHudConfigScript.new([
		null, {"task_id": "task_a"}, MainHudConfigScript.assignment(&"task_b", &"actor_a", &"actor_a"),
	], &"", &"", [null, 3], &"action_b")
	assert_eq(config.get_errors(), PackedStringArray([
		"Atama #0: tanımsız kayıt",
		"Atama #1: tanımsız kayıt",
		"Atama #2: aktör kendisine görev veremez 'actor_a'",
		"Tamir #0: boş bulmaca kimliği",
		"Tamir #1: boş bulmaca kimliği",
	]))
	assert_eq(config.get_assignments().size(), 1, "Tanımsız kayıtlar okuyucuda atlanır.")


func test_error_order_is_deterministic() -> void:
	var make: Callable = func() -> MainHudConfigScript:
		return MainHudConfigScript.new([
			MainHudConfigScript.assignment(&"task_b", &"", &"actor_b"),
			MainHudConfigScript.assignment(&"task_b", &"actor_a", &""),
		], &"decision_a", &"", [&"puzzle_a", &"", &"puzzle_a"], &"")
	var first: PackedStringArray = make.call().get_errors()
	assert_eq(make.call().get_errors(), first)
	assert_eq(first, PackedStringArray([
		"Atama #0: boş görevi veren aktör",
		"Atama #1: tekrarlanan görev kimliği 'task_b'",
		"Atama #1: boş görevi alan aktör",
		"Karar 'decision_a' için öneri kimliği yok",
		"Tamir #1: boş bulmaca kimliği",
		"Tamir #2: tekrarlanan bulmaca kimliği 'puzzle_a'",
		"Boş bekleme eylemi kimliği",
	]))


func test_source_arrays_changed_later_do_not_affect_config() -> void:
	var entry: MainHudConfigScript.Assignment = MainHudConfigScript.assignment(&"task_a", &"actor_a", &"actor_b")
	var assignments: Array = [entry]
	var puzzles: Array = [&"puzzle_a"]
	var config: MainHudConfigScript = MainHudConfigScript.new(assignments, &"decision_a", &"advice_a", puzzles,
			&"action_b")
	entry.task_id = &"task_changed"
	entry.assigned_actor_id = &"actor_a"
	assignments.append(MainHudConfigScript.assignment(&"task_b", &"actor_a", &"actor_b"))
	puzzles.append(&"puzzle_b")
	puzzles[0] = &"puzzle_changed"
	assert_eq(config.get_errors(), PackedStringArray())
	assert_eq(config.get_assignments().size(), 1)
	assert_eq(config.get_assignment(&"task_a").assigned_actor_id, &"actor_b")
	assert_eq(config.get_repair_puzzle_ids(), [&"puzzle_a"] as Array[StringName])


func test_getter_results_cannot_change_config() -> void:
	var config: MainHudConfigScript = _valid()
	var assignments: Array = config.get_assignments()
	assignments[0].task_id = &"task_changed"
	assignments.clear()
	config.get_assignment(&"task_a").active_actor_id = &"actor_changed"
	var puzzles: Array[StringName] = config.get_repair_puzzle_ids()
	puzzles.append(&"puzzle_b")
	puzzles[0] = &"puzzle_changed"
	assert_eq(config.get_assignments().size(), 1)
	assert_eq(config.get_assignment(&"task_a").active_actor_id, &"actor_a")
	assert_eq(config.get_repair_puzzle_ids(), [&"puzzle_a"] as Array[StringName])
	assert_eq(config.get_errors(), PackedStringArray())


func _valid() -> MainHudConfigScript:
	return MainHudConfigScript.new([MainHudConfigScript.assignment(&"task_a", &"actor_a", &"actor_b")],
			&"decision_a", &"advice_a", [&"puzzle_a"], &"action_b")
