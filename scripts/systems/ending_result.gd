class_name EndingResult
extends RefCounted
## EndingResolver.resolve sonucu (K-030); arayüze verilebilir. Bilerek yalnızca durum, hata kodu ve seçilen son
## kimliğini taşır: sağlanmayan koşullar, değerlendirilen diğer sonlar ve öncelikler burada bulunmaz.
## Her çağrıda yeni oluşturulur; değiştirilmesi sonraki çağrıları etkilemez.

## Normal sonuçlar (hata basılmaz):
const STATUS_RESOLVED: StringName = &"resolved"
const STATUS_GAME_NOT_OVER: StringName = &"game_not_over"

## Kurulum/akış hataları (push_error ile birlikte):
const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"

## resolved, game_not_over veya boş (başarısızlık).
var status: StringName = &""
## status doluysa boş.
var failure: StringName = &""
## Yalnızca resolved.
var ending_id: StringName = &""


func is_resolved() -> bool:
	return status == STATUS_RESOLVED


func is_failed() -> bool:
	return status.is_empty()
