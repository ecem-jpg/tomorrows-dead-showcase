class_name TrustRelationshipState
extends RefCounted
## Tek bir yönlü güven ilişkisinin çalışma zamanındaki değeri: kaynak aktörün hedef aktöre güveni.
## Ters yöndeki ilişki ayrı bir kayıttır. Sınırlar TrustSystem'de uygulanır.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const TrustRelationshipStateScript := preload("res://scripts/core/trust_relationship_state.gd")

var source_actor_id: StringName = &""
var target_actor_id: StringName = &""
var value: int = 0


func _init(p_source_actor_id: StringName = &"", p_target_actor_id: StringName = &"", p_value: int = 0) -> void:
	source_actor_id = p_source_actor_id
	target_actor_id = p_target_actor_id
	value = p_value


## Bağımsız kopya.
func copy() -> TrustRelationshipStateScript:
	return TrustRelationshipStateScript.new(source_actor_id, target_actor_id, value)


func equals(other: TrustRelationshipStateScript) -> bool:
	return other != null \
			and source_actor_id == other.source_actor_id \
			and target_actor_id == other.target_actor_id \
			and value == other.value
