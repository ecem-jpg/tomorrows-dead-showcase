class_name ScheduledEventData
extends Resource
## Zamanlanmış bir olayın yalnızca zaman bilgisi. Koşul ve etkiler karar/etki sistemine aittir.

@export var id: String = ""
## Olayın gerçekleştiği gece; 1..night_count.
@export var night: int = 0
## Gece içindeki an; 1..night_length_units.
@export var at_units: int = 0
## Aynı anda gerçekleşen olaylar arasında sıra; eşitlikte id kullanılır.
@export var order: int = 0
