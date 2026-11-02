class_name CablePuzzleRulesData
extends Resource
## Kablo bulmacasının sınırları; CablePuzzleData içinde alt kaynak olarak tutulur (K-019).
## Varsayılan değerler geçersizdir; her bulmaca sınırlarını veride açıkça tanımlar.

# Sınıf önbelleğine bağımlı kalmamak için kendi tipine de yol ile başvurur.
const CablePuzzleRulesDataScript := preload("res://scripts/data/cable_puzzle_rules_data.gd")

## Bulmacanın ilişkili olduğu ekipman; varlığı sonuç uygulayan sistemde denetlenir.
@export var equipment_id: String = ""
## Tek oturumda, bütün terminaller bağlıyken yapılabilecek yanlış kontrol sayısı; en az 1.
@export var max_submissions: int = 0
## Oyun genelinde bu bulmacanın kaç kesin sonuçla (çözüldü/başarısız) tamamlanabileceği; en az 1.
## Uygulanması sonuç sistemine aittir; oturum bu alanı kullanmaz.
@export var max_resolutions: int = 0


## Bağımsız derin kopya. Yalnızca boş olmayan bir örnekte çağrılır.
func copy() -> CablePuzzleRulesDataScript:
	return duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as CablePuzzleRulesDataScript
