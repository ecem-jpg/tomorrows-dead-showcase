extends "res://tests/framework/test_case.gd"
## TrustSystem birim testleri. Yalnızca tarafsız aktör kimlikleri kullanılır (K-018).
## Varsayılan: sınırlar 0..100; actor_a→actor_b 60, actor_b→actor_a 30, actor_a→actor_c 0, actor_c→actor_a 100.

const Fixtures := preload("res://tests/fixtures/trust_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const TrustRulesDataScript := preload("res://scripts/data/trust_rules_data.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const TrustSystemScript := preload("res://scripts/systems/trust_system.gd")

const FIXTURE_PATH: String = "res://tests/fixtures/trust/trust_rules_a.tres"


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var system: TrustSystemScript = Fixtures.make_system(Fixtures.make_state())
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_fixture_file_builds_a_valid_system() -> void:
	var rules: TrustRulesDataScript = ResourceLoader.load(FIXTURE_PATH) as TrustRulesDataScript
	var system: TrustSystemScript = TrustSystemScript.new(Fixtures.make_state(), rules)
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_configuration_reports_bounds_outside_scale() -> void:
	var system: TrustSystemScript = Fixtures.make_system(Fixtures.make_state(), Fixtures.make_rules(Fixtures.DEFAULT_ROWS, -1, 101))
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Alt sınır ölçek dışında: -1 (0..100)",
		"Üst sınır ölçek dışında: 101 (0..100)",
	]))


func test_configuration_reports_reversed_bounds() -> void:
	var system: TrustSystemScript = Fixtures.make_system(Fixtures.make_state(), Fixtures.make_rules(Fixtures.DEFAULT_ROWS, 70, 40))
	assert_eq(system.get_configuration_errors(), PackedStringArray(["Alt sınır üst sınırdan büyük: 70 > 40"]))


func test_configuration_requires_at_least_one_relationship() -> void:
	var system: TrustSystemScript = Fixtures.make_system(Fixtures.make_state(), Fixtures.make_rules([]))
	assert_eq(system.get_configuration_errors(), PackedStringArray(["En az bir güven ilişkisi tanımlanmalı"]))


func test_configuration_reports_invalid_relationships_in_order() -> void:
	var rows: Array = [
		["actor_b", "actor_a", 30],
		null,
		["", "actor_a", 1],
		["actor_a", "actor_a", 5],
		["actor_a", "actor_b", 60],
		["actor_a", "actor_b", 61],
		["actor_c", "actor_a", 101],
	]
	var system: TrustSystemScript = Fixtures.make_system(Fixtures.make_state(), Fixtures.make_rules(rows))
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız güven ilişkisi kaydı",
		"Boş aktör kimliği: '' -> 'actor_a'",
		"Kendine güven ilişkisi geçersiz: 'actor_a'",
		"Tekrarlanan güven ilişkisi: 'actor_a' -> 'actor_b'",
		"Başlangıç güveni sınır dışında: 'actor_c' -> 'actor_a' (101, 0..100)",
	]))


func test_partial_state_is_reported_as_inconsistent() -> void:
	var state: GameStateScript = Fixtures.make_state()
	state.set_trust_state(_entries([["actor_b", "actor_a", 30]]))
	var system: TrustSystemScript = Fixtures.make_system(state)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Durumda eksik güven ilişkisi: 'actor_a' -> 'actor_b'",
		"Durumda eksik güven ilişkisi: 'actor_a' -> 'actor_c'",
		"Durumda eksik güven ilişkisi: 'actor_c' -> 'actor_a'",
	]))


func test_state_with_unknown_or_out_of_range_entries_is_reported() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var rows: Array = Fixtures.DEFAULT_ROWS.duplicate(true)
	rows[0] = ["actor_a", "actor_b", 150]
	rows.append(["actor_b", "actor_c", 10])
	state.set_trust_state(_entries(rows))
	var system: TrustSystemScript = Fixtures.make_system(state)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Durumdaki güven sınır dışında: 'actor_a' -> 'actor_b' (150, 0..100)",
		"Durumda tanımsız güven ilişkisi: 'actor_b' -> 'actor_c'",
	]))


func test_configuration_errors_are_deterministic() -> void:
	var rows: Array = [["actor_c", "actor_a", 101], ["actor_a", "actor_a", 1], ["", "actor_b", 1]]
	var first: PackedStringArray = Fixtures.make_system(Fixtures.make_state(), Fixtures.make_rules(rows)).get_configuration_errors()
	rows.reverse()
	var second: PackedStringArray = Fixtures.make_system(Fixtures.make_state(), Fixtures.make_rules(rows)).get_configuration_errors()
	assert_eq(first, second)
	assert_eq(first.size(), 3)


# --- Başlatılmamış, kısmi ve tam durum ---

func test_initialize_writes_starting_values_with_one_signal() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_system(state)
	var calls: Array[int] = _count_signals(state)
	assert_true(system.initialize_relationships())
	assert_eq(calls[0], 1)
	assert_eq(_describe(state), ["actor_a>actor_b=60", "actor_a>actor_c=0", "actor_b>actor_a=30", "actor_c>actor_a=100"])


func test_initialize_twice_is_rejected_without_change() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	system.change_trust(&"actor_a", &"actor_b", 5)
	var calls: Array[int] = _count_signals(state)
	assert_false(system.initialize_relationships())
	_assert_one_engine_error("zaten başlatıldı")
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 65)
	assert_eq(calls[0], 0)


func test_uninitialized_state_rejects_queries_and_changes() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_system(state)
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.get_trust(&"actor_a", &"actor_b"), 0)
	_assert_one_engine_error("başlatılmadı")
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 5), 0)
	_assert_one_engine_error("başlatılmadı")
	assert_false(system.is_at_least(&"actor_a", &"actor_b", 10))
	_assert_one_engine_error("başlatılmadı")
	assert_eq(state.get_trust_snapshot().size(), 0)
	assert_eq(calls[0], 0)


func test_partial_state_blocks_initialize_and_changes() -> void:
	var state: GameStateScript = Fixtures.make_state()
	state.set_trust_state(_entries([["actor_b", "actor_a", 30]]))
	var system: TrustSystemScript = Fixtures.make_system(state)
	var calls: Array[int] = _count_signals(state)
	assert_false(system.initialize_relationships())
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(system.change_trust(&"actor_b", &"actor_a", 5), 0)
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(_describe(state), ["actor_b>actor_a=30"])
	assert_eq(calls[0], 0)


func test_complete_loaded_state_works_without_initialize() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var rows: Array = Fixtures.DEFAULT_ROWS.duplicate(true)
	rows[0] = ["actor_a", "actor_b", 75]
	state.set_trust_state(_entries(rows))
	var system: TrustSystemScript = Fixtures.make_system(state)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	assert_eq(system.get_trust(&"actor_a", &"actor_b"), 75)
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 5), 5)
	assert_false(system.initialize_relationships())
	_assert_one_engine_error("zaten başlatıldı")
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 80)


func test_invalid_rules_block_every_operation() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_system(state, Fixtures.make_rules([]))
	assert_false(system.initialize_relationships())
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(system.get_trust(&"actor_a", &"actor_b"), 0)
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 1), 0)
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_false(system.is_at_least(&"actor_a", &"actor_b", 0))
	_assert_one_engine_error("geçersiz yapılandırma")
	assert_eq(state.get_trust_snapshot().size(), 0)


func test_has_relationship_reports_rule_definitions_without_errors() -> void:
	var system: TrustSystemScript = Fixtures.make_system(Fixtures.make_state())
	assert_true(system.has_relationship(&"actor_a", &"actor_b"))
	assert_true(system.has_relationship(&"actor_b", &"actor_a"))
	assert_false(system.has_relationship(&"actor_b", &"actor_c"))
	assert_false(system.has_relationship(&"actor_a", &"actor_a"))
	assert_eq(take_engine_errors().size(), 0)


# --- Değişim ---

func test_change_trust_increases_and_decreases() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 10), 10)
	assert_eq(system.get_trust(&"actor_a", &"actor_b"), 70)
	assert_eq(system.change_trust(&"actor_a", &"actor_b", -25), -25)
	assert_eq(system.get_trust(&"actor_a", &"actor_b"), 45)


func test_change_trust_is_clamped_and_returns_applied_delta() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	assert_eq(system.change_trust(&"actor_b", &"actor_a", 80), 70)
	assert_eq(state.get_trust(&"actor_b", &"actor_a"), 100)
	assert_eq(system.change_trust(&"actor_a", &"actor_b", -100), -60)
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 0)


func test_change_trust_respects_custom_data_bounds() -> void:
	var rows: Array = [["actor_a", "actor_b", 50]]
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state, Fixtures.make_rules(rows, 10, 90))
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 100), 40)
	assert_eq(system.change_trust(&"actor_a", &"actor_b", -100), -80)
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 10)


func test_change_at_bound_and_zero_delta_are_silent_noops() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.change_trust(&"actor_a", &"actor_c", -5), 0)
	assert_eq(system.change_trust(&"actor_c", &"actor_a", 5), 0)
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 0), 0)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_change_trust_rejects_undefined_and_self_relationships() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.change_trust(&"actor_b", &"actor_c", 5), 0)
	_assert_one_engine_error("tanımsız güven ilişkisi")
	assert_eq(system.change_trust(&"actor_a", &"actor_a", 5), 0)
	_assert_one_engine_error("kendine güven")
	assert_eq(calls[0], 0)


func test_directions_are_independent() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	system.change_trust(&"actor_a", &"actor_b", 25)
	assert_eq(_describe(state), ["actor_a>actor_b=85", "actor_a>actor_c=0", "actor_b>actor_a=30", "actor_c>actor_a=100"])
	system.change_trust(&"actor_b", &"actor_a", -20)
	assert_eq(_describe(state), ["actor_a>actor_b=85", "actor_a>actor_c=0", "actor_b>actor_a=10", "actor_c>actor_a=100"])


func test_each_real_change_emits_exactly_one_signal() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	var calls: Array[int] = _count_signals(state)
	system.change_trust(&"actor_a", &"actor_b", 5)
	assert_eq(calls[0], 1)
	system.change_trust(&"actor_b", &"actor_a", 200)
	assert_eq(calls[0], 2)
	system.change_trust(&"actor_b", &"actor_a", 1)
	assert_eq(calls[0], 2)


func test_failed_state_write_returns_zero_without_change() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_state_setup())
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	var calls: Array[int] = _count_signals(state)
	state.reject_trust_writes = true
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 10), 0)
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_true(errors.size() == 2 and errors[0].contains("test: yazma reddedildi"), " | ".join(errors))
	assert_true(errors.size() == 2 and errors[1].contains("güven durumu yazılamadı"), " | ".join(errors))
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq(calls[0], 0)


func test_failed_initial_write_returns_false_without_change() -> void:
	var state: RejectingGameState = RejectingGameState.new(Fixtures.make_state_setup())
	state.reject_trust_writes = true
	var system: TrustSystemScript = Fixtures.make_system(state)
	assert_false(system.initialize_relationships())
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 2, " | ".join(errors))
	assert_eq(state.get_trust_snapshot().size(), 0)


# --- Eşik sorgusu ---

func test_is_at_least_compares_without_side_effects() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	var calls: Array[int] = _count_signals(state)
	assert_true(system.is_at_least(&"actor_a", &"actor_b", 60))
	assert_false(system.is_at_least(&"actor_a", &"actor_b", 61))
	assert_true(system.is_at_least(&"actor_b", &"actor_a", 30))
	assert_false(system.is_at_least(&"actor_b", &"actor_a", 31))
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 60)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_is_at_least_requires_threshold_within_active_bounds() -> void:
	var rows: Array = [["actor_a", "actor_b", 50]]
	var system: TrustSystemScript = Fixtures.make_initialized_system(Fixtures.make_state(), Fixtures.make_rules(rows, 10, 90))
	assert_true(system.is_at_least(&"actor_a", &"actor_b", 10))
	assert_false(system.is_at_least(&"actor_a", &"actor_b", 90))
	for threshold in [9, 91, 0, 100]:
		assert_false(system.is_at_least(&"actor_a", &"actor_b", threshold), str(threshold))
		_assert_one_engine_error("eşik")


func test_is_at_least_rejects_undefined_relationship() -> void:
	var system: TrustSystemScript = Fixtures.make_initialized_system(Fixtures.make_state())
	assert_false(system.is_at_least(&"actor_b", &"actor_c", 10))
	_assert_one_engine_error("tanımsız güven ilişkisi")


# --- Yan etkisiz sorgular ve hesaplama (K-025) ---

func test_is_initialized_reports_state_without_errors() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_system(state)
	assert_false(system.is_initialized())
	system.initialize_relationships()
	assert_true(system.is_initialized())
	assert_eq(take_engine_errors().size(), 0)


func test_compute_change_matches_change_trust_without_side_effects() -> void:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state, Fixtures.make_rules([["actor_a", "actor_b", 50]], 10, 90))
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.compute_change(50, 15), 65)
	assert_eq(system.compute_change(50, 100), 90)
	assert_eq(system.compute_change(50, -100), 10)
	assert_eq(state.get_trust(&"actor_a", &"actor_b"), 50)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_is_threshold_in_range_uses_active_bounds() -> void:
	var system: TrustSystemScript = Fixtures.make_system(Fixtures.make_state(), Fixtures.make_rules([["actor_a", "actor_b", 50]], 10, 90))
	assert_true(system.is_threshold_in_range(10))
	assert_true(system.is_threshold_in_range(90))
	assert_false(system.is_threshold_in_range(9))
	assert_false(system.is_threshold_in_range(91))
	assert_eq(take_engine_errors().size(), 0)


# --- Kopyalama ve determinizm ---

func test_rules_are_copied_on_creation() -> void:
	var rules: TrustRulesDataScript = Fixtures.make_rules()
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_system(state, rules)
	rules.min_value = 50
	rules.max_value = 55
	rules.relationships[0].starting_value = 99
	rules.relationships[0].target_actor_id = "actor_c"
	rules.relationships.append(null)
	assert_eq(system.get_configuration_errors(), PackedStringArray())
	system.initialize_relationships()
	assert_eq(_describe(state), ["actor_a>actor_b=60", "actor_a>actor_c=0", "actor_b>actor_a=30", "actor_c>actor_a=100"])
	assert_eq(system.change_trust(&"actor_a", &"actor_b", 50), 40)


func test_same_start_and_same_changes_produce_same_results() -> void:
	assert_eq(_run_reference_sequence(), _run_reference_sequence())


# --- Yardımcılar ---

func _run_reference_sequence() -> Array:
	var state: GameStateScript = Fixtures.make_state()
	var system: TrustSystemScript = Fixtures.make_initialized_system(state)
	var observed: Array = []
	for step in [[&"actor_a", &"actor_b", 15], [&"actor_b", &"actor_a", -40], [&"actor_c", &"actor_a", 3],
			[&"actor_a", &"actor_c", 12], [&"actor_a", &"actor_b", 50]]:
		observed.append(system.change_trust(step[0], step[1], step[2]))
		observed.append(system.is_at_least(step[0], step[1], 50))
	observed.append(_describe(state))
	return observed


# Durumdaki güveni "kaynak>hedef=değer" biçiminde sıralı özetler.
func _describe(state: GameStateScript) -> Array:
	var lines: Array = []
	for entry in state.get_trust_snapshot():
		lines.append("%s>%s=%d" % [entry.source_actor_id, entry.target_actor_id, entry.value])
	return lines


# [[kaynak, hedef, değer], ...] biçiminden tipli güven listesi kurar.
func _entries(rows: Array) -> Array[TrustRelationshipStateScript]:
	var result: Array[TrustRelationshipStateScript] = []
	for row in rows:
		result.append(TrustRelationshipStateScript.new(StringName(row[0]), StringName(row[1]), row[2]))
	return result


func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_one_engine_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))


# Güven yazmasını istendiğinde reddeden test ikizi; başarısız yazma yolunu sınamak için.
class RejectingGameState extends "res://scripts/core/game_state.gd":
	var reject_trust_writes: bool = false

	func set_trust_state(entries: Array[TrustRelationshipStateScript]) -> bool:
		if reject_trust_writes:
			push_error("test: yazma reddedildi")
			return false
		return super(entries)
