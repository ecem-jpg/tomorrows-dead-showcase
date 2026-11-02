class_name AdviceContextData
extends Resource
## Bir önerinin kimden kime ve (isteğe bağlı) hangi karar hakkında olduğu; AdviceData içinde alt kaynak (K-028).
## Kimlik alanları alt kaynakta durur; böylece veri doğrulayıcının en üst düzey `_id` başvuru kuralıyla çakışmaz.

## Öneren aktör.
@export var advisor_actor_id: String = ""
## Öneriyi alan aktör (oyuncunun yönettiği aktör); advisor_actor_id ile aynı olamaz.
@export var recipient_actor_id: String = ""
## İsteğe bağlı; doluysa DecisionSystem'de tanımlı bir karar olmalıdır. Boşsa öneri bir seçenek göstermez.
@export var decision_id: String = ""
