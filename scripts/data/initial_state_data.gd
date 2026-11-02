class_name InitialStateData
extends Resource
## Yeni bir oyunun başlangıç değerleri. Değerler veri dosyalarında tanımlanır, koda yazılmaz (K-016).

const InitialEquipmentDataScript := preload("res://scripts/data/initial_equipment_data.gd")

@export var id: String = ""
@export var starting_resources: Dictionary[StringName, int] = {}
@export var starting_flags: PackedStringArray = []
@export var rng_seed: int = 0
## Oyundaki bütün gelecek ceset görünümlerinin kimlikleri; yeni oyunda hepsi inactive başlar (K-029).
## OccurrenceSystem bu listenin görünüm kataloğuyla birebir aynı olduğunu doğrular.
@export var occurrence_ids: PackedStringArray = []
## Başlangıç ekipmanları (K-031). Geçersiz kayıtlar (boş kayıt, boş veya tekrarlanan kimlik, geçersiz durum,
## negatif süre) GameState kurucusunda hata basılarak tek tek yok sayılır; tekrarlanan kimlikte ilk kayıt kalır.
@export var starting_equipment: Array[InitialEquipmentDataScript] = []
## Oyundaki bütün kablo bulmacalarının kimlikleri; yeni oyunda hepsi (0 çözüm, çözülmemiş) başlar (K-032).
## Boş veya tekrarlanan kimlikleri GameState kurucusu hata basarak yok sayar. CableRepairSystem bu listenin
## bulmaca kataloğuyla birebir aynı olduğunu doğrular.
@export var cable_puzzle_ids: PackedStringArray = []
