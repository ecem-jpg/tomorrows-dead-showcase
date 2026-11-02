extends "res://tests/framework/test_case.gd"
## ResourceSystem birim testleri. Yalnızca tarafsız kimlikler kullanılır (K-018).
## Varsayılan durum: res_a = 3, res_b = 0. Varsayılan sınırlar: res_a 0..10, res_b 0..(sınırsız).

const GameStateScript := preload("res://scripts/core/game_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const ResourceLimitsDataScript := preload("res://scripts/data/resource_limits_data.gd")
const ResourceSystemScript := preload("res://scripts/systems/resource_system.gd")


# --- Yapılandırma ---

func test_valid_configuration_has_no_errors() -> void:
	var system: ResourceSystemScript = ResourceSystemScript.new(_make_state(), _default_limits())
	assert_eq(system.get_configuration_errors(), PackedStringArray())


func test_configuration_reports_undefined_resource() -> void:
	var limits: ResourceLimitsDataScript = _make_limits({&"missing_id": 0}, {})
	var system: ResourceSystemScript = ResourceSystemScript.new(_make_state(), limits)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız kaynak için sınır: 'missing_id'",
	]))


func test_configuration_reports_min_greater_than_max() -> void:
	var limits: ResourceLimitsDataScript = _make_limits({&"res_a": 5}, {&"res_a": 2})
	var system: ResourceSystemScript = ResourceSystemScript.new(_make_state(), limits)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Alt sınır üst sınırdan büyük: 'res_a' (alt 5, üst 2)",
	]))


func test_configuration_reports_values_outside_limits_without_changing_them() -> void:
	var state: GameStateScript = _make_state()
	var limits: ResourceLimitsDataScript = _make_limits({&"res_a": 5}, {&"res_b": -1})
	var system: ResourceSystemScript = ResourceSystemScript.new(state, limits)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Değer alt sınırın altında: 'res_a' (değer 3, alt 5)",
		"Değer üst sınırın üstünde: 'res_b' (değer 0, üst -1)",
	]))
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(state.get_resource(&"res_b"), 0)


func test_configuration_errors_are_in_deterministic_order() -> void:
	# Sözlüğe ters sırayla eklenir; çıktı kimliğe göre sıralı olmalı.
	var limits: ResourceLimitsDataScript = _make_limits(
		{&"res_b": 1, &"missing_id": 0, &"res_a": 5}, {})
	var system: ResourceSystemScript = ResourceSystemScript.new(_make_state(), limits)
	assert_eq(system.get_configuration_errors(), PackedStringArray([
		"Tanımsız kaynak için sınır: 'missing_id'",
		"Değer alt sınırın altında: 'res_a' (değer 3, alt 5)",
		"Değer alt sınırın altında: 'res_b' (değer 0, alt 1)",
	]))


func test_limits_are_copied_on_creation() -> void:
	var limits: ResourceLimitsDataScript = _default_limits()
	var system: ResourceSystemScript = ResourceSystemScript.new(_make_state(), limits)
	limits.max_values[&"res_a"] = 100
	limits.min_values.erase(&"res_b")
	assert_eq(system.add(&"res_a", 20), 7)
	assert_false(system.can_spend(&"res_b", 1))


# --- Ekleme ---

func test_add_increases_value_and_returns_added_amount() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	assert_eq(system.add(&"res_a", 2), 2)
	assert_eq(state.get_resource(&"res_a"), 5)


func test_add_is_clamped_at_max_and_returns_actual_amount() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	assert_eq(system.add(&"res_a", 5), 5)
	assert_eq(state.get_resource(&"res_a"), 8)
	assert_eq(system.add(&"res_a", 5), 2)
	assert_eq(state.get_resource(&"res_a"), 10)


func test_add_at_max_returns_zero_without_signal() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	system.add(&"res_a", 7)
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.add(&"res_a", 1), 0)
	assert_eq(state.get_resource(&"res_a"), 10)
	assert_eq(calls[0], 0)


func test_add_without_max_is_not_clamped() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	assert_eq(system.add(&"res_b", 1000), 1000)
	assert_eq(state.get_resource(&"res_b"), 1000)


func test_add_zero_returns_zero_without_signal() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.add(&"res_a", 0), 0)
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(calls[0], 0)


func test_add_negative_errors_and_returns_zero_without_change() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.add(&"res_a", -1), 0)
	_assert_one_engine_error("res_a")
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(calls[0], 0)


func test_add_when_value_already_above_max_returns_zero_without_change() -> void:
	var state: GameStateScript = _make_state()
	# Hatalı yapılandırma: res_a = 3, üst sınır 1.
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _make_limits({}, {&"res_a": 1}))
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.add(&"res_a", 5), 0)
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(calls[0], 0)


# --- Harcama ---

func test_spend_decreases_value() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	assert_true(system.spend(&"res_a", 2))
	assert_eq(state.get_resource(&"res_a"), 1)


func test_spend_to_exact_min_is_allowed() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	assert_true(system.spend(&"res_a", 3))
	assert_eq(state.get_resource(&"res_a"), 0)


func test_spend_below_min_is_rejected_without_change_signal_or_error() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_false(system.spend(&"res_a", 4))
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0, "Yetersizlik hata sayılmamalı.")


func test_spend_without_min_can_go_negative() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _make_limits({}, {}))
	assert_true(system.spend(&"res_b", 5))
	assert_eq(state.get_resource(&"res_b"), -5)


func test_spend_zero_returns_true_without_signal() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_true(system.spend(&"res_a", 0))
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(calls[0], 0)


func test_spend_negative_errors_without_change() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_false(system.spend(&"res_a", -1))
	_assert_one_engine_error("res_a")
	assert_eq(state.get_resource(&"res_a"), 3)
	assert_eq(calls[0], 0)


func test_can_spend_has_no_side_effects() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_true(system.can_spend(&"res_a", 3))
	assert_false(system.can_spend(&"res_a", 4))
	assert_true(system.can_spend(&"res_a", 0))
	assert_eq(state.get_resources_snapshot(), {&"res_a": 3, &"res_b": 0})
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


# --- Tanımsız kaynak ve sinyal ---

func test_undefined_resource_operations_error_once_each() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	var before: Dictionary = state.get_resources_snapshot()

	assert_eq(system.add(&"missing_id", 1), 0)
	_assert_one_engine_error("missing_id")
	assert_false(system.spend(&"missing_id", 1))
	_assert_one_engine_error("missing_id")
	assert_false(system.can_spend(&"missing_id", 1))
	_assert_one_engine_error("missing_id")

	assert_eq(state.get_resources_snapshot(), before)
	assert_false(state.has_resource(&"missing_id"))
	assert_eq(calls[0], 0)


func test_state_changed_emitted_once_per_real_change() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	system.add(&"res_a", 2)
	assert_eq(calls[0], 1)
	system.spend(&"res_a", 1)
	assert_eq(calls[0], 2)
	# Kesilen ama değeri değiştiren ekleme de tek sinyal üretir.
	system.add(&"res_a", 100)
	assert_eq(calls[0], 3)


# --- Yan etkisiz hesaplama (K-025) ---

func test_compute_add_matches_add_without_side_effects() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_eq(system.compute_add(&"res_a", 2, 3), 5)
	assert_eq(system.compute_add(&"res_a", 20, 3), 10)
	assert_eq(system.compute_add(&"res_b", 1000, 0), 1000)
	# Zaten üst sınırın üstündeki değer düşürülmez.
	assert_eq(system.compute_add(&"res_a", 1, 15), 15)
	assert_eq(state.get_resources_snapshot(), {&"res_a": 3, &"res_b": 0})
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_can_spend_from_matches_can_spend_without_side_effects() -> void:
	var state: GameStateScript = _make_state()
	var system: ResourceSystemScript = ResourceSystemScript.new(state, _default_limits())
	var calls: Array[int] = _count_signals(state)
	assert_true(system.can_spend_from(&"res_a", 3, 3))
	assert_false(system.can_spend_from(&"res_a", 4, 3))
	assert_true(system.can_spend_from(&"res_a", 0, 0))
	var unbounded: ResourceSystemScript = ResourceSystemScript.new(state, _make_limits({}, {}))
	assert_true(unbounded.can_spend_from(&"res_b", 50, 0))
	assert_eq(state.get_resources_snapshot(), {&"res_a": 3, &"res_b": 0})
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


# --- Yardımcılar ---

func _make_state() -> GameStateScript:
	var setup: InitialStateDataScript = InitialStateDataScript.new()
	setup.id = "state_setup_a"
	setup.starting_resources = {&"res_a": 3, &"res_b": 0}
	setup.rng_seed = 12345
	return GameStateScript.new(setup)


func _default_limits() -> ResourceLimitsDataScript:
	return _make_limits({&"res_a": 0, &"res_b": 0}, {&"res_a": 10})


func _make_limits(min_values: Dictionary, max_values: Dictionary) -> ResourceLimitsDataScript:
	var limits: ResourceLimitsDataScript = ResourceLimitsDataScript.new()
	limits.id = "limits_a"
	limits.min_values.assign(min_values)
	limits.max_values.assign(max_values)
	return limits


func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_one_engine_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))
