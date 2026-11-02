extends RefCounted
## Bir klasördeki .tres kaynaklarında kimlik bütünlüğünü denetler (test altyapısı).
##
## Sözleşme (yalnızca bu doğrulayıcı için; gerçek veri modelini tanımlamaz):
## - Her kaynağın boş olmayan bir `id` alanı olur ve bu değer klasörde tektir.
## - Adı `_id` ile biten betik alanları tek bir kimliğe başvurur; boşsa başvuru yok sayılır.
## - Adı `_ids` ile biten betik alanları kimlik listesine başvurur; listede boş öğe olamaz.
## - Her başvuru, aynı klasörde tanımlı bir `id` değerini göstermelidir.

const ID_PROPERTY: String = "id"
const REF_SUFFIX: String = "_id"
const REF_LIST_SUFFIX: String = "_ids"
const RESOURCE_EXTENSION: String = ".tres"


## Klasördeki (alt klasörler dahil) tüm .tres dosyalarını yükler ve denetler.
## Hata yoksa boş liste döner.
func validate_dir(dir_path: String) -> PackedStringArray:
	var errors: PackedStringArray = []
	var paths: PackedStringArray = _find_resource_files(dir_path)
	if paths.is_empty():
		errors.append("Kaynak bulunamadı: %s" % dir_path)
		return errors

	var resources: Dictionary[String, Resource] = {}
	for path in paths:
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			errors.append("Yüklenemedi: %s" % path)
			continue
		resources[path] = resource
	errors.append_array(validate_resources(resources))
	return errors


## Yol → kaynak eşlemesini denetler. Yollar yalnızca hata mesajlarında kullanılır.
func validate_resources(resources: Dictionary[String, Resource]) -> PackedStringArray:
	var errors: PackedStringArray = []
	var paths: Array[String] = resources.keys()
	paths.sort()

	var id_owners: Dictionary[String, String] = {}
	for path in paths:
		var id: String = _read_id(resources[path])
		if id.is_empty():
			errors.append("Eksik id: %s" % path)
		elif id_owners.has(id):
			errors.append("Tekrarlanan id '%s': %s, %s" % [id, id_owners[id], path])
		else:
			id_owners[id] = path

	for path in paths:
		var resource: Resource = resources[path]
		for property in resource.get_property_list():
			if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var field: String = property["name"]
			var value: Variant = resource.get(field)
			if field.ends_with(REF_SUFFIX):
				var ref: String = str(value).strip_edges()
				if not ref.is_empty() and not id_owners.has(ref):
					errors.append("Tanımsız referans '%s': %s (alan: %s)" % [ref, path, field])
			elif field.ends_with(REF_LIST_SUFFIX):
				for item in value:
					var ref: String = str(item).strip_edges()
					if ref.is_empty():
						errors.append("Boş referans: %s (alan: %s)" % [path, field])
					elif not id_owners.has(ref):
						errors.append("Tanımsız referans '%s': %s (alan: %s)" % [ref, path, field])
	return errors


func _read_id(resource: Resource) -> String:
	if not _has_property(resource, ID_PROPERTY):
		return ""
	var value: Variant = resource.get(ID_PROPERTY)
	if value == null:
		return ""
	return str(value).strip_edges()


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property["name"] == property_name:
			return true
	return false


func _find_resource_files(dir_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return result
	for sub_dir in dir.get_directories():
		result.append_array(_find_resource_files(dir_path.path_join(sub_dir)))
	for file_name in dir.get_files():
		if file_name.ends_with(RESOURCE_EXTENSION):
			result.append(dir_path.path_join(file_name))
	result.sort()
	return result
