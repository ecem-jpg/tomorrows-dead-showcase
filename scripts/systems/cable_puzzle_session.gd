class_name CablePuzzleSession
extends RefCounted
## Tek bir kablo birleştirme denemesinin saf mantığı (K-019).
##
## - Durum yazmaz, zaman ilerletmez, sinyal yaymaz, arayüz ve rastgele sayı üreteci kullanmaz; yalnızca kendi
##   bağlantılarını ve yanlış kontrol sayısını tutar. Sonucun uygulanması ayrı bir sisteme aittir.
## - Oturum yalnızca create ile, geçerli bir bulmacanın bağımsız kopyasından açılır.
## - Bağlantılar yönsüzdür ve kanonik çift [küçük, büyük] olarak raporlanır. Terminal başına en fazla bir bağlantı.
## - Yanlış bağlantı kurulabilir ve sökülebilir; yalnızca bütün terminaller bağlıyken yapılan yanlış kontrol bir
##   hak tüketir. Son hak da yanlışsa oturum failed olur. solved ve failed kesindir; sonrasında hiçbir çağrı
##   iç durumu değiştirmez.
## - Normal retler (aynı taraf, kendine bağlantı, dolu terminal, bağlı olmayan terminal, bitmiş oturum) hata basmaz.
##   Bulmacada olmayan terminal kimliği akış hatasıdır ve push_error üretir.
## - Terminal ve bağlantıların veri sırası sonuçları etkilemez.

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir; kendi tipine de yol ile başvurur.
const CablePuzzleSessionScript := preload("res://scripts/systems/cable_puzzle_session.gd")
const CablePuzzleDataScript := preload("res://scripts/data/cable_puzzle_data.gd")
const CablePuzzleOutcomeDataScript := preload("res://scripts/data/cable_puzzle_outcome_data.gd")
const CableTerminalDataScript := preload("res://scripts/data/cable_terminal_data.gd")
const CableConnectionDataScript := preload("res://scripts/data/cable_connection_data.gd")

const STATUS_IN_PROGRESS: StringName = &"in_progress"
const STATUS_SOLVED: StringName = &"solved"
const STATUS_FAILED: StringName = &"failed"

## connect_terminals / disconnect_terminal başarı sonuçları.
const MOVE_CONNECTED: StringName = &"connected"
const MOVE_DISCONNECTED: StringName = &"disconnected"
## Normal retler: iç durum değişmez, hata basılmaz.
const MOVE_SELF_CONNECTION: StringName = &"self_connection"
const MOVE_SAME_SIDE: StringName = &"same_side"
const MOVE_TERMINAL_OCCUPIED: StringName = &"terminal_occupied"
const MOVE_NOT_CONNECTED: StringName = &"not_connected"
const MOVE_FINISHED: StringName = &"finished"
## Akış hatası: iç durum değişmez, push_error üretilir.
const MOVE_UNKNOWN_TERMINAL: StringName = &"unknown_terminal"

## submit sonuçları.
## Bütün terminaller bağlı değil; hak tüketmez.
const SUBMIT_INCOMPLETE: StringName = &"incomplete"
## Bütün terminaller bağlı ve düzen yanlış; bir hak tüketir, hak kaldı.
const SUBMIT_INCORRECT: StringName = &"incorrect"
## Düzen doğru; oturum solved olur.
const SUBMIT_SOLVED: StringName = &"solved"
## Son hak da yanlış; oturum failed olur.
const SUBMIT_FAILED: StringName = &"failed"
## Oturum zaten bitmiş; hiçbir şey değişmez.
const SUBMIT_FINISHED: StringName = &"finished"

var _puzzle: CablePuzzleDataScript
var _sides: Dictionary[StringName, StringName] = {}
var _required_partners: Dictionary[StringName, StringName] = {}
# Kurulan bağlantılar her iki yönde tutulur.
var _partners: Dictionary[StringName, StringName] = {}
var _status: StringName = STATUS_IN_PROGRESS
var _incorrect_submissions: int = 0


## Yalnızca create çağırır; puzzle doğrulanmış ve bu oturuma ait bir kopyadır.
func _init(valid_copy: CablePuzzleDataScript) -> void:
	_puzzle = valid_copy
	for terminal: CableTerminalDataScript in _puzzle.terminals:
		_sides[StringName(terminal.id)] = terminal.side
	for connection: CableConnectionDataScript in _puzzle.required_connections:
		_required_partners[StringName(connection.terminal_a)] = StringName(connection.terminal_b)
		_required_partners[StringName(connection.terminal_b)] = StringName(connection.terminal_a)


## Geçerli bulmacadan bağımsız bir oturum açar. Geçersiz bulmaca akış hatasıdır: push_error ve null.
static func create(puzzle: CablePuzzleDataScript) -> CablePuzzleSessionScript:
	var errors: PackedStringArray = get_puzzle_errors(puzzle)
	if not errors.is_empty():
		push_error("CablePuzzleSession: geçersiz bulmaca; oturum açılamaz: %s" % " | ".join(errors))
		return null
	return CablePuzzleSessionScript.new(puzzle.copy())


## Yönsüz çiftin kanonik biçimi: metin sırasıyla [küçük, büyük].
static func canonical_pair(terminal_a: StringName, terminal_b: StringName) -> Array:
	if String(terminal_b) < String(terminal_a):
		return [terminal_b, terminal_a]
	return [terminal_a, terminal_b]


# --- Hamleler ---

func connect_terminals(terminal_a: StringName, terminal_b: StringName) -> StringName:
	if not _is_known(terminal_a, "connect_terminals") or not _is_known(terminal_b, "connect_terminals"):
		return MOVE_UNKNOWN_TERMINAL
	if is_finished():
		return MOVE_FINISHED
	if terminal_a == terminal_b:
		return MOVE_SELF_CONNECTION
	if _sides[terminal_a] == _sides[terminal_b]:
		return MOVE_SAME_SIDE
	if _partners.has(terminal_a) or _partners.has(terminal_b):
		return MOVE_TERMINAL_OCCUPIED
	_partners[terminal_a] = terminal_b
	_partners[terminal_b] = terminal_a
	return MOVE_CONNECTED


func disconnect_terminal(terminal: StringName) -> StringName:
	if not _is_known(terminal, "disconnect_terminal"):
		return MOVE_UNKNOWN_TERMINAL
	if is_finished():
		return MOVE_FINISHED
	if not _partners.has(terminal):
		return MOVE_NOT_CONNECTED
	var partner: StringName = _partners[terminal]
	_partners.erase(terminal)
	_partners.erase(partner)
	return MOVE_DISCONNECTED


func submit() -> StringName:
	if is_finished():
		return SUBMIT_FINISHED
	if not is_fully_connected():
		return SUBMIT_INCOMPLETE
	if _is_correct():
		_status = STATUS_SOLVED
		return SUBMIT_SOLVED
	_incorrect_submissions += 1
	if _incorrect_submissions >= _puzzle.rules.max_submissions:
		_status = STATUS_FAILED
		return SUBMIT_FAILED
	return SUBMIT_INCORRECT


# --- Okuma ---

func get_puzzle_id() -> StringName:
	return StringName(_puzzle.id)


func get_status() -> StringName:
	return _status


func is_finished() -> bool:
	return _status != STATUS_IN_PROGRESS


func get_max_submissions() -> int:
	return _puzzle.rules.max_submissions


func get_incorrect_submissions() -> int:
	return _incorrect_submissions


func get_remaining_submissions() -> int:
	return _puzzle.rules.max_submissions - _incorrect_submissions


func is_fully_connected() -> bool:
	return _partners.size() == _sides.size()


func has_terminal(terminal: StringName) -> bool:
	return _sides.has(terminal)


## Bir taraftaki terminaller veri sırasıyla (yalnızca görünüm için); geçersiz tarafta boş liste.
func get_terminal_ids(side: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for terminal: CableTerminalDataScript in _puzzle.terminals:
		if terminal.side == side:
			result.append(StringName(terminal.id))
	return result


func get_terminal_side(terminal: StringName) -> StringName:
	if not _is_known(terminal, "get_terminal_side"):
		return &""
	return _sides[terminal]


## Bağlı olduğu terminal; bağlı değilse &"".
func get_partner(terminal: StringName) -> StringName:
	if not _is_known(terminal, "get_partner") or not _partners.has(terminal):
		return &""
	return _partners[terminal]


## Kurulan bağlantılar: kanonik çiftler, sıralı. Her çağrıda yeni diziler döner.
func get_connections() -> Array:
	var result: Array = []
	for terminal: StringName in _partners:
		var pair: Array = canonical_pair(terminal, _partners[terminal])
		if pair[0] == terminal:
			result.append(pair)
	result.sort_custom(_pair_before)
	return result


# --- Doğrulama ---

## Bulmacanın tutarsızlıklarını deterministik sırayla döndürür: kimlik, terminaller, bağlantılar, kullanılmayan
## terminaller, sınırlar, başlangıç koşulu kayıtları, sonuç dalları. Hiçbir değeri düzeltmez ve motor hatası
## üretmez. Koşul ve etkilerin içeriği oyun durumuna bağlıdır; onları sonucu uygulayan sistem doğrular.
static func get_puzzle_errors(puzzle: CablePuzzleDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	if puzzle == null:
		errors.append("Tanımsız bulmaca")
		return errors
	if puzzle.id.is_empty():
		errors.append("Boş bulmaca kimliği")

	# İlk tanımın tarafı geçerlidir; sıra veri sırasıdır.
	var sides: Dictionary[String, StringName] = {}
	var terminal_order: Array[String] = []
	for i in puzzle.terminals.size():
		var terminal: CableTerminalDataScript = puzzle.terminals[i]
		if terminal == null:
			errors.append("Tanımsız terminal kaydı (#%d)" % i)
			continue
		if terminal.id.is_empty():
			errors.append("Boş terminal kimliği (#%d)" % i)
		elif sides.has(terminal.id):
			errors.append("Tekrarlanan terminal kimliği: '%s'" % terminal.id)
		else:
			sides[terminal.id] = terminal.side
			terminal_order.append(terminal.id)
		if not CableTerminalDataScript.SIDES.has(terminal.side):
			errors.append("Terminal #%d: geçersiz taraf '%s'" % [i, terminal.side])

	if puzzle.required_connections.is_empty():
		errors.append("Zorunlu bağlantı yok")
	var pairs: Array = []
	# Terminal → onu ilk kullanan bağlantının sırası.
	var used: Dictionary[String, int] = {}
	for i in puzzle.required_connections.size():
		var connection: CableConnectionDataScript = puzzle.required_connections[i]
		if connection == null:
			errors.append("Tanımsız bağlantı kaydı (#%d)" % i)
			continue
		var ends: Array[String] = [connection.terminal_a, connection.terminal_b]
		var has_unknown: bool = false
		for terminal_id: String in ends:
			if not sides.has(terminal_id):
				errors.append("Bağlantı #%d: tanımsız terminal '%s'" % [i, terminal_id])
				has_unknown = true
		if has_unknown:
			continue
		if connection.terminal_a == connection.terminal_b:
			errors.append("Bağlantı #%d: terminal kendisine bağlanamaz ('%s')" % [i, connection.terminal_a])
			continue
		var side_a: StringName = sides[connection.terminal_a]
		if side_a == sides[connection.terminal_b] and CableTerminalDataScript.SIDES.has(side_a):
			errors.append("Bağlantı #%d: aynı taraftaki terminaller ('%s', '%s')"
					% [i, connection.terminal_a, connection.terminal_b])
			continue
		var pair: Array = canonical_pair(StringName(connection.terminal_a), StringName(connection.terminal_b))
		if pairs.has(pair):
			errors.append("Bağlantı #%d: tekrarlanan bağlantı ('%s', '%s')" % [i, pair[0], pair[1]])
			continue
		pairs.append(pair)
		for terminal_id: String in ends:
			if used.has(terminal_id):
				errors.append("Bağlantı #%d: '%s' birden fazla zorunlu bağlantıda (#%d ile)"
						% [i, terminal_id, used[terminal_id]])
			else:
				used[terminal_id] = i
	for terminal_id in terminal_order:
		if not used.has(terminal_id):
			errors.append("'%s': hiçbir zorunlu bağlantıda kullanılmıyor" % terminal_id)

	if puzzle.rules == null:
		errors.append("Kural kaydı yok")
	else:
		if puzzle.rules.equipment_id.is_empty():
			errors.append("Boş ekipman kimliği")
		if puzzle.rules.max_submissions < 1:
			errors.append("max_submissions 1 veya daha büyük olmalı (%d)" % puzzle.rules.max_submissions)
		if puzzle.rules.max_resolutions < 1:
			errors.append("max_resolutions 1 veya daha büyük olmalı (%d)" % puzzle.rules.max_resolutions)
	for i in puzzle.start_conditions.size():
		if puzzle.start_conditions[i] == null:
			errors.append("Tanımsız başlangıç koşulu kaydı (#%d)" % i)
	errors.append_array(_outcome_errors("Başarı", puzzle.success))
	errors.append_array(_outcome_errors("Başarısızlık", puzzle.failure))
	return errors


static func _outcome_errors(label: String, outcome: CablePuzzleOutcomeDataScript) -> PackedStringArray:
	var errors: PackedStringArray = []
	if outcome == null:
		errors.append("%s sonucu yok" % label)
		return errors
	for i in outcome.effects.size():
		if outcome.effects[i] == null:
			errors.append("%s etkisi #%d tanımsız" % [label, i])
	return errors


# --- Yardımcılar ---

func _is_known(terminal: StringName, caller: String) -> bool:
	if _sides.has(terminal):
		return true
	push_error("CablePuzzleSession.%s: '%s' bulmacasında tanımsız terminal: '%s'" % [caller, _puzzle.id, terminal])
	return false


func _is_correct() -> bool:
	for terminal: StringName in _partners:
		if _required_partners[terminal] != _partners[terminal]:
			return false
	return true


static func _pair_before(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return String(a[0]) < String(b[0])
	return String(a[1]) < String(b[1])
