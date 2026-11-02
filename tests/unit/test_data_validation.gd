extends "res://tests/framework/test_case.gd"
## Veri doğrulayıcının tarafsız örnek veri gruplarıyla testleri.
## Hatalı gruplar bilerek hatalıdır; testler bu hataların doğru raporlandığını doğrular.

const DataValidator := preload("res://tests/framework/data_validator.gd")
const FixtureItem := preload("res://tests/fixtures/fixture_item.gd")

const FIXTURES_DIR: String = "res://tests/fixtures/data"
# Proje dışındaki geçici alan; her test kendi alt klasörünü oluşturur ve siler.
const TEMP_ROOT: String = "user://test_tmp_data_validation"


func test_valid_set_has_no_errors() -> void:
	var errors: PackedStringArray = _validate("valid")
	assert_eq(errors.size(), 0, "\n".join(errors))


func test_missing_id_is_rejected() -> void:
	var errors: PackedStringArray = _validate("missing_id")
	assert_eq(errors.size(), 1, "\n".join(errors))
	assert_true(errors[0].begins_with("Eksik id: "), errors[0])
	assert_true(errors[0].ends_with("item_empty.tres"), errors[0])


func test_duplicate_id_is_rejected() -> void:
	var errors: PackedStringArray = _validate("duplicate_id")
	assert_eq(errors.size(), 1, "\n".join(errors))
	assert_true(errors[0].begins_with("Tekrarlanan id 'item_a': "), errors[0])
	assert_true(errors[0].contains("item_a.tres"), errors[0])
	assert_true(errors[0].contains("item_a_copy.tres"), errors[0])


func test_undefined_references_are_rejected() -> void:
	var errors: PackedStringArray = _validate("undefined_reference")
	assert_eq(errors.size(), 2, "\n".join(errors))
	assert_true(errors[0].begins_with("Tanımsız referans 'missing_id': "), errors[0])
	assert_true(errors[0].ends_with("item_a.tres (alan: ref_id)"), errors[0])
	assert_true(errors[1].begins_with("Tanımsız referans 'missing_id': "), errors[1])
	assert_true(errors[1].ends_with("item_b.tres (alan: ref_ids)"), errors[1])


func test_whitespace_id_counts_as_missing() -> void:
	var item: FixtureItem = FixtureItem.new()
	item.id = "   "
	var resources: Dictionary[String, Resource] = {"memory/item_blank": item}
	var errors: PackedStringArray = DataValidator.new().validate_resources(resources)
	assert_eq(errors, PackedStringArray(["Eksik id: memory/item_blank"]))


func test_empty_entry_in_reference_list_is_rejected() -> void:
	var item: FixtureItem = FixtureItem.new()
	item.id = "item_a"
	item.ref_ids = PackedStringArray([""])
	var resources: Dictionary[String, Resource] = {"memory/item_a": item}
	var errors: PackedStringArray = DataValidator.new().validate_resources(resources)
	assert_eq(errors, PackedStringArray(["Boş referans: memory/item_a (alan: ref_ids)"]))


func test_missing_id_property_is_rejected_without_engine_error() -> void:
	var valid_item: FixtureItem = FixtureItem.new()
	valid_item.id = "item_a"
	var resources: Dictionary[String, Resource] = {
		"memory/item_a": valid_item,
		"memory/item_without_id": Resource.new(),
	}
	var errors: PackedStringArray = DataValidator.new().validate_resources(resources)
	assert_eq(errors, PackedStringArray(["Eksik id: memory/item_without_id"]))
	assert_eq(take_engine_errors().size(), 0, "Motor hatası beklenmiyordu.")


func test_directory_without_resources_is_rejected() -> void:
	var dir_path: String = _make_temp_dir("empty")
	var errors: PackedStringArray = DataValidator.new().validate_dir(dir_path)
	_remove_temp_dir(dir_path, PackedStringArray())
	assert_eq(errors, PackedStringArray(["Kaynak bulunamadı: %s" % dir_path]))


func test_unloadable_resource_is_rejected() -> void:
	var dir_path: String = _make_temp_dir("unloadable")
	var file_path: String = dir_path.path_join("item_a.tres")
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	assert_true(file != null, "Geçici dosya oluşturulamadı.")
	if file == null:
		_remove_temp_dir(dir_path, PackedStringArray())
		return
	file.store_string("bu geçerli bir kaynak değil")
	file.close()

	var errors: PackedStringArray = DataValidator.new().validate_dir(dir_path)
	# Bozuk dosyanın yüklenmesi motor hatası üretir; bu hata burada beklenir ve tüketilir.
	var engine_errors: PackedStringArray = take_engine_errors()
	_remove_temp_dir(dir_path, PackedStringArray(["item_a.tres"]))

	assert_eq(errors, PackedStringArray(["Yüklenemedi: %s" % file_path]))
	assert_true(engine_errors.size() > 0, "Yükleme hatası motor tarafından bildirilmeliydi.")
	assert_false(DirAccess.dir_exists_absolute(dir_path), "Geçici klasör silinmedi.")


func _validate(set_name: String) -> PackedStringArray:
	return DataValidator.new().validate_dir(FIXTURES_DIR.path_join(set_name))


func _make_temp_dir(case_name: String) -> String:
	var dir_path: String = TEMP_ROOT.path_join(case_name)
	DirAccess.make_dir_recursive_absolute(dir_path)
	return dir_path


func _remove_temp_dir(dir_path: String, file_names: PackedStringArray) -> void:
	for file_name in file_names:
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
	# Kök klasör yalnızca boşsa silinir.
	DirAccess.remove_absolute(TEMP_ROOT)
