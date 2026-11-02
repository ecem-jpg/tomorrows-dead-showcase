class_name TimeAdvancePlan
extends RefCounted
## TimeSystem.plan_advance ve plan_start_night sonucu: hesaplanmış yeni zaman durumu (K-025, K-029).
## Hiçbir şey yazılmamıştır; bütün alanlar iç durumdan bağımsız kopyalardır.
## plan_advance hata basmaz; geçersiz istekte failure ve error_message doldurulur.

const TimeAdvanceResultScript := preload("res://scripts/systems/time_advance_result.gd")
const TimedTaskStateScript := preload("res://scripts/core/timed_task_state.gd")

const FAILURE_INVALID_CONFIGURATION: StringName = &"invalid_configuration"
const FAILURE_NEGATIVE_AMOUNT: StringName = &"negative_amount"
const FAILURE_NIGHT_NOT_ACTIVE: StringName = &"night_not_active"
## Yalnızca plan_start_night (K-029):
const FAILURE_NIGHT_ALREADY_ACTIVE: StringName = &"night_already_active"
const FAILURE_NO_NEXT_NIGHT: StringName = &"no_next_night"

## Boşsa plan geçerlidir.
var failure: StringName = &""
var error_message: String = ""
## Geçerli planda ok = true; geçersiz planda boş ve başarısız sonuç.
var result: TimeAdvanceResultScript = TimeAdvanceResultScript.new()
var night: int = 0
var elapsed_units: int = 0
var night_ended: bool = false
var tasks: Array[TimedTaskStateScript] = []


func is_valid() -> bool:
	return failure.is_empty()
