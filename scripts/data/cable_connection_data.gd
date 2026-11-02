class_name CableConnectionData
extends Resource
## Kablo bulmacasının zorunlu (doğru) bağlantılarından biri; CablePuzzleData içinde alt kaynak olarak tutulur (K-019).
## Yönsüzdür: (terminal_a, terminal_b) ile (terminal_b, terminal_a) aynı bağlantıdır.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const CableConnectionDataScript := preload("res://scripts/data/cable_connection_data.gd")

@export var terminal_a: String = ""
@export var terminal_b: String = ""


## Bağımsız derin kopya. Yalnızca boş olmayan bir örnekte çağrılır.
func copy() -> CableConnectionDataScript:
	return duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as CableConnectionDataScript
