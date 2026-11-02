extends "res://tests/framework/test_case.gd"
## Ekipman durumunun GameState kuralları (K-031): başlangıç verisi, anlık görüntüler ve atomik yazma.
## Yalnızca tarafsız kimlikler kullanılır (K-018).

const Fixtures := preload("res://tests/fixtures/equipment_fixtures.gd")
const GameStateScript := preload("res://scripts/core/game_state.gd")
const GameStateChangeScript := preload("res://scripts/core/game_state_change.gd")
const EquipmentStateScript := preload("res://scripts/core/equipment_state.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const InitialEquipmentDataScript := preload("res://scripts/data/initial_equipment_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const OPERATIONAL: StringName = EquipmentStateScript.CONDITION_OPERATIONAL
const BROKEN: StringName = EquipmentStateScript.CONDITION_BROKEN
const FIXTURE_DIR: String = "res://tests/fixtures/equipment"


func test_initial_equipment_fixture_loads_and_passes_validation() -> void:
	var setup: InitialStateDataScript = ResourceLoader.load(FIXTURE_DIR + "/initial_state_equipment.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE) as InitialStateDataScript
	assert_true(setup != null, "Başlangıç dosyası yüklenemedi.")
	if setup == null:
		return
	assert_eq(setup.starting_equipment.get_typed_script(), InitialEquipmentDataScript)
	assert_true(setup.starting_equipment[0].get_script() == InitialEquipmentDataScript)
	var state: GameStateScript = GameStateScript.new(setup)
	assert_eq(Fixtures.rows(state), [["equipment_a", OPERATIONAL, 0], ["equipment_b", BROKEN, 3], ["equipment_c", OPERATIONAL, 2]])
	assert_eq(_statuses(state), [&"operational", &"broken", &"disabled"])
	assert_eq(DataValidator.new().validate_dir(FIXTURE_DIR).size(), 0)
	assert_eq(take_engine_errors().size(), 0)


func test_initial_operational_broken_and_disabled_setups() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup([
		Fixtures.make_initial("equipment_a", OPERATIONAL),
		Fixtures.make_initial("equipment_b", BROKEN),
		Fixtures.make_initial("equipment_c", OPERATIONAL, 4),
		Fixtures.make_initial("equipment_d", BROKEN, 5),
	]))
	assert_eq(_statuses(state), [&"operational", &"broken", &"disabled", &"broken"])
	var usable: Array = []
	for entry in state.get_equipment_snapshot():
		usable.append(entry.is_usable())
	assert_eq(usable, [true, false, false, false])
	assert_eq(take_engine_errors().size(), 0)


func test_invalid_initial_entries_are_skipped_one_by_one() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup([
		null,
		Fixtures.make_initial("", OPERATIONAL),
		Fixtures.make_initial("equipment_x", &"lost"),
		Fixtures.make_initial("equipment_y", OPERATIONAL, -1),
		Fixtures.make_initial("equipment_a", OPERATIONAL),
		Fixtures.make_initial("equipment_a", BROKEN, 9),
		Fixtures.make_initial("equipment_b", BROKEN, 2),
	]))
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 5, " | ".join(errors))
	assert_eq(_contains_each(errors, ["boş başlangıç ekipmanı", "boş ekipman kimliği", "geçersiz ekipman durumu",
			"negatif ekipman süresi", "tekrarlanan ekipman kimliği"]), true, " | ".join(errors))
	# Geçerli kayıtlar korunur; tekrarlanan kimlikte ilk geçerli kayıt kalır.
	assert_eq(Fixtures.rows(state), [["equipment_a", OPERATIONAL, 0], ["equipment_b", BROKEN, 2]])


func test_changing_source_data_does_not_affect_state() -> void:
	var setup: InitialStateDataScript = Fixtures.make_setup(Fixtures.default_equipment())
	var state: GameStateScript = GameStateScript.new(setup)
	setup.starting_equipment[0].condition = BROKEN
	setup.starting_equipment[0].disabled_units = 7
	setup.starting_equipment.clear()
	assert_eq(Fixtures.rows(state), [["equipment_a", OPERATIONAL, 0], ["equipment_b", BROKEN, 0], ["equipment_c", OPERATIONAL, 0]])


func test_changing_state_does_not_affect_source_data() -> void:
	var setup: InitialStateDataScript = Fixtures.make_setup(Fixtures.default_equipment())
	var state: GameStateScript = GameStateScript.new(setup)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.equipment_values.append(EquipmentStateScript.new(&"equipment_a", BROKEN, 4))
	assert_true(state.apply_changes(change))
	var source: InitialEquipmentDataScript = setup.starting_equipment[0]
	assert_eq([source.id, source.condition, source.disabled_units], ["equipment_a", OPERATIONAL, 0])


func test_snapshot_is_sorted_and_independent() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup([
		Fixtures.make_initial("equipment_c", OPERATIONAL), Fixtures.make_initial("equipment_a", BROKEN, 1),
		Fixtures.make_initial("equipment_b", OPERATIONAL),
	]))
	var snapshot: Array[EquipmentStateScript] = state.get_equipment_snapshot()
	assert_eq(Fixtures.rows(state), [["equipment_a", BROKEN, 1], ["equipment_b", OPERATIONAL, 0], ["equipment_c", OPERATIONAL, 0]])
	snapshot[0].condition = OPERATIONAL
	snapshot[0].disabled_units = 99
	snapshot.clear()
	assert_eq(Fixtures.rows(state)[0], ["equipment_a", BROKEN, 1])


func test_get_equipment_returns_an_independent_copy() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(Fixtures.default_equipment()))
	var copy: EquipmentStateScript = state.get_equipment(&"equipment_a")
	copy.condition = BROKEN
	copy.disabled_units = 5
	assert_eq(Fixtures.rows(state)[0], ["equipment_a", OPERATIONAL, 0])
	assert_true(state.has_equipment(&"equipment_a"))
	assert_false(state.has_equipment(&"missing_id"))
	assert_eq(state.get_equipment(&"missing_id"), null)
	_assert_one_engine_error("tanımsız ekipman okunamaz")


func test_apply_changes_rejects_invalid_equipment_entries_without_partial_writes() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(Fixtures.default_equipment()))
	var calls: Array[int] = _count_signals(state)
	var cases: Array = [
		[[null], "geçersiz ekipman kaydı"],
		[[EquipmentStateScript.new(&"", OPERATIONAL, 0)], "geçersiz ekipman kaydı"],
		[[EquipmentStateScript.new(&"missing_id", OPERATIONAL, 0)], "tanımsız ekipman"],
		[[EquipmentStateScript.new(&"equipment_a", &"lost", 0)], "geçersiz ekipman durumu"],
		[[EquipmentStateScript.new(&"equipment_a", OPERATIONAL, -1)], "negatif ekipman süresi"],
		[[EquipmentStateScript.new(&"equipment_a", BROKEN, 0), EquipmentStateScript.new(&"equipment_a", OPERATIONAL, 2)],
				"tekrarlanan ekipman"],
	]
	for case in cases:
		var change: GameStateChangeScript = GameStateChangeScript.new()
		change.resource_values[&"res_a"] = 9
		change.flag_values[&"flag_a"] = true
		for entry in case[0]:
			change.equipment_values.append(entry)
		assert_false(state.apply_changes(change), case[1])
		_assert_one_engine_error(case[1])
	assert_eq([state.get_resource(&"res_a"), state.get_flag(&"flag_a")], [5, false])
	assert_eq(Fixtures.rows(state), [["equipment_a", OPERATIONAL, 0], ["equipment_b", BROKEN, 0], ["equipment_c", OPERATIONAL, 0]])
	assert_eq(calls[0], 0)


func test_apply_changes_writes_valid_equipment_with_one_signal() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(Fixtures.default_equipment()))
	var calls: Array[int] = _count_signals(state)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.equipment_values.append(EquipmentStateScript.new(&"equipment_b", OPERATIONAL, 3))
	change.equipment_values.append(EquipmentStateScript.new(&"equipment_a", BROKEN, 0))
	change.resource_values[&"res_a"] = 4
	assert_true(state.apply_changes(change))
	assert_eq(Fixtures.rows(state), [["equipment_a", BROKEN, 0], ["equipment_b", OPERATIONAL, 3], ["equipment_c", OPERATIONAL, 0]])
	assert_eq(state.get_resource(&"res_a"), 4)
	assert_eq(calls[0], 1)
	# Paket sonradan değiştirilse bile durum etkilenmez.
	change.equipment_values[0].disabled_units = 99
	assert_eq(Fixtures.rows(state)[1], ["equipment_b", OPERATIONAL, 3])


func test_noop_equipment_change_emits_no_signal() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(Fixtures.default_equipment()))
	var calls: Array[int] = _count_signals(state)
	var change: GameStateChangeScript = GameStateChangeScript.new()
	change.equipment_values.append(EquipmentStateScript.new(&"equipment_a", OPERATIONAL, 0))
	assert_true(state.apply_changes(change))
	assert_eq(calls[0], 0)
	assert_eq(take_engine_errors().size(), 0)


func test_equipment_has_no_direct_setter() -> void:
	var state: GameStateScript = GameStateScript.new(Fixtures.make_setup(Fixtures.default_equipment()))
	for method in ["set_equipment", "set_equipment_state", "set_equipment_condition"]:
		assert_false(state.has_method(method), method)


func test_status_precedence_and_usability() -> void:
	var cases: Array = [
		[OPERATIONAL, 0, &"operational", true],
		[OPERATIONAL, 3, &"disabled", false],
		[BROKEN, 0, &"broken", false],
		[BROKEN, 3, &"broken", false],
	]
	for case in cases:
		var entry: EquipmentStateScript = EquipmentStateScript.new(&"equipment_a", case[0], case[1])
		assert_eq([entry.get_status(), entry.is_usable()], [case[2], case[3]], str(case))


func test_equipment_state_copy_and_equals() -> void:
	var source: EquipmentStateScript = EquipmentStateScript.new(&"equipment_a", BROKEN, 4)
	var copy: EquipmentStateScript = source.copy()
	assert_true(copy != source and copy.equals(source))
	copy.disabled_units = 5
	assert_false(copy.equals(source))
	assert_eq(source.disabled_units, 4)
	assert_false(source.equals(null))


func test_game_state_change_is_empty_tracks_equipment() -> void:
	var change: GameStateChangeScript = GameStateChangeScript.new()
	assert_true(change.is_empty())
	change.equipment_values.append(EquipmentStateScript.new(&"equipment_a", OPERATIONAL, 0))
	assert_false(change.is_empty())


# --- Yardımcılar ---

func _statuses(state: GameStateScript) -> Array:
	var result: Array = []
	for entry in state.get_equipment_snapshot():
		result.append(entry.get_status())
	return result


func _contains_each(errors: PackedStringArray, texts: Array) -> bool:
	for text in texts:
		var found: bool = false
		for error in errors:
			if error.contains(text):
				found = true
				break
		if not found:
			return false
	return true


func _count_signals(state: GameStateScript) -> Array[int]:
	var calls: Array[int] = [0]
	state.state_changed.connect(func() -> void: calls[0] += 1)
	return calls


# Beklenen push_error'u tüketir; böylece çalıştırıcı onu beklenmeyen hata saymaz.
func _assert_one_engine_error(text: String) -> void:
	var errors: PackedStringArray = take_engine_errors()
	assert_eq(errors.size(), 1, " | ".join(errors))
	assert_true(errors.size() == 1 and errors[0].contains(text), " | ".join(errors))
