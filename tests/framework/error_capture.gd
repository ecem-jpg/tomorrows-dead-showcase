extends Logger
## Godot'nun hata çıktısını yakalar. Çalıştırıcı, her test sırasında oluşan
## çalışma zamanı hatalarını bununla toplar ve testi başarısız sayar.
## GDScript'te try/catch olmadığı için, doğrulamalardan sonra oluşan bir hatayı
## güvenilir biçimde yakalamanın yolu budur.

var _mutex: Mutex = Mutex.new()
var _errors: PackedStringArray = []


# Logger geri çağrıları farklı iş parçacıklarından gelebilir; erişim kilitlenir.
func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text: String = rationale if not rationale.is_empty() else code
	_mutex.lock()
	_errors.append("%s (%s:%d, %s)" % [text, file, line, function])
	_mutex.unlock()


## Biriken hataları döndürür ve listeyi temizler.
func take_errors() -> PackedStringArray:
	_mutex.lock()
	var result: PackedStringArray = _errors
	_errors = PackedStringArray()
	_mutex.unlock()
	return result
