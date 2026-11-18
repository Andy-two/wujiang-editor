extends Control

# ============================================================
# 演算台 + 小战场测试（同一个覆盖层窗口，两个页签）
#   验算台：面板数值 / 升级曲线 / 升级前后对比 / 技能命中与期望伤害
#   小战场：把改好的武将放到格子上实际走位、普攻、放技能、敌军 AI
# 共用 EdData（当前编辑中的内存数据），所以「改完立即可测」。
# ============================================================

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const THEME = preload("res://scripts/ui/theme.gd")
const BATTLE = preload("res://scripts/core/ed_battle.gd")
const CURVE = preload("res://scripts/ui/curve_chart.gd")

var data: EdData
var start_mode := "calc"
var focus_key := ""

var tabs: TabContainer
var status_label: Label

# --- 验算台 ---
var calc_key_opt: OptionButton
var calc_lv: SpinBox
var calc_star: SpinBox
var calc_arm: OptionButton
var calc_panel: RichTextLabel
var calc_curve: Control
var calc_diff: RichTextLabel
var calc_skill_opt: OptionButton
var calc_skill_lv: SpinBox
var calc_range_grid: RangeGrid
var calc_effect_grid: RangeGrid
var calc_skill_info: RichTextLabel
var calc_compare_lv: SpinBox

# --- 小战场 ---
var battle
var board: Control
var log_box: RichTextLabel
var unit_list: VBoxContainer
var sel_uid := -1
var mode := "select"            # select / move / attack / skill
var pending_skill := ""
var move_preview: Dictionary = {}
var hover_pos := Vector2i(-1, -1)
var enemy_opt: OptionButton
var enemy_lv_spin: SpinBox
var battle_status: Label
var skill_bar: HBoxContainer
var turn_label: Label


func _ready() -> void:
	theme = THEME.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_build()


func _build() -> void:
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 12
	frame.offset_top = 12
	frame.offset_right = -12
	frame.offset_bottom = -12
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	frame.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(THEME.label("测试台", 18, THEME.ACCENT))
	status_label = THEME.label("", 12, THEME.MUTED)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(status_label)
	var close := THEME.button("✕ 关闭（返回编辑）", 14, 170)
	close.pressed.connect(func() -> void: queue_free())
	head.add_child(close)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_build_calc())
	tabs.add_child(_build_battle())
	tabs.set_tab_title(0, "🧮 演算台")
	tabs.set_tab_title(1, "🎮 小战场")
	tabs.current_tab = 1 if start_mode == "battle" else 0
	if start_mode == "battle":
		_setup_battle()


# ============================================================
# 验算台
# ============================================================
func _build_calc() -> Control:
	var h := HBoxContainer.new()
	h.name = "演算台"
	h.add_theme_constant_override("separation", 10)

	# 左：选择
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	left.add_theme_constant_override("separation", 6)
	h.add_child(left)
	left.add_child(THEME.label("武将", 14, THEME.MUTED))
	calc_key_opt = OptionButton.new()
	for k in data.order:
		calc_key_opt.add_item(data.name_of(k))
	calc_key_opt.selected = maxi(0, data.order.find(focus_key))
	calc_key_opt.item_selected.connect(func(_i: int) -> void: _refresh_calc())
	left.add_child(calc_key_opt)
	var g := GridContainer.new()
	g.columns = 2
	left.add_child(g)
	g.add_child(THEME.label("等级", 13, THEME.MUTED))
	calc_lv = SpinBox.new()
	calc_lv.min_value = 1
	calc_lv.max_value = RULEZ.max_level()
	calc_lv.value_changed.connect(func(_v: float) -> void: _refresh_calc())
	g.add_child(calc_lv)
	g.add_child(THEME.label("星级", 13, THEME.MUTED))
	calc_star = SpinBox.new()
	calc_star.min_value = 1
	calc_star.max_value = RULEZ.max_star()
	calc_star.value_changed.connect(func(_v: float) -> void: _refresh_calc())
	g.add_child(calc_star)
	g.add_child(THEME.label("兵种", 13, THEME.MUTED))
	calc_arm = OptionButton.new()
	for a in ["盾", "枪", "弓", "骑"]:
		calc_arm.add_item(RULEZ.arm_name(a))
	calc_arm.item_selected.connect(func(_i: int) -> void: _refresh_calc())
	g.add_child(calc_arm)
	var sync := THEME.button("同步为该武将当前设定", 12)
	sync.pressed.connect(func() -> void:
		_sync_calc_from_general()
		_refresh_calc())
	left.add_child(sync)
	var cmp_row := HBoxContainer.new()
	cmp_row.add_child(THEME.label("对比等级", 13, THEME.MUTED))
	calc_compare_lv = SpinBox.new()
	calc_compare_lv.min_value = 1
	calc_compare_lv.max_value = RULEZ.max_level()
	calc_compare_lv.value_changed.connect(func(_v: float) -> void: _refresh_calc())
	cmp_row.add_child(calc_compare_lv)
	left.add_child(cmp_row)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	var q1 := THEME.button("Lv1", 12)
	q1.pressed.connect(func() -> void:
		calc_compare_lv.value = 1
		_refresh_calc())
	var q2 := THEME.button("Lv+1", 12)
	q2.pressed.connect(func() -> void:
		calc_compare_lv.value = calc_lv.value + 1
		_refresh_calc())
	var q3 := THEME.button("Lv10", 12)
	q3.pressed.connect(func() -> void:
		calc_compare_lv.value = 10
		_refresh_calc())
	var q4 := THEME.button("满级", 12)
	q4.pressed.connect(func() -> void:
		calc_compare_lv.value = RULEZ.max_level()
		_refresh_calc())
	quick.add_child(q1)
	quick.add_child(q2)
	quick.add_child(q3)
	quick.add_child(q4)
	left.add_child(quick)

	left.add_child(THEME.label("技能", 14, THEME.MUTED))
	calc_skill_opt = OptionButton.new()
	calc_skill_opt.item_selected.connect(func(_i: int) -> void: _refresh_calc_skill())
	left.add_child(calc_skill_opt)
	var slv := HBoxContainer.new()
	slv.add_child(THEME.label("技能等级", 13, THEME.MUTED))
	calc_skill_lv = SpinBox.new()
	calc_skill_lv.min_value = 1
	calc_skill_lv.max_value = 3
	calc_skill_lv.value_changed.connect(func(_v: float) -> void: _refresh_calc_skill())
	slv.add_child(calc_skill_lv)
	left.add_child(slv)

	# 中：面板 + 曲线 + 对比
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	h.add_child(mid)
	calc_panel = RichTextLabel.new()
	calc_panel.custom_minimum_size = Vector2(0, 120)
	calc_panel.bbcode_enabled = true
	calc_panel.fit_content = true
	mid.add_child(calc_panel)
	calc_curve = CURVE.new()
	calc_curve.name = "curve_chart"
	calc_curve.custom_minimum_size = Vector2(0, 210)
	calc_curve.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(calc_curve)
	calc_diff = RichTextLabel.new()
	calc_diff.custom_minimum_size = Vector2(0, 120)
	calc_diff.bbcode_enabled = true
	calc_diff.fit_content = true
	mid.add_child(calc_diff)

	# 右：范围与命中
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.add_theme_constant_override("separation", 4)
	h.add_child(right)
	right.add_child(THEME.label("技能范围预览（青=释放距离，橙=作用范围）", 13, THEME.MUTED))
	var grids := HBoxContainer.new()
	grids.add_theme_constant_override("separation", 8)
	right.add_child(grids)
	calc_range_grid = RangeGrid.new()
	calc_range_grid.grid_n = 11
	calc_range_grid.cell_size = 16
	calc_range_grid.center_mark = "unit"
	calc_range_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grids.add_child(calc_range_grid)
	calc_effect_grid = RangeGrid.new()
	calc_effect_grid.grid_n = 7
	calc_effect_grid.cell_size = 16
	calc_effect_grid.center_mark = "target"
	calc_effect_grid.accent = Color("#f97316")
	calc_effect_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grids.add_child(calc_effect_grid)
	calc_skill_info = RichTextLabel.new()
	calc_skill_info.custom_minimum_size = Vector2(0, 300)
	calc_skill_info.bbcode_enabled = true
	right.add_child(calc_skill_info)

	_sync_calc_from_general()
	call_deferred("_refresh_calc")
	return h


func _draw_curve_placeholder() -> void:
	pass


func _sync_calc_from_general() -> void:
	var k := _calc_key()
	if k == "":
		return
	var g: Dictionary = data.generals[k]
	calc_lv.value = int(g.get("ed_level", 1))
	calc_star.value = int(g.get("ed_star", 1))
	calc_compare_lv.value = mini(int(g.get("ed_level", 1)) + 1, RULEZ.max_level())
	calc_arm.selected = maxi(0, ["盾", "枪", "弓", "骑"].find(String(g.get("arm", "盾"))))
	calc_skill_opt.clear()
	calc_skill_opt.add_item("普攻")
	for sid in (g.get("skills", []) as Array):
		calc_skill_opt.add_item(data.skill_name(String(sid)))
	calc_skill_opt.selected = 0


func _calc_key() -> String:
	if data.order.is_empty():
		return ""
	return data.order[clampi(calc_key_opt.selected, 0, data.order.size() - 1)]


func _calc_arm() -> String:
	return ["盾", "枪", "弓", "骑"][clampi(calc_arm.selected, 0, 3)]


func _calc_sid() -> String:
	var k := _calc_key()
	if k == "" or calc_skill_opt.selected <= 0:
		return ""
	var sids: Array = data.generals[k].get("skills", [])
	var i := calc_skill_opt.selected - 1
	return String(sids[i]) if i < sids.size() else ""


func _refresh_calc() -> void:
	if not is_inside_tree() or calc_key_opt == null:
		return
	var k := _calc_key()
	if k == "":
		return
	var t := data.unit_template(k, int(calc_lv.value), int(calc_star.value), _calc_arm())
	var st: Dictionary = t.get("stats", {})
	# ---- 面板 ----
	var lines: Array = []
	lines.append("[color=#38bdf8][b]%s[/b][/color]  Lv%d · %d★ · %s · %s" % [
		t["name"], t["level"], t["star"], RULEZ.arm_name(String(t["arm"])), String(t.get("troop", ""))])
	var cc := RULEZ.crit_chance(float(st.get("luck", 50))) + float(t.get("crit_bonus", 0.0))
	lines.append("兵力 %s　物攻 %s　物防 %s　谋攻 %s　谋防 %s" % [_pill(int(st.get("max_hp", 0)), "#34d399"),
		_pill(int(st.get("atk", 0)), "#f97316"), _pill(int(st.get("def", 0)), "#38bdf8"),
		_pill(int(st.get("matk", 0)), "#c084fc"), _pill(int(st.get("mdef", 0)), "#22d3ee")])
	lines.append("幸运 %d（暴击 %.1f%%）　移动 %d　射程 %d　暴伤 ×%.2f" % [
		int(st.get("luck", 0)), cc * 100.0, int(st.get("move", 0)), int(st.get("range", 0)), RULEZ.get_f("crit_damage")])
	var g: Dictionary = data.generals[k]
	var ext: Dictionary = g.get("ed_ext", {})
	lines.append("[color=#94a3b8]五维：武 %d　智 %d　统 %d　政 %d　魅 %d　｜ 增伤 %+.0f%%　减伤 %+.0f%%　成长曲线 %s[/color]" % [
		int((ext.get("fives", {}) as Dictionary).get("wu", 0)), int((ext.get("fives", {}) as Dictionary).get("zhi", 0)),
		int((ext.get("fives", {}) as Dictionary).get("tong", 0)), int((ext.get("fives", {}) as Dictionary).get("zheng", 0)),
		int((ext.get("fives", {}) as Dictionary).get("mei", 0)), float(ext.get("damage_bonus", 0.0)) * 100.0,
		float(ext.get("damage_cut", 0.0)) * 100.0, String(ext.get("level_curve", "linear"))])
	var tid := String(g.get("talent", ""))
	lines.append("[color=#fbbf24]天赋[/color] %s Lv%d" % [data.talent_name(tid) if tid != "" else "（无）", int(g.get("ed_talent_lv", 1))])
	calc_panel.text = "\n".join(lines)

	# ---- 曲线 ----
	if calc_curve != null:
		var pts := []
		for lv in range(1, RULEZ.max_level() + 1):
			var tt := data.unit_template(k, lv, int(calc_star.value), _calc_arm())
			var s2: Dictionary = tt.get("stats", {})
			pts.append({"lv": lv, "v": int(s2.get("atk", 0)), "v2": int(s2.get("max_hp", 0)), "v3": int(s2.get("def", 0))})
		calc_curve.set("points", pts)
		calc_curve.set("mark_lv", int(calc_lv.value))
		calc_curve.queue_redraw()

	# ---- 升级前后对比 ----
	var from_lv := int(calc_lv.value)
	var to_lv := clampi(int(calc_compare_lv.value), 1, RULEZ.max_level())
	var diff := data.levelup_diff(k, "level", from_lv, to_lv - from_lv)
	var rows: Array = diff.get("rows", [])
	var dl: Array = ["[color=#38bdf8]升级对比：Lv%d → Lv%d[/color]" % [from_lv, to_lv]]
	for r in rows:
		var d := int(r["delta"])
		var col := "#34d399" if d > 0 else ("#f87171" if d < 0 else "#94a3b8")
		dl.append("%s  %d → %d  [color=%s]%s[/color]" % [r["label"], int(r["before"]), int(r["after"]), col,
			("+%d" % d) if d >= 0 else str(d)])
	# 星级对比
	var sdiff := data.levelup_diff(k, "star", int(calc_star.value), 1)
	var sl: Array = []
	for r in sdiff.get("rows", []):
		var d2 := int(r["delta"])
		sl.append("%s %+d" % [r["label"], d2])
	dl.append("[color=#f97316]再升 1 星（%d★→%d★）：[/color]%s" % [int(calc_star.value),
		mini(int(calc_star.value) + 1, RULEZ.max_star()), "　".join(sl)])
	calc_diff.text = "\n".join(dl)
	_refresh_calc_skill()


func _pill(v: int, col: String) -> String:
	return "[color=%s][b]%d[/b][/color]" % [col, v]


func _refresh_calc_skill() -> void:
	if calc_range_grid == null:
		return
	var k := _calc_key()
	if k == "":
		return
	var sid := _calc_sid()
	if sid == "":
		var t := data.unit_template(k, int(calc_lv.value), int(calc_star.value), _calc_arm())
		calc_range_grid.set_area(RULEZ.diamond(int((t.get("stats", {}) as Dictionary).get("range", 1))))
		calc_effect_grid.set_area([Vector2i.ZERO])
		calc_skill_info.text = "[color=#94a3b8]普攻：按射程生成菱形范围。可在「⑧ 技能范围」页改写普攻形状。[/color]"
		return
	var d: Dictionary = data.get_skill(sid)
	var lv := int(calc_skill_lv.value)
	var cast_a: Array = RULEZ.parse_area(d.get("cast", []))
	var area_a: Array = RULEZ.parse_area(d.get("area", []))
	# 武将自定义范围
	var er: Dictionary = data.generals[k].get("ed_ranges", {})
	var custom := false
	if er.has(sid):
		var e: Dictionary = er[sid]
		if e.has("cast"):
			cast_a = RULEZ.parse_area(e["cast"])
			custom = true
		if e.has("area"):
			area_a = RULEZ.parse_area(e["area"])
	if cast_a.is_empty():
		cast_a = RULEZ.diamond(maxi(1, int(d.get("range", 1))))
	if area_a.is_empty():
		var r := int(d.get("radius", 0))
		area_a = RULEZ.diamond(r) if r > 0 else [Vector2i.ZERO]
	calc_range_grid.set_area(cast_a)
	calc_effect_grid.set_area(area_a)
	var t2 := data.unit_template(k, int(calc_lv.value), int(calc_star.value), _calc_arm())
	var tpl_enemy := _dummy_enemy(int(calc_lv.value))
	var arm_m := RULEZ.arm_multiplier(String(t2.get("arm", "盾")), String(tpl_enemy.get("arm", "盾")))
	var mult := float(d.get("mult", 1.0))
	var magic := bool(d.get("magic", false)) or float((t2["stats"] as Dictionary).get("matk", 0)) > float((t2["stats"] as Dictionary).get("atk", 0))
	var exp_dmg := RULEZ.expected_damage(t2["stats"], tpl_enemy["stats"], mult, arm_m, magic)
	var kind := String(d.get("kind", "single"))
	var txt: Array = []
	txt.append("[color=#f97316][b]%s[/b][/color]  [%s]  CD %d%s" % [data.skill_name(sid),
		String(RULEZ.SKILL_KIND_NAMES.get(kind, kind)), int(d.get("cd", 0)), "  ·自定义范围" if custom else ""])
	txt.append("[color=#94a3b8]释放格 %d（最远 %d）　作用格 %d　倍率 ×%.2f　%s[/color]" % [
		cast_a.size(), RULEZ.area_radius(cast_a), area_a.size(), mult, "谋略伤害" if magic else "物理伤害"])
	txt.append("")
	txt.append("描述：%s" % String(d.get("desc", "")))
	var lvs: Array = d.get("lv", [])
	txt.append("")
	txt.append("[color=#34d399]Lv%d：%s[/color]" % [lv, String(lvs[lv - 1]) if lv - 1 < lvs.size() else ""])
	txt.append("[color=#fbbf24]Lv%d：%s[/color]" % [mini(lv + 1, 3), "（已是最高级）" if lv >= 3 else String(lvs[lv]) if lv < lvs.size() else ""])
	txt.append("")
	if kind in ["heal", "support"]:
		var heal := int(round(float((t2["stats"] as Dictionary).get("matk", 0)) * float(d.get("heal", RULEZ.get_f("heal_mult_default")))))
		txt.append("[color=#6ee7b7]预期治疗：%d 兵力[/color]" % heal)
	else:
		txt.append("[color=#fca5a5]对标准靶（同等级盾兵）预期伤害：%d[/color]" % exp_dmg)
		var t3 := t2.duplicate(true)
		t3["stats"]["luck"] = int((t2["stats"] as Dictionary).get("luck", 50)) + 100
		txt.append("[color=#94a3b8]兵种克制倍率 ×%.2f（%s 打 %s）[/color]" % [arm_m,
			RULEZ.arm_name(String(t2.get("arm", ""))), RULEZ.arm_name(String(tpl_enemy.get("arm", "")))])
	calc_skill_info.text = "\n".join(txt)


func _dummy_enemy(lv: int) -> Dictionary:
	# 标准靶：用于演算对比的固定假想敌（盾兵，2 倍等级线性）
	return {
		"name": "标准靶",
		"arm": "盾",
		"stats": {
			"max_hp": 100 + lv * 4, "atk": 50 + lv, "def": 40 + lv,
			"matk": 40, "mdef": 30, "luck": 50, "move": 4, "range": 1,
		},
	}


# ============================================================
# 小战场
# ============================================================
func _build_battle() -> Control:
	var root := HBoxContainer.new()
	root.name = "小战场"
	root.add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	left.add_child(THEME.label("我方出战", 15, THEME.ACCENT))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 200)
	unit_list = VBoxContainer.new()
	unit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(unit_list)
	left.add_child(sc)
	var g := VBoxContainer.new()
	g.add_theme_constant_override("separation", 4)
	left.add_child(g)
	enemy_opt = OptionButton.new()
	for k in data.order:
		enemy_opt.add_item(data.name_of(k))
	enemy_opt.selected = mini(1, data.order.size() - 1)
	_srow(g, "敌军类型", enemy_opt)
	enemy_lv_spin = SpinBox.new()
	enemy_lv_spin.min_value = 1
	enemy_lv_spin.max_value = RULEZ.max_level()
	enemy_lv_spin.value = 5
	_srow(g, "敌军等级", enemy_lv_spin)
	var setup := THEME.button("🔄 重置战场", 14)
	setup.pressed.connect(_setup_battle)
	left.add_child(setup)
	left.add_child(THEME.sep())
	left.add_child(THEME.label("操作", 14, THEME.MUTED))
	var ops := THEME.hint("点我方棋子选中 → 点蓝格移动 / 点敌人普攻 / 点技能按钮后点落点。\n" +
		"R = 结束我方回合（敌军自动行动）")
	left.add_child(ops)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	root.add_child(mid)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	mid.add_child(hb)
	turn_label = THEME.label("", 15, THEME.ACCENT)
	hb.add_child(turn_label)
	battle_status = THEME.label("", 12, THEME.WARN)
	battle_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battle_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_status.custom_minimum_size = Vector2(200, 0)
	hb.add_child(battle_status)
	skill_bar = HBoxContainer.new()
	skill_bar.add_theme_constant_override("separation", 4)
	mid.add_child(skill_bar)
	board = Control.new()
	board.custom_minimum_size = Vector2(560, 470)
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.gui_input.connect(_on_board_input)
	board.mouse_exited.connect(func() -> void:
		hover_pos = Vector2i(-1, -1)
		board.queue_redraw())
	board.draw.connect(_draw_board)
	mid.add_child(board)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.add_theme_constant_override("separation", 4)
	root.add_child(right)
	right.add_child(THEME.label("战报", 15, THEME.ACCENT))
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_box)
	var rb := THEME.button("结束我方回合", 14)
	rb.pressed.connect(_end_player_turn)
	right.add_child(rb)
	return root


func _srow(parent: Control, label: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := THEME.label(label, 13, THEME.MUTED)
	l.custom_minimum_size = Vector2(72, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	if ctrl is SpinBox:
		ctrl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ctrl.custom_minimum_size = Vector2(110, 0)
	else:
		ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	parent.add_child(h)


func _setup_battle() -> void:
	battle = BATTLE.new(13, 11)
	var gens := {}
	for k in data.order:
		gens[k] = data.generals[k]
	_generals_ref = gens
	battle.bind_data(gens, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	battle.set_seed(12345)
	battle.log_line.connect(_on_log)
	battle.changed.connect(func() -> void: _refresh_battle())
	battle.fx_event.connect(_on_fx)
	_tex_cache.clear()
	# 我方：当前武将 + 几个
	var picks: Array = []
	if focus_key != "" and data.generals.has(focus_key):
		picks.append(focus_key)
	for k in data.order:
		if picks.size() >= 4:
			break
		if bool(data.generals[k].get("ed_enabled", true)) and not picks.has(k):
			picks.append(k)
	for i in picks.size():
		var t := data.unit_template(String(picks[i]))
		var u = battle.add_unit(t, Vector2i(2 + i * 2, 8), 0)
		u["hero"] = i == 0
	# 敌军
	var ek := ""
	if enemy_opt != null and enemy_opt.selected >= 0 and enemy_opt.selected < data.order.size():
		ek = data.order[enemy_opt.selected]
	elif not data.order.is_empty():
		ek = data.order[mini(1, data.order.size() - 1)]
	var elv := int(enemy_lv_spin.value) if enemy_lv_spin != null else 5
	for i in 3:
		var t2 := data.unit_template(ek, elv, 1, "")
		battle.add_unit(t2, Vector2i(3 + i * 3, 2), 1)
	sel_uid = -1
	mode = "select"
	pending_skill = ""
	battle.start_side(0)
	_rebuild_skill_bar()
	_refresh_battle()
	_update_unit_list()


func _on_log(text: String, tone: String) -> void:
	if log_box == null:
		return
	var col: Color = THEME.TONE_COLORS.get(tone, THEME.TEXT)
	log_box.append_text("[color=#%s]%s[/color]\n" % [col.to_html(false), text])


# ------------------------------------------------------------
# 技能特效：在落点（或施法者/全部作用格）上播放导入的特效图
# ------------------------------------------------------------
var _fx_playing: Array = []          # [{tex, a, cells, t0, total, size_px}]


func _on_fx(sid: String, cells: Array, skill: Dictionary) -> void:
	var fx = skill.get("ed_fx", null)
	if not (fx is Dictionary):
		return
	var f: Dictionary = fx
	var path := String(f.get("path", ""))
	var tex := _anim_tex(path)
	if tex == null:
		return
	var anchor := String(f.get("anchor", "target"))
	var origin_cells: Array = []
	if anchor == "caster":
		# 施法者：找当前出手的最近单位（用技能数据推断不了，退化为落点）
		origin_cells = [cells[0]] if not cells.is_empty() else []
	elif anchor == "all":
		origin_cells = cells.duplicate()
	elif anchor == "center":
		origin_cells = [cells[cells.size() / 2]] if not cells.is_empty() else []
	else:
		origin_cells = [cells[0]] if not cells.is_empty() else []
	var fw := maxi(1, int(f.get("frame_w", 64)))
	var fh := maxi(1, int(f.get("frame_h", 64)))
	_fx_playing.append({
		"tex": tex, "a": f, "cells": origin_cells, "t0": Time.get_ticks_msec() / 1000.0,
		"n": maxi(1, int(f.get("frames", 4))), "fps": maxf(1.0, float(f.get("fps", 12.0))),
		"fw": fw, "fh": fh, "scale": float(f.get("scale", 1.0)),
		"offset_y": float(f.get("offset_y", 0.0)),
	})


func _draw_fx() -> void:
	if _fx_playing.is_empty() or battle == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var s := _cell_stride()
	var o := _board_origin()
	for e in _fx_playing:
		var a: Dictionary = e["a"]
		var n := int(e["n"])
		var elapsed := now - float(e["t0"])
		var idx := int(elapsed * float(e["fps"]))
		if idx >= n:
			continue
		var fw := int(e["fw"])
		var fh := int(e["fh"])
		var cols := maxi(1, int(a.get("grid_cols", n)))
		var abs_idx := int(a.get("start", 0)) + idx
		var region := Rect2((abs_idx % cols) * fw, (abs_idx / cols) * fh, fw, fh)
		var sz := s * 1.6 * float(e["scale"])
		for c in (e["cells"] as Array):
			var cc: Vector2i = c
			var p := o + Vector2(cc) * s
			var rect := Rect2(p + Vector2(s * 0.5 - sz * 0.5, s * 0.5 - sz * 0.5 + float(e["offset_y"])), Vector2(sz, sz))
			board.draw_texture_rect_region(e["tex"], rect, region)


func _process(delta: float) -> void:
	if battle == null or board == null:
		return
	battle.tick_anim(delta)
	if not _fx_playing.is_empty():
		_fx_playing = _fx_playing.filter(func(e) -> bool:
			return (Time.get_ticks_msec() / 1000.0) - float(e["t0"]) <= float(e["n"]) / float(e["fps"]))
	# 有待机/走路动画或特效时持续重绘
	if _has_any_sprite() or not _fx_playing.is_empty():
		board.queue_redraw()


func _has_any_sprite() -> bool:
	for u in battle.units:
		var art: Dictionary = battle.unit_art(u)
		if not art.is_empty():
			return true
	return false


func _cell_px() -> float:
	var b = battle
	var cw := board.size.x / float(maxi(1, b.gw))
	var ch := board.size.y / float(maxi(1, b.gh))
	return floorf(minf(cw, ch))


func _cell_stride() -> float:
	# 不铺满，居中留边
	return _cell_px()


func _board_origin() -> Vector2:
	var s := _cell_stride()
	return Vector2((board.size.x - s * battle.gw) * 0.5, (board.size.y - s * battle.gh) * 0.5)


func _pos_to_cell(p: Vector2) -> Vector2i:
	var o := _board_origin()
	var s := _cell_stride()
	var x := int(floor((p.x - o.x) / s))
	var y := int(floor((p.y - o.y) / s))
	if x < 0 or y < 0 or x >= battle.gw or y >= battle.gh:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _draw_board() -> void:
	if battle == null:
		return
	var s := _cell_stride()
	var o := _board_origin()
	var font := get_theme_default_font()
	# 底格
	for y in battle.gh:
		for x in battle.gw:
			var r := Rect2(o + Vector2(x, y) * s, Vector2(s, s))
			var col := Color("#16223a") if (x + y) % 2 == 0 else Color("#131d31")
			if battle.blocked.has(Vector2i(x, y)):
				col = Color("#3b2a1a")
			board.draw_rect(r, col)
			if battle.blocked.has(Vector2i(x, y)):
				board.draw_rect(r, Color("#7c5a2a"), false, 2.0)
	# 移动预览
	if move_preview.has(_sel_pos()) or mode == "move":
		for c in move_preview.keys():
			var r2 := Rect2(o + Vector2(c) * s, Vector2(s, s))
			board.draw_rect(r2, Color(0.22, 0.74, 0.97, 0.18))
			board.draw_rect(r2, Color(0.22, 0.74, 0.97, 0.45), false, 1.0)
	var sel = battle.get_unit(sel_uid)
	# 普攻范围
	if sel != null and (mode == "attack" or mode == "select"):
		for off in battle.attack_area(sel):
			var c2: Vector2i = sel["pos"] + off
			if battle.in_bounds(c2):
				var r3 := Rect2(o + Vector2(c2) * s, Vector2(s, s))
				board.draw_rect(r3, Color(0.97, 0.45, 0.16, 0.10))
	# 技能落点预览
	if sel != null and mode == "skill" and pending_skill != "" and hover_pos.x >= 0:
		if battle.can_cast_at(sel, pending_skill, hover_pos):
			for c3 in battle.effect_cells_at(sel, pending_skill, hover_pos):
				if battle.in_bounds(c3):
					var r4 := Rect2(o + Vector2(c3) * s, Vector2(s, s))
					board.draw_rect(r4, Color(0.97, 0.45, 0.16, 0.35))
					board.draw_rect(r4, Color(1, 0.6, 0.25, 0.8), false, 2.0)
		for off in battle.skill_cast_area(sel, pending_skill):
			var c4: Vector2i = sel["pos"] + off
			if battle.in_bounds(c4):
				var r5 := Rect2(o + Vector2(c4) * s, Vector2(s, s))
				board.draw_rect(r5, Color(0.13, 0.83, 0.93, 0.12))
	# 网格
	for x in battle.gw + 1:
		board.draw_line(o + Vector2(x, 0) * s, o + Vector2(x, battle.gh) * s, Color("#1c2534"), 1.0)
	for y in battle.gh + 1:
		board.draw_line(o + Vector2(0, y) * s, o + Vector2(battle.gw, y) * s, Color("#1c2534"), 1.0)
	# 单位
	for u in battle.units:
		if not u["alive"] and String(u.get("anim", "")) != "die":
			continue
		var p := o + Vector2(u["pos"]) * s
		var cr := s * 0.38
		var col := Color(u["color"]) if u["side"] == 0 else Color("#dc2626")
		if String(u["color"]).begins_with("#"):
			col = Color.from_string(String(u["color"]), col)
		# 有精灵图就画精灵帧，否则画色块
		var drew_sprite := _draw_unit_sprite(u, p, s)
		if not drew_sprite:
			board.draw_circle(p + Vector2(s, s) * 0.5, cr, col)
			board.draw_circle(p + Vector2(s, s) * 0.5, cr, Color(1, 1, 1, 0.5), false, 2.0)
		else:
			board.draw_circle(p + Vector2(s * 0.5, s * 0.86), cr * 0.55, Color(0, 0, 0, 0.35))
		if int(u["uid"]) == sel_uid:
			board.draw_arc(p + Vector2(s, s) * 0.5, cr + 4, 0, TAU, 28, Color("#38bdf8"), 3.0)
		elif bool(u["done"]) and int(u["side"]) == battle.turn_side and u["alive"]:
			board.draw_circle(p + Vector2(s, s) * 0.5, cr, Color(0, 0, 0, 0.35))
			board.draw_circle(p + Vector2(s, s) * 0.5, cr, Color("#555c6b"), false, 2.0)
		if not u["alive"]:
			board.draw_string(font, p + Vector2(0, s * 0.5), "✖", HORIZONTAL_ALIGNMENT_CENTER,
				int(s), int(maxf(12, s * 0.35)), Color("#f87171"))
			continue
		var nm := String(u["name"])
		board.draw_string(font, p + Vector2(0, s - 4), nm.substr(0, 4), HORIZONTAL_ALIGNMENT_CENTER,
			int(s), int(maxf(10, s * 0.2)), Color.WHITE)
		# 血条
		var hp_r := float(u["hp"]) / float(maxi(1, u["max_hp"]))
		var br := Rect2(p + Vector2(s * 0.12, s * 0.62), Vector2(s * 0.76, s * 0.1))
		board.draw_rect(br, Color(0, 0, 0, 0.6))
		var fc := Color("#34d399") if hp_r > 0.5 else (Color("#fbbf24") if hp_r > 0.25 else Color("#f87171"))
		board.draw_rect(Rect2(br.position, Vector2(br.size.x * hp_r, br.size.y)), fc)
		if int(u["side"]) == 1:
			board.draw_string(font, p + Vector2(s * 0.02, s * 0.2), "敌", HORIZONTAL_ALIGNMENT_LEFT,
				-1, int(maxf(9, s * 0.18)), Color("#fca5a5"))
	_draw_fx()


# 画单位的精灵帧：按 动作+朝向 取槽位（帧号表 + 三张图之一）
func _draw_unit_sprite(u, p: Vector2, s: float) -> bool:
	var act := String(u.get("anim", "idle"))
	var dir := String(u.get("face", "down"))
	var slot := _pick_slot(act, dir)
	var anims: Dictionary = battle.unit_art(u)
	var a = anims.get(slot, null)
	if not (a is Dictionary):
		return false
	var d: Dictionary = a
	var g: Dictionary = _generals_ref.get(String(u.get("key", "")), {})
	if g.is_empty():
		return false
	var sheet := String(d.get("sheet", "mov"))
	var path := ""
	var art = g.get("ed_art", {})
	if art is Dictionary and (art as Dictionary).get("sheets") is Dictionary:
		path = String(((art as Dictionary)["sheets"] as Dictionary).get(sheet, ""))
	if path == "":
		return false
	var fw := maxi(1, int((art as Dictionary).get("frame_w", 64)))
	var fh := maxi(1, int((art as Dictionary).get("frame_h", 64)))
	var tex := _anim_tex(path)
	if tex == null:
		return false
	var fr: Array = d.get("frames", [1])
	if fr.is_empty():
		return false
	var fps := maxf(1.0, float(d.get("fps", 8.0)))
	var loop := bool(d.get("loop", true))
	var t_anim := Time.get_ticks_msec() / 1000.0
	var start_t := float(u.get("anim_t", t_anim))
	var idx := 0
	if loop:
		idx = int(fmod(t_anim * fps, float(fr.size())))
	else:
		idx = clampi(int(maxf(0.0, t_anim - start_t) * fps), 0, fr.size() - 1)
	if act == "die":
		idx = fr.size() - 1
	var cols := maxi(1, int(tex.get_width() / fw))
	var frame_no := int(fr[idx])
	var zero := maxi(0, frame_no - 1)
	var region := Rect2((zero % cols) * fw, (zero / cols) * fh, fw, fh)
	var size_px := s * 0.95
	var rect := Rect2(p + Vector2(s * 0.5 - size_px * 0.5, s * 0.70 - size_px), Vector2(size_px, size_px))
	var mirror := bool(d.get("mirror", false))
	if mirror:
		board.draw_set_transform(Vector2(rect.position.x + rect.size.x, rect.position.y), 0, Vector2(-1, 1))
		board.draw_texture_rect_region(tex, Rect2(Vector2(0, 0), rect.size), region)
		board.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		board.draw_texture_rect_region(tex, rect, region)
	return true


# 缺某朝向时回退：本动作下方向 → 右方向镜像左方向 → 待机下方向
func _pick_slot(act: String, dir: String) -> String:
	var anims: Dictionary = {}
	for u in battle.units:
		if int(u["side"]) == 0:
			anims = battle.unit_art(u)
			break
	var order := ["%s_%s" % [act, dir], "%s_down" % act]
	if dir == "right":
		order.append("%s_left" % act)
	order.append("idle_down")
	for sl in order:
		if anims.has(sl):
			return String(sl)
	return "%s_%s" % [act, dir]


var _generals_ref: Dictionary = {}


var _tex_cache: Dictionary = {}


func _anim_tex(path: String) -> Texture2D:
	return data.load_tex(path) if data != null else null


func _sel_pos() -> Vector2i:
	var u = battle.get_unit(sel_uid) if battle != null else null
	return u["pos"] if u != null else Vector2i(-99, -99)


func _on_board_input(event: InputEvent) -> void:
	if battle == null:
		return
	if event is InputEventMouseMotion:
		hover_pos = _pos_to_cell(event.position)
		board.queue_redraw()
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var c := _pos_to_cell(event.position)
	if c.x < 0:
		return
	var u = battle.unit_at(c)
	if battle.turn_side != 0:
		battle_status.text = "敌军回合，请稍候"
		return
	if mode == "skill":
		var sel = battle.get_unit(sel_uid)
		if sel == null:
			return
		var r = battle.cast_skill(sel, pending_skill, c)
		# 二选一组：弹出选择菜单
		if bool(r.get("need_choice", false)):
			_open_group_choice(r, sel, c)
			return
		if bool(r.get("ok", false)):
			battle.end_unit_turn(sel)
			mode = "select"
			pending_skill = ""
			_rebuild_skill_bar()
			_refresh_battle()
		else:
			battle_status.text = String(r.get("msg", "无法施放"))
			board.queue_redraw()
		return
	if mode == "move":
		var sel2 = battle.get_unit(sel_uid)
		if sel2 == null:
			return
		var r2 = battle.try_move(sel2, c)
		if bool(r2.get("ok", false)):
			mode = "select"
			move_preview = {}
			battle_status.text = "已移动，可再攻击/放技能，或按「结束该单位」"
			_refresh_battle()
		else:
			battle_status.text = String(r2.get("msg", ""))
		return
	# 选中 / 攻击
	if u != null and int(u["side"]) == 0:
		sel_uid = int(u["uid"])
		mode = "select"
		pending_skill = ""
		_rebuild_skill_bar()
		_refresh_battle()
	elif u != null and int(u["side"]) == 1:
		var sel3 = battle.get_unit(sel_uid)
		if sel3 != null:
			var r3 = battle.basic_attack(sel3, u)
			if bool(r3.get("ok", false)):
				battle.end_unit_turn(sel3)
				_refresh_battle()
			else:
				battle_status.text = String(r3.get("msg", "无法攻击"))
	elif sel_uid >= 0:
		var sel4 = battle.get_unit(sel_uid)
		if sel4 != null and battle.move_cells(sel4).has(c):
			var r4 = battle.try_move(sel4, c)
			if bool(r4.get("ok", false)):
				_refresh_battle()


# 二选一组：弹窗列出子技能，点一个后按子技能施放
func _open_group_choice(r: Dictionary, u, target: Vector2i) -> void:
	if is_instance_valid(_group_win):
		_group_win.queue_free()
	var win := Window.new()
	win.title = "选择技策 · %s" % String(r.get("group", ""))
	win.size = Vector2i(460, 320)
	win.exclusive = true
	add_child(win)
	_group_win = win
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 12
	v.offset_right = -12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 8)
	win.add_child(v)
	v.add_child(THEME.label(String(r.get("msg", "请选择一个技策")), 14, THEME.ACCENT))
	var choices: Array = r.get("choices", [])
	for item in choices:
		var ch: Dictionary = item
		var b := THEME.button("", 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var nm := String(ch.get("name", ch.get("id", "?")))
		var cd := int(ch.get("cd", 0))
		b.text = "%s%s" % [nm, ("  （准备中 %d 回合）" % cd) if cd > 0 else ""]
		b.disabled = cd > 0
		b.tooltip_text = String(ch.get("desc", ""))
		var cid := String(ch.get("id", ""))
		var gid := String(r.get("group", ""))
		b.pressed.connect(func() -> void:
			win.hide()
			var rr = battle.cast_skill(u, gid, target, cid)
			if bool(rr.get("ok", false)):
				battle.end_unit_turn(u)
				mode = "select"
				pending_skill = ""
				_rebuild_skill_bar()
				_refresh_battle()
			else:
				battle_status.text = String(rr.get("msg", "无法施放"))
			win.queue_free())
		v.add_child(b)
	var cancel := THEME.button("取消", 13)
	cancel.pressed.connect(func() -> void: win.queue_free())
	v.add_child(cancel)
	win.popup_centered()


var _group_win: Window


func _rebuild_skill_bar() -> void:
	if skill_bar == null:
		return
	for ch in skill_bar.get_children():
		ch.queue_free()
	var sel = battle.get_unit(sel_uid) if battle != null else null
	if sel == null:
		skill_bar.add_child(THEME.label("选中一名我方武将后显示技能按钮", 12, THEME.MUTED))
		return
	var mbtn := THEME.button("移动", 13)
	mbtn.pressed.connect(func() -> void:
		mode = "move"
		move_preview = battle.move_cells(sel)
		pending_skill = ""
		battle_status.text = "点击蓝格移动"
		board.queue_redraw())
	skill_bar.add_child(mbtn)
	var abtn := THEME.button("普攻", 13)
	abtn.pressed.connect(func() -> void:
		mode = "attack"
		pending_skill = ""
		battle_status.text = "点击射程内的敌人（橙色格）"
		board.queue_redraw())
	skill_bar.add_child(abtn)
	for sid in sel["skills"]:
		var d: Dictionary = battle.skill_def(String(sid))
		if d.is_empty() or String(d.get("kind", "")) == "passive":
			continue
		var grp: bool = battle.is_group(String(sid))
		var cd := int(sel["cd"].get(String(sid), 0))
		var label := data.skill_name(String(sid))
		if grp:
			label = "⇄ " + label + "（二选一）"
		var b := THEME.button("%s%s" % [label, (" (CD%d)" % cd) if cd > 0 else ""], 13)
		b.disabled = cd > 0
		var tip := "CD %d · %s\n%s" % [int(d.get("cd", 0)),
			String(RULEZ.SKILL_KIND_NAMES.get(String(d.get("kind", "")), "")), String(d.get("desc", ""))]
		if grp:
			var cn: Array = []
			for c in battle.group_children(String(sid)):
				cn.append(data.skill_name(String(c)))
			tip += "\n可选：" + " / ".join(cn)
		b.tooltip_text = tip
		b.pressed.connect(func() -> void:
			mode = "skill"
			pending_skill = String(sid)
			battle_status.text = "点击落点施放「%s」" % data.skill_name(String(sid))
			board.queue_redraw())
		skill_bar.add_child(b)
	var done := THEME.button("结束该单位", 13)
	done.pressed.connect(func() -> void:
		battle.end_unit_turn(sel)
		_refresh_battle())
	skill_bar.add_child(done)


func _end_player_turn() -> void:
	if battle == null:
		return
	for u in battle.units:
		if int(u["side"]) == 0:
			u["done"] = true
	battle.next_side()
	_refresh_battle()
	# 敌军自动行动（小延迟，便于观察）
	await get_tree().create_timer(0.35).timeout
	if battle != null:
		battle.run_ai()
		battle.next_side()
		if battle.ended:
			battle_status.text = "战斗结束：" + ("胜利" if battle.result == "victory" else "失败")
		_refresh_battle()


func _refresh_battle() -> void:
	if battle == null or board == null:
		return
	if mode == "select" or mode == "attack":
		var sel = battle.get_unit(sel_uid)
		if sel != null:
			move_preview = {}
	if battle.turn_side == 0:
		turn_label.text = "第 %d 回合 · 我方行动" % battle.round_no
		turn_label.add_theme_color_override("font_color", THEME.ACCENT)
	else:
		turn_label.text = "第 %d 回合 · 敌军行动" % battle.round_no
		turn_label.add_theme_color_override("font_color", Color("#f87171"))
	board.queue_redraw()
	_update_unit_list()


func _update_unit_list() -> void:
	if unit_list == null or battle == null:
		return
	for c in unit_list.get_children():
		c.queue_free()
	for u in battle.units:
		var p := PanelContainer.new()
		var hb := HBoxContainer.new()
		p.add_child(hb)
		var col := Color.from_string(String(u["color"]), Color("#3b82f6")) if int(u["side"]) == 0 else Color("#dc2626")
		var dot := ColorRect.new()
		dot.color = col
		dot.custom_minimum_size = Vector2(10, 0)
		hb.add_child(dot)
		var hp_r := float(u["hp"]) / float(maxi(1, u["max_hp"]))
		var fc := THEME.GOOD if hp_r > 0.5 else (THEME.WARN if hp_r > 0.25 else THEME.BAD)
		var l := THEME.label("%s [%s] Lv%d %d/%d" % [u["name"], RULEZ.arm_name(String(u["arm"])),
			int(u["level"]), int(u["hp"]), int(u["max_hp"])], 12,
			THEME.MUTED if not u["alive"] else fc)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		if int(u["side"]) == 0:
			hb.add_child(THEME.label("我", 11, THEME.ACCENT))
		unit_list.add_child(p)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if mode == "skill" or mode == "move":
				mode = "select"
				pending_skill = ""
				battle_status.text = ""
				board.queue_redraw()
				accept_event()
			else:
				queue_free()
				accept_event()
		elif event.keycode == KEY_R and tabs.current_tab == 1 and battle != null:
			_end_player_turn()
			accept_event()
