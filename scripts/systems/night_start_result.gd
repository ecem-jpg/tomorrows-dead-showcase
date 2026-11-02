class_name NightStartResult
extends RefCounted
## OccurrenceSystem.start_night ve preview_start_night sonucu (K-029). Her çağrıda yeni oluşturulur;
## değiştirilmesi durumu etkilemez. Bütün başarısızlıklar kurulum/akış hatasıdır ve push_error ile gelir.

const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_NIGHT_ALREADY_ACTIVE: StringName = &"night_already_active"
const FAILURE_NO_NEXT_NIGHT: StringName = &"no_next_night"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"
const FAILURE_WRITE_FAILED: StringName = &"write_failed"

## İç atlanma nedenleri (normal sonuç, hata değil):
const SKIP_CONDITIONS_NOT_MET: StringName = &"conditions_not_met"
const SKIP_SUBJECT_BUSY: StringName = &"subject_busy"
const SKIP_SUBJECT_DEAD: StringName = &"subject_dead"

var ok: bool = false
## ok = true ise boş.
var failure: StringName = &""
## Başlayan gece; başarısızlıkta 0.
var night: int = 0
## Bu gecenin başında pending olan görünümler, kimlik sırasıyla. Cesetler morgda görünür hâle gelir.
var arrived_ids: Array[StringName] = []
## İÇ SİSTEM VERİSİ: bu gecenin etkinleşmeyen görünümleri → atlanma nedeni. Arayüze verilmez; gelecek
## görünümlerin varlığını ve koşullarını ele verir.
var internal_skip_reasons: Dictionary[StringName, StringName] = {}
