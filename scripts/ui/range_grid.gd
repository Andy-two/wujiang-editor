extends Control
class_name RangeGrid

# 逐格开关的范围选取器（沿用旧工程 main.gd 的 RangeGrid，并扩充）
#   multi=true  逐格开关，任意形状（用于「释放距离」「作用范围」）
#   multi=false 按曼哈顿距离选取（用于普攻射程）
# 附加能力：笔刷（涂/擦）、生成菱形/直线/矩形、镜像/旋转/清空、撤销
# 坐标系：中心为原点 (0,0)，x 向右、y 向下；导出为 [[x,y],...]

signal changed()

var grid_n := 9
var cell_size := 22
var accent := Color("#22d3ee")
var multi := true
var center_mark := "target"        # unit = 武将；target = 落点星标
var selected: Dictionary = {}      # Vector2i -> true
var hover_cell := Vector2i(-1, -1)
var brush := 1                     # 1 = 涂，0 = 擦
var allow_center := true
var _undo_stack: Array = []

var font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(grid_n * cell_size, grid_n * cell_size)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _center() -> Vector2i:
	var c := int(grid_n / 2)
	return Vector2i(c, c)


func _mdist(c: Vector2i) -> int:
	var m := _center()
	return absi(c.x - m.x) + absi(c.y - m.y)


func _at(pos: Vector2) -> Vector2i:
	var x := int(floor(pos.x / float(cell_size)))
	var y := int(floor(pos.y / float(cell_size)))
	if x < 0 or y < 0 or x >= grid_n or y >= grid_n:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func set_area(area: Array) -> void:
	selected.clear()
	for c in area:
		if c is Vector2i:
			selected[c] = true
		elif c is Array and (c as Array).size() >= 2:
			selected[Vector2i(int(c[0]), int(c[1]))] = true
	if not allow_center:
		selected.erase(Vector2i.ZERO)
	queue_redraw()


func get_area() -> Array:
	var arr: Array = selected.keys()
	arr.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x)
	return arr


func get_area_raw() -> Array:
	var out: Array = []
	for c in get_area():
		out.append([int(c.x), int(c.y)])
	return out


func set_diamond(r: int) -> void:
	_push_undo()
	selected.clear()
	if multi:
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if absi(x) + absi(y) <= r:
					selected[Vector2i(x, y)] = true
	else:
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if absi(x) + absi(y) == r or (r == 0 and x == 0 and y == 0):
					selected[Vector2i(x, y)] = true
	if not allow_center:
		selected.erase(Vector2i.ZERO)
	_after_change()


func set_cross(r: int) -> void:
	_push_undo()
	selected.clear()
	for i in range(-r, r + 1):
		selected[Vector2i(i, 0)] = true
		selected[Vector2i(0, i)] = true
	if not allow_center:
		selected.erase(Vector2i.ZERO)
	_after_change()


func set_ring(r: int) -> void:
	_push_undo()
	selected.clear()
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if absi(x) + absi(y) == r:
				selected[Vector2i(x, y)] = true
	_after_change()


func set_full() -> void:
	_push_undo()
	selected.clear()
	var m := _center()
	for y in grid_n:
		for x in grid_n:
			selected[Vector2i(x, y) - m] = true
	if not allow_center:
		selected.erase(Vector2i.ZERO)
	_after_change()


func clear_all() -> void:
	_push_undo()
	selected.clear()
	_after_change()


func invert() -> void:
	_push_undo()
	var m := _center()
	var inv := {}
	for y in grid_n:
		for x in grid_n:
			var off := Vector2i(x, y) - m
			if not selected.has(off):
				inv[off] = true
	selected = inv
	if not allow_center:
		selected.erase(Vector2i.ZERO)
	_after_change()


func mirror() -> void:
	_push_undo()
	var out := {}
	for c in selected.keys():
		out[Vector2i(-c.x, c.y)] = true
	selected = out
	_after_change()


func rotate_cw() -> void:
	_push_undo()
	var out := {}
	for c in selected.keys():
		out[Vector2i(-c.y, c.x)] = true
	selected = out
	_after_change()


func undo() -> void:
	if _undo_stack.is_empty():
		return
	selected = (_undo_stack.pop_back() as Dictionary).duplicate()
	queue_redraw()
	changed.emit()


func _push_undo() -> void:
	_undo_stack.append(selected.duplicate())
	if _undo_stack.size() > 40:
		_undo_stack.pop_front()


func _after_change() -> void:
	queue_redraw()
	changed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := _at(event.position)
		if c != hover_cell:
			hover_cell = c
			queue_redraw()
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and c.x >= 0 and multi:
			_paint(c)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := _at(event.position)
		if c.x >= 0:
			if multi:
				_push_undo()
				_paint(c)
			else:
				var d := _mdist(c)
				_push_undo()
				selected.clear()
				for y in grid_n:
					for x in grid_n:
						if _mdist(Vector2i(x, y)) == d:
							selected[Vector2i(x, y) - _center()] = true
				_after_change()
			accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var c := _at(event.position)
		if c.x >= 0 and multi:
			# 右键快速擦除
			_push_undo()
			selected.erase(c - _center())
			_after_change()
			accept_event()


func _paint(c: Vector2i) -> void:
	var off := c - _center()
	if off == Vector2i.ZERO and not allow_center:
		return
	if brush == 1:
		selected[off] = true
	else:
		selected.erase(off)
	_after_change()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_cell = Vector2i(-1, -1)
		queue_redraw()


func _draw() -> void:
	var total := float(grid_n * cell_size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#0b1220")
	bg.border_color = Color("#2b3648")
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	draw_style_box(bg, Rect2(Vector2.ZERO, Vector2(total, total)))
	var m := _center()
	for y in grid_n:
		for x in grid_n:
			var c := Vector2i(x, y)
			var r := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
			var on := selected.has(c - m)
			if on:
				var col := accent
				col.a = 0.32 if c - m != Vector2i.ZERO else 0.55
				draw_rect(r, col)
				draw_rect(r, Color(accent.r, accent.g, accent.b, 0.75), false, 1.0)
			if c == hover_cell:
				draw_rect(r, Color(1, 1, 1, 0.14))
				draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
	for i in range(grid_n + 1):
		var off := float(i * cell_size)
		draw_line(Vector2(off, 0), Vector2(off, total), Color("#1c2534"), 1.0)
		draw_line(Vector2(0, off), Vector2(total, off), Color("#1c2534"), 1.0)
	# 中心标记
	var cc := Vector2(m) * float(cell_size) + Vector2(cell_size, cell_size) * 0.5
	var f := font
	if f == null:
		f = ThemeDB.fallback_font
	if center_mark == "target":
		draw_arc(cc, float(cell_size) * 0.34, 0, TAU, 20, ORANGE_C, 2.0)
		draw_line(cc + Vector2(-cell_size * 0.3, 0), cc + Vector2(cell_size * 0.3, 0), ORANGE_C, 1.0)
		draw_line(cc + Vector2(0, -cell_size * 0.3), cc + Vector2(0, cell_size * 0.3), ORANGE_C, 1.0)
	else:
		draw_circle(cc, float(cell_size) * 0.28, Color("#38bdf8"))
		draw_string(f, cc + Vector2(-5, 5), "将", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#0b1220"))


const ORANGE_C := Color("#f97316")
