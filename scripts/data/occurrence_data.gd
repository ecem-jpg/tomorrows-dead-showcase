class_name OccurrenceData
extends Resource
## Bir kişinin belirli bir gecede görünebilecek tek gelecek ölüm ihtimali; ceset bu kayıtla temsil edilir (K-029).
## Tekrar görünme yalnızca veride açıkça yazılmış ayrı bir kayıtla mümkündür; kod görünüm üretmez.

const ConditionDataScript := preload("res://scripts/data/condition_data.gd")

@export var id: String = ""
## Aynı klasördeki bir SubjectData kimliği.
@export var subject_id: String = ""
## 1..gece sayısı. Varış yalnızca bu gecenin başında denenir; kaçırılırsa tekrar denenmez.
## Aynı kişinin iki görünümü aynı gecede olamaz.
@export var night: int = 0
## Varış koşulları (bayrak, kaynak, güven, görünüm durumu). Boş liste koşulsuzdur. Çözülmemiş neden gibi
## bilgiler genel bayraklarla, önceki görünümün sonucu occurrence koşuluyla ifade edilir.
@export var arrival_conditions: Array[ConditionDataScript] = []
