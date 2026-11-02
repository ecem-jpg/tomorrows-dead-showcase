extends "res://tests/framework/test_case.gd"
## CablePuzzleProgressState testleri (K-032). Yalnızca tarafsız kimlikler.

const CablePuzzleProgressStateScript := preload("res://scripts/core/cable_puzzle_progress_state.gd")


func test_defaults() -> void:
	var progress: CablePuzzleProgressStateScript = CablePuzzleProgressStateScript.new()
	assert_eq([progress.puzzle_id, progress.resolutions_used, progress.solved], [&"", 0, false])


func test_constructor_sets_every_field() -> void:
	var progress: CablePuzzleProgressStateScript = CablePuzzleProgressStateScript.new(&"puzzle_a", 2, true)
	assert_eq([progress.puzzle_id, progress.resolutions_used, progress.solved], [&"puzzle_a", 2, true])


func test_copy_is_an_independent_instance() -> void:
	var source: CablePuzzleProgressStateScript = CablePuzzleProgressStateScript.new(&"puzzle_a", 1, false)
	var copy: CablePuzzleProgressStateScript = source.copy()
	assert_false(is_same(copy, source))
	assert_true(copy.equals(source))
	copy.puzzle_id = &"puzzle_z"
	copy.resolutions_used = 9
	copy.solved = true
	assert_eq([source.puzzle_id, source.resolutions_used, source.solved], [&"puzzle_a", 1, false])


func test_equals_compares_every_field() -> void:
	var base: CablePuzzleProgressStateScript = CablePuzzleProgressStateScript.new(&"puzzle_a", 1, false)
	assert_true(base.equals(CablePuzzleProgressStateScript.new(&"puzzle_a", 1, false)))
	assert_false(base.equals(CablePuzzleProgressStateScript.new(&"puzzle_b", 1, false)))
	assert_false(base.equals(CablePuzzleProgressStateScript.new(&"puzzle_a", 2, false)))
	assert_false(base.equals(CablePuzzleProgressStateScript.new(&"puzzle_a", 1, true)))


func test_equals_null_is_false() -> void:
	assert_false(CablePuzzleProgressStateScript.new(&"puzzle_a").equals(null))
