class_name CableBoard
extends Control
## Kablo bulmacasının yer tutucu çizim yüzeyi (K-033).
##
## - Yalnızca kendisine verilen uçları, tarafları ve bağlantıları çizer; oturumu, doğru bağlantıları, terminal anlamını
##   ve sonucu bilmez.
## - Taraf açıkça verilir; konumdan, board merkezinden veya düğüm adından tahmin edilmez. Taraf yalnızca bağlantı
##   noktasının düğmenin hangi kenarında olacağını seçer: left → sağ kenar ortası, right → sol kenar ortası.
## - Eksik ya da geçersiz taraf, serbest bırakılmış veya ağaç dışındaki uç çizimde sessizce atlanır.
## - Bütün kablolar aynı görünümdedir; bağlantının doğru olup olmadığı görsel olarak ifade edilmez.
## - Hesap ve çizim yalnızca okur. Yeniden çizim olaylarla tetiklenir (boyut değişimi, show_cables, clear).

const SIDE_LEFT: StringName = &"left"
const SIDE_RIGHT: StringName = &"right"

const CABLE_WIDTH: float = 6.0
const CABLE_COLOR: Color = Color(0.86, 0.84, 0.78)
const PORT_RADIUS: float = 10.0
const PORT_RING_WIDTH: float = 3.0
const PORT_RING_POINTS: int = 24

# Uçlar zayıf referansla tutulur; silinen düğme hata üretmeden atlanır.
var _anchors: Dictionary[StringName, WeakRef] = {}
var _sides: Dictionary[StringName, StringName] = {}
var _connections: Array = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## anchors: terminal → düğme; sides: terminal → left / right; connections: [terminal, terminal] çiftleri.
## Girdiler kopyalanır; sonradan değişmeleri çizimi etkilemez.
func show_cables(anchors: Dictionary[StringName, Control], sides: Dictionary[StringName, StringName],
		connections: Array) -> void:
	_anchors.clear()
	for terminal: StringName in anchors:
		var anchor: Variant = anchors[terminal]
		if is_instance_valid(anchor):
			_anchors[terminal] = weakref(anchor)
	_sides = sides.duplicate()
	_connections = connections.duplicate(true)
	queue_redraw()


func clear() -> void:
	_anchors.clear()
	_sides.clear()
	_connections.clear()
	queue_redraw()


## Çizilecek kablolar, board'un yerel koordinatlarında [başlangıç, bitiş]. Uçlarından biri çizilemeyen kablo atlanır.
func get_segments() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for pair: Variant in _connections:
		if not (pair is Array) or pair.size() != 2:
			continue
		var start: Control = _anchor_for(pair[0])
		var end: Control = _anchor_for(pair[1])
		if start == null or end == null:
			continue
		result.append(PackedVector2Array([_port_point(start, _sides[pair[0]]), _port_point(end, _sides[pair[1]])]))
	return result


## Çizilebilen bütün uçların bağlantı noktaları: {"terminal", "point", "connected"}; uç veriliş sırasıyla.
func get_port_points() -> Array[Dictionary]:
	var connected: Dictionary[StringName, bool] = {}
	for pair: Variant in _connections:
		if pair is Array:
			for terminal: Variant in pair:
				if terminal is StringName:
					connected[terminal] = true
	var result: Array[Dictionary] = []
	for terminal: StringName in _anchors:
		var anchor: Control = _anchor_for(terminal)
		if anchor == null:
			continue
		result.append({
			"terminal": terminal,
			"point": _port_point(anchor, _sides[terminal]),
			"connected": connected.has(terminal),
		})
	return result


func _draw() -> void:
	for segment: PackedVector2Array in get_segments():
		draw_line(segment[0], segment[1], CABLE_COLOR, CABLE_WIDTH, true)
	# Bağlı uç dolu, boş uç halka: durum renkten bağımsız şekille de okunur.
	for port: Dictionary in get_port_points():
		var point: Vector2 = port["point"]
		if port["connected"]:
			draw_circle(point, PORT_RADIUS, CABLE_COLOR, true, -1.0, true)
		else:
			draw_arc(point, PORT_RADIUS, 0.0, TAU, PORT_RING_POINTS, CABLE_COLOR, PORT_RING_WIDTH, true)


func _anchor_for(terminal: Variant) -> Control:
	if not (terminal is StringName) or not is_inside_tree():
		return null
	var side: StringName = _sides.get(terminal, &"")
	if side != SIDE_LEFT and side != SIDE_RIGHT:
		return null
	var ref: WeakRef = _anchors.get(terminal)
	if ref == null:
		return null
	var anchor: Control = ref.get_ref() as Control
	if anchor == null or not anchor.is_inside_tree():
		return null
	return anchor


func _port_point(anchor: Control, side: StringName) -> Vector2:
	var rect: Rect2 = get_global_transform().affine_inverse() * anchor.get_global_rect()
	var x: float = rect.end.x if side == SIDE_LEFT else rect.position.x
	return Vector2(x, rect.get_center().y)
