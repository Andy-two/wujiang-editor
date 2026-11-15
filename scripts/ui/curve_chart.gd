extends Control

# 升级曲线图：物攻 / 兵力 / 物防 随等级变化，并标出当前等级
# points: [{"lv":1,"v":atk,"v2":hp,"v3":def}, ...]

var points: Array = []
var mark_lv := 1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var f := get_theme_default_font()
	var w := size.x
	var h := size.y
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#0d1626")
	bg.set_corner_radius_all(6)
	bg.border_color = Color("#243149")
	bg.set_border_width_all(1)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	if points.is_empty() or w < 40 or h < 40:
		return
	var pad_l := 52.0
	var pad_r := 16.0
	var pad_t := 26.0
	var pad_b := 22.0
	var gw := w - pad_l - pad_r
	var gh := h - pad_t - pad_b
	var maxv := 1
	var maxhp := 1
	for p in points:
		maxv = maxi(maxv, int(p["v"]))
		maxv = maxi(maxv, int(p["v3"]))
		maxhp = maxi(maxhp, int(p["v2"]))
	var n := points.size()
	# 网格
	for i in 5:
		var y := pad_t + gh * float(i) / 4.0
		draw_line(Vector2(pad_l, y), Vector2(pad_l + gw, y), Color(1, 1, 1, 0.06), 1.0)
		var vv := int(round(float(maxv) * (1.0 - float(i) / 4.0)))
		draw_string(f, Vector2(4, y + 4), str(vv), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7b8aa3"))
	# 曲线
	_draw_series(f, pad_l, pad_t, gw, gh, maxv, "v", Color("#f97316"))
	_draw_series(f, pad_l, pad_t, gw, gh, maxv, "v3", Color("#38bdf8"))
	_draw_series(f, pad_l, pad_t, gw, gh, maxhp, "v2", Color("#34d399"), true)
	# 当前等级竖线
	var mi := clampi(mark_lv - 1, 0, n - 1)
	var mx := pad_l + gw * float(mi) / float(maxi(1, n - 1))
	draw_line(Vector2(mx, pad_t), Vector2(mx, pad_t + gh), Color(1, 1, 1, 0.5), 1.0)
	var mp: Dictionary = points[mi]
	draw_string(f, Vector2(mx + 4, pad_t + 12), "Lv%d 物攻%d 兵力%d" % [int(mp["lv"]), int(mp["v"]), int(mp["v2"])],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#e2e8f0"))
	# 图例
	var lx := pad_l + 8.0
	draw_string(f, Vector2(lx, 14), "物攻", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#f97316"))
	draw_string(f, Vector2(lx + 46, 14), "物防", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#38bdf8"))
	draw_string(f, Vector2(lx + 92, 14), "兵力（右轴）", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#34d399"))
	for i in [1, 10, 20, 30, 40, 50]:
		if i > n:
			break
		var x := pad_l + gw * float(i - 1) / float(maxi(1, n - 1))
		draw_string(f, Vector2(x - 8, h - 6), str(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#7b8aa3"))


func _draw_series(f: Font, pad_l: float, pad_t: float, gw: float, gh: float, maxv: int,
		key: String, col: Color, dashed: bool = false) -> void:
	var n := points.size()
	var prev := Vector2.ZERO
	for i in n:
		var v := float(int(points[i][key]))
		var x := pad_l + gw * float(i) / float(maxi(1, n - 1))
		var y := pad_t + gh * (1.0 - v / float(maxi(1, maxv)))
		var cur := Vector2(x, y)
		if i > 0:
			draw_line(prev, cur, col, 2.0 if not dashed else 1.5)
		prev = cur
