class_name CablePuzzleData
extends Resource
## Kablo birleştirme mini oyununun teknik tanımı (K-019). Terminaller, zorunlu bağlantılar, sınırlar, başlangıç
## koşulları ve iki sonuç dalı iç içe alt kaynaklardır. Doğrulamanın tek kaynağı CablePuzzleSession.get_puzzle_errors.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CableTerminalDataScript := preload("res://scripts/data/cable_terminal_data.gd")
const CableConnectionDataScript := preload("res://scripts/data/cable_connection_data.gd")
const CablePuzzleRulesDataScript := preload("res://scripts/data/cable_puzzle_rules_data.gd")
const CablePuzzleOutcomeDataScript := preload("res://scripts/data/cable_puzzle_outcome_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")

@export var id: String = ""
## Veri sırası yalnızca görünümdeki sırayı belirler; oturum sonuçlarını etkilemez.
@export var terminals: Array[CableTerminalDataScript] = []
## Her terminal tam olarak bir zorunlu bağlantıda yer alır; en az bir bağlantı gerekir.
@export var required_connections: Array[CableConnectionDataScript] = []
@export var rules: CablePuzzleRulesDataScript = null
## Oturumun ne zaman açılabileceği; değerlendirilmesi sonuç sistemine aittir.
@export var start_conditions: Array[ConditionDataScript] = []
@export var success: CablePuzzleOutcomeDataScript = null
@export var failure: CablePuzzleOutcomeDataScript = null


## Bağımsız kopya; koşullar ConditionData.copy(), etkiler EffectData.copy() ile kopyalanır. Boş kayıtlar hata
## raporu için yerinde kalır; böylece kaynak veride sonradan yapılan değişiklik kopyaya ulaşmaz.
func copy() -> CablePuzzleDataScript:
	var result: CablePuzzleDataScript = CablePuzzleDataScript.new()
	result.id = id
	for terminal: CableTerminalDataScript in terminals:
		result.terminals.append(null if terminal == null else terminal.copy())
	for connection: CableConnectionDataScript in required_connections:
		result.required_connections.append(null if connection == null else connection.copy())
	result.rules = null if rules == null else rules.copy()
	for condition: ConditionDataScript in start_conditions:
		result.start_conditions.append(null if condition == null else condition.copy())
	result.success = null if success == null else success.copy()
	result.failure = null if failure == null else failure.copy()
	return result
