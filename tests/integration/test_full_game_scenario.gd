extends "res://tests/framework/test_case.gd"
## Genel senaryo: tarafsız sahte verilerle oyun başlangıçtan son gece sonuna kadar yalnızca açık üretim API'leriyle
## oynanır. Yol A: bütün görünümler engellenir → ending_a ("Kimse Ölmedi" teknik ölçütü). Yol B: kablo başarısız,
## görev reddedilir, iki görünüm de gece sonunda kalıcılaşır → koşulsuz yedek ending_b. Her iki yolda oyuncu öneriyi
## izlemez. Her adımın yazma/sinyal farkı ve özeti sürücü tarafından doğrulanır.

const Fixtures := preload("res://tests/fixtures/full_scenario_fixtures.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CablePuzzleStartResultScript := preload("res://scripts/systems/cable_puzzle_start_result.gd")
const DecisionResultScript := preload("res://scripts/systems/decision_result.gd")
const EndingResultScript := preload("res://scripts/systems/ending_result.gd")
const AdviceResultScript := preload("res://scripts/systems/advice_result.gd")
const AdviceVariantDataScript := preload("res://scripts/data/advice_variant_data.gd")

const PREVENTED: String = "death_prevented"
const PERMANENT: String = "death_permanent"

## Planlanan son özetler (alan sırası Fixtures.SUMMARY_FIELDS).
const EXPECTED_A: Array = [
	["ending", ["resolved", "ending_a"]],
	["time", [2, 10, true]],
	["resources", [["resource_a", 2]]],
	["flags", [["flag_a", true]]],
	["trust", [["actor_a", "actor_b", 50], ["actor_b", "actor_a", 55]]],
	["tasks", []],
	["occurrences", [["occurrence_a", PREVENTED], ["occurrence_b", PREVENTED]]],
	["equipment", [["equipment_a", "operational", "operational", 0]]],
	["cable", [["puzzle_a", 1, true]]],
]
const EXPECTED_B: Array = [
	["ending", ["resolved", "ending_b"]],
	["time", [2, 10, true]],
	["resources", [["resource_a", 2]]],
	["flags", []],
	["trust", [["actor_a", "actor_b", 45], ["actor_b", "actor_a", 50]]],
	["tasks", []],
	["occurrences", [["occurrence_a", PERMANENT], ["occurrence_b", PERMANENT]]],
	["equipment", [["equipment_a", "broken", "broken", 0]]],
	["cable", [["puzzle_a", 1, false]]],
]
## Yollar arasında farklı olması planlanan alanlar; geri kalanı aynı olmalı.
const DIFFERING_FIELDS: Array[String] = ["ending", "flags", "trust", "occurrences", "equipment", "cable"]


func test_world_configuration_is_valid_before_play() -> void:
	var world: Fixtures.World = Fixtures.make_world()
	assert_eq(world.configuration_errors(), PackedStringArray(), "Bütün yapılandırma denetimleri boş olmalı.")
	assert_eq(world.completions.get_catalog_errors(), PackedStringArray())
	assert_false(world.trust.is_initialized(), "Güven yalnızca açıkça başlatılmalı.")
	assert_eq(world.state.get_night(), 0)
	var views: Array = world.equipment.get_views()
	assert_eq(views.size(), 1)
	if views.size() == 1:
		assert_eq([String(views[0].equipment_id), String(views[0].status), views[0].usable], ["equipment_a", "broken", false])
	assert_eq(world.state.counters(), [0, 0, 0, 0, 0, 0], "Kurulum hiçbir yazma yapmamalı.")
	assert_eq(take_engine_errors(), PackedStringArray())


func test_path_a_no_one_dies_and_reaches_ending_a() -> void:
	var harness: Fixtures.ScenarioHarness = _play_path_a()
	assert_false(harness.halted, "Yol A sonuna kadar oynanmalı.")
	var world: Fixtures.World = harness.world
	var summary: Array = Fixtures.summary(world)
	assert_eq(summary, EXPECTED_A)
	# "Kimse Ölmedi" teknik kanıtı.
	var snapshot: Dictionary = world.state.get_occurrences_snapshot()
	assert_eq(snapshot.size(), 2)
	for occurrence_id: StringName in snapshot:
		assert_eq(String(snapshot[occurrence_id]), PREVENTED, "%s engellenmiş olmalı." % occurrence_id)
	var counts: Dictionary = Fixtures.occurrence_counts(world)
	assert_eq(counts[PERMANENT], 0, "death_permanent olmamalı.")
	assert_eq(counts["pending"], 0, "pending kalmamalı.")
	assert_eq(world.occurrences.get_visible_bodies().size(), 0, "Görünen ceset olmamalı.")
	assert_eq([world.state.get_night(), world.state.get_elapsed_units(), world.state.is_night_ended()], [2, 10, true])
	assert_true(world.endings.is_game_over())
	var ending: EndingResultScript = world.endings.resolve()
	assert_eq([ending.status, ending.ending_id], [EndingResultScript.STATUS_RESOLVED, &"ending_a"])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_path_b_permanent_deaths_reach_fallback_ending_b() -> void:
	var harness: Fixtures.ScenarioHarness = _play_path_b()
	assert_false(harness.halted, "Yol B sonuna kadar oynanmalı.")
	var world: Fixtures.World = harness.world
	assert_eq(Fixtures.summary(world), EXPECTED_B)
	var counts: Dictionary = Fixtures.occurrence_counts(world)
	assert_eq(counts[PERMANENT], 2, "İki görünüm de kalıcı olmalı.")
	assert_eq(counts["pending"], 0)
	assert_eq(counts[PREVENTED], 0)
	assert_eq(world.occurrences.get_visible_bodies().size(), 2, "Kalıcı cesetler görünür kalır.")
	assert_true(world.endings.is_game_over())
	var ending: EndingResultScript = world.endings.resolve()
	assert_ne(ending.ending_id, &"ending_a")
	assert_eq([ending.status, ending.ending_id], [EndingResultScript.STATUS_RESOLVED, &"ending_b"])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_advice_informs_but_explicit_choice_is_applied() -> void:
	var path_a: Fixtures.ScenarioHarness = _play_path_a()
	var path_b: Fixtures.ScenarioHarness = _play_path_b()
	# Yol A: öneri choice_b, oyuncu choice_a; yalnız choice_a etkileri (görünüm, kaynak, bayrak) uygulanır.
	assert_eq(_recommended(path_a, "advice_night_2"), "choice_b")
	assert_eq(_chosen(path_a, "choose"), "choice_a")
	assert_eq(_changed_fields(path_a.record("choose")), ["time", "resources", "flags", "occurrences"])
	assert_eq(Fixtures.field(path_a.record("choose")["after"], "trust"),
			Fixtures.field(path_a.record("choose")["before"], "trust"), "choice_b güven etkisi uygulanmamalı.")
	# Yol B: öneri choice_a, oyuncu choice_b; yalnız choice_b güven etkisi uygulanır.
	assert_eq(_recommended(path_b, "advice_night_2"), "choice_a")
	assert_eq(_chosen(path_b, "choose"), "choice_b")
	assert_eq(_changed_fields(path_b.record("choose")), ["time", "trust"])
	assert_eq(String(path_b.world.state.get_occurrence_status(&"occurrence_b")), PERMANENT)
	assert_false(path_b.world.state.get_flag(&"flag_a"), "choice_a bayrak etkisi uygulanmamalı.")
	# Gizli doğruluk sınıfı ve biçim kimliği arayüz sonucunda ve özette yoktur.
	var result: AdviceResultScript = path_a.world.advice.get_advice(&"advice_a")
	for property: Dictionary in result.get_property_list():
		assert_false(String(property["name"]) in ["accuracy", "variant_id"], "Öneri sonucu gizli alan taşımamalı.")
	assert_false(str(Fixtures.summary(path_a.world)).contains("variant"))
	assert_false(str(Fixtures.summary(path_a.world)).contains(AdviceVariantDataScript.ACCURACY_INCORRECT))
	assert_eq(take_engine_errors(), PackedStringArray())


func test_advice_reading_writes_nothing() -> void:
	for harness: Fixtures.ScenarioHarness in [_play_path_a(), _play_path_b()]:
		for label: String in ["advice_night_1", "advice_night_2"]:
			var entry: Dictionary = harness.record(label)
			assert_eq(entry["delta"], [0, 0, 0, 0, 0, 0], "%s yazmamalı." % label)
			assert_false(entry["changed"], "%s özeti değiştirmemeli." % label)
		# Oyun sonunda da tekrarlanan okuma ve iç değerlendirme yazmaz.
		var before: Array[int] = harness.world.state.counters()
		var summary: Array = Fixtures.summary(harness.world)
		harness.world.advice.get_advice(&"advice_a")
		harness.world.advice.evaluate(&"advice_a")
		assert_eq(harness.world.state.counters(), before)
		assert_eq(Fixtures.summary(harness.world), summary)
	# Biçim bilgi durumuna göre değişir: önce koşulsuz biçim, occurrence_a engellenince variant_a.
	var path_a: Fixtures.ScenarioHarness = _play_path_a()
	assert_eq(_recommended(path_a, "advice_night_1"), "choice_a")
	assert_eq(_recommended(path_a, "advice_night_2"), "choice_b")
	assert_eq(take_engine_errors(), PackedStringArray())


func test_cable_success_repairs_equipment_and_progress_atomically() -> void:
	var harness: Fixtures.ScenarioHarness = _play_path_a()
	var apply: Dictionary = harness.record("cable_apply")
	assert_eq(apply["delta"], [1, 0, 0, 0, 0, 1])
	assert_eq(_changed_fields(apply), ["time", "equipment", "cable"])
	assert_eq(Fixtures.field(apply["after"], "equipment"), [["equipment_a", "operational", "operational", 0]])
	assert_eq(Fixtures.field(apply["after"], "cable"), [["puzzle_a", 1, true]])
	assert_eq(Fixtures.field(apply["after"], "time"), [1, 2, false])
	var again: Dictionary = harness.record("cable_start_again")
	assert_eq(again["delta"], [0, 0, 0, 0, 0, 0])
	assert_false(again["changed"])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_cable_failure_applies_data_defined_outcome() -> void:
	var harness: Fixtures.ScenarioHarness = _play_path_b()
	var apply: Dictionary = harness.record("cable_apply")
	assert_eq(apply["delta"], [1, 0, 0, 0, 0, 1])
	assert_eq(_changed_fields(apply), ["time", "resources", "equipment", "cable"])
	# equipment_disable 4 aynı pakette eylemin 2 birimiyle 2'ye iner; arızalı ekipman arızalı kalır.
	assert_eq(Fixtures.field(apply["after"], "equipment"), [["equipment_a", "broken", "broken", 2]])
	assert_eq(Fixtures.field(apply["after"], "resources"), [["resource_a", 2]])
	assert_eq(Fixtures.field(apply["after"], "cable"), [["puzzle_a", 1, false]])
	assert_eq(Fixtures.field(apply["after"], "time"), [1, 2, false])
	var again: Dictionary = harness.record("cable_start_again")
	assert_eq(again["delta"], [0, 0, 0, 0, 0, 0], "Hak bitince yeni oturum yazma üretmemeli.")
	assert_false(again["changed"])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_task_and_decision_effects_reach_occurrences() -> void:
	var harness: Fixtures.ScenarioHarness = _play_path_a()
	var assign: Dictionary = harness.record("assign_task")
	assert_eq(_changed_fields(assign), ["time", "tasks"])
	assert_eq(Fixtures.field(assign["after"], "tasks"), [["task_a", "actor_b", 3]])
	var completion: Dictionary = harness.record("advance_task")
	assert_eq(_changed_fields(completion), ["time", "trust", "tasks", "occurrences"])
	assert_eq(Fixtures.field(completion["after"], "occurrences"), [["occurrence_a", PREVENTED], ["occurrence_b", "inactive"]])
	assert_eq(Fixtures.field(completion["after"], "time"), [1, 6, false])
	var choose: Dictionary = harness.record("choose")
	assert_eq(Fixtures.field(choose["after"], "occurrences"), [["occurrence_a", PREVENTED], ["occurrence_b", PREVENTED]])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_night_end_finalizes_remaining_pending() -> void:
	var harness: Fixtures.ScenarioHarness = _play_path_b()
	var first: Dictionary = harness.record("advance_to_night_end")
	assert_eq(_changed_fields(first), ["time", "occurrences", "equipment"])
	assert_eq(Fixtures.field(first["before"], "occurrences"), [["occurrence_a", "pending"], ["occurrence_b", "inactive"]])
	assert_eq(Fixtures.field(first["after"], "occurrences"), [["occurrence_a", PERMANENT], ["occurrence_b", "inactive"]])
	assert_eq(Fixtures.field(first["after"], "time"), [1, 10, true])
	var last: Dictionary = harness.record("advance_to_game_end")
	assert_eq(Fixtures.field(last["before"], "occurrences"), [["occurrence_a", PERMANENT], ["occurrence_b", "pending"]])
	assert_eq(Fixtures.field(last["after"], "occurrences"), [["occurrence_a", PERMANENT], ["occurrence_b", PERMANENT]])
	# Yol A'da gece sonları hiçbir şeyi kalıcılaştırmaz.
	var path_a: Fixtures.ScenarioHarness = _play_path_a()
	assert_eq(_changed_fields(path_a.record("advance_to_night_end")), ["time"])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_unavailable_choice_changes_nothing() -> void:
	var harness: Fixtures.ScenarioHarness = _play_path_b()
	var entry: Dictionary = harness.record("choose_unavailable")
	assert_eq(entry["delta"], [0, 0, 0, 0, 0, 0])
	assert_false(entry["changed"], "Uygulanamayan seçimde hiçbir kategori değişmemeli.")
	var rejected: Dictionary = harness.record("assign_task")
	assert_eq(_changed_fields(rejected), ["time", "equipment"], "Ret yalnızca deneme süresini yazar.")
	assert_eq(Fixtures.field(rejected["after"], "tasks"), [])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_every_step_writes_at_most_once() -> void:
	for harness: Fixtures.ScenarioHarness in [_play_path_a(), _play_path_b()]:
		assert_false(harness.halted)
		for entry: Dictionary in harness.records:
			assert_true(entry["delta"][0] <= 1 and entry["delta"][5] <= 1, "%s en fazla bir yazma/sinyal" % entry["label"])
			assert_eq(entry["delta"], entry["expected"], "%s sayaç farkı" % entry["label"])
		var totals: Array[int] = harness.world.state.counters()
		assert_eq(totals.slice(1, 5), [0, 0, 0, 1], "Doğrudan yazma yok; yalnız güven başlatma set_trust_state kullanır.")
		var writing_steps: int = 0
		for entry: Dictionary in harness.records:
			writing_steps += entry["delta"][0]
		assert_eq(totals[0], writing_steps, "Toplam apply_changes adımların toplamına eşit olmalı.")
		assert_eq(totals[5], writing_steps + 1, "Sinyaller: her yazma bir kez + güven başlatma.")
	assert_eq(take_engine_errors(), PackedStringArray())


func test_ending_resolves_only_after_last_night() -> void:
	for harness: Fixtures.ScenarioHarness in [_play_path_a(), _play_path_b()]:
		for label: String in ["resolve_before_start", "resolve_after_night_1"]:
			var entry: Dictionary = harness.record(label)
			assert_eq(Fixtures.field(entry["after"], "ending"), ["game_not_over", ""], label)
			assert_eq(entry["delta"], [0, 0, 0, 0, 0, 0])
	var path_a: Fixtures.ScenarioHarness = _play_path_a()
	assert_eq(Fixtures.field(path_a.record("resolve_during_night_2")["after"], "ending"), ["game_not_over", ""])
	assert_eq(Fixtures.field(path_a.record("advance_to_game_end")["before"], "ending"), ["game_not_over", ""])
	assert_eq(Fixtures.field(path_a.record("advance_to_game_end")["after"], "ending"), ["resolved", "ending_a"])
	assert_eq(take_engine_errors(), PackedStringArray())


func test_worlds_share_no_objects() -> void:
	var first: Fixtures.World = Fixtures.make_world()
	var second: Fixtures.World = Fixtures.make_world()
	assert_true(first.setup != second.setup, "InitialStateData paylaşılmamalı.")
	assert_true(first.state != second.state, "GameState paylaşılmamalı.")
	var first_systems: Array[RefCounted] = first.systems()
	var second_systems: Array[RefCounted] = second.systems()
	for i in first_systems.size():
		assert_true(first_systems[i] != null and first_systems[i] != second_systems[i], "Sistem #%d paylaşılmamalı." % i)
	var first_resources: Array[Resource] = first.all_resources()
	var second_ids: Dictionary = {}
	for resource: Resource in second.all_resources():
		second_ids[resource.get_instance_id()] = true
	assert_true(first_resources.size() > 20, "Alt kaynaklar da toplanmalı (%d)." % first_resources.size())
	var shared: int = 0
	for resource: Resource in first_resources:
		if second_ids.has(resource.get_instance_id()):
			shared += 1
	assert_eq(shared, 0, "Veri kaynakları veya alt kaynakları paylaşılmamalı.")
	assert_eq(take_engine_errors(), PackedStringArray())


func test_unplayed_world_is_unaffected_by_other_path() -> void:
	var untouched: Fixtures.World = Fixtures.make_world()
	var before: Array = Fixtures.summary(untouched)
	var counters: Array[int] = untouched.state.counters()
	_play_path_a()
	_play_path_b()
	assert_eq(Fixtures.summary(untouched), before)
	assert_eq(untouched.state.counters(), counters)
	assert_eq(untouched.configuration_errors(), PackedStringArray())
	assert_eq(take_engine_errors(), PackedStringArray())


func test_each_path_is_deterministic_across_fresh_runs() -> void:
	var a1: Array = Fixtures.summary(_play_path_a().world)
	var a2: Array = Fixtures.summary(_play_path_a().world)
	var b1: Array = Fixtures.summary(_play_path_b().world)
	var b2: Array = Fixtures.summary(_play_path_b().world)
	assert_eq(a1, a2, "Yol A iki koşuda aynı özeti üretmeli.")
	assert_eq(b1, b2, "Yol B iki koşuda aynı özeti üretmeli.")
	assert_eq(_step_trace(_play_path_a()), _step_trace(_play_path_a()), "Yol A adım izleri aynı olmalı.")
	assert_eq(_step_trace(_play_path_b()), _step_trace(_play_path_b()), "Yol B adım izleri aynı olmalı.")
	assert_eq(take_engine_errors(), PackedStringArray())


func test_paths_differ_only_in_planned_fields() -> void:
	var a: Array = Fixtures.summary(_play_path_a().world)
	var b: Array = Fixtures.summary(_play_path_b().world)
	for field_name: String in Fixtures.SUMMARY_FIELDS:
		if DIFFERING_FIELDS.has(field_name):
			assert_ne(Fixtures.field(a, field_name), Fixtures.field(b, field_name), "%s farklı olmalı." % field_name)
		else:
			assert_eq(Fixtures.field(a, field_name), Fixtures.field(b, field_name), "%s aynı olmalı." % field_name)
	assert_eq(take_engine_errors(), PackedStringArray())


# --- Yollar ---

## Yol A: kablo çözülür, görev occurrence_a'yı engeller; ikinci gece öneri choice_b der, oyuncu choice_a seçer.
func _play_path_a() -> Fixtures.ScenarioHarness:
	var world: Fixtures.World = Fixtures.make_world()
	var h: Fixtures.ScenarioHarness = Fixtures.ScenarioHarness.new(world, self, "Yol A")
	_opening(h)
	var start: Variant = h.step("cable_start", 0, func() -> Variant: return world.cable.start_session(&"puzzle_a"),
			func(r: Variant) -> bool: return r.is_started())
	if h.halted:
		return h
	var session: CablePuzzleSessionScript = start.session
	var solve: Callable = func() -> Variant:
		session.connect_terminals(Fixtures.TERMINAL_A, Fixtures.TERMINAL_B)
		session.connect_terminals(Fixtures.TERMINAL_C, Fixtures.TERMINAL_D)
		return session.submit()
	h.step("cable_moves", 0, solve, func(r: Variant) -> bool: return r == CablePuzzleSessionScript.SUBMIT_SOLVED)
	h.step("cable_apply", 1, func() -> Variant: return world.cable.apply_result(session),
			func(r: Variant) -> bool: return r.ok and r.outcome == CablePuzzleSessionScript.STATUS_SOLVED)
	h.step("cable_start_again", 0, func() -> Variant: return world.cable.start_session(&"puzzle_a"),
			func(r: Variant) -> bool: return r.failure == CablePuzzleStartResultScript.FAILURE_ALREADY_SOLVED)
	h.step("assign_task", 1, func() -> Variant: return world.tasks.assign_task(&"task_a", &"actor_a", &"actor_b"),
			func(r: Variant) -> bool: return r.is_accepted())
	h.step("advance_task", 1, func() -> Variant: return world.completions.advance(3),
			func(r: Variant) -> bool: return (r.ok and r.completed_task_ids() == [&"task_a"]
				and r.completions[0].status == &"applied"))
	h.step("advance_to_night_end", 1, func() -> Variant: return world.completions.advance(100),
			func(r: Variant) -> bool: return r.ok and r.time_result.applied_units == 4 and r.permanent_occurrence_ids.is_empty())
	_middle(h)
	h.step("advice_night_2", 0, func() -> Variant: return world.advice.get_advice(&"advice_a"),
			func(r: Variant) -> bool: return r.is_offered() and r.recommended_choice_id == &"choice_b")
	h.step("resolve_during_night_2", 0, func() -> Variant: return world.endings.resolve(),
			func(r: Variant) -> bool: return r.status == EndingResultScript.STATUS_GAME_NOT_OVER)
	h.step("choose", 1, func() -> Variant: return world.decisions.choose(&"decision_a", &"choice_a"),
			func(r: Variant) -> bool: return r.ok and r.choice_id == &"choice_a")
	h.step("advance_to_game_end", 1, func() -> Variant: return world.completions.advance(100),
			func(r: Variant) -> bool: return r.ok and r.time_result.applied_units == 9 and r.permanent_occurrence_ids.is_empty())
	h.step("resolve_final", 0, func() -> Variant: return world.endings.resolve(),
			func(r: Variant) -> bool: return r.is_resolved() and r.ending_id == &"ending_a")
	return h


## Yol B: kablo başarısız, tekrar hakkı yok, görev reddedilir; occurrence_a gece sonunda kalıcılaşır. İkinci gece
## öneri choice_a der, oyuncu choice_b seçer; occurrence_b de kalıcılaşır.
func _play_path_b() -> Fixtures.ScenarioHarness:
	var world: Fixtures.World = Fixtures.make_world()
	var h: Fixtures.ScenarioHarness = Fixtures.ScenarioHarness.new(world, self, "Yol B")
	_opening(h)
	var start: Variant = h.step("cable_start", 0, func() -> Variant: return world.cable.start_session(&"puzzle_a"),
			func(r: Variant) -> bool: return r.is_started())
	if h.halted:
		return h
	var session: CablePuzzleSessionScript = start.session
	var miswire: Callable = func() -> Variant:
		session.connect_terminals(Fixtures.TERMINAL_A, Fixtures.TERMINAL_D)
		session.connect_terminals(Fixtures.TERMINAL_C, Fixtures.TERMINAL_B)
		return session.submit()
	h.step("cable_moves", 0, miswire, func(r: Variant) -> bool: return r == CablePuzzleSessionScript.SUBMIT_FAILED)
	h.step("cable_apply", 1, func() -> Variant: return world.cable.apply_result(session),
			func(r: Variant) -> bool: return r.ok and r.outcome == CablePuzzleSessionScript.STATUS_FAILED)
	h.step("cable_start_again", 0, func() -> Variant: return world.cable.start_session(&"puzzle_a"),
			func(r: Variant) -> bool: return r.failure == CablePuzzleStartResultScript.FAILURE_RESOLUTION_LIMIT_REACHED)
	h.step("choose_unavailable", 0, func() -> Variant: return world.decisions.choose(&"decision_a", &"choice_a"),
			func(r: Variant) -> bool: return (not r.ok and r.failure == DecisionResultScript.FAILURE_EFFECT_NOT_APPLICABLE
				and r.blocking_effect_index == 0))
	h.step("assign_task", 1, func() -> Variant: return world.tasks.assign_task(&"task_a", &"actor_a", &"actor_b"),
			func(r: Variant) -> bool: return r.is_rejected() and r.failed_condition_indexes == PackedInt32Array([1]))
	h.step("advance_to_night_end", 1, func() -> Variant: return world.completions.advance(100),
			func(r: Variant) -> bool: return (r.ok and r.time_result.applied_units == 7
				and r.permanent_occurrence_ids == [&"occurrence_a"] and r.equipment_disable_expirations.size() == 1
				and r.equipment_disable_expirations[0].at_units == 4))
	_middle(h)
	h.step("advice_night_2", 0, func() -> Variant: return world.advice.get_advice(&"advice_a"),
			func(r: Variant) -> bool: return r.is_offered() and r.recommended_choice_id == &"choice_a")
	h.step("choose", 1, func() -> Variant: return world.decisions.choose(&"decision_a", &"choice_b"),
			func(r: Variant) -> bool: return r.ok and r.choice_id == &"choice_b")
	h.step("advance_to_game_end", 1, func() -> Variant: return world.completions.advance(100),
			func(r: Variant) -> bool: return (r.ok and r.time_result.applied_units == 9
				and r.permanent_occurrence_ids == [&"occurrence_b"]))
	h.step("resolve_final", 0, func() -> Variant: return world.endings.resolve(),
			func(r: Variant) -> bool: return r.is_resolved() and r.ending_id == &"ending_b")
	return h


## İki yolun ortak açılışı: güven başlatma, son sorgusu, ilk gece ve ilk öneri (koşulsuz biçim → choice_a).
func _opening(h: Fixtures.ScenarioHarness) -> void:
	var world: Fixtures.World = h.world
	h.step("trust_init", 0, func() -> Variant: return world.trust.initialize_relationships(),
			func(r: Variant) -> bool: return r == true, 1)
	h.step("resolve_before_start", 0, func() -> Variant: return world.endings.resolve(),
			func(r: Variant) -> bool: return r.status == EndingResultScript.STATUS_GAME_NOT_OVER)
	h.step("night_1", 1, func() -> Variant: return world.occurrences.start_night(),
			func(r: Variant) -> bool: return r.ok and r.night == 1 and r.arrived_ids == [&"occurrence_a"])
	h.step("advice_night_1", 0, func() -> Variant: return world.advice.get_advice(&"advice_a"),
			func(r: Variant) -> bool: return r.is_offered() and r.recommended_choice_id == &"choice_a")


## İlk gece bittikten sonra: son sorgusu ve ikinci gece.
func _middle(h: Fixtures.ScenarioHarness) -> void:
	var world: Fixtures.World = h.world
	h.step("resolve_after_night_1", 0, func() -> Variant: return world.endings.resolve(),
			func(r: Variant) -> bool: return r.status == EndingResultScript.STATUS_GAME_NOT_OVER)
	h.step("night_2", 1, func() -> Variant: return world.occurrences.start_night(),
			func(r: Variant) -> bool: return r.ok and r.night == 2 and r.arrived_ids == [&"occurrence_b"])


# --- Yardımcılar ---

func _recommended(harness: Fixtures.ScenarioHarness, label: String) -> String:
	var result: Variant = _result_of(harness, label)
	return "" if result == null else String(result.recommended_choice_id)


func _chosen(harness: Fixtures.ScenarioHarness, label: String) -> String:
	var result: Variant = _result_of(harness, label)
	return "" if result == null else String(result.choice_id)


## Adımın kaydedilmiş üretim sonucu (öneri, seçim); kayıt yoksa null.
func _result_of(harness: Fixtures.ScenarioHarness, label: String) -> Variant:
	var entry: Dictionary = harness.record(label)
	return entry.get("result")


## Önceki ve sonraki özet arasında değişen alanlar (SUMMARY_FIELDS sırasıyla).
func _changed_fields(entry: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if entry.is_empty():
		return result
	for field_name: String in Fixtures.SUMMARY_FIELDS:
		if Fixtures.field(entry["before"], field_name) != Fixtures.field(entry["after"], field_name):
			result.append(field_name)
	return result


## Karşılaştırılabilir adım izi: etiket, sayaç farkı, sonraki özet.
func _step_trace(harness: Fixtures.ScenarioHarness) -> Array:
	var trace: Array = []
	for entry: Dictionary in harness.records:
		trace.append([entry["label"], entry["delta"], entry["after"]])
	return trace
