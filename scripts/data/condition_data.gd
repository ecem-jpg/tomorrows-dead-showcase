class_name ConditionData
extends Resource
## Tek bir koşul; ChoiceData, TaskAssignmentData, AdviceData, AdviceVariantData, OccurrenceData veya EndingData
## içinde alt kaynak olarak tutulur (K-024, K-026, K-028, K-029, K-030).
## Değerlendirme ve doğrulamanın tek kaynağı ConditionEvaluator'dır.
## Tür ve karşılaştırma, .tres dosyalarında sıra değişikliğine dayanıklı olsun diye metin sabitleriyle saklanır.
## Bir türün kullanmadığı alanlar varsayılan değerinde kalmalıdır; dolu ilgisiz alan yapılandırma hatasıdır.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")

const KIND_RESOURCE: StringName = &"resource"
const KIND_TRUST: StringName = &"trust"
const KIND_FLAG: StringName = &"flag"
## Gelecek ceset görünümünün iç durumu (K-029); yalnızca eşitlik. Bayrağın yerine kullanılır, bayrağa kopyalanmaz.
const KIND_OCCURRENCE: StringName = &"occurrence"
## Ekipmanın görünür durumu (K-031); yalnızca eşitlik: operational, broken veya disabled.
const KIND_EQUIPMENT: StringName = &"equipment"

const COMPARISON_EQ: StringName = &"eq"
const COMPARISON_NE: StringName = &"ne"
const COMPARISON_LT: StringName = &"lt"
const COMPARISON_LE: StringName = &"le"
const COMPARISON_GT: StringName = &"gt"
const COMPARISON_GE: StringName = &"ge"

@export var kind: StringName = &""
## resource
@export var resource_id: String = ""
## trust: kaynak aktörün hedef aktöre güveni
@export var source_actor_id: String = ""
@export var target_actor_id: String = ""
## flag
@export var flag_id: String = ""
## resource ve trust
@export var comparison: StringName = &""
@export var value: int = 0
## flag: beklenen bayrak değeri
@export var flag_value: bool = false
## occurrence: görünüm kimliği ve beklenen iç durum (OccurrenceStatus)
@export var occurrence_id: String = ""
@export var occurrence_status: StringName = &""
## equipment: ekipman kimliği ve beklenen görünür durum (EquipmentState.STATUSES)
@export var equipment_id: String = ""
@export var equipment_status: StringName = &""


## Bağımsız derin kopya; koşul kopyalamanın tek kaynağı. Saklanan bütün alanları (yalnızca @export olanlar)
## motor kopyalar; böylece yeni bir alan eklendiğinde kopyalarda sessizce düşmez. DEEP_DUPLICATE_ALL doğrudan
## alt kaynakları ve dizi/sözlük içindeki kaynakları da kopyalar. Yalnızca boş olmayan bir örnekte çağrılır.
func copy() -> ConditionDataScript:
	return duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as ConditionDataScript
