class_name CableTerminalData
extends Resource
## Kablo bulmacasında tek bir bağlantı ucu; CablePuzzleData içinde alt kaynak olarak tutulur (K-019).
## Renk, metin veya ad taşımaz; görünüm yalnızca kimlik ve taraftan kurulur.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const CableTerminalDataScript := preload("res://scripts/data/cable_terminal_data.gd")

const SIDE_LEFT: StringName = &"left"
const SIDE_RIGHT: StringName = &"right"
const SIDES: Array[StringName] = [SIDE_LEFT, SIDE_RIGHT]

## Bulmaca içinde benzersiz.
@export var id: String = ""
## SIDES içinden biri; bağlantı yalnızca farklı taraflardaki iki terminal arasında kurulur.
@export var side: StringName = &""


## Bağımsız derin kopya. Yalnızca boş olmayan bir örnekte çağrılır.
func copy() -> CableTerminalDataScript:
	return duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as CableTerminalDataScript
