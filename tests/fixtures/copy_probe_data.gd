extends "res://scripts/data/condition_data.gd"
## Yalnızca test amaçlı; oyun verisi değildir. ConditionData.copy() mekanizmasının iç içe kaynaklarda ve
## koleksiyonlarda gerçek derin kopya ürettiğini kanıtlamak için ConditionData'yı ek alanlarla genişletir.
## Böylece ileride ConditionData'ya dizi veya alt kaynak eklenmesi durumunda davranış önceden sınanmış olur.

## Doğrudan alt kaynak.
@export var child: Resource = null
## Dizi içindeki kaynaklar.
@export var children: Array[Resource] = []
## Sözlük içindeki kaynaklar (anahtar → kaynak).
@export var keyed: Dictionary = {}
## İlkel dizi.
@export var numbers: Array[int] = []
## İlkel sözlük.
@export var labels: Dictionary = {}
