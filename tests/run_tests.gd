extends SceneTree
## Eklentisiz başsız test çalıştırıcı.
##
## Kullanım:
##   godot --headless --path . --script res://tests/run_tests.gd [-- --tests-dir=<klasör>]
##
## Varsayılan olarak res://tests altındaki (framework/ hariç) "test_*.gd" dosyalarını bulur
## ve her dosyadaki "test_" ile başlayan yöntemleri çalıştırır.
## Bir test şu durumlarda başarısız sayılır: başarısız doğrulama, hiç doğrulama yapılmaması
## veya test sırasında Godot'nun bir hata (ör. GDScript çalışma zamanı hatası) bildirmesi.
## Testler `await` ile kare bekleyebilir; TEST_TIMEOUT_SEC içinde bitmeyen test
## başarısız sayılır ve çalıştırma 1 ile sonlanır (asılı kalmaz).
## Tüm testler geçerse çıkış kodu 0, herhangi biri başarısızsa 1 olur.

const TestCase := preload("res://tests/framework/test_case.gd")
const ErrorCapture := preload("res://tests/framework/error_capture.gd")

const DEFAULT_TESTS_DIR: String = "res://tests"
const FRAMEWORK_DIR: String = "framework"
const TEST_FILE_PREFIX: String = "test_"
const TEST_METHOD_PREFIX: String = "test_"
const TESTS_DIR_ARG: String = "--tests-dir="
const TEST_TIMEOUT_SEC: float = 10.0

var _passed: int = 0
var _failed: int = 0
var _error_capture: ErrorCapture = ErrorCapture.new()


func _initialize() -> void:
	OS.add_logger(_error_capture)
	var tests_dir: String = _parse_tests_dir()
	var files: PackedStringArray = _find_test_files(tests_dir)
	print("Test klasörü: %s" % tests_dir)
	if files.is_empty():
		printerr("Test dosyası bulunamadı.")
		_finish(1)
		return

	# _initialize sırasında kök pencere henüz ağaçta değil; sahne testleri için bir kare beklenir.
	await process_frame
	for path in files:
		await _run_file(path, tests_dir)

	print("")
	print("Toplam: %d | Geçti: %d | Başarısız: %d" % [_passed + _failed, _passed, _failed])
	print("SONUÇ: %s" % ("BAŞARILI" if _failed == 0 else "BAŞARISIZ"))
	_finish(0 if _failed == 0 else 1)


func _finish(exit_code: int) -> void:
	OS.remove_logger(_error_capture)
	quit(exit_code)


func _parse_tests_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(TESTS_DIR_ARG):
			return arg.trim_prefix(TESTS_DIR_ARG).replace("\\", "/")
	return DEFAULT_TESTS_DIR


func _find_test_files(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		printerr("Klasör açılamadı: %s" % dir_path)
		return result
	for sub_dir in dir.get_directories():
		if sub_dir != FRAMEWORK_DIR:
			result.append_array(_find_test_files(dir_path.path_join(sub_dir)))
	for file_name in dir.get_files():
		if file_name.begins_with(TEST_FILE_PREFIX) and file_name.ends_with(".gd"):
			result.append(dir_path.path_join(file_name))
	result.sort()
	return result


func _run_file(path: String, root_dir: String) -> void:
	var display_path: String = path.trim_prefix(root_dir).trim_prefix("/")
	_error_capture.take_errors()
	var script: GDScript = _load_script(path)
	var load_errors: PackedStringArray = _error_capture.take_errors()
	if script == null or not script.can_instantiate():
		load_errors.insert(0, "Betik yüklenemedi veya derlenemedi.")
	if not load_errors.is_empty():
		_report(display_path, "<yükleme>", _prefixed("Hata: ", load_errors))
		return

	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with(TEST_METHOD_PREFIX):
			continue
		_error_capture.take_errors()
		# Her test yalıtılmış olsun diye yeni örnek.
		var test_case: TestCase = script.new() as TestCase
		if test_case == null:
			_report(display_path, method_name, PackedStringArray(["Test betiği test_case.gd'yi genişletmiyor."]))
			return
		test_case.error_capture = _error_capture
		var on_timeout: Callable = _on_test_timeout.bind(display_path, method_name)
		var timer: SceneTreeTimer = create_timer(TEST_TIMEOUT_SEC)
		timer.timeout.connect(on_timeout)
		# Test bir eşyordamsa (await içeriyorsa) bitmesi beklenir; değilse hemen döner.
		await test_case.call(method_name)
		timer.timeout.disconnect(on_timeout)
		var failures: PackedStringArray = test_case.failures
		if test_case.assertion_count == 0:
			failures.append("Hiç doğrulama yapılmadı.")
		failures.append_array(_prefixed("Çalışma zamanı hatası: ", _error_capture.take_errors()))
		_report(display_path, method_name, failures)


func _on_test_timeout(file_label: String, method_name: String) -> void:
	_report(file_label, method_name, PackedStringArray(["Zaman aşımı: %.0f saniyede bitmedi." % TEST_TIMEOUT_SEC]))
	print("")
	print("Toplam (yarıda kesildi): %d | Geçti: %d | Başarısız: %d" % [_passed + _failed, _passed, _failed])
	print("SONUÇ: BAŞARISIZ")
	_finish(1)


func _prefixed(prefix: String, lines: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = []
	for line in lines:
		result.append(prefix + line)
	return result


func _load_script(path: String) -> GDScript:
	if path.begins_with("res://"):
		return load(path) as GDScript
	# Proje dışındaki klasörler (ör. geçici doğrulama) için kaynak koddan derle.
	var script: GDScript = GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	if script.reload() != OK:
		return null
	return script


func _report(file_label: String, method_name: String, failures: PackedStringArray) -> void:
	if failures.is_empty():
		_passed += 1
		print("[GEÇTİ] %s :: %s" % [file_label, method_name])
		return
	_failed += 1
	print("[BAŞARISIZ] %s :: %s" % [file_label, method_name])
	for failure in failures:
		print("    - %s" % failure)
