class_name TrustSystem
extends RefCounted
## Yönlü güven ilişkilerini veriyle tanımlı ortak sınırlar içinde değiştirir ve sorgular (K-023).
## Değerleri saklamaz; GameState üzerinden okur ve yazar. Kendi sinyali yoktur.
##
## Sorumluluk sınırı: güven yalnızca bir sayıdır; görev kabulü ve tepkiler için koşul olarak okunabilir.
## Bir önerinin doğru, eksik veya hatalı olup olmadığını belirlemez ve bunu garanti etmez (K-021).
## Bu nedenle karar, öneri veya bilgi verisine ve rastgele sayı üretecine bağımlı değildir.
##
## Durumlar: boş güven listesi = henüz başlatılmadı (geçerli); kısmi liste = tutarsız yapılandırma;
## kurallardaki bütün ilişkileri içeren liste = başlatılmış (ör. kayıttan yüklenmiş) ve geçerli.

## Onaylı temel güven ölçeği. Etkin sınırlar veriden gelir ve bu aralıkta olmalıdır.
const SCALE_MIN: int = 0
const SCALE_MAX: int = 100

# Sınıf önbelleğine bağımlı kalmamak için tipler yol ile yüklenir.
const GameStateScript := preload("res://scripts/core/game_state.gd")
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")
const TrustRulesDataScript := preload("res://scripts/data/trust_rules_data.gd")
const TrustRelationshipDataScript := preload("res://scripts/data/trust_relationship_data.gd")

var _state: GameStateScript
var _has_rules: bool = false
var _min_value: int = 0
var _max_value: int = 0
# İlişkilerin bağımsız kopyaları; (kaynak, hedef) sırasına göre sıralı.
var _relationships: Array[TrustRelationshipDataScript] = []
var _null_relationship_count: int = 0


func _init(state: GameStateScript, rules: TrustRulesDataScript) -> void:
	if state == null or rules == null:
		push_error("TrustSystem: oyun durumu ve güven kuralları verilmelidir.")
	_state = state
	if rules == null:
		return
	_has_rules = true
	_min_value = rules.min_value
	_max_value = rules.max_value
	for relationship in rules.relationships:
		if relationship == null:
			_null_relationship_count += 1
			continue
		_relationships.append(_copy_relationship(relationship))
	_relationships.sort_custom(_relationship_sorts_before)


## Kural ve durum tutarsızlıklarını deterministik sırayla döndürür; hiçbir değeri düzeltmez.
func get_configuration_errors() -> PackedStringArray:
	var errors: PackedStringArray = _rule_errors()
	errors.append_array(_state_errors())
	return errors


## Başlangıç değerlerini tek seferde yazar. Güven zaten başlatılmışsa veya yapılandırma hatalıysa
## hata verir ve durumu değiştirmez.
func initialize_relationships() -> bool:
	if not _ensure_valid_configuration("güven başlatılamaz"):
		return false
	if not _state.get_trust_snapshot().is_empty():
		push_error("TrustSystem: güven zaten başlatıldı.")
		return false
	var entries: Array[TrustRelationshipStateScript] = []
	for relationship in _relationships:
		entries.append(TrustRelationshipStateScript.new(StringName(relationship.source_actor_id),
				StringName(relationship.target_actor_id), relationship.starting_value))
	if not _state.set_trust_state(entries):
		push_error("TrustSystem: güven durumu yazılamadı; başlatma uygulanmadı.")
		return false
	return true


## İlişki kurallarda tanımlı mı. Hata vermez.
func has_relationship(source_actor_id: StringName, target_actor_id: StringName) -> bool:
	return _find_relationship(source_actor_id, target_actor_id) != null


## Geçersiz istekte hata verir ve 0 döner.
func get_trust(source_actor_id: StringName, target_actor_id: StringName) -> int:
	if not _ensure_ready("güven okunamaz", source_actor_id, target_actor_id):
		return 0
	return _state.get_trust(source_actor_id, target_actor_id)


## Güveni delta kadar değiştirir, etkin sınırlarda keser ve gerçekten uygulanan işaretli değişimi döndürür.
## Değer değişmezse 0 döner ve sinyal yayılmaz. Geçersiz istekte veya başarısız yazmada hata verir ve 0 döner.
func change_trust(source_actor_id: StringName, target_actor_id: StringName, delta: int) -> int:
	if not _ensure_ready("güven değiştirilemez", source_actor_id, target_actor_id):
		return 0
	var current: int = _state.get_trust(source_actor_id, target_actor_id)
	var updated: int = compute_change(current, delta)
	if updated == current:
		return 0
	var entries: Array[TrustRelationshipStateScript] = _state.get_trust_snapshot()
	for entry in entries:
		if entry.source_actor_id == source_actor_id and entry.target_actor_id == target_actor_id:
			entry.value = updated
	if not _state.set_trust_state(entries):
		push_error("TrustSystem: güven durumu yazılamadı; değişim uygulanmadı: '%s' -> '%s'"
				% [source_actor_id, target_actor_id])
		return 0
	return updated - current


## Güven eşiğe eşit veya üstündeyse true. Yan etkisizdir. Eşik etkin [min_value, max_value]
## aralığında olmalıdır; geçersiz istekte hata verir ve false döner.
func is_at_least(source_actor_id: StringName, target_actor_id: StringName, threshold: int) -> bool:
	if not _ensure_ready("güven eşiği sorgulanamaz", source_actor_id, target_actor_id):
		return false
	if not is_threshold_in_range(threshold):
		push_error("TrustSystem: eşik etkin aralık dışında: %d (%d..%d)" % [threshold, _min_value, _max_value])
		return false
	return _state.get_trust(source_actor_id, target_actor_id) >= threshold


## Güven başlatılmış mı (durumda en az bir ilişki var mı). Hata vermez; tutarlılığı
## get_configuration_errors denetler.
func is_initialized() -> bool:
	return _state != null and not _state.get_trust_snapshot().is_empty()


## Yan etkisiz: verilen değere delta uygulandığında change_trust'ın yazacağı, etkin sınırlarda
## kesilmiş yeni değer (K-025). Hata basmaz.
func compute_change(current: int, delta: int) -> int:
	return clampi(current + delta, _min_value, _max_value)


## Eşik etkin [min_value, max_value] aralığında mı. Hata vermez.
func is_threshold_in_range(threshold: int) -> bool:
	return threshold >= _min_value and threshold <= _max_value


# --- Doğrulama ---

func _rule_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if not _has_rules:
		errors.append("Güven kuralları verilmedi")
		return errors
	if _min_value < SCALE_MIN or _min_value > SCALE_MAX:
		errors.append("Alt sınır ölçek dışında: %d (%d..%d)" % [_min_value, SCALE_MIN, SCALE_MAX])
	if _max_value < SCALE_MIN or _max_value > SCALE_MAX:
		errors.append("Üst sınır ölçek dışında: %d (%d..%d)" % [_max_value, SCALE_MIN, SCALE_MAX])
	var bounds_ordered: bool = _min_value <= _max_value
	if not bounds_ordered:
		errors.append("Alt sınır üst sınırdan büyük: %d > %d" % [_min_value, _max_value])
	if _relationships.is_empty() and _null_relationship_count == 0:
		errors.append("En az bir güven ilişkisi tanımlanmalı")
	for i in _null_relationship_count:
		errors.append("Tanımsız güven ilişkisi kaydı")

	var reported_duplicates: Array[TrustRelationshipDataScript] = []
	for i in _relationships.size():
		var relationship: TrustRelationshipDataScript = _relationships[i]
		var source: String = relationship.source_actor_id
		var target: String = relationship.target_actor_id
		if source.is_empty() or target.is_empty():
			errors.append("Boş aktör kimliği: '%s' -> '%s'" % [source, target])
		elif source == target:
			errors.append("Kendine güven ilişkisi geçersiz: '%s'" % source)
		elif i > 0 and _same_pair(_relationships[i - 1], relationship):
			# Liste sıralı olduğu için tekrarlar yan yanadır; her çift bir kez raporlanır.
			if not _contains_pair(reported_duplicates, relationship):
				errors.append("Tekrarlanan güven ilişkisi: '%s' -> '%s'" % [source, target])
				reported_duplicates.append(relationship)
		if bounds_ordered and (relationship.starting_value < _min_value or relationship.starting_value > _max_value):
			errors.append("Başlangıç güveni sınır dışında: '%s' -> '%s' (%d, %d..%d)"
					% [source, target, relationship.starting_value, _min_value, _max_value])
	return errors


func _state_errors() -> PackedStringArray:
	var errors: PackedStringArray = []
	if _state == null:
		errors.append("Oyun durumu verilmedi")
		return errors
	var entries: Array[TrustRelationshipStateScript] = _state.get_trust_snapshot()
	if entries.is_empty():
		# Henüz başlatılmamış yeni oyun: geçerli durum.
		return errors
	for relationship in _relationships:
		if not _is_structurally_valid(relationship):
			continue
		if not _state.has_trust(StringName(relationship.source_actor_id), StringName(relationship.target_actor_id)):
			errors.append("Durumda eksik güven ilişkisi: '%s' -> '%s'"
					% [relationship.source_actor_id, relationship.target_actor_id])
	for entry in entries:
		if _find_relationship(entry.source_actor_id, entry.target_actor_id) == null:
			errors.append("Durumda tanımsız güven ilişkisi: '%s' -> '%s'" % [entry.source_actor_id, entry.target_actor_id])
		elif entry.value < _min_value or entry.value > _max_value:
			errors.append("Durumdaki güven sınır dışında: '%s' -> '%s' (%d, %d..%d)"
					% [entry.source_actor_id, entry.target_actor_id, entry.value, _min_value, _max_value])
	return errors


func _ensure_valid_configuration(action: String) -> bool:
	var errors: PackedStringArray = get_configuration_errors()
	if errors.is_empty():
		return true
	push_error("TrustSystem: geçersiz yapılandırma; %s: %s" % [action, " | ".join(errors)])
	return false


# Yapılandırma geçerli, güven başlatılmış ve ilişki tanımlı olmalı; her durumda tek hata verilir.
func _ensure_ready(action: String, source_actor_id: StringName, target_actor_id: StringName) -> bool:
	if not _ensure_valid_configuration(action):
		return false
	if _state.get_trust_snapshot().is_empty():
		push_error("TrustSystem: güven başlatılmadı; %s." % action)
		return false
	if source_actor_id == target_actor_id:
		push_error("TrustSystem: kendine güven ilişkisi geçersiz: '%s'" % source_actor_id)
		return false
	if not has_relationship(source_actor_id, target_actor_id):
		push_error("TrustSystem: tanımsız güven ilişkisi: '%s' -> '%s'" % [source_actor_id, target_actor_id])
		return false
	return true


# --- Yardımcılar ---

func _find_relationship(source_actor_id: StringName, target_actor_id: StringName) -> TrustRelationshipDataScript:
	for relationship in _relationships:
		if _is_structurally_valid(relationship) \
				and StringName(relationship.source_actor_id) == source_actor_id \
				and StringName(relationship.target_actor_id) == target_actor_id:
			return relationship
	return null


func _is_structurally_valid(relationship: TrustRelationshipDataScript) -> bool:
	return not relationship.source_actor_id.is_empty() and not relationship.target_actor_id.is_empty() \
			and relationship.source_actor_id != relationship.target_actor_id


func _same_pair(a: TrustRelationshipDataScript, b: TrustRelationshipDataScript) -> bool:
	return a.source_actor_id == b.source_actor_id and a.target_actor_id == b.target_actor_id


func _contains_pair(list: Array[TrustRelationshipDataScript], relationship: TrustRelationshipDataScript) -> bool:
	for item in list:
		if _same_pair(item, relationship):
			return true
	return false


func _copy_relationship(relationship: TrustRelationshipDataScript) -> TrustRelationshipDataScript:
	var copy: TrustRelationshipDataScript = TrustRelationshipDataScript.new()
	copy.source_actor_id = relationship.source_actor_id
	copy.target_actor_id = relationship.target_actor_id
	copy.starting_value = relationship.starting_value
	return copy


func _relationship_sorts_before(a: TrustRelationshipDataScript, b: TrustRelationshipDataScript) -> bool:
	if a.source_actor_id != b.source_actor_id:
		return a.source_actor_id < b.source_actor_id
	return a.target_actor_id < b.target_actor_id
