extends "res://tests/framework/test_case.gd"
## TimeRulesData ve ScheduledEventData'nın veri dosyalarından yüklenmesi ve kimlik doğrulaması.

const TimeRulesDataScript := preload("res://scripts/data/time_rules_data.gd")
const ScheduledEventDataScript := preload("res://scripts/data/scheduled_event_data.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/time"


func test_rules_fixture_loads_with_expected_fields() -> void:
	var rules: TimeRulesDataScript = _load(FIXTURE_DIR.path_join("time_rules_a.tres"), TimeRulesDataScript) as TimeRulesDataScript
	if rules == null:
		return
	assert_eq(rules.id, "time_rules_a")
	assert_eq(rules.night_count, 2)
	assert_eq(rules.night_length_units, 10)
	assert_eq(rules.action_costs.size(), 2)
	assert_eq(rules.action_costs[&"action_a"], 2)
	assert_eq(rules.action_costs[&"action_b"], 0)


func test_event_fixture_loads_with_expected_fields() -> void:
	var event: ScheduledEventDataScript = _load(FIXTURE_DIR.path_join("event_a.tres"), ScheduledEventDataScript) as ScheduledEventDataScript
	if event == null:
		return
	assert_eq(event.id, "event_a")
	assert_eq(event.night, 1)
	assert_eq(event.at_units, 4)
	assert_eq(event.order, 1)


func test_fixtures_pass_data_validation() -> void:
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))


func _load(path: String, expected_script: GDScript) -> Resource:
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(resource != null, "Yüklenemedi: %s" % path)
	if resource == null:
		return null
	assert_true(resource.get_script() == expected_script, "Beklenmeyen kaynak türü: %s" % path)
	return resource
