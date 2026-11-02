class_name AdviceVariantData
extends Resource
## Bir önerinin, belirli bilgi ve oyun durumu koşullarında aldığı biçim; AdviceData içinde alt kaynak (K-028).
##
## accuracy, yazarın bu biçim için veride tanımladığı gizli sınıflandırmadır. Sistem bunu hesaplamaz,
## güvene veya rastgeleliğe göre değiştirmez; evrensel bir gerçeklik ölçüsü değildir. Arayüze verilmez.

const ACCURACY_CORRECT: StringName = &"correct"
const ACCURACY_INCOMPLETE: StringName = &"incomplete"
const ACCURACY_INCORRECT: StringName = &"incorrect"
## Geçerli accuracy değerleri; başka her değer (boş dahil) yapılandırma hatasıdır.
const ACCURACIES: Array[StringName] = [ACCURACY_CORRECT, ACCURACY_INCOMPLETE, ACCURACY_INCORRECT]

const ConditionDataScript := preload("res://scripts/data/condition_data.gd")

## Öneri içinde benzersiz. Arayüze verilmez; doğruluğu ele veren adlar kullanılmamalıdır.
@export var id: String = ""
## Gizli sınıflandırma: ACCURACIES değerlerinden biri.
@export var accuracy: StringName = &""
## Bilgi (bayrak) ve oyun durumu koşulları; güven koşulu kullanılamaz. Boş liste koşulsuz biçimdir:
## bir öneride en fazla bir tane olabilir ve varsa son biçim olmalıdır.
@export var conditions: Array[ConditionDataScript] = []
## İsteğe bağlı; yalnızca bağlamda decision_id doluysa kullanılabilir ve o kararın tanımlı bir seçeneği olmalıdır.
@export var recommended_choice_id: String = ""
