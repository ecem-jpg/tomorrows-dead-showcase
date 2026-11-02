class_name EndingData
extends Resource
## Bir oyun sonunun teknik tanımı (K-030). Ad, açıklama ve metin bu sınıfın parçası değildir.
## Sonlar priority sırasıyla değerlendirilir; koşulları sağlanan ilk son seçilir.

const ConditionDataScript := preload("res://scripts/data/condition_data.gd")

@export var id: String = ""
## 1 veya daha büyük; küçük sayı önce değerlendirilir. İki son aynı önceliği taşıyamaz.
@export var priority: int = 0
## Boş liste koşulsuz yedek sondur: tam olarak bir tane bulunmalı ve en büyük priority değerini taşımalıdır.
@export var conditions: Array[ConditionDataScript] = []
