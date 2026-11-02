extends Node2D
## Ana sahnenin akış ve bağlama betiği (K-010). Üretim oyun oturumu henüz yoktur: başlangıçta ana arayüz yalnızca
## oturumsuz modeli gösterir. Sistem, presenter veya veri kurulmaz; sinyal bağlanmaz ve eylemler kapalı kalır.

const MainHudModelScript := preload("res://scripts/presentation/main_hud_model.gd")
const MainHudViewScript := preload("res://scripts/ui/main_hud_view.gd")

const NO_SESSION_FEEDBACK: StringName = &"UI_HUD_NO_SESSION"


func _ready() -> void:
	var ui: MainHudViewScript = get_node_or_null("UI") as MainHudViewScript
	if ui == null:
		push_error("Main: UI düğümü bulunamadı; ana arayüz gösterilemez.")
		return
	ui.show_model(MainHudModelScript.empty(NO_SESSION_FEEDBACK))
