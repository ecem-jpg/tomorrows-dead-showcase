extends RefCounted
## Testlerin temel sınıfı. Test dosyaları bu betiği yol ile genişletir
## (`extends "res://tests/framework/test_case.gd"`) ve adı "test_" ile başlayan
## yöntemler tanımlar. Çalıştırıcı her test yöntemi için yeni bir örnek oluşturur.

const ErrorCapture := preload("res://tests/framework/error_capture.gd")

var assertion_count: int = 0
var failures: PackedStringArray = []
## Çalıştırıcı tarafından atanır. Test sırasında tüketilmeyen motor hataları testi başarısız sayar.
var error_capture: ErrorCapture = null


## Test sırasında bilerek tetiklenen motor hatalarını alır ve doğrulamaya sunar.
## Yalnızca hata beklenen testlerde kullanılmalı; alınan hatalar testi başarısız saymaz.
func take_engine_errors() -> PackedStringArray:
	if error_capture == null:
		return PackedStringArray()
	return error_capture.take_errors()


func assert_true(condition: bool, message: String = "") -> void:
	_record(condition, "true bekleniyordu", message)


func assert_false(condition: bool, message: String = "") -> void:
	_record(not condition, "false bekleniyordu", message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_record(_values_equal(actual, expected), "beklenen: %s, gelen: %s" % [str(expected), str(actual)], message)


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	_record(not _values_equal(actual, unexpected), "farklı olmalıydı: %s" % str(unexpected), message)


func _record(passed: bool, detail: String, message: String) -> void:
	assertion_count += 1
	if not passed:
		failures.append(detail if message.is_empty() else "%s (%s)" % [message, detail])


# Farklı tipleri `==` ile karşılaştırmak çalışma zamanı hatası verebilir;
# int/float dışındaki tip uyuşmazlıkları doğrudan "eşit değil" sayılır.
static func _values_equal(a: Variant, b: Variant) -> bool:
	var a_type: int = typeof(a)
	var b_type: int = typeof(b)
	var numeric: Array[int] = [TYPE_INT, TYPE_FLOAT]
	if a_type != b_type and not (a_type in numeric and b_type in numeric):
		return false
	return a == b
