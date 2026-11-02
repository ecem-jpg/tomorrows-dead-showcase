class_name TrustRulesData
extends Resource
## Güven kuralları (K-023): bütün ilişkiler için ortak sınırlar ve yönlü ilişkilerin başlangıç değerleri.
## Değerler veri dosyalarında tanımlanır, koda yazılmaz. Öneri doğruluğuna dair alan içermez.

const TrustRelationshipDataScript := preload("res://scripts/data/trust_relationship_data.gd")

@export var id: String = ""
## 0..100 ölçeği içinde ve max_value'dan büyük olmamalı.
@export var min_value: int = 0
## 0..100 ölçeği içinde olmalı.
@export var max_value: int = 0
## En az bir ilişki gerekir; boş kurallar başlatılmamış durumla karışmasın diye.
@export var relationships: Array[TrustRelationshipDataScript] = []
