extends "res://tests/framework/test_case.gd"
## SubjectData ve OccurrenceData'nın yüklenmesi ve doğrulanması (K-029).

const SubjectDataScript := preload("res://scripts/data/subject_data.gd")
const OccurrenceDataScript := preload("res://scripts/data/occurrence_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")
const InitialStateDataScript := preload("res://scripts/data/initial_state_data.gd")
const OccurrenceStatusScript := preload("res://scripts/core/occurrence_status.gd")
const DataValidator := preload("res://tests/framework/data_validator.gd")

const FIXTURE_DIR: String = "res://tests/fixtures/occurrences"


func test_defaults_are_empty_and_statuses_are_fixed() -> void:
	assert_eq(SubjectDataScript.new().id, "")
	var occurrence: OccurrenceDataScript = OccurrenceDataScript.new()
	assert_eq([occurrence.id, occurrence.subject_id, occurrence.night, occurrence.arrival_conditions.size()], ["", "", 0, 0])
	assert_eq(occurrence.arrival_conditions.get_typed_script(), ConditionDataScript)
	assert_eq(InitialStateDataScript.new().occurrence_ids.size(), 0)
	assert_eq(OccurrenceStatusScript.STATUSES,
			[&"inactive", &"pending", &"death_prevented", &"death_permanent"] as Array[StringName])


func test_occurrence_fixtures_load_with_typed_conditions() -> void:
	var subject: Resource = ResourceLoader.load(FIXTURE_DIR + "/subject_a.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(subject != null and subject.get_script() == SubjectDataScript)
	var first: OccurrenceDataScript = ResourceLoader.load(FIXTURE_DIR + "/occurrence_a.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE) as OccurrenceDataScript
	var second: OccurrenceDataScript = ResourceLoader.load(FIXTURE_DIR + "/occurrence_b.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE) as OccurrenceDataScript
	assert_true(first != null and second != null, "Görünüm dosyaları yüklenemedi.")
	if first == null or second == null:
		return
	assert_eq([first.id, first.subject_id, first.night, first.arrival_conditions.size()], ["occurrence_a", "subject_a", 1, 0])
	assert_eq([second.id, second.subject_id, second.night], ["occurrence_b", "subject_a", 2])
	assert_eq(second.arrival_conditions.get_typed_script(), ConditionDataScript)
	var occurrence_condition: ConditionDataScript = second.arrival_conditions[0]
	var flag_condition: ConditionDataScript = second.arrival_conditions[1]
	assert_eq([occurrence_condition.kind, occurrence_condition.occurrence_id, occurrence_condition.occurrence_status],
			[&"occurrence", "occurrence_a", &"death_prevented"])
	assert_eq([flag_condition.kind, flag_condition.flag_id, flag_condition.flag_value], [&"flag", "condition_a", false])


func test_occurrence_fixtures_pass_data_validation() -> void:
	# subject_id, aynı klasördeki SubjectData kimliğine başvurmalıdır.
	var errors: PackedStringArray = DataValidator.new().validate_dir(FIXTURE_DIR)
	assert_eq(errors.size(), 0, "\n".join(errors))
