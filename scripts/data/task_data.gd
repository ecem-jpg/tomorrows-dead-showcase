class_name TaskData
extends Resource
## Bir aktöre verilebilen görevin tanımı (K-026, K-027). Görev başına tek aktör çifti vardır.
## Atama alanlarını TaskSystem, tamamlanma etkilerini TaskCompletionSystem doğrular ve kullanır.

const TaskAssignmentDataScript := preload("res://scripts/data/task_assignment_data.gd")
const EffectDataScript := preload("res://scripts/data/effect_data.gd")

@export var id: String = ""
## Kabul edildiğinde görevin ortak saatte süreceği birim; pozitif olmalı. Gece sonunu aşabilir.
@export var duration_units: int = 0
## Zorunlu.
@export var assignment: TaskAssignmentDataScript = null
## Görev tamamlandığında veri sırasıyla uygulanır; aynı hedefe birden fazla etki olamaz. Boş liste geçerlidir.
## Bir etki uygulanamazsa (yetersiz harcama) görev yine tamamlanır ama hiçbir etkisi uygulanmaz.
@export var completion_effects: Array[EffectDataScript] = []
