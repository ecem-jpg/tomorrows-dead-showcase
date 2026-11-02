class_name TaskAssignmentData
extends Resource
## Bir görevin kimden kime verildiği, deneme maliyeti ve kabul koşulları; TaskData içinde alt kaynak (K-026).
## Kimlik alanları alt kaynakta durur; böylece veri doğrulayıcının en üst düzey `_id` başvuru kuralıyla çakışmaz.

const ConditionDataScript := preload("res://scripts/data/condition_data.gd")

## Görevi veren aktör (oyuncunun yönettiği aktör).
@export var active_actor_id: String = ""
## Görevi alan aktör; active_actor_id ile aynı olamaz.
@export var assigned_actor_id: String = ""
## İsteğe bağlı; doluysa her deneme (kabul veya ret) aynı atomik pakette bu eylemin maliyeti kadar zaman harcar.
@export var action_id: String = ""
## Hepsi sağlanırsa görev kabul edilir, biri sağlanmazsa reddedilir. Boş liste her zaman kabul demektir.
@export var acceptance_conditions: Array[ConditionDataScript] = []
