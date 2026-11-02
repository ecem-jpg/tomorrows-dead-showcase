extends "res://tests/framework/test_case.gd"
## Test altyapısının kendisini doğrulayan tarafsız örnek testler.

const TestCase := preload("res://tests/framework/test_case.gd")


func test_integer_addition() -> void:
	assert_eq(2 + 3, 5)


func test_string_concatenation() -> void:
	assert_eq("ab" + "cd", "abcd")


func test_array_sort() -> void:
	var values: Array[int] = [3, 1, 2]
	values.sort()
	assert_eq(values.size(), 3)
	assert_eq(values.front(), 1)
	assert_eq(values.back(), 3)


func test_failed_assertion_is_recorded() -> void:
	var probe: TestCase = TestCase.new()
	probe.assert_eq(1, 2)
	probe.assert_true(true)
	assert_eq(probe.assertion_count, 2)
	assert_eq(probe.failures.size(), 1)


func test_mismatched_types_are_not_equal() -> void:
	assert_ne(1, "1")
	assert_eq(1, 1.0)
