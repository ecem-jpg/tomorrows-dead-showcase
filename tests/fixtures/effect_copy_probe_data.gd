extends "res://scripts/data/effect_data.gd"
## Yalnızca test amaçlı; oyun verisi değildir. EffectData.copy() mekanizmasının iç içe kaynaklarda ve
## koleksiyonlarda gerçek derin kopya ürettiğini kanıtlamak için EffectData'yı ek alanlarla genişletir.
## Böylece ileride EffectData'ya dizi veya alt kaynak eklenmesi durumunda davranış önceden sınanmış olur.

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
