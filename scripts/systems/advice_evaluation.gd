class_name AdviceEvaluation
extends RefCounted
## AdviceSystem.evaluate sonucu (K-028). İÇ SİSTEM VERİSİDİR: arayüze, oyuncuya veya önizlemeye verilmez.
## Sonların, analizlerin ve testlerin seçilen biçimi ve yazarın tanımladığı gizli sınıflandırmayı okuması
## içindir. Arayüz yalnızca AdviceSystem.get_advice ve AdviceResult kullanır.

const AdviceResultScript := preload("res://scripts/systems/advice_result.gd")

## get_advice'ın döndüreceği sonucun aynısı (bağımsız örnek).
var result: AdviceResultScript = AdviceResultScript.new()
## Yalnızca offered: seçilen biçimin kimliği.
var variant_id: StringName = &""
## Yalnızca offered: seçilen biçimin veride tanımlanan gizli sınıflandırması (AdviceVariantData.ACCURACIES).
var accuracy: StringName = &""
