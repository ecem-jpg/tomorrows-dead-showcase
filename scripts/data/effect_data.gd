class_name EffectData
extends Resource
## Tek bir etki; ChoiceData.effects veya TaskData.completion_effects içinde alt kaynak olarak tutulur
## (K-024, K-027). Planlama ve doğrulamanın tek kaynağı EffectPlanner'dır.
## Tür, .tres dosyalarında sıra değişikliğine dayanıklı olsun diye metin sabitiyle saklanır.
## Bir türün kullanmadığı alanlar varsayılan değerinde kalmalıdır; dolu ilgisiz alan yapılandırma hatasıdır.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const EffectDataScript := preload("res://scripts/data/effect_data.gd")

## Kaynağı artırır; üst sınırda keser.
const KIND_RESOURCE_ADD: StringName = &"resource_add"
## Kaynağı harcar; ya tamamen ya hiç.
const KIND_RESOURCE_SPEND: StringName = &"resource_spend"
## Yönlü güveni işaretli miktarda değiştirir; sınırlarda keser.
const KIND_TRUST_CHANGE: StringName = &"trust_change"
## Bayrağı verilen değere ayarlar; tanımsız bayrak oluşturulabilir.
const KIND_FLAG_SET: StringName = &"flag_set"
## Bekleyen görünümün ölümünü engeller (pending → death_prevented); başka durumda uygulanamaz (K-029).
const KIND_OCCURRENCE_PREVENT_DEATH: StringName = &"occurrence_prevent_death"
## Bekleyen görünümün ölümünü kalıcı yapar (pending → death_permanent); başka durumda uygulanamaz (K-029).
const KIND_OCCURRENCE_MAKE_DEATH_PERMANENT: StringName = &"occurrence_make_death_permanent"
## Çalışan ekipmanı arızalı yapar (operational → broken); arızalıysa uygulanamaz. Süreyi değiştirmez (K-031).
const KIND_EQUIPMENT_BREAK: StringName = &"equipment_break"
## Arızalı ekipmanı onarır (broken → operational); çalışıyorsa uygulanamaz. Süreyi değiştirmez (K-031).
const KIND_EQUIPMENT_REPAIR: StringName = &"equipment_repair"
## Ekipmanı amount birim geçici devre dışı bırakır; kalan süre max(kalan, amount) olur, kısalmaz (K-031).
const KIND_EQUIPMENT_DISABLE: StringName = &"equipment_disable"

@export var kind: StringName = &""
## resource_add, resource_spend
@export var resource_id: String = ""
## trust_change
@export var source_actor_id: String = ""
@export var target_actor_id: String = ""
## flag_set
@export var flag_id: String = ""
## resource_add/resource_spend: en az 0; trust_change: işaretli değişim; equipment_disable: en az 1
@export var amount: int = 0
## flag_set
@export var flag_value: bool = false
## occurrence_prevent_death, occurrence_make_death_permanent
@export var occurrence_id: String = ""
## equipment_break, equipment_repair, equipment_disable
@export var equipment_id: String = ""


## Bağımsız derin kopya; etki kopyalamanın tek kaynağı. Saklanan bütün alanları (yalnızca @export olanlar)
## motor kopyalar; böylece yeni bir alan eklendiğinde kopyalarda sessizce düşmez. DEEP_DUPLICATE_ALL doğrudan
## alt kaynakları ve dizi/sözlük içindeki kaynakları da kopyalar. Yalnızca boş olmayan bir örnekte çağrılır.
func copy() -> EffectDataScript:
	return duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as EffectDataScript
