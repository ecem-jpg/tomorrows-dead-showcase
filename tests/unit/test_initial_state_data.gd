extends "res://tests/framework/test_case.gd"
## InitialStateData'nın veri dosyasından yüklenmesi ve kimlik doğrulaması.

const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/state"
const FIXTURE_PATH: String = "res://tests/fixtures/state/state_setup_a.tres"


func test_fixture_loads_with_expected_fields() -> void:
	var resource: Resource = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null, "Örnek dosya yüklenemedi.")
	if resource == null:
		return
	assert_true(resource.get_script() == InitialStateDataScript, "Kaynak InitialStateData değil.")
	var setup: InitialStateDataScript = resource as InitialStateDataScript
	assert_eq(setup.id, "state_setup_a")
	assert_eq(setup.starting_resources.size(), 2)
	assert_eq(setup.starting_resources[&"res_a"], 3)
	assert_eq(setup.starting_resources[&"res_b"], 0)
	assert_eq(setup.starting_flags, PackedStringArray(["flag_a"]))
	assert_eq(setup.rng_seed, 12345)


func test_fixture_passes_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
