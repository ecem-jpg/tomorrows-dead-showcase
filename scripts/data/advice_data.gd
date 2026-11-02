class_name AdviceData
extends Resource
## Bir aktörün başka bir aktöre sunabileceği önerinin tanımı (K-021, K-028). Biçimler veri sırasıyla
## değerlendirilir; koşulları sağlanan ilk biçim seçilir. Öneri salt okunurdur ve seçimi değiştirmez.

const AdviceContextDataScript := preload("res://scripts/data/advice_context_data.gd")
const AdviceVariantDataScript := preload("res://scripts/data/advice_variant_data.gd")
const ConditionDataScript := preload("res://scripts/data/condition_data.gd")

@export var id: String = ""
## Zorunlu.
@export var context: AdviceContextDataScript = null
## Önerinin sunulup sunulmayacağı; güven yalnızca burada kullanılabilir. Boş liste her zaman sunulur demektir.
@export var presentation_conditions: Array[ConditionDataScript] = []
## En az bir biçim gerekir; veri sırası önceliktir.
@export var variants: Array[AdviceVariantDataScript] = []
