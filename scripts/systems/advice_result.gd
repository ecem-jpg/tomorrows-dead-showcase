class_name AdviceResult
extends RefCounted
## AdviceSystem.get_advice sonucu (K-028); arayüze verilebilecek tek öneri sonucu. Gizli sınıflandırmayı
## (accuracy) ve biçim kimliğini bilerek içermez. Her çağrıda yeni oluşturulur; değiştirilmesi sonraki
## çağrıları etkilemez. Kimlikler istenen önerinin verisidir.

## Normal oyun sonuçları (hata basılmaz):
const STATUS_OFFERED: StringName = &"offered"
const STATUS_NOT_OFFERED: StringName = &"not_offered"
const STATUS_NO_APPLICABLE_VARIANT: StringName = &"no_applicable_variant"

## Kurulum/akış hataları (push_error ile birlikte):
const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_UNKNOWN_ADVICE: StringName = &"unknown_advice"
const FAILURE_SYSTEM_NOT_READY: StringName = &"system_not_ready"

## offered, not_offered, no_applicable_variant veya boş (başarısızlık).
var status: StringName = &""
## status doluysa boş.
var failure: StringName = &""
var advice_id: StringName = &""
## Bağlam alanları yalnızca öneri tanımlıysa ve yapılandırma geçerliyse doludur.
var advisor_actor_id: StringName = &""
var recipient_actor_id: StringName = &""
var decision_id: StringName = &""
## Yalnızca offered; seçilen biçim seçenek göstermiyorsa boştur. Oyuncunun seçimini değiştirmez.
var recommended_choice_id: StringName = &""


func is_offered() -> bool:
	return status == STATUS_OFFERED


func is_failed() -> bool:
	return status.is_empty()
