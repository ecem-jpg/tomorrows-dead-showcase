extends "res://tests/framework/test_case.gd"
## ResourceLimitsData'nın veri dosyasından yüklenmesi ve kimlik doğrulaması.

const ResourceLimitsDataScript := preload("res://scripts/data/resource_limits_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/resources"
const FIXTURE_PATH: String = "res://tests/fixtures/resources/limits_a.tres"


func test_fixture_loads_with_expected_fields() -> void:
	var resource: Resource = ResourceLoader.load(FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null, "Örnek dosya yüklenemedi.")
	if resource == null:
		return
	assert_true(resource.get_script() == ResourceLimitsDataScript, "Kaynak ResourceLimitsData değil.")
	var limits: ResourceLimitsDataScript = resource as ResourceLimitsDataScript
	assert_eq(limits.id, "limits_a")
	assert_eq(limits.min_values.size(), 2)
	assert_eq(limits.min_values[&"res_a"], 0)
	assert_eq(limits.min_values[&"res_b"], 0)
	assert_eq(limits.max_values.size(), 1)
	assert_eq(limits.max_values[&"res_a"], 10)


func test_fixture_passes_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
