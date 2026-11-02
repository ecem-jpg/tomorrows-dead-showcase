class_name CablePuzzleProgressState
extends RefCounted
## Bir kablo bulmacasının oyun geneli ilerlemesi (K-032): kaç kesin sonucun uygulandığı ve çözülüp çözülmediği.
## Tek doğruluk kaynağı GameState'tir; geçiş kuralları GameState.apply_changes içinde zorlanır. Bulmacanın
## max_resolutions sınırı burada bilinmez; onu CableRepairSystem denetler.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const CablePuzzleProgressStateScript := preload("res://scripts/core/cable_puzzle_progress_state.gd")

var puzzle_id: StringName = &""
## Uygulanan kesin sonuç (solved veya failed) sayısı; 0 veya daha büyük, geriye gitmez.
var resolutions_used: int = 0
## Yalnızca false → true geçer; çözülmüş kayıt bir daha değişmez.
var solved: bool = false


func _init(p_puzzle_id: StringName = &"", p_resolutions_used: int = 0, p_solved: bool = false) -> void:
	puzzle_id = p_puzzle_id
	resolutions_used = p_resolutions_used
	solved = p_solved


## Bağımsız kopya.
func copy() -> CablePuzzleProgressStateScript:
	return CablePuzzleProgressStateScript.new(puzzle_id, resolutions_used, solved)


func equals(other: CablePuzzleProgressStateScript) -> bool:
	return other != null \
			and puzzle_id == other.puzzle_id \
			and resolutions_used == other.resolutions_used \
			and solved == other.solved
