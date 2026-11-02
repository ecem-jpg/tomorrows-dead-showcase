extends "res://tests/framework/test_case.gd"
## MainHudPresenter: yapılandırma hataları, yan etkisiz ve tekrarlanabilir model, model içeriği, komutların tek
## durum değiştiren sistem çağrısına iletilmesi, genel geri bildirim, yapılandırma dışı kimlikler ve mimari sınır.
## Her test genel senaryo fikstüründen tamamen yeni bir dünya kurar (bekleme eylemi olarak action_b = 1 birim).

const Fixtures := preload("res://tests/fixtures/full_scenario_fixtures.gd")
const MainHudPresenterScript := preload("res://scripts/presentation/main_hud_presenter.gd")
const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")
const MainHudConfigScript := preload("res://scripts/presentation/main_hud_config.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CablePuzzleStartResultScript := preload("res://scripts/systems/cable_puzzle_start_result.gd")
const CableRepairResultScript := preload("res://scripts/systems/cable_repair_result.gd")
const TaskAssignmentResultScript := preload("res://scripts/systems/task_assignment_result.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const TimeProgressResultScript := preload("res://scripts/systems/time_progress_result.gd")
const NightStartResultScript := preload("res://scripts/systems/night_start_result.gd")

const PRESENTER_PATH: String = "res://scripts/presentation/main_hud_presenter.gd"
const DONE: StringName = &"UI_HUD_DONE"
const REJECTED: StringName = &"UI_HUD_REJECTED"
const UNAVAILABLE: StringName = &"UI_HUD_UNAVAILABLE"
const ERROR_KEY: StringName = &"UI_HUD_ERROR"
const NO_WRITES: Array[int] = [0, 0, 0, 0, 0, 0]
const ONE_WRITE: Array[int] = [1, 0, 0, 0, 0, 1]

var _world: Fixtures.World
var _presenter: MainHudPresenterScript


func test_configuration_errors_report_missing_and_unknown() -> void:
	var missing: MainHudPresenterScript = MainHudPresenterScript.new(null, null, null, null, null, null, null, null,
			null, null, null)
	assert_eq(missing.get_configuration_errors().size(), 11, "Her eksik bağımlılık ayrı satır.")
	_setup()
	assert_eq(_presenter.get_configuration_errors(), PackedStringArray())
	var unknown: MainHudConfigScript = MainHudConfigScript.new(
			[MainHudConfigScript.assignment(&"task_x", &"actor_a", &"actor_b")], &"decision_x", &"advice_x",
			[&"puzzle_x"], &"action_x")
	assert_eq(_make(unknown).get_configuration_errors(), PackedStringArray([
		"Yapılandırmada tanımsız görev 'task_x'",
		"Yapılandırmada tanımsız karar 'decision_x'",
		"Yapılandırmada tanımsız öneri 'advice_x'",
		"Yapılandırmada tanımsız bulmaca 'puzzle_x'",
		"Yapılandırmada tanımsız bekleme eylemi 'action_x'",
	]))
	var inconsistent: MainHudConfigScript = MainHudConfigScript.new([], &"decision_a", &"", [], &"")
	assert_eq(_make(inconsistent).get_configuration_errors(), PackedStringArray([
		"MainHudConfig: Karar 'decision_a' için öneri kimliği yok",
		"MainHudConfig: Boş bekleme eylemi kimliği",
	]))
	assert_eq(take_engine_errors(), PackedStringArray())


func test_model_before_first_night_is_safe() -> void:
	_setup(false)
	var before: Array[int] = _world.state.counters()
	var model: MainHudModelScript = _presenter.build_model()
	assert_eq(_world.state.counters(), before)
	assert_true(model.has_session)
	assert_eq([model.night, model.night_count, model.elapsed_units, model.night_length_units, model.night_ended],
			[0, 2, 0, 0, false])
	assert_eq([model.can_wait, model.can_start_night, model.advice_offered], [false, true, false])
	assert_eq(_available(model.assignable) + _available(model.repairs) + _available(model.choices), [false, false, false, false])
	assert_eq(model.ending_id, &"")
	assert_eq(take_engine_errors(), PackedStringArray(), "Güven başlamadan önizleme yapılmamalı.")


func test_build_model_writes_nothing_and_repeats_identically() -> void:
	_setup()
	_presenter.start_night()
	var before: Array[int] = _world.state.counters()
	var summary: Array = Fixtures.summary(_world)
	var first: MainHudModelScript = _presenter.build_model()
	var second: MainHudModelScript = _presenter.build_model()
	assert_eq(_world.state.counters(), before, "build_model yazma veya sinyal üretmemeli.")
	assert_eq(Fixtures.summary(_world), summary)
	assert_true(first.equals(second))
	assert_true(first != second)
	first.resources[0].value = 99
	first.bodies.clear()
	first.choices[0].available = not first.choices[0].available
	var third: MainHudModelScript = _presenter.build_model()
	assert_true(third.equals(second), "Önceki modeli değiştirmek sonrakini etkilememeli.")
	assert_eq(Fixtures.summary(_world), summary)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_model_reflects_resources_time_tasks_equipment_and_bodies() -> void:
	_setup()
	_presenter.start_night()
	_repair(true)
	_presenter.assign(&"task_a")
	var data: Dictionary = _presenter.build_model().to_dict()
	assert_eq(data["resources"], [{"resource_id": &"resource_a", "value": 3}])
	assert_eq([data["night"], data["elapsed_units"], data["night_length_units"], data["night_ended"]], [1, 3, 10, false])
	assert_eq(data["tasks"], [{"task_id": &"task_a", "assigned_actor_id": &"actor_b", "remaining_units": 3}])
	assert_eq(data["assignable"], [{"task_id": &"task_a", "active_actor_id": &"actor_a", "assigned_actor_id": &"actor_b",
			"available": false}], "Etkin görev yeniden denenemez.")
	assert_eq(data["equipment"], [{"equipment_id": &"equipment_a", "status": &"operational", "disabled_units": 0,
			"usable": true}])
	assert_eq(data["repairs"], [{"puzzle_id": &"puzzle_a", "available": true}])
	assert_eq(data["bodies"], [{"occurrence_id": &"occurrence_a", "subject_id": &"subject_a", "night": 1,
			"presence": &"present"}])
	assert_eq(data["decision_id"], &"decision_a")
	assert_eq(data["choices"], [{"choice_id": &"choice_a", "available": false}, {"choice_id": &"choice_b", "available": true}],
			"occurrence_b henüz gelmediği için choice_a uygulanamaz.")
	assert_eq([data["can_wait"], data["can_start_night"]], [true, false])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_advice_exposes_only_displayable_fields() -> void:
	_setup()
	_presenter.start_night()
	var model: MainHudModelScript = _presenter.build_model()
	assert_eq([model.advice_offered, model.advisor_actor_id, model.recommended_choice_id], [true, &"actor_b", &"choice_a"])
	var text: String = str(model.to_dict())
	for forbidden: String in ["accuracy", "variant", "correct"]:
		assert_false(text.contains(forbidden), "Modelde '%s' olmamalı." % forbidden)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_assign_calls_task_system_once() -> void:
	_setup()
	_presenter.start_night()
	_repair(true)
	var before: Array[int] = _world.state.counters()
	var result: TaskAssignmentResultScript = _presenter.assign(&"task_a")
	assert_eq(_delta(before), ONE_WRITE)
	assert_true(result != null and result.is_accepted())
	assert_eq(result.started_task.task_id, &"task_a")
	assert_eq(_presenter.get_feedback_key(), DONE)
	assert_eq(_presenter.build_model().feedback_key, DONE)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_assign_rejection_stays_a_rejection() -> void:
	_setup()
	_presenter.start_night()
	var before: Array[int] = _world.state.counters()
	var result: TaskAssignmentResultScript = _presenter.assign(&"task_a")
	assert_eq(_delta(before), ONE_WRITE, "Ret yalnızca deneme süresini yazar.")
	assert_true(result != null and result.is_rejected())
	assert_eq(result.failed_condition_indexes, PackedInt32Array([1]))
	assert_eq(_presenter.get_feedback_key(), REJECTED)
	assert_eq(_world.state.get_tasks_snapshot().size(), 0, "Ret başka bir komuta dönüşmemeli.")
	assert_eq(take_engine_errors(), PackedStringArray())


func test_choose_applies_explicit_choice_not_the_advice() -> void:
	_setup()
	_presenter.start_night()
	assert_eq(_presenter.build_model().recommended_choice_id, &"choice_a")
	var before: Array[int] = _world.state.counters()
	var result: DecisionResultScript = _presenter.choose(&"choice_b")
	assert_eq(_delta(before), ONE_WRITE)
	assert_true(result != null and result.ok and result.choice_id == &"choice_b")
	assert_eq(_world.state.get_trust(&"actor_a", &"actor_b"), 45)
	assert_eq(_world.state.get_resource(&"resource_a"), 3, "Önerilen choice_a etkileri uygulanmamalı.")
	assert_false(_world.state.get_flag(&"flag_a"))
	assert_eq(_presenter.get_feedback_key(), DONE)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_unavailable_choice_changes_nothing() -> void:
	_setup()
	_presenter.start_night()
	var before: Array[int] = _world.state.counters()
	var summary: Array = Fixtures.summary(_world)
	var result: DecisionResultScript = _presenter.choose(&"choice_a")
	assert_eq(_delta(before), NO_WRITES)
	assert_eq(Fixtures.summary(_world), summary)
	assert_eq(result.failure, DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE)
	assert_eq(_presenter.get_feedback_key(), UNAVAILABLE)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_wait_uses_data_cost_and_only_advance() -> void:
	_setup()
	var before: Array[int] = _world.state.counters()
	assert_true(_presenter.wait() == null, "Etkin gece yokken sistem çağrılmaz.")
	assert_eq(_delta(before), NO_WRITES)
	assert_eq(_presenter.get_feedback_key(), UNAVAILABLE)
	_presenter.start_night()
	before = _world.state.counters()
	var result: TimeProgressResultScript = _presenter.wait()
	assert_eq(_delta(before), ONE_WRITE)
	assert_true(result != null and result.ok and result.time_result.applied_units == 1)
	assert_eq(_world.state.get_elapsed_units(), 1, "Süre bekleme eyleminin verideki maliyetidir.")
	assert_eq(_presenter.get_feedback_key(), DONE)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_start_night_once_then_unavailable() -> void:
	_setup()
	var before: Array[int] = _world.state.counters()
	var result: NightStartResultScript = _presenter.start_night()
	assert_eq(_delta(before), ONE_WRITE)
	assert_true(result != null and result.ok and result.night == 1)
	assert_eq(_presenter.get_feedback_key(), DONE)
	before = _world.state.counters()
	assert_true(_presenter.start_night() == null, "Gece sürerken sistem çağrılmaz.")
	assert_eq(_delta(before), NO_WRITES)
	assert_eq(_presenter.get_feedback_key(), UNAVAILABLE)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_repair_start_and_finish() -> void:
	_setup()
	_presenter.start_night()
	var before: Array[int] = _world.state.counters()
	var start: CablePuzzleStartResultScript = _presenter.start_repair(&"puzzle_a")
	assert_eq(_delta(before), NO_WRITES, "Oturum açmak yazmaz.")
	assert_true(start != null and start.is_started())
	assert_eq(_presenter.get_feedback_key(), &"")
	var session: CablePuzzleSessionScript = start.session
	session.connect_terminals(Fixtures.TERMINAL_A, Fixtures.TERMINAL_B)
	session.connect_terminals(Fixtures.TERMINAL_C, Fixtures.TERMINAL_D)
	session.submit()
	before = _world.state.counters()
	var result: CableRepairResultScript = _presenter.finish_repair(session)
	assert_eq(_delta(before), ONE_WRITE)
	assert_true(result != null and result.ok)
	assert_eq(_presenter.get_feedback_key(), DONE)
	assert_eq(_presenter.build_model().equipment[0].status, &"operational")
	before = _world.state.counters()
	var again: CablePuzzleStartResultScript = _presenter.start_repair(&"puzzle_a")
	assert_eq(again.failure, CablePuzzleStartResultScript.FAILURE_ALREADY_SOLVED)
	assert_eq(_presenter.get_feedback_key(), UNAVAILABLE, "Normal ret başka komuta dönüşmez.")
	assert_eq(_delta(before), NO_WRITES)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_repair_failure_applies_failure_branch() -> void:
	_setup()
	_presenter.start_night()
	_repair(false)
	assert_eq(_presenter.get_feedback_key(), DONE, "Başarısızlık dalının uygulanması başarılı bir komuttur.")
	var model: MainHudModelScript = _presenter.build_model()
	assert_eq([model.equipment[0].status, model.equipment[0].disabled_units], [&"broken", 2])
	assert_eq(model.resources[0].value, 2)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_unknown_ids_change_nothing() -> void:
	_setup()
	_presenter.start_night()
	var before: Array[int] = _world.state.counters()
	var summary: Array = Fixtures.summary(_world)
	assert_true(_presenter.assign(&"task_x") == null)
	assert_eq(_presenter.get_feedback_key(), ERROR_KEY)
	assert_true(_presenter.choose(&"choice_x") == null)
	assert_true(_presenter.start_repair(&"puzzle_x") == null)
	assert_true(_presenter.finish_repair(null) == null)
	var foreign: CablePuzzleSessionScript = CablePuzzleSessionScript.create(_world.puzzles_data[0])
	foreign.connect_terminals(Fixtures.TERMINAL_A, Fixtures.TERMINAL_B)
	foreign.connect_terminals(Fixtures.TERMINAL_C, Fixtures.TERMINAL_D)
	foreign.submit()
	var unlisted: MainHudPresenterScript = _make(MainHudConfigScript.new([], &"", &"", [], &"action_b"))
	assert_true(unlisted.finish_repair(foreign) == null, "Yapılandırmada olmayan bulmacanın oturumu reddedilir.")
	assert_true(unlisted.choose(&"choice_a") == null, "Sunulan karar yoksa seçim yapılmaz.")
	assert_eq(take_engine_errors(), PackedStringArray(), "Presenter retleri motor hatası basmaz.")
	assert_eq(_delta(before), NO_WRITES)
	assert_eq(Fixtures.summary(_world), summary)
	assert_eq(_presenter.get_feedback_key(), ERROR_KEY)


func test_invalid_configuration_blocks_model_and_commands() -> void:
	_setup()
	_presenter = _make(MainHudConfigScript.new([], &"", &"", [], &""))
	_presenter.start_night()
	var before: Array[int] = _world.state.counters()
	var model: MainHudModelScript = _presenter.build_model()
	assert_false(model.has_session)
	assert_eq(model.feedback_key, ERROR_KEY)
	assert_true(_presenter.wait() == null)
	assert_eq(_presenter.get_feedback_key(), ERROR_KEY)
	assert_eq(take_engine_errors(), PackedStringArray(), "Presenter retleri motor hatası basmaz.")
	assert_eq(_delta(before), NO_WRITES)
	assert_eq(_world.state.get_night(), 0, "Geçersiz yapılandırmada gece başlatılmaz.")


func test_ending_appears_only_after_last_night() -> void:
	_setup()
	_presenter.start_night()
	_repair(true)
	_presenter.assign(&"task_a")
	_wait_until_night_end()
	var mid: MainHudModelScript = _presenter.build_model()
	assert_eq([mid.ending_id, mid.can_start_night, mid.can_wait], [&"", true, false])
	_presenter.start_night()
	assert_eq(_presenter.build_model().recommended_choice_id, &"choice_b")
	_presenter.choose(&"choice_a")
	_wait_until_night_end()
	var final: MainHudModelScript = _presenter.build_model()
	assert_eq(final.ending_id, &"ending_a")
	assert_eq([final.can_start_night, final.can_wait, final.night, final.night_ended], [false, false, 2, true])
	assert_eq(final.bodies.size(), 0)
	assert_eq(take_engine_errors(), PackedStringArray())


func test_presenter_source_respects_mutation_boundary() -> void:
	var code: String = _code_of(FileAccess.get_file_as_string(PRESENTER_PATH))
	for forbidden: String in ["apply_changes", "set_resource", "set_flag", "set_time_state", "set_trust_state",
			".evaluate(", "get(\"_", "initialize_relationships", "full_scenario", "res://tests/", "_process", "push_error"]:
		assert_false(code.contains(forbidden), "Presenter '%s' izi taşımamalı." % forbidden)
	for mutator: String in ["\\.assign_task\\(", "\\.choose\\(", "\\.advance\\(", "\\.start_night\\(",
			"\\.start_session\\(", "\\.apply_result\\("]:
		assert_eq(RegEx.create_from_string(mutator).search_all(code).size(), 1, "%s tam bir yerde çağrılmalı." % mutator)


# --- Yardımcılar ---

## Yeni dünya ve geçerli yapılandırmalı presenter; started = true ise güven açıkça başlatılır.
func _setup(started: bool = true) -> void:
	_world = Fixtures.make_world()
	if started:
		_world.trust.initialize_relationships()
	_presenter = _make(MainHudConfigScript.new([MainHudConfigScript.assignment(&"task_a", &"actor_a", &"actor_b")],
			&"decision_a", &"advice_a", [&"puzzle_a"], &"action_b"))


func _make(config: MainHudConfigScript) -> MainHudPresenterScript:
	return MainHudPresenterScript.new(_world.state, _world.time, _world.completions, _world.tasks, _world.decisions,
			_world.advice, _world.occurrences, _world.equipment, _world.cable, _world.endings, config)


func _repair(solve: bool) -> void:
	var session: CablePuzzleSessionScript = _presenter.start_repair(&"puzzle_a").session
	if solve:
		session.connect_terminals(Fixtures.TERMINAL_A, Fixtures.TERMINAL_B)
		session.connect_terminals(Fixtures.TERMINAL_C, Fixtures.TERMINAL_D)
	else:
		session.connect_terminals(Fixtures.TERMINAL_A, Fixtures.TERMINAL_D)
		session.connect_terminals(Fixtures.TERMINAL_C, Fixtures.TERMINAL_B)
	session.submit()
	_presenter.finish_repair(session)


func _wait_until_night_end() -> void:
	for i in 20:
		if not _presenter.build_model().can_wait:
			return
		_presenter.wait()


func _delta(before: Array[int]) -> Array[int]:
	var after: Array[int] = _world.state.counters()
	var result: Array[int] = []
	for i in after.size():
		result.append(after[i] - before[i])
	return result


static func _available(rows: Array) -> Array:
	return rows.map(func(row: RefCounted) -> bool: return row.get("available"))


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
