class_name OccurrenceStatus
extends RefCounted
## Gelecek ceset görünümlerinin iç durumları ve izin verilen geçişleri; tek kaynak (K-029).
## Bu adlar iç sistem verisidir. Arayüz bunları değil, OccurrenceSystem.get_visible_bodies() sonucunu kullanır.

## Görünüm henüz gerçekleşmedi; oyun sonunda hâlâ böyleyse hiç görünmemiştir.
const STATUS_INACTIVE: StringName = &"inactive"
## Ölüm ihtimali beklemede; ceset morgda görünür.
const STATUS_PENDING: StringName = &"pending"
## Ölüm engellendi; kesin sonuç. Ceset morgdan kaybolur.
const STATUS_DEATH_PREVENTED: StringName = &"death_prevented"
## Ölüm kalıcı hâle geldi; kesin sonuç. Ceset morgda kalıcıdır.
const STATUS_DEATH_PERMANENT: StringName = &"death_permanent"

const STATUSES: Array[StringName] = [STATUS_INACTIVE, STATUS_PENDING, STATUS_DEATH_PREVENTED, STATUS_DEATH_PERMANENT]


static func is_valid(status: StringName) -> bool:
	return STATUSES.has(status)


## Yalnızca inactive → pending, pending → death_prevented ve pending → death_permanent izinlidir.
## Kesin sonuçlardan hiçbir geçiş yoktur. Aynı duruma "geçiş" bir geçiş sayılmaz (false).
static func can_transition(from: StringName, to: StringName) -> bool:
	if from == STATUS_INACTIVE:
		return to == STATUS_PENDING
	if from == STATUS_PENDING:
		return to == STATUS_DEATH_PREVENTED or to == STATUS_DEATH_PERMANENT
	return false


static func is_final(status: StringName) -> bool:
	return status == STATUS_DEATH_PREVENTED or status == STATUS_DEATH_PERMANENT
