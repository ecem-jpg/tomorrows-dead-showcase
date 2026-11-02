class_name TrustRelationshipData
extends Resource
## Bir yönlü güven ilişkisinin başlangıç verisi: kaynak aktörün hedef aktöre güveni (K-023).
## TrustRulesData içinde alt kaynak olarak tutulur. Öneri doğruluğuna dair alan içermez.

@export var source_actor_id: String = ""
@export var target_actor_id: String = ""
## TrustRulesData.min_value..max_value içinde olmalı.
@export var starting_value: int = 0
