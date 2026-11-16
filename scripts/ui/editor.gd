extends Control
# ============================================================
# 战棋武将编辑器 · 主控
#   左：武将列表（搜索 / 新建 / 复制 / 删除 / 排序）
#   右：页签（基础 / 属性 / 五维 / 成长 / 兵种 / 技能 / 天赋 / 范围 / 立绘 / 扩展）
#   顶：保存、导出、演算台、小战场、全局设定
# ============================================================
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const THEME = preload("res://scripts/ui/theme.gd")
const RG = preload("res://scripts/ui/range_grid.gd")
const SANDBOX = preload("res://scenes/Sandbox.tscn")
var data: EdData
var cur_key := ""
var busy := false
# --- 左侧 ---
var list_box: VBoxContainer
var search_edit: LineEdit
var filter_opt: OptionButton
var count_label: Label
# --- 右侧页签 ---
var tabs: TabContainer
# 基础
var f_key: LineEdit
var f_name: LineEdit
var f_id: SpinBox
var f_troop: LineEdit
var f_color: ColorPickerButton
var f_note: TextEdit
var f_tags: LineEdit
var portrait_tex: TextureRect
var illust_tex: TextureRect
var basic_list: VBoxContainer
# 属性
var stat_spins := {}
var stat_preview: Label
var move_readonly_lbl: Label
var range_readonly_lbl: Label
# 五维
var five_spins := {}
# 成长 / 升星
var star_plan_box: VBoxContainer
var star_status: Label
var star_dup_spin: SpinBox
var star_skill_opt: OptionButton
var star_skill_ids: Array[String] = []
var star_rule_cost_spin: SpinBox
var five_growth_label: Label
var grow_spins := {}
var curve_opt: OptionButton
var growth_preview: VBoxContainer
# 兵种
var arm_opt: OptionButton
var arm2_opt: OptionButton
# 兵种
var arm_info: RichTextLabel
var counter_table: RichTextLabel
var arm_up_lv_spin: SpinBox
var arm_up_summary: Label
var arm_up_widgets := {}
var arm_up_grid: VBoxContainer
var arm_up_note: Label
var base_move_spins := {}
var base_range_spins := {}
# 技能
var skill_list: VBoxContainer
var skill_edit_box: VBoxContainer
var skill_search: LineEdit
var skill_pick_dialog: Window
# 天赋
var talent_opt: OptionButton
var talent_lv_spin: SpinBox
var talent_desc: RichTextLabel
var talent_fx_box: VBoxContainer
# 范围
var range_owner_opt: OptionButton
var range_skill_opt: OptionButton
var range_layer_btns := {}
var cast_grid: RangeGrid
var effect_grid: RangeGrid
var range_cd_spin: SpinBox
var range_info: Label
var range_brush_btn: Button
var _range_ctx := {"owner": "", "sid": "basic", "layer": 1}
# 立绘 / 动画
var art_portrait_tex: TextureRect
var art_illust_tex: TextureRect
var art_sprite_tex: TextureRect
var art_frame_idx: SpinBox
var anim_matrix: VBoxContainer
var anim_slot_title: Label
var anim_slot_info: Label
var anim_color_rect: ColorRect
var anim_type_opt: OptionButton
var anim_frame_idx: SpinBox
var anim_param_spins := {}
var anim_sheet_ui := {}
var anim_sheet_opt: OptionButton
var anim_frames_edit: LineEdit
var anim_fps_spin: SpinBox
var anim_loop_cb: CheckBox
var anim_mirror_cb: CheckBox
var anim_frame_w_spin: SpinBox
var anim_frame_h_spin: SpinBox
var _fx_rebuild: Callable = Callable()
var _fx_editing_sid := ""
var _fx_sync_desc := true
var anim_strip: HBoxContainer
var anim_play_state: Label
var art_sel := {"act": "idle", "dir": "down"}
# 扩展
var ext_widgets := {}
# 全局设定
var set_widgets := {}
# 状态
var status_label: Label
var sandbox = null
func _ready() -> void:
	theme = THEME.make_theme()
	data = EdData.new()
	if not data.load_all():
		push_error(data.last_error)
	_build()
	if not data.order.is_empty():
		select_general.call(data.order[0])
# ------------------------------------------------------------
# 布局
# ------------------------------------------------------------
func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = THEME.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_topbar())
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 290
	root.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_right())
	root.add_child(_build_statusbar())
func _build_topbar() -> Control:
	var bar := PanelContainer.new()
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	bar.add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	m.add_child(h)
	var title := THEME.label("⚔ 战棋武将编辑器 · 测试台", 20, THEME.ACCENT)
	h.add_child(title)
	h.add_child(THEME.label("  录入 → 修改 → 测试 → 导出", 12, THEME.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var b_save := THEME.button("💾 保存", 14, 90)
	b_save.tooltip_text = "保存到 res://data/editor/（武将 / 技策 / 天赋 / 设定）"
	b_save.pressed.connect(_on_save)
	h.add_child(b_save)
	var b_export := THEME.button("📦 导出给游戏", 14, 130)
	b_export.tooltip_text = "导出 JSON（完整 / 旧工程兼容 / 精简战斗包），或直接写入指定目录"
	b_export.pressed.connect(_on_export)
	h.add_child(b_export)
	var b_calc := THEME.button("🧮 演算台", 14, 110)
	b_calc.tooltip_text = "面板数值、升级曲线、升级效果变化、技能命中预览"
	b_calc.pressed.connect(_on_open_sandbox.bind("calc"))
	h.add_child(b_calc)
	var b_test := THEME.button("🎮 小战场测试", 14, 140)
	b_test.tooltip_text = "部署改好的武将，实际移动 / 普攻 / 放技能，验证效果"
	b_test.pressed.connect(_on_open_sandbox.bind("battle"))
	h.add_child(b_test)
	var b_set := THEME.button("⚙ 全局设定", 14, 110)
	b_set.tooltip_text = "等级上限、星级成长、兵种修正、克制、暴击、伤害浮动等全局参数"
	b_set.pressed.connect(func() -> void:
		tabs.current_tab = tabs.get_tab_count() - 1)
	h.add_child(b_set)
	return bar
func _build_left() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(280, 0)
	box.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_child(THEME.label("武将", 16, THEME.ACCENT))
	count_label = THEME.label("", 12, THEME.MUTED)
	head.add_child(count_label)
	box.add_child(head)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "搜索：名称 / key / 兵种 / 阵营"
	search_edit.text_changed.connect(func(_t: String) -> void: refresh_list())
	box.add_child(search_edit)
	filter_opt = OptionButton.new()
	filter_opt.add_item("全部武将")
	filter_opt.add_item("仅启用的")
	filter_opt.add_item("仅禁用的")
	filter_opt.item_selected.connect(func(_i: int) -> void: refresh_list())
	box.add_child(filter_opt)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	var b_new := THEME.button("＋新建", 13)
	b_new.pressed.connect(_on_new_general)
	tools.add_child(b_new)
	var b_dup := THEME.button("⧉复制", 13)
	b_dup.pressed.connect(_on_dup_general)
	tools.add_child(b_dup)
	var b_del := THEME.button("🗑删除", 13)
	b_del.pressed.connect(_on_del_general)
	tools.add_child(b_del)
	var b_up := THEME.button("↑", 13, 30)
	b_up.pressed.connect(func() -> void:
		if cur_key != "":
			data.move_general(cur_key, -1)
			refresh_list())
	tools.add_child(b_up)
	var b_dn := THEME.button("↓", 13, 30)
	b_dn.pressed.connect(func() -> void:
		if cur_key != "":
			data.move_general(cur_key, 1)
			refresh_list())
	tools.add_child(b_dn)
	box.add_child(tools)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 3)
	sc.add_child(list_box)
	box.add_child(sc)
	refresh_list()
	return box
func _build_right() -> Control:
	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_page_basic())
	tabs.add_child(_page_stats())
	tabs.add_child(_page_five())
	tabs.add_child(_page_growth())
	tabs.add_child(_page_arm())
	tabs.add_child(_page_skills())
	tabs.add_child(_page_talent())
	tabs.add_child(_page_range())
	tabs.add_child(_page_art())
	tabs.add_child(_page_ext())
	tabs.add_child(_page_settings())
	# 页签标题
	var names := ["① 基础", "② 属性", "③ 五维", "④ 等级/星级", "⑤ 兵种",
		"⑥ 技能", "⑦ 天赋", "⑧ 技能范围", "⑨ 头像/立绘/精灵图", "⑩ 扩展与补充", "⑪ 全局设定"]
	for i in names.size():
		tabs.set_tab_title(i, names[i])
	return tabs
func _build_statusbar() -> Control:
	var bar := PanelContainer.new()
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	bar.add_child(m)
	status_label = THEME.label("就绪", 12, THEME.MUTED)
	m.add_child(status_label)
	return bar
func _scroll_page() -> Array:
	var sc := ScrollContainer.new()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return [sc, v]
func _section(title: String, sub: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(THEME.label(title, 15, THEME.ACCENT))
	if sub != "":
		v.add_child(THEME.hint(sub))
	return v
# ------------------------------------------------------------
# ① 基础
# ------------------------------------------------------------
func _page_basic() -> Control:
	var r := _scroll_page()
	var sc: ScrollContainer = r[0]
	var v: VBoxContainer = r[1]
	sc.name = "基础"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	# 立绘预览
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(230, 0)
	row.add_child(pv)
	pv.add_child(THEME.label("头像（可把图片直接拖到这里）", 13, THEME.MUTED))
	portrait_tex = TextureRect.new()
	portrait_tex.custom_minimum_size = Vector2(120, 120)
	portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_tex.name = "portrait_drop"
	portrait_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait_tex.tooltip_text = "把 PNG/JPG 图片拖进来即可设为头像"
	portrait_tex.set_drag_forwarding(_drag_nothing, _can_drop_file, _drop_portrait)
	var pf := PanelContainer.new()
	pf.add_child(portrait_tex)
	pv.add_child(pf)
	pv.add_child(THEME.label("立绘（可把图片直接拖到这里）", 13, THEME.MUTED))
	illust_tex = TextureRect.new()
	illust_tex.custom_minimum_size = Vector2(220, 300)
	illust_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illust_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	illust_tex.name = "illust_drop"
	illust_tex.mouse_filter = Control.MOUSE_FILTER_STOP
	illust_tex.tooltip_text = "把 PNG/JPG 图片拖进来即可设为立绘"
	illust_tex.set_drag_forwarding(_drag_nothing, _can_drop_file, _drop_illust)
	var ilf := PanelContainer.new()
	ilf.add_child(illust_tex)
	pv.add_child(ilf)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	row.add_child(form)
	var g1 := VBoxContainer.new()
	g1.add_theme_constant_override("separation", 6)
	form.add_child(g1)
	f_name = _form_line(g1, "姓名", func(t: String) -> void:
		if cur_key != "":
			data.generals[cur_key]["name"] = t
			_mark_dirty()
			refresh_list())
	f_key = _form_line(g1, "数据 key", func(_t: String) -> void:
		pass)
	f_key.editable = false
	f_key.tooltip_text = "导出给游戏时使用的唯一标识，可点右侧「重命名 key」修改"
	var krow := HBoxContainer.new()
	var rename_btn := THEME.button("重命名 key", 12)
	rename_btn.pressed.connect(_on_rename_key)
	krow.add_child(rename_btn)
	g1.add_child(krow)
	f_id = _form_spin(g1, "武将 id", 1, 99999999, func(v: int) -> void:
		if cur_key != "":
			data.generals[cur_key]["id"] = v
			_mark_dirty())
	f_troop = _form_line(g1, "兵种名（显示）", func(t: String) -> void:
		if cur_key != "":
			data.generals[cur_key]["troop"] = t
			_mark_dirty()
			refresh_list())
	f_color = ColorPickerButton.new()
	f_color.custom_minimum_size = Vector2(120, 30)
	f_color.color_changed.connect(func(c: Color) -> void:
		if cur_key != "":
			data.generals[cur_key]["color"] = "#" + c.to_html(false)
			_mark_dirty())
	_form_row(g1, "代表色", f_color)
	f_tags = _form_line(g1, "标签（逗号分隔）", func(t: String) -> void:
		if cur_key != "":
			var arr: Array = []
			for s in t.split(",", false):
				arr.append(s.strip_edges())
			data.generals[cur_key]["ed_tags"] = arr
			_mark_dirty())
	f_note = TextEdit.new()
	f_note.custom_minimum_size = Vector2(0, 120)
	f_note.text_changed.connect(func() -> void:
		if cur_key != "":
			data.generals[cur_key]["ed_note"] = f_note.text
			_mark_dirty())
	var nv := VBoxContainer.new()
	nv.add_child(THEME.label("设计备注", 13, THEME.MUTED))
	nv.add_child(f_note)
	form.add_child(nv)
	var art_row := HBoxContainer.new()
	art_row.add_theme_constant_override("separation", 6)
	art_row.add_child(THEME.label("图片：", 13, THEME.MUTED))
	var b_p := THEME.button("导入头像…", 13)
	b_p.pressed.connect(func() -> void: _import_art("portrait"))
	art_row.add_child(b_p)
	var b_i := THEME.button("导入立绘…", 13)
	b_i.pressed.connect(func() -> void: _import_art("illust"))
	art_row.add_child(b_i)
	var b_s := THEME.button("去精灵图页 →", 13)
	b_s.pressed.connect(func() -> void: tabs.current_tab = 8)
	art_row.add_child(b_s)
	form.add_child(art_row)
	var tips := THEME.hint("提示：所有改动即时写入内存，点右上角「💾 保存」写入项目 data/editor/；" +
		"点「🧮 演算台」可对比升级前后效果，点「🎮 小战场测试」可实际打一局验证。")
	v.add_child(tips)
	return sc
func _form_row(parent: Control, label: String, ctrl: Control) -> Control:
	# 一行：固定宽度标签 + 控件
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := THEME.label(label, 13)
	l.custom_minimum_size = Vector2(110, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if (ctrl is SpinBox or ctrl is CheckBox) else Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	parent.add_child(h)
	return ctrl
func _form_line(parent: Control, label: String, cb: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.text_changed.connect(cb)
	_form_row(parent, label, e)
	return e
func _form_spin(parent: Control, label: String, mn: float, mx: float, cb: Callable,
		step: float = 1.0, as_float: bool = false) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	s.custom_minimum_size = Vector2(120, 0)
	s.value_changed.connect(func(v: float) -> void:
		if as_float:
			cb.call(v)
		else:
			cb.call(int(v)))
	_form_row(parent, label, s)
	return s
# ------------------------------------------------------------
# ② 属性
# ------------------------------------------------------------
func _page_stats() -> Control:
	var r := _scroll_page()
	var sc: ScrollContainer = r[0]
	var v: VBoxContainer = r[1]
	sc.name = "属性"
	var s := _section("面板基础属性", "这里填「1 级、1 星、无装备」的裸数值；实际战斗值 = 基础 + 等级成长，再乘星级与兵种修正。")
	v.add_child(s)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	s.add_child(grid)
	var defs := [
		["hp", "兵力", 1, 99999], ["atk", "物攻", 0, 9999], ["def", "物防", 0, 9999],
		["matk", "谋攻", 0, 9999], ["mdef", "谋防", 0, 9999], ["luck", "幸运(暴击)", 0, 200],
	]
	for d in defs:
		var k: String = d[0]
		var sp := SpinBox.new()
		sp.min_value = d[2]
		sp.max_value = d[3]
		sp.custom_minimum_size = Vector2(120, 0)
		sp.value_changed.connect(func(val: float) -> void:
			if cur_key != "" and not busy:
				data.generals[cur_key]["stats"][k] = int(val)
				_mark_dirty()
				_update_stat_preview())
		_form_row(grid, "%s（%s）" % [d[1], k], sp)
		stat_spins[k] = sp
	# 移动力 / 射程：由兵种决定，这里只显示（去「⑤ 兵种」改）
	move_readonly_lbl = THEME.label("", 13, THEME.ACCENT)
	_form_row(grid, "移动力（跟随兵种）", move_readonly_lbl)
	range_readonly_lbl = THEME.label("", 13, THEME.ACCENT)
	_form_row(grid, "射程（跟随兵种）", range_readonly_lbl)
	var note := THEME.hint("暴击率 = 幸运 × 全局系数（默认 0.004，即 50 幸运 = 20%）。暴击伤害、浮动等见「⑪ 全局设定」。")
	s.add_child(note)
	var s2 := _section("当前生效面板（按等级/星级/兵种换算）")
	v.add_child(s2)
	stat_preview = THEME.label("", 13)
	stat_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s2.add_child(stat_preview)
	return sc
func _update_stat_preview() -> void:
	if cur_key == "":
		return
	var t := data.unit_template(cur_key)
	var st := _stats_of(t)
	var parts: Array = []
	for k in ["max_hp", "atk", "def", "matk", "mdef", "luck", "move", "range"]:
		parts.append("%s %d" % [str(RULEZ.STAT_LABELS.get(k, k)), int(st.get(k, 0))])
	var ex: Dictionary = t.get("ext", {}) if t.get("ext") is Dictionary else {}
	# 暴击率：魅力（幸运与运势已合并）
	var mei := 0
	var fv = t.get("fives", null)
	if fv is Dictionary:
		mei = int((fv as Dictionary).get("mei", 0))
	var mei_cc := float(mei) * RULEZ.get_f("crit_per_mei")
	var extra_cc := float(t.get("crit_bonus", 0.0))
	var cc := RULEZ.crit_chance_of(t)
	var cm := RULEZ.crit_mult_of(t)
	stat_preview.text = "Lv%d / %d★ / %s 兵： %s\n" % [
		int(t.get("level", 1)), int(t.get("star", 1)), RULEZ.arm_name(String(t.get("arm", "盾"))),
		"  ".join(parts)]
	stat_preview.text += "暴击率 %.1f%%（魅力%d点 %.1f%% + 附加 %.1f%%，另有对敌运势差±0.1%%/点）　暴击伤害 ×%.2f（基础 ×%.2f + 魅力 +%.2f）\n" % [
		cc * 100.0, mei, mei_cc * 100.0, extra_cc * 100.0,
		cm, RULEZ.get_f("crit_damage"), cm - RULEZ.get_f("crit_damage")]
	stat_preview.text += "总增伤 %+.0f%%　减伤 %+.0f%%\n" % [
		float(ex.get("damage_bonus", 0.0)) * 100.0, float(t.get("damage_cut", 0.0)) * 100.0]
	# 战力：当前 + 升 1 级 / 升 1 星后的对比
	var p_now := RULEZ.combat_power(t)
	var p_lv := RULEZ.combat_power(data.unit_template(cur_key, int(t.get("level", 1)) + 1, int(t.get("star", 1))))
	var p_star := RULEZ.combat_power(data.unit_template(cur_key, int(t.get("level", 1)), int(t.get("star", 1)) + 1))
	stat_preview.text += "⚔ 战力 %d　（升 1 级 → %d，+%d　｜　升 1 星 → %d，+%d ⚡）" % [
		p_now, p_lv, p_lv - p_now, p_star, p_star - p_now]
	# 移动力 / 射程：显示由兵种算出的值，并注明来源
	if move_readonly_lbl != null:
		var armn := RULEZ.arm_name(String(t.get("arm", "盾")))
		move_readonly_lbl.text = "%d（%s 基础 %d）" % [int(st.get("move", 0)), armn, RULEZ.arm_base_move(String(t.get("arm", "盾")))]
	if range_readonly_lbl != null:
		var armn2 := RULEZ.arm_name(String(t.get("arm", "盾")))
		range_readonly_lbl.text = "%d（%s 基础 %d）" % [int(st.get("range", 0)), armn2, RULEZ.arm_base_range(String(t.get("arm", "盾")))]
# 安全取 stats（避免字典无键时用 [] 访问报错）
func _stats_of(t: Dictionary) -> Dictionary:
	var v = t.get("stats", {})
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}
func _dict_of(t: Dictionary, k: String) -> Dictionary:
	var v = t.get(k, {})
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}
# ------------------------------------------------------------
# ③ 五维
# ------------------------------------------------------------
func _update_five_growth_label() -> void:
	if five_growth_label == null or cur_key == "":
		return
	var g: Dictionary = data.generals[cur_key]
	var lv := clampi(int(g.get("ed_level", 1)), 1, RULEZ.max_level())
	var base_fives: Dictionary = (g["ed_ext"].get("fives", {}) as Dictionary)
	var cur5: Dictionary = RULEZ.fives_at(base_fives, lv)
	var add: Dictionary = RULEZ.five_growth_of(lv)
	five_growth_label.text = "当前 Lv%d 实际五维：武 %d　智 %d　统 %d　政 %d　魅 %d　（升级累计各 +%d）" % [
		lv, int(cur5.get("wu", 0)), int(cur5.get("zhi", 0)), int(cur5.get("tong", 0)),
		int(cur5.get("zheng", 0)), int(cur5.get("mei", 0)), int(add.get("wu", 0))]
func _page_five() -> Control:
	var r := _scroll_page()
	var sc: ScrollContainer = r[0]
	var v: VBoxContainer = r[1]
	sc.name = "五维"
	var s := _section("五维属性（武 / 智 / 统 / 政 / 魅）",
		"这里填 1 级时的初始五维。**武将升级会直接提升五维**（每级各 +N，可在「⑪ 全局设定」调），" +
		"下方会显示当前等级的实际五维。打开「五维派生」后才会按权重影响物攻/谋攻/物防/谋防/幸运。")
	v.add_child(s)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	s.add_child(grid)
	var meta := [
		["wu", "武力", "影响物攻"], ["zhi", "智力", "影响谋攻"], ["tong", "统率", "影响物防"],
		["zheng", "政治", "影响谋防"], ["mei", "魅力", "影响暴击/爆伤"],
	]
	for m in meta:
		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 100
		sp.custom_minimum_size = Vector2(110, 0)
		sp.value_changed.connect(func(val: float) -> void:
			if cur_key != "" and not busy:
				data.generals[cur_key]["ed_ext"]["fives"][String(m[0])] = int(val)
				_mark_dirty()
				_update_stat_preview()
				_update_five_growth_label())
		_form_row(grid, "%s（%s）" % [m[1], m[2]], sp)
		five_spins[m[0]] = sp
	# 等级带来的五维成长显示
	five_growth_label = THEME.label("", 13, THEME.GOOD)
	v.add_child(five_growth_label)
	var bar := THEME.label("", 13)
	v.add_child(bar)
	five_spins["_bar"] = bar
	var der := THEME.hint("五维派生开关：%s" % ("开启" if RULEZ.get_b("derive_five") else "关闭"))
	v.add_child(der)
	der.name = "five_derive_hint"
	var b := THEME.button("一键按面板属性推算五维", 13)
	b.pressed.connect(func() -> void:
		if cur_key == "":
			return
		var st: Dictionary = data.generals[cur_key]["stats"]
		var fx: Dictionary = data.generals[cur_key]["ed_ext"]["fives"]
		fx["wu"] = clampi(int(round(float(st.get("atk", 50)) / 2.0)), 1, 100)
		fx["zhi"] = clampi(int(round(float(st.get("matk", 50)) / 2.0)), 1, 100)
		fx["tong"] = clampi(int(round(float(st.get("def", 40)) / 1.5)), 1, 100)
		fx["zheng"] = clampi(int(round(float(st.get("mdef", 40)) / 1.5)), 1, 100)
		fx["mei"] = clampi(int(st.get("luck", 50)) + 10, 1, 100)
		_mark_dirty()
		load_general(cur_key)
		status("已按面板属性推算五维"))
	v.add_child(b)
	return sc
# ------------------------------------------------------------
# ④ 等级 / 星级 / 成长
# ------------------------------------------------------------
func _page_growth() -> Control:
	var r := _scroll_page()
	var sc: ScrollContainer = r[0]
	var v: VBoxContainer = r[1]
	sc.name = "成长"
	var s := _section("等级与星级（可任意修改）",
		"等级与星级决定面板数值：每级按下方成长值增加；每星全属性 ×(1+星级%)、兵力额外 +值。上限在「⑪ 全局设定」。")
	v.add_child(s)
	var g := VBoxContainer.new()
	# ---------------- 升星模块（1 星起；按规则升技能/天赋/属性；每星消耗 1 个同名武将） ----------------
	var s5 := _section("升星（初始 1 星 · 每星消耗 1 个同名武将 · 武将靠抽卡获得）",
		"升星规则：2/3/4/6/7/9 星 → 技能升阶（**升哪个技能由你选**）；5/10 星 → 天赋升阶；8 星 → 全属性 +8%。" +
		"每一星都只消耗 1 个同名武将。同名武将数量代表抽到的重复角色，可在下方直接登记或用「抽卡」获得。")
	v.add_child(s5)
	# 升技能星时选哪个技能（每个技能星分别设置，见下方计划表）
	var sk_row := HBoxContainer.new()
	sk_row.add_theme_constant_override("separation", 8)
	s5.add_child(sk_row)
	sk_row.add_child(THEME.label("技能升星在下方计划表里逐星选择要升的技能", 12, THEME.MUTED))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	s5.add_child(srow)
	srow.add_child(THEME.label("同名武将持有", 13, THEME.MUTED))
	var dup_sp := SpinBox.new()
	dup_sp.min_value = 0
	dup_sp.max_value = 999
	dup_sp.custom_minimum_size = Vector2(90, 0)
	dup_sp.value_changed.connect(func(v: float) -> void:
		if cur_key == "" or busy:
			return
		data.generals[cur_key]["ed_dup"] = int(v)
		_mark_dirty()
		_refresh_star_ui())
	star_dup_spin = dup_sp
	srow.add_child(dup_sp)
	var gacha := THEME.button("抽卡（随机获得同名 +1）", 12)
	gacha.tooltip_text = "模拟抽卡：有概率抽到本武将的同名副本"
	gacha.pressed.connect(func() -> void:
		if cur_key == "":
			return
		var dup := int(data.generals[cur_key].get("ed_dup", 0))
		var got := 1 if RULEZ.RNG.randf() < float(RULEZ.get_f("gacha_rate_same") if RULEZ.settings.has("gacha_rate_same") else 0.05) else 0
		dup += got
		data.generals[cur_key]["ed_dup"] = dup
		_mark_dirty()
		_refresh_star_ui()
		status("抽卡：%s +%d（当前同名 %d）" % ["命中！" if got > 0 else "未命中", got, dup]))
	srow.add_child(gacha)
	var up_now := THEME.button("升星（按规则）", 13)
	up_now.pressed.connect(_do_star_now)
	srow.add_child(up_now)
	var auto := THEME.button("一路升到 10 星（演示）", 12)
	auto.pressed.connect(_auto_star_demo)
	srow.add_child(auto)
	star_plan_box = VBoxContainer.new()
	star_plan_box.add_theme_constant_override("separation", 2)
	s5.add_child(star_plan_box)
	star_status = THEME.label("", 13, THEME.WARN)
	s5.add_child(star_status)
	s.add_child(g)
	# 当前等级 / 星级
	var lv_sp := _form_spin(g, "当前等级", 1, RULEZ.max_level(), func(val: int) -> void:
		if cur_key != "" and not busy:
			data.generals[cur_key]["ed_level"] = clampi(val, 1, RULEZ.max_level())
			_mark_dirty()
			_update_stat_preview()
			_update_growth_preview())
	var star_sp := _form_spin(g, "当前星级", 1, RULEZ.max_star(), func(val: int) -> void:
		if cur_key != "" and not busy:
			data.generals[cur_key]["ed_star"] = clampi(val, 1, RULEZ.max_star())
			_mark_dirty()
			_update_stat_preview()
			_update_growth_preview())
	growth_preview = VBoxContainer.new()
	v.add_child(growth_preview)
	var s2 := _section("每级成长值（升 1 级增加的裸数值）", "默认沿用旧工程：兵力 +4、四维 +1，每 5 级额外 +1。")
	v.add_child(s2)
	var g2 := VBoxContainer.new()
	s2.add_child(g2)
	for d in [["level_hp", "兵力/级"], ["level_atk", "物攻/级"], ["level_def", "物防/级"],
			["level_matk", "谋攻/级"], ["level_mdef", "谋防/级"]]:
		var gsp := _form_spin(g2, d[1], 0, 50, func(val: int) -> void:
			RULEZ.settings["growth"][d[0]] = val
			_mark_dirty()
			_update_growth_preview(), 0.5)
		gsp.name = "grow_" + String(d[0])
	var s3 := _section("成长率与曲线（扩展项）",
		"成长率：≥1 表示该类属性成长更快（兵力按比例放大）；曲线 fast = 高等级额外加成，slow = 递减。")
	v.add_child(s3)
	var g3 := VBoxContainer.new()
	s3.add_child(g3)
	for d in [["hp", "兵力"], ["atk", "物攻"], ["def", "物防"], ["matk", "谋攻"], ["mdef", "谋防"]]:
		_form_spin(g3, d[1] + "成长率", 0.2, 3.0, func(val: float) -> void:
			if cur_key != "" and not busy:
				data.generals[cur_key]["ed_ext"]["growth_rates"][d[0]] = val
				_mark_dirty()
				_update_growth_preview(), 0.05, true).name = "rate_" + String(d[0])
	curve_opt = OptionButton.new()
	curve_opt.add_item("线形 linear", 0)
	curve_opt.add_item("前强后稳 fast", 1)
	curve_opt.add_item("平缓 slow", 2)
	curve_opt.item_selected.connect(func(i: int) -> void:
		if cur_key != "":
			data.generals[cur_key]["ed_ext"]["level_curve"] = ["linear", "fast", "slow"][i]
			_mark_dirty()
			_update_growth_preview())
	_form_row(g3, "成长曲线", curve_opt)
	var s4 := _section("快速调整")
	v.add_child(s4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	s4.add_child(row)
	var b1 := THEME.button("等级 +1", 13)
	b1.pressed.connect(func() -> void: _bump("level", 1))
	row.add_child(b1)
	var b2 := THEME.button("等级 +10", 13)
	b2.pressed.connect(func() -> void: _bump("level", 10))
	row.add_child(b2)
	var b3 := THEME.button("等级 -1", 13)
	b3.pressed.connect(func() -> void: _bump("level", -1))
	row.add_child(b3)
	var b4 := THEME.button("星级 +1", 13)
	b4.pressed.connect(func() -> void: _bump("star", 1))
	row.add_child(b4)
	var b5 := THEME.button("星级 -1", 13)
	b5.pressed.connect(func() -> void: _bump("star", -1))
	row.add_child(b5)
	var b6 := THEME.button("满级满星", 13)
	b6.pressed.connect(func() -> void:
		if cur_key == "":
			return
		data.generals[cur_key]["ed_level"] = RULEZ.max_level()
		data.generals[cur_key]["ed_star"] = RULEZ.max_star()
		_mark_dirty()
		load_general(cur_key))
	row.add_child(b6)
	return sc
func _refresh_star_ui() -> void:
	if star_plan_box == null or cur_key == "":
		return
	busy = true
	var g: Dictionary = data.generals[cur_key]
	star_dup_spin.value = int(g.get("ed_dup", 0))
	busy = false
	for c in star_plan_box.get_children():
		c.queue_free()
	var plan: Array = data.star_plan(cur_key)
	var star := int(g.get("ed_star", 1))
	star_plan_box.add_child(THEME.label("当前 %d 星 → 逐星设置（技能星可各自选一个技能）" % star, 13, THEME.ACCENT))
	for item in plan:
		var kind := String(item["kind"])
		var col := THEME.ORANGE if kind == "skill" else (THEME.GOOD if kind == "talent" else THEME.TEXT)
		var s_num := int(item["star"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		star_plan_box.add_child(row)
		var lb := THEME.label("  %2d★" % s_num, 12, col)
		lb.custom_minimum_size = Vector2(46, 0)
		row.add_child(lb)
		var head := THEME.label("%s：" % String(item["label"]), 12, col)
		head.custom_minimum_size = Vector2(70, 0)
		row.add_child(head)
		if kind == "skill":
			# 两个独立下拉：① 选技能 ② 升到几级（2 或 3）
			var opt := OptionButton.new()
			opt.custom_minimum_size = Vector2(200, 0)
			# 全部技能都可选（含被动技能）
			var ids: Array = []
			for s in (g.get("skills", []) as Array):
				ids.append(String(s))
			# 该星「开始时」的技能等级快照（逐星累积模拟）
			var before: Dictionary = item.get("skill_before", {}) if item.get("skill_before") is Dictionary else {}
			var cur_map: Dictionary = g.get("ed_star_skill", {}) if g.get("ed_star_skill") is Dictionary else {}
			var cur_lv_map: Dictionary = g.get("ed_star_lv", {}) if g.get("ed_star_lv") is Dictionary else {}
			var want := String(cur_map.get(str(s_num), ""))
			var want_idx := ids.find(want)
			var want_lv := int(cur_lv_map.get(str(s_num), 0))
			var s_key := str(s_num)
			if ids.is_empty():
				opt.add_item("（没有技能）")
				opt.disabled = true
			else:
				for sid in ids:
					opt.add_item("%s（本星前 Lv%d）" % [data.skill_name(String(sid)),
						int(before.get(sid, 1))])
				opt.selected = want_idx if want_idx >= 0 else 0
				opt.item_selected.connect(func(i2: int) -> void:
					if cur_key == "":
						return
					var gg: Dictionary = data.generals[cur_key]
					if not (gg.get("ed_star_skill") is Dictionary):
						gg["ed_star_skill"] = {}
					(gg["ed_star_skill"] as Dictionary)[s_key] = String(ids[i2])
					_mark_dirty()
					_refresh_star_ui())
			row.add_child(opt)
			# ② 升到几级（标签直接写清「本星前 LvN → 结果」避免歧义）
			var lv_opt := OptionButton.new()
			lv_opt.custom_minimum_size = Vector2(150, 0)
			# 当前选中技能在本星开始时的等级
			var sel_sid := String(ids[maxi(0, want_idx)]) if not ids.is_empty() else ""
			var sel_before := int(before.get(sel_sid, 1)) if sel_sid != "" else 1
			var eff2 := clampi(maxi(2, sel_before + 1), 2, 3)
			var eff3 := clampi(maxi(3, sel_before + 1), 2, 3)
			lv_opt.add_item("Lv%d → Lv%d" % [sel_before, eff2])
			lv_opt.add_item("Lv%d → Lv%d" % [sel_before, eff3])
			lv_opt.set_item_metadata(0, 2)
			lv_opt.set_item_metadata(1, 3)
			lv_opt.selected = 1 if want_lv == 3 else 0
			lv_opt.tooltip_text = "这一星升到几级；本星前已 Lv2 时选 Lv2 也会至少升到 Lv3，不会白费"
			lv_opt.item_selected.connect(func(i3: int) -> void:
				if cur_key == "":
					return
				var gg: Dictionary = data.generals[cur_key]
				if not (gg.get("ed_star_lv") is Dictionary):
					gg["ed_star_lv"] = {}
				(gg["ed_star_lv"] as Dictionary)[s_key] = int(lv_opt.get_item_metadata(i3))
				_mark_dirty()
				_refresh_star_ui())
			row.add_child(lv_opt)
			# 显示本星实际推进
			var proj := String(item.get("projection", ""))
			if proj != "":
				row.add_child(THEME.label("→ " + proj, 12, THEME.GOOD))
		else:
			var desc := THEME.label(String(item["desc"]), 12, col)
			desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(desc)
			var tproj := String(item.get("projection", ""))
			if kind == "talent" and tproj != "":
				row.add_child(THEME.label("→ " + tproj, 12, THEME.GOOD))
		row.add_child(THEME.label("（消耗同名 ×%d）" % int(item["cost"]), 11, THEME.MUTED))


# 取某一技能星要升的技能（优先逐星设置）
func _star_pick_for(star_num: int) -> String:
	if cur_key == "":
		return ""
	var g: Dictionary = data.generals[cur_key]
	var m: Dictionary = g.get("ed_star_skill", {}) if g.get("ed_star_skill") is Dictionary else {}
	var v := String(m.get(str(star_num), ""))
	if v != "" and (g.get("skills", []) as Array).has(v):
		# 若该星指定的技能已满级，自动改挑一个未满级的（避免卡住）
		if int((g.get("ed_skill_lv", {}) as Dictionary).get(v, 1)) < 3:
			return v
	# 没设置 / 指定已满级时自动挑一个未满级的技能（含被动）
	for s in (g.get("skills", []) as Array):
		var sid := String(s)
		if int((g.get("ed_skill_lv", {}) as Dictionary).get(sid, 1)) < 3:
			return sid
	return ""
func _do_star_now() -> void:
	if cur_key == "":
		return
	var g: Dictionary = data.generals[cur_key]
	var next := int(g.get("ed_star", 1)) + 1
	var cost := RULEZ.star_cost(next)
	var dup := int(g.get("ed_dup", 0))
	if dup < cost:
		status("同名武将不足：升到 %d★ 需要 %d 张，当前 %d 张（可用「抽卡」获得）" % [next, cost, dup])
		star_status.text = "✖ 同名武将不足（需要 %d 张）" % cost
		return
	# 按目标星级的设置取要升的技能 + 要升到几级
	var skill_id := _star_pick_for(next)
	var lv_map: Dictionary = g.get("ed_star_lv", {}) if g.get("ed_star_lv") is Dictionary else {}
	var t_lv := int(lv_map.get(str(next), 0))
	if RULEZ.star_upgrade_kind(next) == "skill" and skill_id == "":
		status("没有可升阶的主动技能，请先给该武将加主动技能，或先升其他星级")
		star_status.text = "✖ 没有可升阶的主动技能"
		return
	var r := data.do_star_upgrade(cur_key, skill_id, t_lv)
	if not bool(r.get("ok", false)):
		status(String(r.get("msg", "升星失败")))
		star_status.text = "✖ " + String(r.get("msg", ""))
		return
	g["ed_dup"] = dup - cost
	_mark_dirty()
	load_general(cur_key)
	_refresh_star_ui()
	status("★ 升到 %d 星：%s（消耗同名 ×%d）" % [int(r.get("star", next)), String(r.get("msg", "")), cost])
	star_status.text = "✔ " + String(r.get("msg", ""))
func _auto_star_demo() -> void:
	if cur_key == "":
		return
	var g: Dictionary = data.generals[cur_key]
	g["ed_dup"] = maxi(int(g.get("ed_dup", 0)), 60)
	var guard := 0
	while int(g.get("ed_star", 1)) < RULEZ.max_star() and guard < 20:
		guard += 1
		# 演示时：升技能星自动挑一个还没满级的技能（含被动）
		var pick := ""
		for s in (g.get("skills", []) as Array):
			if int((g.get("ed_skill_lv", {}) as Dictionary).get(s, 1)) < 3:
				pick = String(s)
				break
		var r := data.do_star_upgrade(cur_key, pick)
		if not bool(r.get("ok", false)):
			break
		g["ed_dup"] = maxi(0, int(g.get("ed_dup", 0)) - RULEZ.star_cost(int(g.get("ed_star", 1))))
	_mark_dirty()
	load_general(cur_key)
	_refresh_star_ui()
	status("演示：已升到 %d 星" % int(g.get("ed_star", 1)))
func _bump(attr: String, d: int) -> void:
	if cur_key == "":
		return
	var g: Dictionary = data.generals[cur_key]
	var p0 := RULEZ.combat_power(data.unit_template(cur_key))
	if attr == "level":
		g["ed_level"] = clampi(int(g.get("ed_level", 1)) + d, 1, RULEZ.max_level())
	else:
		g["ed_star"] = clampi(int(g.get("ed_star", 1)) + d, 1, RULEZ.max_star())
	_mark_dirty()
	load_general(cur_key)
	var p1 := RULEZ.combat_power(data.unit_template(cur_key))
	status("⚔ 战力 %d → %d（%+d）" % [p0, p1, p1 - p0])
func _update_growth_preview() -> void:
	if cur_key == "":
		return
	for c in growth_preview.get_children():
		c.queue_free()
	var g: Dictionary = data.generals[cur_key]
	var lv := clampi(int(g.get("ed_level", 1)), 1, RULEZ.max_level())
	var star := clampi(int(g.get("ed_star", 1)), 1, RULEZ.max_star())
	var t := data.unit_template(cur_key)
	var st: Dictionary = t.get("stats", {})
	var per := RULEZ.per_level_gain(lv)
	var row1 := THEME.label("当前 Lv%d %d★ → %s" % [lv, star, _stats_str(st)], 13, THEME.TEXT)
	growth_preview.add_child(row1)
	var parts: Array = []
	for k in ["max_hp", "atk", "def", "matk", "mdef"]:
		parts.append("%s +%d" % [RULEZ.STAT_LABELS.get(k, k), int(per.get(k, 0))])
	var row2 := THEME.label("再升 1 级： " + "  ".join(parts), 13, THEME.GOOD)
	growth_preview.add_child(row2)
	var nxt: Dictionary = data.levelup_diff(cur_key, "level", lv, 1)
	var next_t: Dictionary = nxt.get("after", {})
	growth_preview.add_child(THEME.label("→ Lv%d %d★： %s" % [mini(lv + 1, RULEZ.max_level()), star,
		_stats_str(_stats_of(next_t))], 13, THEME.ACCENT))
	if star < RULEZ.max_star():
		var ns: Dictionary = (data.levelup_diff(cur_key, "star", star, 1).get("after", {}) as Dictionary)
		growth_preview.add_child(THEME.label("→ 星级 %d★： %s" % [star + 1,
			_stats_str(_stats_of(ns))], 13, THEME.ORANGE))
func _stats_str(st: Dictionary) -> String:
	return "兵力 %d 物攻 %d 物防 %d 谋攻 %d 谋防 %d 幸运 %d 移动 %d 射程 %d" % [
		int(st.get("max_hp", st.get("hp", 0))), int(st.get("atk", 0)), int(st.get("def", 0)),
		int(st.get("matk", 0)), int(st.get("mdef", 0)), int(st.get("luck", 0)),
		int(st.get("move", 0)), int(st.get("range", 0))]
# ------------------------------------------------------------
# ⑤ 兵种
# ------------------------------------------------------------
func _page_arm() -> Control:
	var r := _scroll_page()
	var sc: ScrollContainer = r[0]
	var v: VBoxContainer = r[1]
	sc.name = "兵种"
	var s := _section("兵种（盾 / 枪 / 弓 / 骑）",
		"兵种会给面板属性乘系数（如盾兵：兵力 ×1.15、物防 ×1.25、物攻 ×0.95），并参与克制：枪克骑、骑克弓、弓克盾、盾克枪。")
	v.add_child(s)
	var g := VBoxContainer.new()
	s.add_child(g)
	arm_opt = OptionButton.new()
	for a in ["盾", "枪", "弓", "骑"]:
		arm_opt.add_item("%s（%s）" % [a, RULEZ.arm_name(a)])
	arm_opt.item_selected.connect(func(i: int) -> void:
		if cur_key == "":
			return
		# 换兵种：移动力/射程按新兵种重算，普攻范围换成新兵种的形状
		data.apply_arm_to_general(cur_key, ["盾", "枪", "弓", "骑"][i])
		_mark_dirty()
		_update_stat_preview()
		_update_growth_preview()
		_refresh_arm_info()
		_refresh_range_page()
		refresh_list()
		status("已换为%s：移动力/射程/普攻范围已同步" % RULEZ.arm_name(["盾", "枪", "弓", "骑"][i])))
	_form_row(g, "主兵种", arm_opt)
	arm2_opt = OptionButton.new()
	arm2_opt.add_item("无")
	for a in ["盾", "枪", "弓", "骑"]:
		arm2_opt.add_item(a)
	arm2_opt.item_selected.connect(func(i: int) -> void:
		if cur_key == "":
			return
		data.generals[cur_key]["ed_ext"]["arm2"] = "" if i == 0 else ["盾", "枪", "弓", "骑"][i - 1]
		_mark_dirty())
	_form_row(g, "第二兵种（扩展，占位）", arm2_opt)
	f_troop = LineEdit.new()
	f_troop.text_changed.connect(func(t: String) -> void:
		if cur_key != "":
			data.generals[cur_key]["troop"] = t
			_mark_dirty()
			refresh_list())
	_form_row(g, "兵种名（显示）", f_troop)
	arm_info = RichTextLabel.new()
	arm_info.custom_minimum_size = Vector2(0, 120)
	arm_info.fit_content = true
	arm_info.bbcode_enabled = true
	s.add_child(arm_info)
	v.add_child(THEME.hint("换兵种后：该武将自动「继承」新兵种的移动力与攻击范围；只有技能/天赋里写明了对移动或范围的影响，才会在这个值上继续叠加。"))
	# ---------- 四个兵种的基础数值 + 攻击范围形状（可像技能方位一样编辑） ----------
	var s_move := _section("兵种基础：移动力 / 攻击范围 / 攻击范围形状",
		"这里是兵种本身的基础值，所有该兵种的武将都继承。攻击范围形状与技能一样可逐格编辑（青=可打到的格，中心=武将自身）。")
	v.add_child(s_move)
	var tbl := VBoxContainer.new()
	tbl.add_theme_constant_override("separation", 4)
	s_move.add_child(tbl)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	tbl.add_child(head_row)
	for spec in [["兵种", 96], ["移动力", 118], ["攻击范围(射程)", 128], ["范围形状", 210], ["面板系数", 0]]:
		var lb := THEME.label(String(spec[0]), 13, THEME.MUTED)
		lb.custom_minimum_size = Vector2(float(spec[1]), 0)
		head_row.add_child(lb)
	for arm in ["盾", "枪", "弓", "骑"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		tbl.add_child(row)
		var lb2 := THEME.label("%s（%s）" % [arm, RULEZ.arm_name(arm)], 13, THEME.TEXT)
		lb2.custom_minimum_size = Vector2(96, 0)
		row.add_child(lb2)
		var arm_key := String(arm)
		var mv := SpinBox.new()
		mv.min_value = 0
		mv.max_value = 15
		mv.custom_minimum_size = Vector2(110, 0)
		mv.tooltip_text = "该兵种的移动力（武将继承）"
		mv.value = float(int(RULEZ.arm_base_move(arm_key)))
		mv.value_changed.connect(func(val: float) -> void:
			if busy:
				return
			var m: Dictionary = RULEZ.settings.get("arm_base_move", {})
			m[arm_key] = int(val)
			RULEZ.settings["arm_base_move"] = m
			_mark_dirty()
			_refresh_arm_info()
			_update_stat_preview()
			_update_growth_preview())
		row.add_child(mv)
		var rg := SpinBox.new()
		rg.min_value = 0
		rg.max_value = 9
		rg.custom_minimum_size = Vector2(120, 0)
		rg.tooltip_text = "该兵种的攻击范围（射程），用于「菱形」形状"
		rg.value = float(int(RULEZ.arm_base_range(arm_key)))
		rg.value_changed.connect(func(val: float) -> void:
			if busy:
				return
			var m2: Dictionary = RULEZ.settings.get("arm_base_range", {})
			m2[arm_key] = int(val)
			RULEZ.settings["arm_base_range"] = m2
			_mark_dirty()
			_refresh_arm_info()
			_update_stat_preview()
			_update_growth_preview())
		row.add_child(rg)
		base_move_spins[arm_key] = mv
		base_range_spins[arm_key] = rg
		var shape_btn := THEME.button("编辑形状…", 12, 110)
		shape_btn.pressed.connect(func() -> void: _open_arm_range_editor(arm))
		row.add_child(shape_btn)
		var shape_lbl := THEME.label("", 12, THEME.MUTED)
		row.add_child(shape_lbl)
		var note_lbl := THEME.label("", 12, THEME.MUTED)
		row.add_child(note_lbl)
		set_widgets["arm_%s_base_move" % arm] = mv
		set_widgets["arm_%s_base_range" % arm] = rg
		set_widgets["arm_%s_note" % arm] = note_lbl
		set_widgets["arm_%s_shape" % arm] = shape_lbl
	# ---------- 兵种升级（预留模块：不加兵力等属性，具体功效后续设置） ----------
	var s_up := _section("兵种升级（预留模块 · 暂不加属性）",
		"兵种升级目前只记「兵种等级」与「升级点数」（点数上限与五维之和挂钩），**不加兵力/攻防等面板数值**；" +
		"具体功效（例如解锁兵种特性、被动效果）留到之后再设置。")
	v.add_child(s_up)
	var up_box := VBoxContainer.new()
	up_box.add_theme_constant_override("separation", 4)
	s_up.add_child(up_box)
	var up_top := HBoxContainer.new()
	up_top.add_theme_constant_override("separation", 8)
	up_box.add_child(up_top)
	up_top.add_child(THEME.label("兵种等级", 13, THEME.MUTED))
	var lv_sp := SpinBox.new()
	lv_sp.min_value = 0
	lv_sp.max_value = 20
	lv_sp.custom_minimum_size = Vector2(96, 0)
	lv_sp.value_changed.connect(func(val: float) -> void:
		if cur_key == "" or busy:
			return
		data.set_arm_level(cur_key, int(val))
		_mark_dirty()
		_refresh_arm_upgrade()
		_update_stat_preview()
		_update_growth_preview())
	up_top.add_child(lv_sp)
	arm_up_lv_spin = lv_sp
	var b_lv1 := THEME.button("升级 +1", 12)
	b_lv1.pressed.connect(func() -> void:
		if cur_key == "":
			return
		data.set_arm_level(cur_key, int(lv_sp.value) + 1)
		_mark_dirty()
		load_general(cur_key))
	up_top.add_child(b_lv1)
	var b_max := THEME.button("升满", 12)
	b_max.pressed.connect(func() -> void:
		if cur_key == "":
			return
		data.set_arm_level(cur_key, int(arm_up_lv_spin.max_value))
		_mark_dirty()
		load_general(cur_key))
	up_top.add_child(b_max)
	arm_up_summary = THEME.label("", 13, THEME.WARN)
	up_top.add_child(arm_up_summary)
	var up_grid := VBoxContainer.new()
	up_box.add_theme_constant_override("separation", 2)
	up_box.add_child(up_grid)
	arm_up_grid = up_grid
	arm_up_note = THEME.label("", 12, THEME.MUTED)
	arm_up_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	up_box.add_child(arm_up_note)
	# 加点行（默认全部为 0：兵种升级不加属性，等功效定好再在全局设定里放开）
	for spec in [["hp", "兵力"], ["atk", "物攻"], ["def", "物防"], ["matk", "谋攻"], ["mdef", "谋防"], ["luck", "幸运"]]:
		var stk := String(spec[0])
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		up_grid.add_child(row2)
		var l2 := THEME.label(String(spec[1]), 13, THEME.MUTED)
		l2.custom_minimum_size = Vector2(60, 0)
		row2.add_child(l2)
		var minus := THEME.button("−", 12, 30)
		minus.disabled = true
		minus.pressed.connect(func() -> void:
			if cur_key == "":
				return
			data.add_arm_point(cur_key, stk, -1)
			_mark_dirty()
			_refresh_arm_upgrade()
			_update_stat_preview())
		row2.add_child(minus)
		var val_lbl := THEME.label("0", 13, THEME.MUTED)
		val_lbl.custom_minimum_size = Vector2(44, 0)
		row2.add_child(val_lbl)
		var plus := THEME.button("＋", 12, 30)
		plus.disabled = true
		plus.pressed.connect(func() -> void:
			if cur_key == "":
				return
			var res := data.add_arm_point(cur_key, stk, 1)
			if not bool(res.get("ok", false)):
				status(String(res.get("msg", "")))
				return
			_mark_dirty()
			_refresh_arm_upgrade()
			_update_stat_preview())
		row2.add_child(plus)
		var gain_lbl := THEME.label("", 12, THEME.MUTED)
		row2.add_child(gain_lbl)
		arm_up_widgets[stk] = {"val": val_lbl, "gain": gain_lbl, "plus": plus, "minus": minus}
	v.add_child(THEME.hint("说明：武将的成长改为「升级升五维」（见「③ 五维」与「④ 等级/星级」）；兵种升级只作为预留层级。"))
	var s2 := _section("克制关系表（在「⑪ 全局设定」可改倍率）")
	v.add_child(s2)
	counter_table = RichTextLabel.new()
	counter_table.custom_minimum_size = Vector2(0, 160)
	counter_table.fit_content = true
	counter_table.bbcode_enabled = true
	s2.add_child(counter_table)
	return sc
# 兵种攻击范围形状编辑器（与技能范围一样逐格改）
func _open_arm_range_editor(arm: String) -> void:
	var win := Window.new()
	win.title = "%s 攻击范围形状" % RULEZ.arm_name(arm)
	win.size = Vector2i(560, 620)
	add_child(win)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 12
	v.offset_right = -12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 6)
	win.add_child(v)
	v.add_child(THEME.hint("中心 = 武将自身；涂上的格子就是该兵种普攻能打到的位置（不用形状时按「射程」自动生成菱形）。"))
	var grid := RangeGrid.new()
	grid.grid_n = 11
	grid.cell_size = 30
	grid.multi = true
	grid.center_mark = "unit"
	grid.accent = Color("#22d3ee")
	var shapes: Dictionary = data.get_arm_shape(arm)
	if (shapes.get("area", []) as Array).is_empty():
		grid.set_area(RULEZ.diamond(RULEZ.arm_base_range(arm)))
	else:
		grid.set_area(RULEZ.parse_area(shapes["area"]))
	v.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var b_dia := THEME.button("按射程生成菱形", 12)
	b_dia.pressed.connect(func() -> void: grid.set_diamond(RULEZ.arm_base_range(arm)))
	row.add_child(b_dia)
	var b_line := THEME.button("直线 1~3", 12)
	b_line.pressed.connect(func() -> void: grid.set_cross(3))
	row.add_child(b_line)
	var b_clear := THEME.button("清除（用默认）", 12)
	b_clear.pressed.connect(func() -> void: grid.clear_all())
	row.add_child(b_clear)
	var b_save := THEME.button("保存并同步到武将", 13)
	b_save.tooltip_text = "保存该兵种的普攻范围，并同步到所有该兵种的武将"
	b_save.pressed.connect(func() -> void:
		data.set_arm_shape(arm, grid.get_area_raw())
		var n := data.sync_arm_shape_to_generals(arm)
		_mark_dirty()
		_refresh_arm_info()
		_refresh_range_page()
		status("已保存 %s 攻击范围形状（%d 格），并同步到 %d 名武将" % [
			RULEZ.arm_name(arm), grid.get_area().size(), n])
		win.queue_free())
	row.add_child(b_save)
	var b_close := THEME.button("取消", 12)
	b_close.pressed.connect(func() -> void: win.queue_free())
	row.add_child(b_close)
	win.popup_centered()
func _refresh_arm_upgrade() -> void:
	if cur_key == "" or arm_up_lv_spin == null:
		return
	busy = true
	var info: Dictionary = data.arm_upgrade_info(cur_key)
	arm_up_lv_spin.max_value = int(info.get("max_lv", 20))
	arm_up_lv_spin.value = int(info.get("level", 0))
	busy = false
	arm_up_summary.text = "兵种等级 %d / %d　升级点数：%d（五维和 %d × %.1f）" % [
		int(info.get("level", 0)), int(info.get("max_lv", 20)),
		int(info.get("points_total", 0)), int(info.get("five_sum", 0)),
		float((info.get("up", {}) as Dictionary).get("five_pool", 0.5))]
	var spend: Dictionary = info.get("spend", {})
	var up: Dictionary = info.get("up", {})
	var gain: Dictionary = info.get("gain", {})
	var any_add := false
	for stk in arm_up_widgets.keys():
		var w: Dictionary = arm_up_widgets[stk]
		var per := int(up.get("point_%s" % stk, 0))
		(w["val"] as Label).text = str(int(spend.get(stk, 0)))
		(w["gain"] as Label).text = "→ +%d" % int(gain.get(stk if stk != "hp" else "max_hp", 0))
		(w["plus"] as Button).disabled = (per <= 0)
		(w["minus"] as Button).disabled = (int(spend.get(stk, 0)) <= 0)
		if per > 0:
			any_add = true
	# 兵种升级目前不加属性：显示说明
	if arm_up_note != null:
		arm_up_note.text = ("当前兵种升级不加任何面板属性与移动/射程（功效待定）。") if not any_add \
			else "已在「⑪ 全局设定」开启部分加点。"
	if arm_up_grid != null:
		arm_up_grid.visible = any_add
func _refresh_arm_info() -> void:
	# 同步四兵种基础值 / 形状说明
	# 兵种基础移动 / 攻击范围：构建完成后统一回填一次（避免控件初始化时把设置写回 0）
	for arm3 in base_move_spins.keys():
		var spm: SpinBox = base_move_spins[arm3]
		spm.set_value_no_signal(float(RULEZ.arm_base_move(String(arm3))))
		var spr: SpinBox = base_range_spins[arm3]
		spr.set_value_no_signal(float(RULEZ.arm_base_range(String(arm3))))
	for arm2 in ["盾", "枪", "弓", "骑"]:
		var mk := "arm_%s_base_move" % arm2
		var rk := "arm_%s_base_range" % arm2
		if set_widgets.has(mk) and set_widgets[mk] is SpinBox:
			(set_widgets[mk] as SpinBox).set_value_no_signal(float(RULEZ.arm_base_move(arm2)))
		if set_widgets.has(rk) and set_widgets[rk] is SpinBox:
			(set_widgets[rk] as SpinBox).set_value_no_signal(float(RULEZ.arm_base_range(arm2)))
		var sk := "arm_%s_shape" % arm2
		if set_widgets.has(sk) and set_widgets[sk] is Label:
			var arr: Array = data.get_arm_shape(arm2).get("area", [])
			(set_widgets[sk] as Label).text = ("自定义 %d 格" % arr.size()) if not arr.is_empty() else "默认菱形"
		var nk := "arm_%s_note" % arm2
		if set_widgets.has(nk) and set_widgets[nk] is Label:
			var am2: Dictionary = RULEZ.arm_mods(arm2)
			(set_widgets[nk] as Label).text = "兵力×%.2f 物攻×%.2f 物防×%.2f 谋防×%.2f" % [
				float(am2.get("hp", 1.0)), float(am2.get("atk", 1.0)),
				float(am2.get("def", 1.0)), float(am2.get("mdef", 1.0))]
	if cur_key == "":
		return
	_refresh_arm_upgrade()
	var arm := String(data.generals[cur_key].get("arm", "盾"))
	var am: Dictionary = RULEZ.arm_mods(arm)
	var t := data.unit_template(cur_key)
	var st: Dictionary = t.get("stats", {}) if t.get("stats") is Dictionary else {}
	var ext: Dictionary = data.generals[cur_key].get("ed_ext", {})
	var info: Dictionary = data.arm_upgrade_info(cur_key)
	var base_move := RULEZ.arm_base_move(arm)
	var base_range := RULEZ.arm_base_range(arm)
	var up_move := int((info.get("gain", {}) as Dictionary).get("move", 0))
	var up_range := int((info.get("gain", {}) as Dictionary).get("range", 0))
	var ext_move := int(ext.get("move_bonus", 0))
	var ext_range := int(ext.get("reach_bonus", 0))
	arm_info.text = "[color=#38bdf8]%s 面板修正[/color]　兵力 ×%.2f　物攻 ×%.2f　物防 ×%.2f　谋防 ×%.2f\n" % [
		RULEZ.arm_name(arm), float(am.get("hp", 1.0)), float(am.get("atk", 1.0)),
		float(am.get("def", 1.0)), float(am.get("mdef", 1.0))]
	arm_info.text += "本将最终：移动 [b]%d[/b] = 兵种 %d %+d(兵种升级) %+d(技能天赋)\n射程 [b]%d[/b] = 兵种 %d %+d(兵种升级) %+d(技能天赋)" % [
		int(st.get("move", 0)), base_move, up_move, ext_move,
		int(st.get("range", 0)), base_range, up_range, ext_range]
# ============================================================
# 编辑器：⑥ 技能 / ⑦ 天赋 / ⑧ 技能范围 / ⑨ 图片 / ⑩ 扩展 / ⑪ 全局设定
# （与 editor.gd 同属一个类；editor.gd 只承载基础页，这里承载其余页签与通用逻辑）
# ============================================================
# ------------------------------------------------------------
# ⑥ 技能
# ------------------------------------------------------------
func _page_skills() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "技能"
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	var s := _section("武将技能列表",
		"每个技能可单独设等级（Lv1~3）与冷却；点「范围…」可逐格编辑该技能的释放距离与作用范围（沿用旧程序的范围编辑器）。")
	v.add_child(s)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	s.add_child(tools)
	var add_btn := THEME.button("＋ 从技能库添加", 13)
	add_btn.pressed.connect(_open_skill_picker)
	tools.add_child(add_btn)
	var new_btn := THEME.button("＋ 新建技能", 13)
	new_btn.pressed.connect(_on_new_skill)
	tools.add_child(new_btn)
	var up_btn := THEME.button("全部 Lv3", 13)
	up_btn.pressed.connect(func() -> void:
		if cur_key == "":
			return
		for sid in data.generals[cur_key]["skills"]:
			data.generals[cur_key]["ed_skill_lv"][String(sid)] = 3
		_mark_dirty()
		load_general(cur_key))
	tools.add_child(up_btn)
	var down_btn := THEME.button("全部 Lv1", 13)
	down_btn.pressed.connect(func() -> void:
		if cur_key == "":
			return
		for sid in data.generals[cur_key]["skills"]:
			data.generals[cur_key]["ed_skill_lv"][String(sid)] = 1
		_mark_dirty()
		load_general(cur_key))
	tools.add_child(down_btn)
	var merge_btn := THEME.button("⛓ 技能合并 / 组合…", 13)
	merge_btn.tooltip_text = "把任意多个技能融合成一个（效果合并），或做成多选一的组合技策"
	merge_btn.pressed.connect(_open_skill_workshop)
	tools.add_child(merge_btn)
	skill_list = VBoxContainer.new()
	skill_list.add_theme_constant_override("separation", 4)
	v.add_child(skill_list)
	skill_edit_box = VBoxContainer.new()
	skill_edit_box.add_theme_constant_override("separation", 4)
	v.add_child(skill_edit_box)
	return sc
func _skill_kind_name(k: String) -> String:
	if k == EdData.GROUP_KIND:
		return "组合·多选一"
	return String(RULEZ.SKILL_KIND_NAMES.get(k, k))
# ============================================================
# 技能工坊：任意多个技能的「融合」或「多选一组合」
#   融合：选中的 N 个技能 → 合并进其中一个（目标），其余从武将移除并可从库删除
#   组合：选中的 N 个技能 → 生成一个组合技策（子技能保留在库），点它时多选一施放
# ============================================================
var _ws_win: Window
var _ws_checks: Dictionary = {}
func _open_skill_workshop() -> void:
	if cur_key == "":
		status("请先选中一名武将")
		return
	if is_instance_valid(_ws_win):
		_ws_win.queue_free()
	_ws_checks.clear()
	var win := Window.new()
	win.title = "技能合并 / 组合 —— %s" % data.name_of(cur_key)
	win.size = Vector2i(760, 680)
	add_child(win)
	_ws_win = win
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 12
	v.offset_right = -12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 8)
	win.add_child(v)
	v.add_child(THEME.hint(
		"① 从【全部技能库】里勾选要处理的技能（可搜索，包含其他武将的技能；可以 2 个、3 个或更多）；" +
		"② 选择「融合」——把效果并入目标技能；或「组合」——变成点它时多选一的技策。"))
	# 模式
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	v.add_child(mode_row)
	var mode_opt := OptionButton.new()
	mode_opt.add_item("融合成一个技能（效果合并，其余移除）", 0)
	mode_opt.add_item("做成多选一的组合技策", 1)
	mode_row.add_child(mode_opt)
	mode_row.add_child(THEME.label("目标技能（仅融合用）", 12, THEME.MUTED))
	var target_opt := OptionButton.new()
	target_opt.custom_minimum_size = Vector2(220, 0)
	mode_row.add_child(target_opt)
	# 搜索框（技能库全部技能）
	var ws_search := LineEdit.new()
	ws_search.placeholder_text = "搜索技能名 / id / 拥有武将"
	v.add_child(ws_search)
	# 技能列表
	var list_sc := ScrollContainer.new()
	list_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(list_sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	list_sc.add_child(list)
	var g: Dictionary = data.generals[cur_key]
	# 技能库全部 id（排序）
	var all_ids: Array = []
	for k in data.skills.keys():
		all_ids.append(String(k))
	all_ids.sort()
	# 每个技能被哪些武将拥有
	var owners: Dictionary = {}
	for gk in data.order:
		var gg: Dictionary = data.generals[gk]
		for sk in (gg.get("skills", []) as Array):
			var ss := String(sk)
			if not owners.has(ss):
				owners[ss] = []
			(owners[ss] as Array).append(String(gg.get("name", gk)))
	var rebuild_targets := func() -> void:
		target_opt.clear()
		for k in _ws_checks.keys():
			var cb = _ws_checks[k]
			if cb is CheckBox and (cb as CheckBox).button_pressed:
				target_opt.add_item(data.skill_name(String(k)))
				target_opt.set_item_metadata(target_opt.item_count - 1, String(k))
		if target_opt.item_count == 0:
			target_opt.add_item("（先勾选技能）")
	var rebuild_list := func(q: String) -> void:
		for c in list.get_children():
			c.queue_free()
		_ws_checks.clear()
		for sid in all_ids:
			var d: Dictionary = data.get_skill(sid)
			var nm := data.skill_name(sid)
			var own: Array = owners.get(sid, [])
			var own_txt := ""
			if own.size() > 0:
				own_txt = "　拥有：" + "、".join(own.slice(0, 4))
				if own.size() > 4:
					own_txt += "…"
			else:
				own_txt = "　（库中未使用）"
			var hay: String = (nm + " " + sid + " " + "、".join(own)).to_lower()
			if q != "" and not hay.contains(q.to_lower()):
				continue
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 6)
			list.add_child(h)
			var cb := CheckBox.new()
			cb.text = ""
			cb.toggled.connect(func(_on: bool) -> void: rebuild_targets.call())
			h.add_child(cb)
			_ws_checks[sid] = cb
			var mine := (g.get("skills", []) as Array).has(sid)
			var grp_note := ""
			if data.is_group(sid):
				grp_note = "〔组合：%d 项〕" % data.group_children(sid).size()
			var tag := "【本武将】" if mine else ""
			var lb := THEME.label("%s%s　[%s] %s%s" % [tag, nm,
				_skill_kind_name(String(d.get("kind", ""))), grp_note, own_txt], 12,
				THEME.GOOD if mine else (THEME.MUTED if own.is_empty() else THEME.TEXT))
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(lb)
			if data.is_group(sid):
				var kids: Array = []
				for c in data.group_children(sid):
					kids.append(data.skill_name(String(c)))
				h.add_child(THEME.label(" → " + " / ".join(kids), 11, THEME.ACCENT))
	ws_search.text_changed.connect(rebuild_list)
	# 组合技策名称
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	v.add_child(name_row)
	name_row.add_child(THEME.label("组合技策名称", 12, THEME.MUTED))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "例如：唇枪舌剑（留空则自动用「组合技策」）"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	# 底部操作
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	v.add_child(btns)
	var del_src := CheckBox.new()
	del_src.text = "融合后从技能库彻底删除被合并的源技能"
	del_src.button_pressed = true
	btns.add_child(del_src)
	var go := THEME.button("执行", 14, 110)
	go.pressed.connect(func() -> void:
		var picked: Array = []
		for k in _ws_checks.keys():
			var c = _ws_checks[k]
			if c is CheckBox and (c as CheckBox).button_pressed:
				picked.append(String(k))
		if picked.size() < 2:
			status("请至少勾选 2 个技能")
			return
		var res: Dictionary
		if mode_opt.selected == 0:
			# 融合：target 是「保留」的那个，其余按勾选决定是否删除
			var ti := target_opt.selected
			if ti < 0 or target_opt.get_item_metadata(ti) == null:
				status("请选择要保留的技能")
				return
			var target := String(target_opt.get_item_metadata(ti))
			data.push_undo("融合技能 → 保留「%s」" % data.skill_name(target))
			var ok_n := 0
			var msgs: Array = []
			for sid2 in picked:
				if String(sid2) == target:
					continue
				var rr := data.merge_skills(String(sid2), target)
				if bool(rr.get("ok", false)):
					ok_n += 1
					# merge_skills 已把源从所有武将移除并删库；这里按勾选决定是否彻底删
					if not del_src.button_pressed and data.skills.has(String(sid2)):
						pass
				else:
					msgs.append(String(rr.get("msg", "")))
			res = {"ok": ok_n > 0, "msg": "已保留「%s」并融合 %d 个技能%s" % [
				data.skill_name(target), ok_n, ("" if msgs.is_empty() else "；" + "；".join(msgs))]}
			# 保留的技能若不在本武将身上，加进来
			if not (data.generals[cur_key]["skills"] as Array).has(target):
				(data.generals[cur_key]["skills"] as Array).append(target)
				data.generals[cur_key]["ed_skill_lv"][target] = 1
			# 被合并的从本武将移除
			for sid3 in picked:
				if String(sid3) != target:
					data.remove_skill_from_general(cur_key, String(sid3))
		else:
			# 组合：用勾选的技能组成一个组合技策，可命名
			var kids: Array = picked.duplicate()
			var nm := name_edit.text.strip_edges()
			data.push_undo("组合技策（%d 个技能）" % kids.size())
			res = data.make_skill_group("", kids, nm)
			if bool(res.get("ok", false)):
				var gid := String(res.get("id", ""))
				if gid != "" and not (data.generals[cur_key]["skills"] as Array).has(gid):
					data.generals[cur_key]["skills"].append(gid)
					data.generals[cur_key]["ed_skill_lv"][gid] = 1
				for c in kids:
					data.remove_skill_from_general(cur_key, String(c))
		_mark_dirty()
		load_general(cur_key)
		refresh_skill_list()
		status(String(res.get("msg", "")) + "（可点「撤销」回退）")
		win.queue_free())
	btns.add_child(go)
	var undo_btn := THEME.button("↶ 撤销上一步", 13)
	undo_btn.disabled = not data.can_undo()
	undo_btn.tooltip_text = "撤销上一次融合/组合：" + data.undo_label() if data.can_undo() else "没有可撤销的操作"
	undo_btn.pressed.connect(func() -> void:
		var r := data.undo()
		_mark_dirty()
		load_general(cur_key)
		refresh_skill_list()
		status(String(r.get("msg", ""))))
	btns.add_child(undo_btn)
	var close := THEME.button("取消", 13)
	close.pressed.connect(func() -> void: win.queue_free())
	btns.add_child(close)
	rebuild_list.call("")
	rebuild_targets.call()
	win.popup_centered()
# 打开某个技能的组合编辑（增删子技能）
func _open_group_editor(sid: String) -> void:
	if is_instance_valid(_ws_win):
		_ws_win.queue_free()
	var win := Window.new()
	win.title = "编辑组合技策：%s" % data.skill_name(sid)
	win.size = Vector2i(700, 620)
	add_child(win)
	_ws_win = win
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 12
	v.offset_right = -12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 8)
	win.add_child(v)
	v.add_child(THEME.hint("勾选要为该组合添加的子技能；已加入的取消勾选即移除。子技能数量不限。" +
		"每个子技能都保留自己的效果与范围，可点「单独编辑」修改。"))
	# 组合技策改名
	var nm_row := HBoxContainer.new()
	nm_row.add_theme_constant_override("separation", 8)
	v.add_child(nm_row)
	nm_row.add_child(THEME.label("组合名称", 12, THEME.MUTED))
	var nm_edit := LineEdit.new()
	nm_edit.text = data.skill_name(sid)
	nm_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm_edit.text_changed.connect(func(t: String) -> void:
		var gd: Dictionary = data.get_skill(sid)
		if gd.is_empty():
			return
		gd["name"] = t
		data.skills[sid] = gd
		data.dirty = true
		_mark_dirty())
	nm_row.add_child(nm_edit)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var cur_children: Array = data.group_children(sid)
	var checks: Dictionary = {}
	var keys: Array = data.skills.keys()
	keys.sort()
	var kw := LineEdit.new()
	kw.placeholder_text = "搜索技能名"
	list.add_child(kw)
	var items := VBoxContainer.new()
	list.add_child(items)
	var rebuild := func(q: String) -> void:
		for c in items.get_children():
			c.queue_free()
		checks.clear()
		var n := 0
		for k in keys:
			var ks := String(k)
			if ks == sid:
				continue
			var d: Dictionary = data.get_skill(ks)
			var nm := String(d.get("name", ks))
			if q != "" and not (nm + " " + ks).to_lower().contains(q.to_lower()):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			items.add_child(row)
			var cb := CheckBox.new()
			cb.text = "%s　[%s]" % [nm, _skill_kind_name(String(d.get("kind", "")))]
			cb.button_pressed = cur_children.has(ks)
			row.add_child(cb)
			checks[ks] = cb
			# 单独编辑该子技能（效果 / 范围 / 等级都独立）
			var eb := THEME.button("单独编辑", 11)
			eb.tooltip_text = "修改「%s」自己的效果与范围（不影响其它技能）" % nm
			eb.pressed.connect(func() -> void:
				if cur_key == "":
					return
				win.hide()
				_show_skill_edit(ks))
			row.add_child(eb)
			n += 1
			if n > 300:
				break
	kw.text_changed.connect(rebuild)
	rebuild.call("")
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	v.add_child(btns)
	var save := THEME.button("保存子技能", 14, 140)
	save.pressed.connect(func() -> void:
		var kids: Array = []
		for k2 in checks.keys():
			var c2 = checks[k2]
			if c2 is CheckBox and (c2 as CheckBox).button_pressed:
				kids.append(String(k2))
		if kids.size() < 2:
			status("组合至少需要 2 个子技能")
			return
		var d3: Dictionary = data.get_skill(sid)
		d3["ed_group"] = kids
		d3["kind"] = EdData.GROUP_KIND
		data.dirty = true
		_mark_dirty()
		load_general(cur_key)
		refresh_skill_list()
		status("「%s」现有 %d 个子技能" % [data.skill_name(sid), kids.size()])
		win.queue_free())
	btns.add_child(save)
	var c3 := THEME.button("关闭", 13)
	c3.pressed.connect(func() -> void: win.queue_free())
	btns.add_child(c3)
	win.popup_centered()
func refresh_skill_list() -> void:
	if skill_list == null:
		return
	for c in skill_list.get_children():
		c.queue_free()
	for c in skill_edit_box.get_children():
		c.queue_free()
	if cur_key == "":
		return
	var g: Dictionary = data.generals[cur_key]
	var sids: Array = g.get("skills", [])
	if sids.is_empty():
		skill_list.add_child(THEME.hint("该武将还没有技能，点上方「从技能库添加」或「新建技能」。"))
		return
	for sid_v in sids:
		var sid := String(sid_v)
		var d: Dictionary = data.get_skill(sid)
		var panel := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)
		var kind := String(d.get("kind", "?"))
		var grp_info := ""
		if data.is_group(sid):
			var kids: Array = []
			for c in data.group_children(sid):
				kids.append(data.skill_name(String(c)))
			grp_info = "　⇄ 可选：" + " / ".join(kids)
		var merged_info := ""
		var name_lbl := THEME.label("%s  [%s%s]%s" % [
			data.skill_name(sid), _skill_kind_name(kind),
			" · CD%d" % int(d.get("cd", 0)) if int(d.get("cd", 0)) > 0 else "",
			grp_info], 14,
			THEME.MUTED if (kind == "passive" and not data.is_group(sid)) else THEME.TEXT)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var lv_sp := SpinBox.new()
		lv_sp.min_value = 1
		lv_sp.max_value = 3
		lv_sp.value = int((g.get("ed_skill_lv", {}) as Dictionary).get(sid, 1))
		lv_sp.custom_minimum_size = Vector2(70, 0)
		lv_sp.prefix = "Lv"
		lv_sp.value_changed.connect(func(val: float) -> void:
			if cur_key == "" or busy:
				return
			data.generals[cur_key]["ed_skill_lv"][sid] = int(val)
			_mark_dirty()
			_show_skill_edit(sid))
		row.add_child(lv_sp)
		var rb := THEME.button("范围…", 12)
		rb.pressed.connect(func() -> void:
			tabs.current_tab = 7
			_range_ctx["sid"] = sid
			_refresh_range_page())
		row.add_child(rb)
		var eb := THEME.button("编辑", 12)
		eb.pressed.connect(func() -> void: _show_skill_edit(sid))
		row.add_child(eb)
		if data.is_group(sid):
			var gb := THEME.button("组合 %d 项…" % data.group_children(sid).size(), 12)
			gb.tooltip_text = "增删该组合技策里的子技能"
			gb.pressed.connect(func() -> void: _open_group_editor(sid))
			row.add_child(gb)
		var ub := THEME.button("↑", 12, 26)
		ub.pressed.connect(func() -> void: _move_skill(sid, -1))
		row.add_child(ub)
		var db := THEME.button("↓", 12, 26)
		db.pressed.connect(func() -> void: _move_skill(sid, 1))
		row.add_child(db)
		var xb := THEME.button("✕", 12, 26)
		xb.pressed.connect(func() -> void: _remove_skill(sid))
		row.add_child(xb)
		skill_list.add_child(panel)
	_show_skill_edit(String(sids[0]))
func _move_skill(sid: String, d: int) -> void:
	if cur_key == "":
		return
	var arr: Array = data.generals[cur_key]["skills"]
	var i := arr.find(sid)
	if i < 0:
		return
	var j := clampi(i + d, 0, arr.size() - 1)
	if i == j:
		return
	arr.remove_at(i)
	arr.insert(j, sid)
	_mark_dirty()
	refresh_skill_list()
func _remove_skill(sid: String) -> void:
	if cur_key == "":
		return
	data.generals[cur_key]["skills"].erase(sid)
	_mark_dirty()
	refresh_skill_list()
func _add_skill(sid: String) -> void:
	if cur_key == "":
		return
	if (data.generals[cur_key]["skills"] as Array).has(sid):
		status("该武将已有技能 " + sid)
		return
	data.generals[cur_key]["skills"].append(sid)
	data.generals[cur_key]["ed_skill_lv"][sid] = 1
	_mark_dirty()
	refresh_skill_list()
func _show_skill_edit(sid: String) -> void:
	_fx_editing_sid = sid
	for c in skill_edit_box.get_children():
		c.queue_free()
	var d: Dictionary = data.get_skill(sid)
	if d.is_empty():
		return
	var g: Dictionary = data.generals[cur_key]
	var lv := int((g.get("ed_skill_lv", {}) as Dictionary).get(sid, 1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var head := THEME.label("编辑技能：%s（%s）" % [data.skill_name(sid), sid], 15, THEME.ORANGE)
	box.add_child(head)
	var grid := VBoxContainer.new()
	box.add_child(grid)
	_form_line(grid, "技能名", func(t: String) -> void:
		d["name"] = t
		_mark_dirty()
		refresh_skill_list())
	var kind_opt := OptionButton.new()
	for k in RULEZ.SKILL_KINDS:
		kind_opt.add_item(_skill_kind_name(k))
	kind_opt.selected = maxi(0, RULEZ.SKILL_KINDS.find(String(d.get("kind", "single"))))
	kind_opt.item_selected.connect(func(i: int) -> void:
		d["kind"] = RULEZ.SKILL_KINDS[i]
		_mark_dirty()
		refresh_skill_list())
	var cd_sp := SpinBox.new()
	cd_sp.min_value = 0
	cd_sp.max_value = 99
	cd_sp.value = int(d.get("cd", 0))
	cd_sp.value_changed.connect(func(val: float) -> void:
		d["cd"] = int(val)
		_mark_dirty()
		refresh_skill_list()
		_refresh_range_page())
	var mult_sp := SpinBox.new()
	mult_sp.min_value = 0
	mult_sp.max_value = 10
	mult_sp.step = 0.05
	mult_sp.value = float(d.get("mult", 1.0))
	mult_sp.value_changed.connect(func(val: float) -> void:
		d["mult"] = float(val)
		_mark_dirty())
	var heal_sp := SpinBox.new()
	heal_sp.min_value = 0
	heal_sp.max_value = 10
	heal_sp.step = 0.05
	heal_sp.value = float(d.get("heal", RULEZ.get_f("heal_mult_default")))
	heal_sp.value_changed.connect(func(val: float) -> void:
		d["heal"] = float(val)
		_mark_dirty())
	var magic_cb := CheckBox.new()
	magic_cb.button_pressed = bool(d.get("magic", false))
	magic_cb.toggled.connect(func(on: bool) -> void:
		d["magic"] = on
		_mark_dirty())
	_form_row(grid, "类型", kind_opt)
	_form_row(grid, "冷却 CD", cd_sp)
	_form_row(grid, "威力倍率 mult", mult_sp)
	_form_row(grid, "治疗系数 heal", heal_sp)
	_form_row(grid, "谋略伤害", magic_cb)
	var desc_lbl := THEME.label("描述", 13, THEME.MUTED)
	box.add_child(desc_lbl)
	var desc := TextEdit.new()
	desc.custom_minimum_size = Vector2(0, 90)
	desc.text = String(d.get("desc", ""))
	desc.text_changed.connect(func() -> void:
		d["desc"] = desc.text
		_mark_dirty())
	box.add_child(desc)
	var lv_row := HBoxContainer.new()
	lv_row.add_child(THEME.label("升级文案（Lv1 / Lv2 / Lv3）", 13, THEME.MUTED))
	box.add_child(lv_row)
	var lvs: Array = d.get("lv", [])
	if not (lvs is Array):
		lvs = []
	for i in 3:
		var e := LineEdit.new()
		e.placeholder_text = "Lv%d 效果说明" % (i + 1)
		e.text = String(lvs[i]) if i < lvs.size() else ""
		e.text_changed.connect(func() -> void:
			var arr: Array = d.get("lv", [])
			while arr.size() < 3:
				arr.append("")
			arr[i] = e.text
			d["lv"] = arr
			_mark_dirty())
		box.add_child(e)
	box.add_child(THEME.sep())
	# 升阶文案是累积生效的：Lv2 的说明对 2/3 级都有效，Lv3 的只在 3 级
	var sum := THEME.label("当前 Lv%d 生效（逐级累积）：\n%s" % [lv, _lv_text_stack(d, lv)], 13, THEME.GOOD)
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sum)
	var sum2 := THEME.label("升级到 Lv%d 后新增：%s" % [mini(lv + 1, 3), _lv_text(d, mini(lv + 1, 3))], 13, THEME.ORANGE)
	sum2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sum2)
	box.add_child(THEME.hint("升阶规则：Lv2 写的内容对 2、3 级都生效；Lv3 写的只对 3 级生效。技能范围同理（Lv2 画的范围 2/3 级共用，Lv3 单独画才只在 3 级生效）。"))
	var range_sum := THEME.hint(_range_summary(sid))
	box.add_child(range_sum)
	# ---------- 效果块编辑器（真正改效果，而不只是改描述） ----------
	box.add_child(THEME.sep())
	box.add_child(THEME.label("技能效果（按顺序执行，可自由增删）", 15, THEME.GOOD))
	box.add_child(THEME.hint("这里决定技能真正造成的效果；描述文字只是给人看的。可以给任意技能加任意多个效果块，" +
		"例如给「鬼哭神嚎」再加一个「施加减益：撕裂」。"))
	var sync_cb := CheckBox.new()
	sync_cb.text = "效果变化时自动写入描述与升级文案（【效果】行）"
	sync_cb.button_pressed = _fx_sync_desc
	sync_cb.toggled.connect(func(on: bool) -> void:
		_fx_sync_desc = on
		if on:
			_sync_fx_to_desc(sid)
			_show_skill_edit(sid)
		_mark_dirty())
	box.add_child(sync_cb)
	_build_effect_editor(box, sid, d)
	# ---------- 技能特效（导入图片，留好槽位） ----------
	box.add_child(THEME.sep())
	var fx_head := THEME.label("技能特效", 15, THEME.ORANGE)
	box.add_child(fx_head)
	box.add_child(THEME.hint("导入特效图后保存路径与切帧参数，随导出一起交给游戏。特效图可以是横向帧条，也可以是网格图；" +
		"小战场放技能时会按这些参数播放一次。已接入路径：res://assets/imported/fx/。"))
	var fx: Dictionary = d.get("ed_fx", {}) if d.get("ed_fx") is Dictionary else {}
	var fx_row := HBoxContainer.new()
	fx_row.add_theme_constant_override("separation", 8)
	box.add_child(fx_row)
	var fx_preview := TextureRect.new()
	fx_preview.custom_minimum_size = Vector2(96, 96)
	fx_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fx_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fx_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	(fx_preview as Control).name = "fx_preview"
	fx_row.add_child(fx_preview)
	var fx_info := THEME.label(_fx_info(d), 12, THEME.MUTED)
	fx_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fx_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fx_row.add_child(fx_info)
	var fx_btns := HBoxContainer.new()
	fx_btns.add_theme_constant_override("separation", 6)
	box.add_child(fx_btns)
	var b_import_fx := THEME.button("导入技能特效图…", 13)
	b_import_fx.pressed.connect(func() -> void: _import_skill_fx(sid))
	fx_btns.add_child(b_import_fx)
	var b_clear_fx := THEME.button("清除特效", 13)
	b_clear_fx.pressed.connect(func() -> void:
		d.erase("ed_fx")
		_mark_dirty()
		_show_skill_edit(sid)
		status("已清除「%s」的特效" % data.skill_name(sid)))
	fx_btns.add_child(b_clear_fx)
	var b_play_fx := THEME.button("▶ 预览播放", 13)
	b_play_fx.pressed.connect(func() -> void: _play_skill_fx(d))
	fx_btns.add_child(b_play_fx)
	var fx_grid := VBoxContainer.new()
	box.add_child(fx_grid)
	for spec in [["frame_w", "帧宽", 8, 512, 1], ["frame_h", "帧高", 8, 512, 1],
			["frames", "帧数", 1, 64, 1], ["fps", "帧率", 1, 60, 1],
			["scale", "缩放", 0.1, 4.0, 0.05], ["offset_y", "垂直偏移", -128, 128, 1]]:
		var key := String(spec[0])
		var sp := SpinBox.new()
		sp.min_value = spec[2]
		sp.max_value = spec[3]
		sp.step = spec[4]
		sp.value = float(fx.get(key, _fx_default(key)))
		sp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		sp.custom_minimum_size = Vector2(120, 0)
		sp.value_changed.connect(func(val: float) -> void:
			var f2: Dictionary = d.get("ed_fx", {}) if d.get("ed_fx") is Dictionary else {}
			f2[key] = val
			d["ed_fx"] = f2
			_mark_dirty()
			fx_info.text = _fx_info(d))
		_form_row(fx_grid, String(spec[1]), sp)
	var fx_attach := VBoxContainer.new()
	box.add_child(fx_attach)
	var attach_opt := OptionButton.new()
	var anchor_opts := ["目标格", "施法者格", "落点格", "全部作用格"]
	var anchor_ids := ["target", "caster", "center", "all"]
	for it in anchor_opts:
		attach_opt.add_item(String(it))
	attach_opt.selected = maxi(0, anchor_ids.find(String(fx.get("anchor", "target"))))
	attach_opt.item_selected.connect(func(i: int) -> void:
		var f3: Dictionary = d.get("ed_fx", {}) if d.get("ed_fx") is Dictionary else {}
		f3["anchor"] = anchor_ids[i]
		d["ed_fx"] = f3
		_mark_dirty())
	_form_row(fx_attach, "播放位置", attach_opt)
	var layer_opt := OptionButton.new()
	var layer_names := ["角色之上（前景）", "角色之下（地面）", "全屏覆盖"]
	var layer_ids := ["above", "below", "screen"]
	for it in layer_names:
		layer_opt.add_item(String(it))
	layer_opt.selected = maxi(0, layer_ids.find(String(fx.get("layer", "above"))))
	layer_opt.item_selected.connect(func(i: int) -> void:
		var f4: Dictionary = d.get("ed_fx", {}) if d.get("ed_fx") is Dictionary else {}
		f4["layer"] = layer_ids[i]
		d["ed_fx"] = f4
		_mark_dirty())
	_form_row(fx_attach, "显示层级", layer_opt)
	var sync_start := CheckBox.new()
	sync_start.text = "与技能等级联动（Lv1/2/3 用不同起始帧）"
	sync_start.button_pressed = bool(fx.get("sync_level", false))
	sync_start.toggled.connect(func(on: bool) -> void:
		var f5: Dictionary = d.get("ed_fx", {}) if d.get("ed_fx") is Dictionary else {}
		f5["sync_level"] = on
		d["ed_fx"] = f5
		_mark_dirty())
	fx_attach.add_child(sync_start)
	var fx_path = fx.get("path", "")
	if String(fx_path) != "":
		fx_preview.texture = _load_tex(String(fx_path))
	skill_edit_box.add_child(box)
func _fx_default(key: String) -> float:
	match key:
		"scale":
			return 1.0
		"fps":
			return 12.0
		"frames":
			return 4
		"frame_w", "frame_h":
			return 64
	return 0.0
func _fx_info(d: Dictionary) -> String:
	var fx = d.get("ed_fx", null)
	if not (fx is Dictionary) or String((fx as Dictionary).get("path", "")) == "":
		return "尚未导入特效图（占位：导入后会随技能一起导出）"
	var f: Dictionary = fx
	return "路径：%s\n帧 %dx%d　共 %d 帧　%.0f fps" % [
		String(f.get("path", "")), int(f.get("frame_w", 64)), int(f.get("frame_h", 64)),
		int(f.get("frames", 4)), float(f.get("fps", 12.0))]
func _import_skill_fx(sid: String) -> void:
	if cur_key == "":
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = "选择技能特效图（横向帧条 / 序列帧）"
	dlg.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; 图片"])
	add_child(dlg)
	dlg.file_selected.connect(func(path: String) -> void:
		var r := data.import_art(path, "fx", sid)
		if bool(r.get("ok", false)):
			var d: Dictionary = data.get_skill(sid)
			var sz = r.get("size", Vector2i(64, 64))
			var fw := 64
			var fh := 64
			if sz is Vector2i:
				fh = int(sz.y)
				if int(sz.x) % 4 == 0:
					fw = int(sz.x) / 4
				else:
					fw = int(sz.x)
			d["ed_fx"] = {
				"path": String(r["res"]), "sheet_type": "strip",
				"frame_w": fw, "frame_h": fh, "frames": 4, "fps": 12.0,
				"scale": 1.0, "offset_y": 0.0, "anchor": "target", "layer": "above",
				"sync_level": false,
			}
			_mark_dirty()
			_show_skill_edit(sid)
			status("已导入「%s」的特效" % data.skill_name(sid))
		else:
			status(String(r.get("msg", "导入失败")))
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered_ratio(0.7)
func _play_skill_fx(d: Dictionary) -> void:
	var fx = d.get("ed_fx", null)
	if not (fx is Dictionary):
		return
	var f: Dictionary = fx
	var path := String(f.get("path", ""))
	if path == "":
		status("请先导入特效图")
		return
	var prev := find_child("fx_preview", true, false)
	if not (prev is TextureRect):
		return
	var tex := _load_tex(path)
	if tex == null:
		return
	var fw := int(f.get("frame_w", 64))
	var fh := int(f.get("frame_h", 64))
	var n := int(f.get("frames", 4))
	var fps := maxf(1.0, float(f.get("fps", 12.0)))
	var tw := create_tween()
	for i in n:
		tw.tween_callback(func() -> void:
			var at := AtlasTexture.new()
			at.atlas = tex
			var cols := maxi(1, int(tex.get_width() / maxi(1, fw)))
			at.region = Rect2((i % cols) * fw, (i / cols) * fh, fw, fh)
			(prev as TextureRect).texture = at)
		tw.tween_interval(1.0 / fps)
# ============================================================
# 效果块改动后重绘整个技能编辑区（保证新增/删除立刻可见）
func _refresh_fx_editor() -> void:
	if _fx_editing_sid != "":
		_show_skill_edit(_fx_editing_sid)
		# 同步把效果变化写进描述/升级文案（可选，见下方设置）
		if _fx_sync_desc and cur_key != "":
			_sync_fx_to_desc(_fx_editing_sid)


# 把效果块自动同步成描述文字
func _sync_fx_to_desc(sid: String) -> void:
	var d: Dictionary = data.get_skill(sid)
	if d.is_empty():
		return
	var effects: Array = RULEZ.skill_effects(d)
	# 先清掉所有旧的效果行（效果删空时也要清）
	var desc := String(d.get("desc", ""))
	var kept: Array = []
	for ln in desc.split("\n"):
		if not String(ln).begins_with("【效果】"):
			kept.append(ln)
	var newdesc := "\n".join(kept).strip_edges()
	var lvs: Array = d.get("lv", [])
	if not (lvs is Array):
		lvs = []
	var clean_lv: Array = []
	for i in lvs.size():
		var keep2: Array = []
		for ln2 in String(lvs[i]).split("\n"):
			if not String(ln2).begins_with("【效果】"):
				keep2.append(ln2)
		clean_lv.append("\n".join(keep2).strip_edges())
	if effects.is_empty():
		d["desc"] = newdesc
		d["lv"] = clean_lv
		data.skills[sid] = d
		data.dirty = true
		return
	# 按「自Lv」分级：某级生效 = 所有 min_lv ≤ 该级 的效果
	for L in [1, 2, 3]:
		var parts: Array = []
		for fx in effects:
			if int((fx as Dictionary).get("min_lv", 1)) <= L:
				parts.append(String(RULEZ.sfx_text(fx)))
		var line := "【效果】" + "；".join(parts)
		while clean_lv.size() < 3:
			clean_lv.append("")
		var base := String(clean_lv[L - 1]).strip_edges()
		clean_lv[L - 1] = (base + "\n" + line) if base != "" else line
	# 描述主体用 Lv1 生效的效果
	var p0: Array = []
	for fx in effects:
		if int((fx as Dictionary).get("min_lv", 1)) <= 1:
			p0.append(String(RULEZ.sfx_text(fx)))
	d["desc"] = (newdesc + "\n【效果】" + "；".join(p0)) if newdesc != "" else ("【效果】" + "；".join(p0))
	d["lv"] = clean_lv
	data.skills[sid] = d
	data.dirty = true


# 效果块编辑器：真正修改技能效果
# ============================================================
func _build_effect_editor(box: Control, sid: String, d: Dictionary) -> void:
	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 4)
	box.add_child(list_box)
	var rebuild := func() -> void:
		for c in list_box.get_children():
			c.queue_free()
		var effects: Array = RULEZ.skill_effects(d)
		# 首次编辑时把「按描述推断的默认块」固化进数据，之后以数据为准
		if not (d.get("ed_fx_list") is Array) or (d.get("ed_fx_list") as Array).is_empty():
			d["ed_fx_list"] = effects.duplicate(true)
			data.dirty = true
			_mark_dirty()
		var cur: Array = d["ed_fx_list"]
		if cur.is_empty():
			list_box.add_child(THEME.hint("（该技能还没有效果块，点下面「＋添加效果」。）"))
		for i in cur.size():
			var fx: Dictionary = cur[i]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			list_box.add_child(row)
			var idx_lb := THEME.label("%d." % (i + 1), 13, THEME.MUTED)
			idx_lb.custom_minimum_size = Vector2(28, 0)
			row.add_child(idx_lb)
			var t := String(fx.get("type", ""))
			# 类型选择
			var type_opt := OptionButton.new()
			type_opt.custom_minimum_size = Vector2(130, 0)
			for k in RULEZ.SFX_TYPES:
				type_opt.add_item(String(RULEZ.SFX_LABELS.get(k, k)))
			type_opt.selected = maxi(0, RULEZ.SFX_TYPES.find(t))
			var fi := i
			type_opt.item_selected.connect(func(sel: int) -> void:
				var nt := String(RULEZ.SFX_TYPES[sel])
				(d["ed_fx_list"] as Array)[fi] = RULEZ.default_sfx(nt)
				data.dirty = true
				_mark_dirty()
				_mark_dirty()
				_refresh_fx_editor())
			row.add_child(type_opt)
			# 参数
			match t:
				RULEZ.SFX_DAMAGE:
					row.add_child(THEME.label("倍率", 12, THEME.MUTED))
					var v := SpinBox.new()
					v.min_value = 0
					v.max_value = 10
					v.step = 0.05
					v.custom_minimum_size = Vector2(80, 0)
					v.value = float(fx.get("value", 1.0))
					v.value_changed.connect(func(x: float) -> void:
						fx["value"] = x
						data.dirty = true
						_mark_dirty())
					row.add_child(v)
					row.add_child(THEME.label("次", 12, THEME.MUTED))
					var tm := SpinBox.new()
					tm.min_value = 1
					tm.max_value = 9
					tm.custom_minimum_size = Vector2(60, 0)
					tm.value = int(fx.get("times", 1))
					tm.value_changed.connect(func(x: float) -> void:
						fx["times"] = int(x)
						data.dirty = true
						_mark_dirty())
					row.add_child(tm)
					var mg := CheckBox.new()
					mg.text = "谋略伤害"
					mg.button_pressed = bool(fx.get("magic", false))
					mg.toggled.connect(func(on: bool) -> void:
						fx["magic"] = on
						data.dirty = true
						_mark_dirty())
					row.add_child(mg)
				RULEZ.SFX_HEAL, RULEZ.SFX_SELF_HEAL:
					row.add_child(THEME.label("系数", 12, THEME.MUTED))
					var v2 := SpinBox.new()
					v2.min_value = 0
					v2.max_value = 5
					v2.step = 0.05
					v2.custom_minimum_size = Vector2(80, 0)
					v2.value = float(fx.get("value", 0.8))
					v2.value_changed.connect(func(x: float) -> void:
						fx["value"] = x
						data.dirty = true
						_mark_dirty())
					row.add_child(v2)
				RULEZ.SFX_DEBUFF, RULEZ.SFX_BUFF:
					# 状态名：常用名下拉 + 可自由输入的自定义名（输入框优先）
					var name_edit := LineEdit.new()
					name_edit.custom_minimum_size = Vector2(110, 0)
					name_edit.placeholder_text = "状态名"
					name_edit.text = String(fx.get("value", ""))
					name_edit.text_changed.connect(func(x: String) -> void:
						fx["value"] = x
						data.dirty = true
						_mark_dirty())
					row.add_child(name_edit)
					var name_opt := OptionButton.new()
					name_opt.custom_minimum_size = Vector2(96, 0)
					name_opt.tooltip_text = "从常用状态里选一个"
					name_opt.add_item("常用…")
					for nm in RULEZ.COMMON_STATUS:
						name_opt.add_item(String(nm))
					name_opt.item_selected.connect(func(i2: int) -> void:
						if i2 <= 0:
							return
						var picked := name_opt.get_item_text(i2)
						fx["value"] = picked
						name_edit.text = picked
						data.dirty = true
						_mark_dirty())
					row.add_child(name_opt)
					row.add_child(THEME.label("回合", 12, THEME.MUTED))
					var tn := SpinBox.new()
					tn.min_value = 1
					tn.max_value = 9
					tn.custom_minimum_size = Vector2(60, 0)
					tn.value = int(fx.get("turns", 2))
					tn.value_changed.connect(func(x: float) -> void:
						fx["turns"] = int(x)
						data.dirty = true
						_mark_dirty())
					row.add_child(tn)
					if t == RULEZ.SFX_DEBUFF:
						row.add_child(THEME.label("层", 12, THEME.MUTED))
						var st := SpinBox.new()
						st.min_value = 1
						st.max_value = 9
						st.custom_minimum_size = Vector2(60, 0)
						st.value = int(fx.get("stacks", 1))
						st.value_changed.connect(func(x: float) -> void:
							fx["stacks"] = int(x)
							data.dirty = true
							_mark_dirty())
						row.add_child(st)
				RULEZ.SFX_PUSH, RULEZ.SFX_CD_DOWN, RULEZ.SFX_DISPEL, RULEZ.SFX_SELF_DISPEL:
					row.add_child(THEME.label("数值", 12, THEME.MUTED))
					var v3 := SpinBox.new()
					v3.min_value = 1
					v3.max_value = 9
					v3.custom_minimum_size = Vector2(70, 0)
					v3.value = int(fx.get("value", 1))
					v3.value_changed.connect(func(x: float) -> void:
						fx["value"] = int(x)
						data.dirty = true
						_mark_dirty())
					row.add_child(v3)
				_:
					pass
			# 生效等级：从第几级开始生效
			row.add_child(THEME.label("自Lv", 11, THEME.MUTED))
			var lv_opt := OptionButton.new()
			lv_opt.custom_minimum_size = Vector2(56, 0)
			for L in [1, 2, 3]:
				lv_opt.add_item("Lv%d" % L)
			lv_opt.selected = clampi(int(fx.get("min_lv", 1)) - 1, 0, 2)
			lv_opt.tooltip_text = "该效果从第几级开始生效：选 Lv2 则 1 级无效，2/3 级有效"
			lv_opt.item_selected.connect(func(sel2: int) -> void:
				fx["min_lv"] = sel2 + 1
				data.dirty = true
				_mark_dirty()
				_refresh_fx_editor())
			row.add_child(lv_opt)
			var sum := THEME.label("＝ " + RULEZ.sfx_text(fx) + ("" if int(fx.get("min_lv", 1)) <= 1 else "　[Lv%d起]" % int(fx.get("min_lv", 1))), 12, THEME.ACCENT)
			sum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sum)
			var up := THEME.button("↑", 12, 26)
			up.disabled = i == 0
			up.pressed.connect(func() -> void:
				var arr: Array = d["ed_fx_list"]
				if fi > 0:
					var tmp = arr[fi]
					arr[fi] = arr[fi - 1]
					arr[fi - 1] = tmp
					data.dirty = true
					_mark_dirty()
					_refresh_fx_editor())
			row.add_child(up)
			var del := THEME.button("✕", 12, 26)
			del.pressed.connect(func() -> void:
				(d["ed_fx_list"] as Array).remove_at(fi)
				data.dirty = true
				_mark_dirty()
				_refresh_fx_editor())
			row.add_child(del)
		var add_row := HBoxContainer.new()
		add_row.add_theme_constant_override("separation", 6)
		list_box.add_child(add_row)
		var add_opt := OptionButton.new()
		add_opt.custom_minimum_size = Vector2(160, 0)
		for k in RULEZ.SFX_TYPES:
			add_opt.add_item("＋ " + String(RULEZ.SFX_LABELS.get(k, k)))
		add_row.add_child(add_opt)
		var add_btn := THEME.button("添加效果", 12)
		add_btn.pressed.connect(func() -> void:
			var nt := String(RULEZ.SFX_TYPES[add_opt.selected])
			if not (d.get("ed_fx_list") is Array):
				d["ed_fx_list"] = []
			(d["ed_fx_list"] as Array).append(RULEZ.default_sfx(nt))
			data.dirty = true
			_mark_dirty()
			_refresh_fx_editor())
		add_row.add_child(add_btn)
		var copy_btn := THEME.button("复制本技能全部效果…", 12)
		copy_btn.tooltip_text = "把这些效果块追加到另一个技能（效果层面的融合）"
		copy_btn.pressed.connect(func() -> void:
			_open_copy_effects(sid, d))
		add_row.add_child(copy_btn)
	rebuild.call()
# 把某技能的效果块追加到另一个技能
func _open_copy_effects(sid: String, d: Dictionary) -> void:
	var win := Window.new()
	win.title = "把「%s」的效果复制到…" % data.skill_name(sid)
	win.size = Vector2i(460, 480)
	add_child(win)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 12
	v.offset_right = -12
	v.offset_bottom = -12
	win.add_child(v)
	v.add_child(THEME.hint("选择目标技能：本技能的全部效果块会追加到它后面（可再在该技能里调整）。"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var keys: Array = data.skills.keys()
	keys.sort()
	var effects: Array = RULEZ.skill_effects(d)
	for k in keys:
		var ks := String(k)
		if ks == sid:
			continue
		var b := THEME.button("%s　[%s]" % [data.skill_name(ks), _skill_kind_name(String(data.get_skill(ks).get("kind", "")))], 12)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			var td: Dictionary = data.get_skill(ks)
			if not (td.get("ed_fx_list") is Array):
				td["ed_fx_list"] = RULEZ.skill_effects(td)
			for fx in effects:
				(td["ed_fx_list"] as Array).append((fx as Dictionary).duplicate(true))
			data.dirty = true
			_mark_dirty()
			status("已把 %d 个效果复制到「%s」" % [effects.size(), data.skill_name(ks)])
			win.queue_free())
		list.add_child(b)
	win.popup_centered()
# 逐级累积的生效文案：Lv1..当前等级 依次列出（每级只列该级新增）
func _lv_text_stack(d: Dictionary, lv: int) -> String:
	var lvs: Array = d.get("lv", [])
	var lines: Array = []
	var base := String(d.get("desc", ""))
	if base != "" and not lvs.is_empty():
		lines.append("· Lv1：%s" % base)
	for i in range(1, mini(lv, 3)):
		if i < lvs.size():
			var t := String(lvs[i])
			# Lv1 那一行是完整描述，从 Lv2 起才是"升阶新增"
			if i >= 1 and t != "":
				lines.append("· Lv%d 新增：%s" % [i + 1, t])
	return "\n".join(lines) if not lines.is_empty() else "（无）"


func _lv_text(d: Dictionary, lv: int) -> String:
	var lvs: Array = d.get("lv", [])
	if lv - 1 < lvs.size() and lv - 1 >= 0:
		return String(lvs[lv - 1])
	return String(d.get("desc", ""))
func _grid_line(grid: Control, label: String, value: String) -> void:
	var l := THEME.label(value, 13, THEME.MUTED)
	l.clip_text = true
	_form_row(grid, label, l)
func _open_skill_picker() -> void:
	if skill_pick_dialog != null and is_instance_valid(skill_pick_dialog):
		skill_pick_dialog.queue_free()
	var win := Window.new()
	win.title = "技能库（共 %d 条）" % data.skills.size()
	win.size = Vector2i(720, 640)
	win.exclusive = false
	add_child(win)
	skill_pick_dialog = win
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	win.add_child(v)
	var se := LineEdit.new()
	se.placeholder_text = "搜索技能名 / id / 类型"
	v.add_child(se)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	v.add_child(toolbar)
	var close_btn := THEME.button("✕ 关闭", 13, 90)
	close_btn.pressed.connect(func() -> void:
		win.hide()
		win.queue_free())
	toolbar.add_child(close_btn)
	var count_lb := THEME.label("", 12, THEME.MUTED)
	count_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(count_lb)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var rebuild := func(q: String) -> void:
		for c in list.get_children():
			c.queue_free()
		var n := 0
		for sid in data.skills.keys():
			var d: Dictionary = data.skills[sid]
			var nm := String(d.get("name", sid))
			var hay := (nm + " " + String(sid) + " " + String(d.get("kind", "")) + " " + _skill_kind_name(String(d.get("kind", "")))).to_lower()
			if q != "" and not hay.contains(q.to_lower()):
				continue
			var b := THEME.button("%s   [%s]   %s" % [nm, _skill_kind_name(String(d.get("kind", ""))), sid], 13)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.pressed.connect(func() -> void:
				_add_skill(String(sid))
				status("已添加技能 " + nm))
			list.add_child(b)
			n += 1
			if n > 400:
				break
		count_lb.text = "共 %d 条（点一下即添加，可连续添加）" % n
	se.text_changed.connect(rebuild)
	rebuild.call("")
	# 关闭窗口时彻底释放，避免残留挡住界面
	win.close_requested.connect(func() -> void: win.queue_free())
	win.popup_centered()
func _on_new_skill() -> void:
	if cur_key == "":
		return
	var sid := data.new_skill_id("skill_" + cur_key)
	var d := {
		"name": "新技能",
		"kind": "single",
		"cd": 2,
		"range": 1,
		"radius": 0,
		"mult": 1.0,
		"desc": "对范围内的敌军造成物攻100%的伤害。",
		"lv": ["对范围内的敌军造成物攻100%的伤害。", "", ""],
		"from_official": false,
	}
	data.add_skill(sid, d)
	_add_skill(sid)
	_mark_dirty()
	status("已新建技能 " + sid)
# ------------------------------------------------------------
# ⑦ 天赋
# ------------------------------------------------------------
func _page_talent() -> Control:
	var r := _scroll_page()
	var sc: ScrollContainer = r[0]
	var v: VBoxContainer = r[1]
	sc.name = "天赋"
	var s := _section("天赋（被动）",
		"天赋分 Lv1/Lv2/Lv3 三段描述；等级可任意调。天赋描述里的数值只作展示，真正生效的是描述中写明并被引擎实现的通用效果。")
	v.add_child(s)
	var g := VBoxContainer.new()
	s.add_child(g)
	g.add_child(THEME.label("天赋", 13))
	talent_opt = OptionButton.new()
	talent_opt.add_item("（无）")
	var tids: Array = ["", ]
	var keys: Array = data.talents.keys()
	keys.sort()
	for tid in keys:
		tids.append(String(tid))
		talent_opt.add_item("%s（%s）" % [data.talent_name(String(tid)), tid])
	talent_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talent_opt.item_selected.connect(func(i: int) -> void:
		if cur_key == "":
			return
		data.generals[cur_key]["talent"] = String(tids[i])
		_mark_dirty()
		_refresh_talent_desc())
	g.add_child(talent_opt)
	g.add_child(THEME.label("天赋等级", 13))
	talent_lv_spin = SpinBox.new()
	talent_lv_spin.min_value = 1
	talent_lv_spin.max_value = 3
	talent_lv_spin.value_changed.connect(func(val: float) -> void:
		if cur_key == "" or busy:
			return
		data.generals[cur_key]["ed_talent_lv"] = int(val)
		_mark_dirty()
		_refresh_talent_desc()
		_update_stat_preview())
	g.add_child(talent_lv_spin)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	s.add_child(trow)
	var nbtn := THEME.button("＋ 新建天赋", 13)
	nbtn.pressed.connect(_on_new_talent)
	trow.add_child(nbtn)
	var ebtn := THEME.button("编辑天赋文案", 13)
	ebtn.pressed.connect(_on_edit_talent)
	trow.add_child(ebtn)
	var pbtn := THEME.button("＋ 添加一个天赋效果（占位）", 13)
	pbtn.pressed.connect(func() -> void:
		status("扩展效果请到「⑩ 扩展与补充」页设置（增伤/减伤/暴击/射程/移动等）。"))
	trow.add_child(pbtn)
	talent_desc = RichTextLabel.new()
	talent_desc.custom_minimum_size = Vector2(0, 260)
	talent_desc.bbcode_enabled = true
	s.add_child(talent_desc)
	var s2 := _section("天赋效果（与技能一样可自由添加效果块）",
		"天赋也能挂真实效果：勾选的天赋等级达到效果块的「自Lv」才会生效。天赋效果在【战斗开始时】对自身生效" +
		"（例如加护盾、加暴击、加状态），持续类效果按设定回合数计算。")
	v.add_child(s2)
	talent_fx_box = VBoxContainer.new()
	talent_fx_box.add_theme_constant_override("separation", 4)
	s2.add_child(talent_fx_box)
	var t_sync := CheckBox.new()
	t_sync.text = "天赋效果变化时自动写入天赋描述"
	t_sync.button_pressed = _fx_sync_desc
	t_sync.toggled.connect(func(on: bool) -> void:
		_fx_sync_desc = on
		_mark_dirty())
	s2.add_child(t_sync)
	return sc
func _refresh_talent_desc() -> void:
	_refresh_talent_desc_text_only()
	_refresh_talent_fx()


# 只刷新天赋文案显示（不重建效果块控件，避免递归）
func _refresh_talent_desc_text_only() -> void:
	if cur_key == "" or talent_desc == null:
		return
	var g: Dictionary = data.generals[cur_key]
	var tid := String(g.get("talent", ""))
	var lv := int(g.get("ed_talent_lv", 1))
	var d: Dictionary = data.get_talent(tid)
	var txt := ""
	if d.is_empty():
		txt = "[color=#94a3b8]未配置天赋。可从上方下拉选择，或新建一个。[/color]"
	else:
		var lvs: Array = d.get("lv", [])
		var lines: Array = []
		for i in lvs.size():
			var mark := "▶ " if i == lv - 1 else "　 "
			var col := "#34d399" if i == lv - 1 else "#94a3b8"
			lines.append("[color=%s]%sLv%d：%s[/color]" % [col, mark, i + 1, String(lvs[i])])
		txt = "[color=#f97316]%s[/color]（%s）\n\n%s" % [data.talent_name(tid), tid, "\n".join(lines)]
	talent_desc.text = txt
# 天赋效果块（结构同技能：ed_fx_list + min_lv）
# 把天赋效果写入天赋描述（按等级标注）
func _sync_talent_desc(t: Dictionary) -> void:
	if t.is_empty():
		return
	var fx_raw = t.get("ed_fx_list", [])
	if not (fx_raw is Array):
		fx_raw = []
	# 按「自Lv」分组生成描述行
	var lvs: Array = t.get("lv", [])
	if not (lvs is Array):
		lvs = []
	while lvs.size() < 3:
		lvs.append("")
	for L in [1, 2, 3]:
		var parts: Array = []
		for fx in (fx_raw as Array):
			if not (fx is Dictionary):
				continue
			# 累积：min_lv ≤ 当前级 的都生效（Lv2 加的 3 级也有）
			if int((fx as Dictionary).get("min_lv", 1)) > L:
				continue
			parts.append(String(RULEZ.sfx_text(fx)))
		var line := "【效果·天赋Lv%d】%s" % [L, "；".join(parts)] if not parts.is_empty() else ""
		var cur := String(lvs[L - 1])
		# 去掉旧行再加（删除效果时 line 为空 → 旧行被清掉）
		var kept: Array = []
		for ln in cur.split("\n"):
			if not String(ln).begins_with("【效果·天赋Lv"):
				kept.append(ln)
		var base := "\n".join(kept).strip_edges()
		lvs[L - 1] = (base + "\n" + line) if line != "" else base
	t["lv"] = lvs
	# 同步描述主体（为空时清掉旧行）
	var all_parts: Array = []
	for fx in (fx_raw as Array):
		if fx is Dictionary:
			all_parts.append("[Lv%d]%s" % [int(fx.get("min_lv", 1)), String(RULEZ.sfx_text(fx))])
	var desc := String(t.get("desc", ""))
	var kept2: Array = []
	for ln2 in desc.split("\n"):
		if not String(ln2).begins_with("【效果】"):
			kept2.append(ln2)
	var base2 := "\n".join(kept2).strip_edges()
	if all_parts.is_empty():
		if base2 == "":
			t.erase("desc")
		else:
			t["desc"] = base2
	else:
		var body := "【效果】" + "；".join(all_parts)
		t["desc"] = (base2 + "\n" + body) if base2 != "" else body


func _refresh_talent_fx() -> void:
	if talent_fx_box == null:
		return
	for c in talent_fx_box.get_children():
		c.queue_free()
	if cur_key == "":
		return
	var g: Dictionary = data.generals[cur_key]
	var tid := String(g.get("talent", ""))
	if tid == "":
		talent_fx_box.add_child(THEME.hint("（该武将没有天赋，可点击上方的天赋名后再编辑）"))
		return
	var t: Dictionary = data.get_talent(tid)
	if t.is_empty():
		return
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	talent_fx_box.add_child(list)
	var rebuild := func() -> void:
		for c in list.get_children():
			c.queue_free()
		if not (t.get("ed_fx_list") is Array):
			t["ed_fx_list"] = []
		var cur: Array = t["ed_fx_list"]
		if cur.is_empty():
			list.add_child(THEME.hint("（暂无天赋效果，点下面添加：如「施加增益：昂扬」「套护盾」。）"))
		for i in cur.size():
			var fx: Dictionary = cur[i]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			list.add_child(row)
			row.add_child(THEME.label("%d." % (i + 1), 12, THEME.MUTED))
			var to := OptionButton.new()
			to.custom_minimum_size = Vector2(140, 0)
			for k in RULEZ.SFX_TYPES:
				to.add_item(String(RULEZ.SFX_LABELS.get(k, k)))
			to.selected = maxi(0, RULEZ.SFX_TYPES.find(String(fx.get("type", ""))))
			var fi := i
			to.item_selected.connect(func(sel: int) -> void:
				cur[fi] = RULEZ.default_sfx(String(RULEZ.SFX_TYPES[sel]))
				data.dirty = true
				_mark_dirty()
				_refresh_talent_fx())
			row.add_child(to)
			# 生效等级
			var lo := OptionButton.new()
			lo.custom_minimum_size = Vector2(56, 0)
			for L in [1, 2, 3]:
				lo.add_item("Lv%d" % L)
			lo.selected = clampi(int(fx.get("min_lv", 1)) - 1, 0, 2)
			lo.item_selected.connect(func(sel2: int) -> void:
				fx["min_lv"] = sel2 + 1
				data.dirty = true
				_mark_dirty()
				_refresh_talent_fx())
			row.add_child(THEME.label("自", 11, THEME.MUTED))
			row.add_child(lo)
			# 数值 / 状态名
			var tp := String(fx.get("type", ""))
			if tp in [RULEZ.SFX_DEBUFF, RULEZ.SFX_BUFF]:
				var ne := LineEdit.new()
				ne.custom_minimum_size = Vector2(100, 0)
				ne.text = String(fx.get("value", ""))
				ne.placeholder_text = "状态名"
				ne.text_changed.connect(func(x: String) -> void:
					fx["value"] = x
					data.dirty = true
					_mark_dirty())
				row.add_child(ne)
				var tn := SpinBox.new()
				tn.min_value = 1
				tn.max_value = 9
				tn.custom_minimum_size = Vector2(56, 0)
				tn.value = int(fx.get("turns", 2))
				tn.value_changed.connect(func(x: float) -> void:
					fx["turns"] = int(x)
					data.dirty = true
					_mark_dirty())
				row.add_child(tn)
			elif tp != RULEZ.SFX_EXTRA_MOVE and tp != RULEZ.SFX_SELF_DISPEL:
				var vs := SpinBox.new()
				vs.min_value = 0
				vs.max_value = 999
				vs.custom_minimum_size = Vector2(72, 0)
				vs.value = float(fx.get("value", 1))
				vs.value_changed.connect(func(x: float) -> void:
					fx["value"] = x
					data.dirty = true
					_mark_dirty())
				row.add_child(vs)
			var sm := THEME.label("＝ " + RULEZ.sfx_text(fx), 11, THEME.ACCENT)
			sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sm)
			var dl := THEME.button("✕", 11, 26)
			dl.pressed.connect(func() -> void:
				cur.remove_at(fi)
				data.dirty = true
				_mark_dirty()
				_refresh_talent_fx())
			row.add_child(dl)
		var ar := HBoxContainer.new()
		ar.add_theme_constant_override("separation", 6)
		list.add_child(ar)
		var ao := OptionButton.new()
		ao.custom_minimum_size = Vector2(160, 0)
		for k in RULEZ.SFX_TYPES:
			ao.add_item("＋ " + String(RULEZ.SFX_LABELS.get(k, k)))
		ar.add_child(ao)
		var ab := THEME.button("添加天赋效果", 12)
		ab.pressed.connect(func() -> void:
			if not (t.get("ed_fx_list") is Array):
				t["ed_fx_list"] = []
			(t["ed_fx_list"] as Array).append(RULEZ.default_sfx(String(RULEZ.SFX_TYPES[ao.selected])))
			data.dirty = true
			_mark_dirty()
			_refresh_talent_fx())
		ar.add_child(ab)
	if _fx_sync_desc:
		_sync_talent_desc(t)
	rebuild.call()
	_refresh_talent_desc_text_only()


func _on_new_talent() -> void:
	if cur_key == "":
		return
	var tid := data.new_talent_id("talent_" + cur_key)
	data.add_talent(tid, {"name": "新天赋", "type": "talent", "icon": "", "lv": ["", "", ""]})
	data.generals[cur_key]["talent"] = tid
	data.generals[cur_key]["ed_talent_lv"] = 1
	_mark_dirty()
	load_general(cur_key)
	status("已新建天赋 " + tid)
func _on_edit_talent() -> void:
	if cur_key == "":
		return
	var tid := String(data.generals[cur_key].get("talent", ""))
	if tid == "":
		status("请先选择或新建天赋")
		return
	var d: Dictionary = data.get_talent(tid)
	var win := Window.new()
	win.title = "编辑天赋：" + tid
	win.size = Vector2i(640, 520)
	add_child(win)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_top = 10
	v.offset_right = -10
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 6)
	win.add_child(v)
	v.add_child(THEME.label("天赋名", 13))
	var nm := LineEdit.new()
	nm.text = String(d.get("name", ""))
	nm.text_changed.connect(func(t: String) -> void:
		d["name"] = t
		_mark_dirty())
	v.add_child(nm)
	var lvs: Array = d.get("lv", [])
	for i in 3:
		v.add_child(THEME.label("Lv%d 描述" % (i + 1), 13, THEME.MUTED))
		var e := TextEdit.new()
		e.custom_minimum_size = Vector2(0, 90)
		e.text = String(lvs[i]) if i < lvs.size() else ""
		e.text_changed.connect(func() -> void:
			var arr: Array = d.get("lv", [])
			while arr.size() < 3:
				arr.append("")
			arr[i] = e.text
			d["lv"] = arr
			_mark_dirty()
			_refresh_talent_desc())
		v.add_child(e)
	var ok := THEME.button("完成", 14)
	ok.pressed.connect(func() -> void:
		win.hide()
		_refresh_talent_desc())
	v.add_child(ok)
	win.popup_centered()
# ------------------------------------------------------------
# ⑧ 技能范围（沿用旧程序的范围编辑器）
# ------------------------------------------------------------
func _page_range() -> Control:
	var root := VBoxContainer.new()
	root.name = "范围"
	root.add_theme_constant_override("separation", 8)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 10)
	root.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)
	v.add_child(THEME.label("技能范围 / 冷却设置", 16, THEME.ACCENT))
	v.add_child(THEME.hint(
		"青格 = 释放距离（相对武将自身，格子按「朝右」画，实战自动转向目标方向）；橙格 = 作用范围（相对落点，中心为落点）。" +
		"左键涂、右键擦、按住拖动可连涂；升阶 Lv1/2/3 可各存一套形状。改完即时生效，记得点「💾 保存」。"))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	range_owner_opt = OptionButton.new()
	range_owner_opt.custom_minimum_size = Vector2(280, 0)
	range_owner_opt.item_selected.connect(func(i: int) -> void:
		_range_ctx["owner"] = data.order[i]
		_range_ctx["sid"] = "basic"
		_refresh_range_page())
	head.add_child(range_owner_opt)
	range_skill_opt = OptionButton.new()
	range_skill_opt.custom_minimum_size = Vector2(240, 0)
	range_skill_opt.item_selected.connect(func(i: int) -> void:
		var g: Dictionary = data.generals.get(str(_range_ctx.get("owner", "")), {})
		if i == 0:
			_range_ctx["sid"] = "basic"
		else:
			var sids: Array = g.get("skills", [])
			if i - 1 < sids.size():
				_range_ctx["sid"] = String(sids[i - 1])
		_refresh_range_page())
	head.add_child(range_skill_opt)
	var layer_row := HBoxContainer.new()
	layer_row.add_theme_constant_override("separation", 6)
	layer_row.add_child(THEME.label("  升阶：", 13, THEME.MUTED))
	for i in [1, 2, 3]:
		var b := THEME.button("Lv%d" % i, 13, 52)
		b.toggle_mode = true
		b.pressed.connect(func() -> void:
			_range_ctx["layer"] = i
			_refresh_range_page())
		layer_row.add_child(b)
		range_layer_btns[i] = b
	head.add_child(layer_row)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	# 释放距离
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	body.add_child(cv)
	cv.add_child(THEME.label("释放距离（青）", 13, THEME.ACCENT))
	cast_grid = RangeGrid.new()
	cast_grid.grid_n = 13
	cast_grid.cell_size = 22
	cast_grid.multi = true
	cast_grid.center_mark = "unit"
	cast_grid.accent = Color("#22d3ee")
	cast_grid.changed.connect(_on_range_changed.bind("cast"))
	cv.add_child(cast_grid)
	var cw := HBoxContainer.new()
	cw.add_theme_constant_override("separation", 4)
	cv.add_child(cw)
	cw.add_child(THEME.label("笔刷", 12, THEME.MUTED))
	var paint_btn := THEME.button("涂", 12, 32)
	var erase_btn := THEME.button("擦", 12, 32)
	paint_btn.pressed.connect(func() -> void:
		cast_grid.brush = 1
		effect_grid.brush = 1
		paint_btn.button_pressed = true)
	erase_btn.pressed.connect(func() -> void:
		cast_grid.brush = 0
		effect_grid.brush = 0)
	cw.add_child(paint_btn)
	cw.add_child(erase_btn)
	var ub := THEME.button("撤销", 12)
	ub.pressed.connect(func() -> void:
		cast_grid.undo()
		effect_grid.undo())
	cw.add_child(ub)
	# 作用范围
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 4)
	body.add_child(ev)
	ev.add_child(THEME.label("作用范围（橙，中心=落点）", 13, THEME.ORANGE))
	effect_grid = RangeGrid.new()
	effect_grid.grid_n = 13
	effect_grid.cell_size = 22
	effect_grid.multi = true
	effect_grid.center_mark = "target"
	effect_grid.accent = Color("#f97316")
	effect_grid.changed.connect(_on_range_changed.bind("area"))
	ev.add_child(effect_grid)
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	body.add_child(tools)
	tools.add_child(THEME.label("快捷生成", 13, THEME.MUTED))
	var gens := [
		["菱形 r=1", func(gd: RangeGrid) -> void: gd.set_diamond(1)],
		["菱形 r=2", func(gd: RangeGrid) -> void: gd.set_diamond(2)],
		["菱形 r=3", func(gd: RangeGrid) -> void: gd.set_diamond(3)],
		["十字 r=2", func(gd: RangeGrid) -> void: gd.set_cross(2)],
		["直线 r=1..5", func(gd: RangeGrid) -> void: gd.set_cross(5)],
		["环形 r=2", func(gd: RangeGrid) -> void: gd.set_ring(2)],
		["满格", func(gd: RangeGrid) -> void: gd.set_full()],
		["取反", func(gd: RangeGrid) -> void: gd.invert()],
		["左右镜像", func(gd: RangeGrid) -> void: gd.mirror()],
		["旋转 90°", func(gd: RangeGrid) -> void: gd.rotate_cw()],
		["清空", func(gd: RangeGrid) -> void: gd.clear_all()],
	]
	for it in gens:
		var b := THEME.button(String(it[0]), 12, 100)
		var fn: Callable = it[1]
		b.pressed.connect(func() -> void:
			_fn_both(fn))
		tools.add_child(b)
	var cdrow := HBoxContainer.new()
	cdrow.add_theme_constant_override("separation", 8)
	v.add_child(cdrow)
	cdrow.add_child(THEME.label("准备期（回合）", 13, THEME.MUTED))
	range_cd_spin = SpinBox.new()
	range_cd_spin.min_value = 0
	range_cd_spin.max_value = 99
	range_cd_spin.value_changed.connect(func(val: float) -> void:
		if busy:
			return
		var sid := str(_range_ctx.get("sid", ""))
		if sid == "basic":
			return
		var d: Dictionary = data.get_skill(sid)
		if not d.is_empty():
			d["cd"] = int(val)
			_mark_dirty())
	cdrow.add_child(range_cd_spin)
	var reset_btn := THEME.button("恢复默认形状", 13)
	reset_btn.pressed.connect(func() -> void:
		if cur_key == "":
			return
		var sid := str(_range_ctx.get("sid", ""))
		var owner := str(_range_ctx.get("owner", ""))
		var er: Dictionary = data.generals[owner].get("ed_ranges", {})
		er.erase(sid)
		_mark_dirty()
		_refresh_range_page()
		status("已恢复「%s」的默认范围" % ("普攻" if sid == "basic" else data.skill_name(sid))))
	cdrow.add_child(reset_btn)
	range_info = THEME.label("", 12, THEME.MUTED)
	range_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(range_info)
	return root
func _fn_both(fn: Callable) -> void:
	fn.call(cast_grid)
	fn.call(effect_grid)
func _on_range_changed(_which: String) -> void:
	if busy or cur_key == "":
		return
	var owner := str(_range_ctx.get("owner", ""))
	if owner == "" or not data.generals.has(owner):
		return
	var sid := str(_range_ctx.get("sid", "basic"))
	# layer 可能是 int 也可能是 String，统一取数字再转字符串
	var layer := str(int(_range_ctx.get("layer", 1)))
	var g: Dictionary = data.generals[owner]
	if not (g.get("ed_ranges") is Dictionary):
		g["ed_ranges"] = {}
	var er: Dictionary = g["ed_ranges"]
	var entry = er.get(sid, {})
	if not (entry is Dictionary):
		entry = {}
	if sid == "basic":
		# 普攻形状：各等级独立存放（layer_1/2/3），area 只作为 Lv1 基准
		entry["layer_%s" % layer] = cast_grid.get_area_raw()
		if int(layer) == 1:
			entry["area"] = cast_grid.get_area_raw()
	else:
		# 技能范围：只改当前这一级的形状，绝不覆盖其它等级
		var layers: Dictionary = entry.get("layers", {}) if entry.get("layers") is Dictionary else {}
		layers["lv_%s" % layer] = {"cast": cast_grid.get_area_raw(), "area": effect_grid.get_area_raw()}
		entry["layers"] = layers
		# 顶层 cast/area 仅作为「Lv1 基准」，只有编辑 Lv1 时才同步
		if int(layer) == 1:
			entry["cast"] = cast_grid.get_area_raw()
			entry["area"] = effect_grid.get_area_raw()
		entry["cd"] = int(range_cd_spin.value)
	er[sid] = entry
	g["ed_ranges"] = er
	_mark_dirty()
	_update_range_info()
func _refresh_range_page() -> void:
	if cast_grid == null:
		return
	if data == null or data.order.is_empty():
		return
	busy = true
	# owner 必须是有效武将，否则回退到当前武将/第一个
	var owner0 := str(_range_ctx.get("owner", ""))
	if owner0 == "" or not data.generals.has(owner0):
		owner0 = cur_key if data.generals.has(cur_key) else data.order[0]
		_range_ctx["owner"] = owner0
	range_owner_opt.clear()
	var idx := 0
	for i in data.order.size():
		var k := data.order[i]
		range_owner_opt.add_item(data.name_of(k))
		if k == owner0:
			idx = i
	range_owner_opt.selected = idx
	var owner := owner0
	var g: Dictionary = data.generals.get(owner, {})
	range_skill_opt.clear()
	range_skill_opt.add_item("普攻（射程形状）")
	for sid in (g.get("skills", []) as Array):
		range_skill_opt.add_item("%s%s" % [data.skill_name(String(sid)),
			"（被动）" if String(data.get_skill(String(sid)).get("kind", "")) == "passive" else ""])
	var sid := str(_range_ctx.get("sid", ""))
	var sids: Array = g.get("skills", [])
	var si := sids.find(sid)
	range_skill_opt.selected = 0 if (sid == "basic" or si < 0) else si + 1
	if si < 0 and sid != "basic":
		_range_ctx["sid"] = "basic"
		sid = "basic"
	var layer := int(_range_ctx["layer"])
	for i in range_layer_btns.keys():
		(range_layer_btns[i] as Button).button_pressed = int(i) == layer
	var er: Dictionary = g.get("ed_ranges", {})
	var entry: Dictionary = er.get(sid, {})
	if sid == "basic":
		var area: Array = []
		# 普攻形状：按层级向下继承（Lv2 画的 2/3 级共用）
		if entry.has("layer_%d" % layer):
			area = RULEZ.parse_area(entry["layer_%d" % layer])
		else:
			for L in [3, 2, 1]:
				if int(L) <= layer and entry.has("layer_%d" % L):
					area = RULEZ.parse_area(entry["layer_%d" % L])
					break
			if area.is_empty() and entry.has("area"):
				area = RULEZ.parse_area(entry["area"])
		if area.is_empty():
			area = RULEZ.diamond(int((g.get("stats", {}) as Dictionary).get("range", 1)))
		cast_grid.set_area(area)
		effect_grid.set_area([Vector2i.ZERO])
		effect_grid.modulate = Color(1, 1, 1, 0.25)
		range_cd_spin.editable = false
	else:
		var d: Dictionary = data.get_skill(sid)
		var layers: Dictionary = entry.get("layers", {}) if entry.get("layers") is Dictionary else {}
		var cast_a: Array = []
		var area_a: Array = []
		# 取 ≤ 当前层 的最高一层（向下继承）
		var best := -1
		for k in layers.keys():
			var n := int(String(k).replace("lv_", ""))
			if n <= layer and n > best and layers[k] is Dictionary:
				best = n
		if best > 0:
			var lyr: Dictionary = layers["lv_%d" % best]
			if lyr.has("cast"):
				cast_a = RULEZ.parse_area(lyr["cast"])
			if lyr.has("area"):
				area_a = RULEZ.parse_area(lyr["area"])
		if cast_a.is_empty():
			cast_a = RULEZ.parse_area(entry["cast"]) if entry.has("cast") else _default_cast(sid, d, layer)
		if area_a.is_empty():
			area_a = RULEZ.parse_area(entry["area"]) if entry.has("area") else _default_area(sid, d, layer)
		cast_grid.set_area(cast_a)
		effect_grid.set_area(area_a)
		effect_grid.modulate = Color(1, 1, 1, 1)
		range_cd_spin.editable = true
		range_cd_spin.value = int(d.get("cd", 0))
	busy = false
	_update_range_info()
func _gray_default_hint(_on: bool) -> void:
	pass
func _default_cast(sid: String, d: Dictionary, layer: int) -> Array:
	if d.has("ed_layers"):
		var layers: Dictionary = d["ed_layers"]
		var lk := "lv_%d" % layer
		if layers.has(lk) and (layers[lk] as Dictionary).has("cast"):
			return RULEZ.parse_area((layers[lk] as Dictionary)["cast"])
	if d.has("cast"):
		return RULEZ.parse_area(d["cast"])
	return RULEZ.diamond(maxi(1, int(d.get("range", 1))))
func _default_area(sid: String, d: Dictionary, layer: int) -> Array:
	if d.has("ed_layers"):
		var layers: Dictionary = d["ed_layers"]
		var lk := "lv_%d" % layer
		if layers.has(lk) and (layers[lk] as Dictionary).has("area"):
			return RULEZ.parse_area((layers[lk] as Dictionary)["area"])
	if d.has("area"):
		return RULEZ.parse_area(d["area"])
	var r := int(d.get("radius", 0))
	return RULEZ.diamond(r) if r > 0 else [Vector2i.ZERO]
func _update_range_info() -> void:
	if range_info == null:
		return
	var owner := str(_range_ctx.get("owner", ""))
	var sid := str(_range_ctx.get("sid", ""))
	var g: Dictionary = data.generals.get(owner, {})
	var er: Dictionary = g.get("ed_ranges", {})
	var entry: Dictionary = er.get(sid, {})
	var has_override := not entry.is_empty()
	var cast_n := cast_grid.get_area().size()
	var area_n := effect_grid.get_area().size()
	var reach := RULEZ.area_radius(cast_grid.get_area())
	range_info.text = "当前：%s · %s · Lv%d　释放格 %d　作用格 %d　最远释放 %d 格　%s" % [
		data.name_of(owner), "普攻" if sid == "basic" else data.skill_name(sid),
		int(_range_ctx["layer"]), cast_n, area_n, reach,
		"（已自定义）" if has_override else "（默认形状）"]
func _range_summary(sid: String) -> String:
	if cur_key == "":
		return ""
	var g: Dictionary = data.generals[cur_key]
	var er: Dictionary = g.get("ed_ranges", {})
	if sid != "basic" and er.has(sid):
		var e: Dictionary = er[sid]
		var cast_a: Array = RULEZ.parse_area(e.get("cast", []))
		var area_a: Array = RULEZ.parse_area(e.get("area", []))
		return "自定义范围：释放 %d 格（最远 %d），作用 %d 格" % [cast_a.size(), RULEZ.area_radius(cast_a), area_a.size()]
	if sid == "basic" and er.has("basic"):
		return "自定义普攻形状：%d 格" % RULEZ.parse_area((er["basic"] as Dictionary).get("area", [])).size()
	return "范围：使用默认形状（可在「⑧ 技能范围」页自定义）"
# ------------------------------------------------------------
# ⑨ 头像 / 立绘 / 精灵图
# ------------------------------------------------------------
# ------------------------------------------------------------
# 头像 / 立绘：导入（对话框或拖放）→ 复制进 assets/imported → 立即刷新预览
# ------------------------------------------------------------
func _drag_nothing(_a: Vector2) -> Variant:
	return null
func _can_drop_file(_pos: Vector2, drop: Variant) -> bool:
	if not (drop is Dictionary) or not (drop as Dictionary).has("files"):
		return false
	for f in (drop as Dictionary)["files"]:
		if String(f).to_lower().get_extension() in ["png", "jpg", "jpeg", "webp", "bmp"]:
			return true
	return false
func _drop_portrait(_pos: Vector2, drop: Variant) -> void:
	for f in (drop as Dictionary)["files"]:
		_apply_art_import(String(f), "portrait")
		return
func _drop_illust(_pos: Vector2, drop: Variant) -> void:
	for f in (drop as Dictionary)["files"]:
		_apply_art_import(String(f), "illust")
		return
func _import_art(kind: String, path_override: String = "") -> void:
	if cur_key == "":
		status("请先在左侧选中一名武将")
		return
	if path_override != "":
		_apply_art_import(path_override, kind)
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = "选择%s" % ("头像" if kind == "portrait" else "立绘")
	dlg.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.svg ; 图片"])
	dlg.use_native_dialog = false
	add_child(dlg)
	dlg.file_selected.connect(func(path: String) -> void:
		_apply_art_import(path, kind)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered_ratio(0.7)
func _apply_art_import(path: String, kind: String) -> void:
	if cur_key == "":
		return
	var r := data.import_art(path, kind, cur_key)
	if not bool(r.get("ok", false)):
		status("✖ " + String(r.get("msg", "导入失败")))
		return
	var res := String(r["res"])
	var art: Dictionary = data.generals[cur_key]["ed_art"]
	art["%s_path" % kind] = res
	if kind == "portrait":
		data.generals[cur_key]["portrait"] = res
	_mark_dirty()
	# 立即刷新预览（不依赖重新选中）
	var tex := _load_tex(res)
	if kind == "portrait":
		if portrait_tex != null:
			portrait_tex.texture = tex
		if art_portrait_tex != null:
			art_portrait_tex.texture = tex
	elif kind == "illust":
		if illust_tex != null:
			illust_tex.texture = tex
		if art_illust_tex != null:
			art_illust_tex.texture = tex
	_refresh_library()
	status("✔ " + String(r.get("msg", "已导入")))
func _clear_art() -> void:
	if cur_key == "":
		return
	data.generals[cur_key]["portrait"] = ""
	var art: Dictionary = data.generals[cur_key]["ed_art"]
	art["portrait_path"] = ""
	art["illust_path"] = ""
	_mark_dirty()
	if portrait_tex != null:
		portrait_tex.texture = null
	if illust_tex != null:
		illust_tex.texture = null
	if art_portrait_tex != null:
		art_portrait_tex.texture = null
	if art_illust_tex != null:
		art_illust_tex.texture = null
	status("已清空头像 / 立绘")
# 贴图加载：新导入的图直接解码，不依赖 Godot 是否已导入
func _load_tex(path: String) -> Texture2D:
	if path == "" or data == null:
		return null
	var tex: Texture2D = data.load_tex(path)
	if tex != null:
		return tex
	# 图片文件不存在（例如美术素材未随仓库分发）→ 返回占位图，避免界面空白
	return _placeholder_tex()


# 生成一张「图片未找到」占位图（程序绘制，无版权问题）
var _ph_tex: Texture2D = null
func _placeholder_tex() -> Texture2D:
	if _ph_tex != null:
		return _ph_tex
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.15, 0.20, 1.0))
	# 画一个虚线边框
	var c := Color(0.35, 0.40, 0.50, 1.0)
	for x in w:
		if (x / 8) % 2 == 0:
			img.set_pixel(x, 0, c)
			img.set_pixel(x, h - 1, c)
	for y in h:
		if (y / 8) % 2 == 0:
			img.set_pixel(0, y, c)
			img.set_pixel(w - 1, y, c)
	# 画一个斜杠表示「缺失」
	for i in range(1, h - 1):
		var x2: int = int(float(i) * float(w - 1) / float(h - 1))
		if x2 >= 0 and x2 < w:
			img.set_pixel(x2, i, c)
			if x2 + 1 < w:
				img.set_pixel(x2 + 1, i, c)
	_ph_tex = ImageTexture.create_from_image(img)
	return _ph_tex

func _art_slot(parent: HBoxContainer, title: String, sz: Vector2) -> TextureRect:
	var v := VBoxContainer.new()
	v.add_child(THEME.label(title, 13, THEME.MUTED))
	var p := PanelContainer.new()
	var t := TextureRect.new()
	t.custom_minimum_size = sz
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.add_child(t)
	v.add_child(p)
	parent.add_child(v)
	return t
func _page_art() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "图片"
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	# ============ 预览 / 播放面板（自包含：画面 + 控制同屏） ============
	var s_play := _section("动作预览与播放（预览画面就在控制按钮下方，同屏可见）",
		"选中动作后点「播放」即可看到动画：待机/移动按设定循环，攻击/受击播一次后停住；下面一排小图是逐帧预览，点某帧可停住查看。")
	v.add_child(s_play)
	# 控制行
	var ctl_row := HBoxContainer.new()
	ctl_row.add_theme_constant_override("separation", 6)
	s_play.add_child(ctl_row)
	var pb_big := THEME.button("▶ 播放所选动作", 14)
	pb_big.pressed.connect(_play_slot_anim)
	ctl_row.add_child(pb_big)
	var pb_all := THEME.button("▶ 播放全部动作", 13)
	pb_all.pressed.connect(_play_all_anims)
	ctl_row.add_child(pb_all)
	var pb_stop := THEME.button("■ 停止", 13)
	pb_stop.pressed.connect(_stop_anim_play)
	ctl_row.add_child(pb_stop)
	ctl_row.add_child(THEME.label("预览帧", 12, THEME.MUTED))
	# 复用同一个帧号控件：若还没建则建；否则只在页面尾部创建一次
	if anim_frame_idx == null:
		anim_frame_idx = SpinBox.new()
	anim_frame_idx.min_value = 0
	anim_frame_idx.max_value = 63
	# 避免重复绑定信号
	if not anim_frame_idx.is_connected("value_changed", Callable(self, "_on_anim_frame_idx")):
		anim_frame_idx.value_changed.connect(_on_anim_frame_idx)
	ctl_row.add_child(anim_frame_idx)
	var play_panel := HBoxContainer.new()
	play_panel.add_theme_constant_override("separation", 14)
	s_play.add_child(play_panel)
	# 大预览
	var big_col := VBoxContainer.new()
	big_col.add_theme_constant_override("separation", 4)
	play_panel.add_child(big_col)
	big_col.add_child(THEME.label("实时预览", 13, THEME.MUTED))
	var big_bg := PanelContainer.new()
	var big_t := TextureRect.new()
	big_t.custom_minimum_size = Vector2(140, 140)
	big_t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big_t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big_t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	big_t.name = "sprite_big"
	big_bg.add_child(big_t)
	big_col.add_child(big_bg)
	art_sprite_tex = big_t
	anim_play_state = THEME.label("", 12, THEME.GOOD)
	big_col.add_child(anim_play_state)
	# 逐帧缩略
	var strip_col := VBoxContainer.new()
	strip_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_col.add_theme_constant_override("separation", 4)
	play_panel.add_child(strip_col)
	strip_col.add_child(THEME.label("逐帧预览（点击某帧可停在该帧）", 13, THEME.MUTED))
	var strip_sc := ScrollContainer.new()
	strip_sc.custom_minimum_size = Vector2(0, 96)
	strip_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	strip_col.add_child(strip_sc)
	anim_strip = HBoxContainer.new()
	anim_strip.add_theme_constant_override("separation", 4)
	strip_sc.add_child(anim_strip)
	var s := _section("头像 / 立绘 / 精灵图（可导入自己的图片）",
		"支持 PNG / JPG / WEBP / BMP / SVG。导入后会复制到项目 res://assets/imported/ 下，随工程一起带走；导出给游戏时可选择同时拷出图片。")
	v.add_child(s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	art_portrait_tex = _art_slot(row, "头像 portrait", Vector2(120, 120))
	art_illust_tex = _art_slot(row, "立绘 illust", Vector2(150, 200))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	v.add_child(row2)
	var b1 := THEME.button("导入头像…", 13)
	b1.pressed.connect(func() -> void: _import_art("portrait"))
	row2.add_child(b1)
	var b2 := THEME.button("导入立绘…", 13)
	b2.pressed.connect(func() -> void: _import_art("illust"))
	row2.add_child(b2)
	var b4 := THEME.button("清除头像/立绘", 13)
	b4.pressed.connect(_clear_art)
	row2.add_child(b4)
	# ---------------- 动作动画（按《像素武将角色动画接入说明》） ----------------
	var s_anim := _section("动作动画：三张图 + 按帧号定义动作（下 / 左 / 右 / 上）",
		"按旧游戏的接入说明：atk64 = 12 帧（1-4 正面 / 5-8 背面 / 9-12 侧面，右侧用镜像）；" +
		"mov64 = 11 帧（1-2 正走 / 3-4 背走 / 5-6 侧走 / 7 正待机 / 8 背待机 / 9 侧待机 / 10-11 受伤）；" +
		"spc64 = 5 张单帧（1-3 防守 / 4 受击 / 5 升级）。帧号从 1 开始、自上而下。")
	v.add_child(s_anim)
	# 三张图导入
	var sheet_row := HBoxContainer.new()
	sheet_row.add_theme_constant_override("separation", 10)
	s_anim.add_child(sheet_row)
	for spec in [["atk", "攻击图 atk64"], ["mov", "移动图 mov64"], ["spc", "特殊图 spc64"]]:
		var sk := String(spec[0])
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		sheet_row.add_child(col)
		var lb := THEME.label(String(spec[1]), 13, THEME.ACCENT)
		col.add_child(lb)
		var thumb := TextureRect.new()
		thumb.custom_minimum_size = Vector2(56, 96)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumb.name = "thumb_" + sk
		var pc := PanelContainer.new()
		pc.add_child(thumb)
		col.add_child(pc)
		var b := THEME.button("导入…", 12)
		b.pressed.connect(func() -> void: _import_sheet(sk))
		col.add_child(b)
		var st := THEME.label("", 11, THEME.MUTED)
		st.name = "state_" + sk
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(st)
		anim_sheet_ui[sk] = {"tex": thumb, "state": st}
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	s_anim.add_child(tool_row)
	var b_import_slot := THEME.button("仅导入当前动作的图…", 13)
	b_import_slot.tooltip_text = "只替换选中动作所用的那张图（atk / mov / spc 之一）"
	b_import_slot.pressed.connect(_import_anim_slot)
	tool_row.add_child(b_import_slot)
	var b_legacy := THEME.button("从旧素材目录一次导入 atk/mov/spc…", 13)
	b_legacy.pressed.connect(_import_legacy_sheet)
	tool_row.add_child(b_legacy)
	var b_reset := THEME.button("恢复说明默认帧表", 13)
	b_reset.pressed.connect(func() -> void:
		if cur_key == "":
			return
		data.reset_anim_spec(data.generals[cur_key])
		_mark_dirty()
		_refresh_anim_matrix()
		status("已恢复旧说明的默认帧号表"))
	tool_row.add_child(b_reset)
	var fw_lbl := THEME.label("帧宽", 12, THEME.MUTED)
	tool_row.add_child(fw_lbl)
	var fw_sp := SpinBox.new()
	fw_sp.min_value = 8
	fw_sp.max_value = 512
	fw_sp.custom_minimum_size = Vector2(80, 0)
	fw_sp.value_changed.connect(func(v: float) -> void:
		if cur_key == "" or busy:
			return
		data.generals[cur_key]["ed_art"]["frame_w"] = int(v)
		_mark_dirty()
		_refresh_anim_matrix())
	tool_row.add_child(fw_sp)
	anim_frame_w_spin = fw_sp
	var fh_lbl := THEME.label("帧高", 12, THEME.MUTED)
	tool_row.add_child(fh_lbl)
	var fh_sp := SpinBox.new()
	fh_sp.min_value = 8
	fh_sp.max_value = 512
	fh_sp.custom_minimum_size = Vector2(80, 0)
	fh_sp.value_changed.connect(func(v: float) -> void:
		if cur_key == "" or busy:
			return
		data.generals[cur_key]["ed_art"]["frame_h"] = int(v)
		_mark_dirty()
		_refresh_anim_matrix())
	tool_row.add_child(fh_sp)
	anim_frame_h_spin = fh_sp
	# 动作 × 朝向 表格（显示帧号与所在图）
	anim_matrix = VBoxContainer.new()
	anim_matrix.add_theme_constant_override("separation", 4)
	s_anim.add_child(anim_matrix)
	# 选中动作的参数
	var slot_box := VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 4)
	slot_box.name = "slot_box"
	s_anim.add_child(slot_box)
	anim_slot_title = THEME.label("", 14, THEME.ORANGE)
	slot_box.add_child(anim_slot_title)
	var param_row := HBoxContainer.new()
	param_row.add_theme_constant_override("separation", 8)
	slot_box.add_child(param_row)
	param_row.add_child(THEME.label("所用图片", 13, THEME.MUTED))
	anim_sheet_opt = OptionButton.new()
	anim_sheet_opt.add_item("攻击图 atk64", 0)
	anim_sheet_opt.add_item("移动图 mov64", 1)
	anim_sheet_opt.add_item("特殊图 spc64", 2)
	anim_sheet_opt.item_selected.connect(func(i: int) -> void:
		var a := _cur_slot_anim()
		a["sheet"] = ["atk", "mov", "spc"][i]
		_save_slot_anim(a)
		_refresh_anim_params())
	param_row.add_child(anim_sheet_opt)
	anim_frames_edit = LineEdit.new()
	anim_frames_edit.custom_minimum_size = Vector2(150, 0)
	anim_frames_edit.placeholder_text = "帧号，如 1,2,3,4"
	anim_frames_edit.text_changed.connect(func(t: String) -> void:
		if cur_key == "" or busy:
			return
		var a := _cur_slot_anim()
		var arr: Array = []
		for part in t.replace("，", ",").split(",", false):
			var n := int(part.strip_edges())
			if n >= 1:
				arr.append(n)
		if arr.is_empty():
			return
		a["frames"] = arr
		_save_slot_anim(a)
		_refresh_anim_params())
	param_row.add_child(THEME.label("帧号", 13, THEME.MUTED))
	param_row.add_child(anim_frames_edit)
	param_row.add_child(THEME.label("帧率", 13, THEME.MUTED))
	var fps_sp := SpinBox.new()
	fps_sp.min_value = 1
	fps_sp.max_value = 60
	fps_sp.custom_minimum_size = Vector2(90, 0)
	fps_sp.value_changed.connect(func(v: float) -> void:
		if cur_key == "" or busy:
			return
		var a := _cur_slot_anim()
		a["fps"] = v
		_save_slot_anim(a))
	param_row.add_child(fps_sp)
	anim_fps_spin = fps_sp
	var loop_cb := CheckBox.new()
	loop_cb.text = "循环"
	loop_cb.toggled.connect(func(on: bool) -> void:
		if cur_key == "" or busy:
			return
		var a := _cur_slot_anim()
		a["loop"] = on
		_save_slot_anim(a))
	param_row.add_child(loop_cb)
	anim_loop_cb = loop_cb
	var mirror_cb := CheckBox.new()
	mirror_cb.text = "水平镜像（右侧用左侧图）"
	mirror_cb.toggled.connect(func(on: bool) -> void:
		if cur_key == "" or busy:
			return
		var a := _cur_slot_anim()
		a["mirror"] = on
		_save_slot_anim(a))
	param_row.add_child(mirror_cb)
	anim_mirror_cb = mirror_cb
	anim_slot_info = THEME.label("", 12, THEME.MUTED)
	anim_slot_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_box.add_child(anim_slot_info)
	var s3 := _section("已导入的素材库")
	v.add_child(s3)
	var lib_box := VBoxContainer.new()
	lib_box.name = "lib_box"
	lib_box.add_theme_constant_override("separation", 2)
	s3.add_child(lib_box)
	return sc
func _sel_slot() -> String:
	return "%s_%s" % [String(art_sel.get("act", "idle")), String(art_sel.get("dir", "down"))]
func _cur_slot_anim() -> Dictionary:
	if cur_key == "":
		return EdData.empty_anim()
	return data.get_anim(data.generals[cur_key], _sel_slot())
func _slot_sheet_path(act: String, dir: String) -> String:
	if cur_key == "":
		return ""
	var a := data.get_anim(data.generals[cur_key], "%s_%s" % [act, dir])
	return data.sheet_path(data.generals[cur_key], String(a.get("sheet", "mov")))
func _save_slot_anim(a: Dictionary) -> void:
	if cur_key == "":
		return
	data.set_anim(data.generals[cur_key], _sel_slot(), a)
	_mark_dirty()
	_refresh_anim_matrix(false)
func _refresh_anim_matrix(rebuild: bool = true) -> void:
	if anim_matrix == null:
		return
	if rebuild:
		for c in anim_matrix.get_children():
			c.queue_free()
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		anim_matrix.add_child(head)
		var h0 := THEME.label("动作＼朝向", 12, THEME.MUTED)
		h0.custom_minimum_size = Vector2(88, 0)
		head.add_child(h0)
		for d in RULEZ.DIRS:
			var hl := THEME.label(RULEZ.DIR_LABELS.get(d, d), 13, THEME.ACCENT)
			hl.custom_minimum_size = Vector2(150, 0)
			head.add_child(hl)
		for act in RULEZ.ACTIONS:
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 4)
			anim_matrix.add_child(r)
			var al := THEME.label(String(RULEZ.ACTION_LABELS.get(act, act)), 13, THEME.TEXT)
			al.custom_minimum_size = Vector2(88, 0)
			r.add_child(al)
			for d in RULEZ.DIRS:
				var slot := "%s_%s" % [act, d]
				var has := _slot_sheet_path(act, d) != ""
				var a: Dictionary = data.get_anim(data.generals[cur_key], slot) if cur_key != "" else {}
				var frv = a.get("frames", [])
				var fr: Array = frv if frv is Array else []
				var fs := ""
				for i in mini(4, fr.size()):
					fs += ("," if i > 0 else "") + str(int(fr[i]))
				if fr.size() > 4:
					fs += "…"
				var sh := String(a.get("sheet", "mov"))
				var bt := THEME.button("%s%s %s [%s]" % ["●" if has else "○", fs, String(RULEZ.DIR_ARROWS.get(d, "")), sh.to_upper()], 11, 146)
				bt.toggle_mode = true
				bt.button_pressed = (slot == _sel_slot())
				bt.tooltip_text = "点击选中「%s·%s」，帧号 %s（%s）" % [
					RULEZ.ACTION_LABELS.get(act, act), RULEZ.DIR_LABELS.get(d, d), str(fr),
					RULEZ.SHEET_LABELS.get(sh, sh)]
				if has:
					bt.add_theme_color_override("font_color", THEME.GOOD)
				else:
					bt.add_theme_color_override("font_color", Color("#5b6b85"))
				bt.pressed.connect(func() -> void:
					art_sel["act"] = act
					art_sel["dir"] = d
					_refresh_anim_matrix())
				r.add_child(bt)
	# 三张图的缩略与状态
	if cur_key != "":
		var art: Dictionary = data.generals[cur_key]["ed_art"]
		busy = true
		if anim_frame_w_spin != null:
			anim_frame_w_spin.value = int(art.get("frame_w", 64))
		if anim_frame_h_spin != null:
			anim_frame_h_spin.value = int(art.get("frame_h", 64))
		busy = false
		for sk in anim_sheet_ui.keys():
			var ui: Dictionary = anim_sheet_ui[sk]
			var p := data.sheet_path(data.generals[cur_key], sk)
			(ui["tex"] as TextureRect).texture = _load_tex(p) if p != "" else null
			var fw := int(art.get("frame_w", 64))
			var fh := int(art.get("frame_h", 64))
			var total := 0
			var tex := _load_tex(p) if p != "" else null
			if tex != null:
				total = maxi(1, (tex.get_width() / maxi(1, fw)) * (tex.get_height() / maxi(1, fh)))
			(ui["state"] as Label).text = ("%d 帧" % total) if p != "" else "未导入"
	_refresh_anim_params()
func _refresh_anim_params() -> void:
	var a := _cur_slot_anim()
	var act := String(art_sel.get("act", "idle"))
	var d := String(art_sel.get("dir", "down"))
	if anim_slot_title != null:
		anim_slot_title.text = "所选动作：%s · %s方向（%s）" % [
			RULEZ.ACTION_LABELS.get(act, act), RULEZ.DIR_LABELS.get(d, d), _sel_slot()]
	busy = true
	if anim_sheet_opt != null:
		anim_sheet_opt.selected = maxi(0, ["atk", "mov", "spc"].find(String(a.get("sheet", "mov"))))
	var frv = a.get("frames", [])
	var fr: Array = frv if frv is Array else []
	var parts: Array = []
	for x in fr:
		parts.append(str(int(x)))
	if anim_frames_edit != null:
		anim_frames_edit.text = ",".join(parts)
	if anim_fps_spin != null:
		anim_fps_spin.value = float(a.get("fps", 8.0))
	if anim_loop_cb != null:
		anim_loop_cb.button_pressed = bool(a.get("loop", true))
	if anim_mirror_cb != null:
		anim_mirror_cb.button_pressed = bool(a.get("mirror", false))
	busy = false
	if anim_frame_idx != null:
		anim_frame_idx.max_value = maxi(0, fr.size() - 1)
	if anim_slot_info != null:
		var sheet := String(a.get("sheet", "mov"))
		var p := data.sheet_path(data.generals[cur_key], sheet) if cur_key != "" else ""
		var base := "所用图片：%s（%s）　帧号 %s　%.0f fps　%s%s" % [
			RULEZ.SHEET_LABELS.get(sheet, sheet), p.get_file() if p != "" else "未导入",
			str(fr), float(a.get("fps", 8.0)), "循环" if bool(a.get("loop", true)) else "播放一次",
			"　水平镜像" if bool(a.get("mirror", false)) else ""]
		anim_slot_info.text = base
	_rebuild_anim_strip()
	_refresh_anim_preview()
	if _anim_playing:
		_play_slot_anim()
# 帧号（1-based）→ 图上区域
func _anim_frame_region(a: Dictionary) -> Rect2:
	var art: Dictionary = data.generals[cur_key]["ed_art"]
	var fw := maxi(1, int(art.get("frame_w", 64)))
	var fh := maxi(1, int(art.get("frame_h", 64)))
	var frv = a.get("frames", [1])
	var fr: Array = frv if frv is Array else [1]
	var idx := int(anim_frame_idx.value) if anim_frame_idx != null else 0
	idx = clampi(idx, 0, maxi(0, fr.size() - 1))
	var frame_no := int(fr[idx]) if idx < fr.size() else 1
	var p := data.sheet_path(data.generals[cur_key], String(a.get("sheet", "mov")))
	var tex := _load_tex(p) if p != "" else null
	var cols := 1
	if tex != null:
		cols = maxi(1, tex.get_width() / fw)
	var zero := maxi(0, frame_no - 1)
	return Rect2((zero % cols) * fw, (zero / cols) * fh, fw, fh)
func _refresh_anim_preview() -> void:
	_show_anim_frame(int(anim_frame_idx.value) if anim_frame_idx != null else 0)
func _on_anim_frame_idx(v: float) -> void:
	if _anim_playing:
		return
	_show_anim_frame(int(v))
func _show_anim_frame(_i: int) -> void:
	if art_sprite_tex == null or cur_key == "":
		return
	var a := _cur_slot_anim()
	var p := data.sheet_path(data.generals[cur_key], String(a.get("sheet", "mov")))
	var tex := _load_tex(p) if p != "" else null
	if tex == null:
		art_sprite_tex.texture = null
		return
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = _anim_frame_region(a)
	art_sprite_tex.texture = at
	# 逐帧缩略图高亮
	if anim_strip != null:
		for i in anim_strip.get_child_count():
			var c = anim_strip.get_child(i)
			if c is Button:
				(c as Button).button_pressed = (i == int(anim_frame_idx.value))
# 逐帧缩略图：把当前动作的每一帧都画成小图
func _rebuild_anim_strip() -> void:
	if anim_strip == null or cur_key == "":
		return
	for c in anim_strip.get_children():
		c.queue_free()
	var a := _cur_slot_anim()
	var p := data.sheet_path(data.generals[cur_key], String(a.get("sheet", "mov")))
	var tex := _load_tex(p) if p != "" else null
	var frv = a.get("frames", [])
	var fr: Array = frv if frv is Array else []
	if tex == null or fr.is_empty():
		anim_strip.add_child(THEME.label("（没有可预览的帧）", 12, THEME.MUTED))
		return
	var art: Dictionary = data.generals[cur_key]["ed_art"]
	var fw := maxi(1, int(art.get("frame_w", 64)))
	var fh := maxi(1, int(art.get("frame_h", 64)))
	var cols := maxi(1, tex.get_width() / fw)
	for i in fr.size():
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(76, 96)
		b.tooltip_text = "第 %d 帧（帧号 %d）" % [i + 1, int(fr[i])]
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_bottom = -18
		var at := AtlasTexture.new()
		at.atlas = tex
		var zero := maxi(0, int(fr[i]) - 1)
		at.region = Rect2((zero % cols) * fw, (zero / cols) * fh, fw, fh)
		tr.texture = at
		b.add_child(tr)
		var lb := THEME.label("%d" % (i + 1), 11, THEME.MUTED)
		lb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		lb.offset_top = -18
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(lb)
		var idx := i
		b.pressed.connect(func() -> void:
			_stop_anim_play()
			anim_frame_idx.value = idx
			_show_anim_frame(idx))
		anim_strip.add_child(b)
# ---------------- 播放循环（由 _process 驱动，循环动作会一直播） ----------------
var _anim_playing := false
var _anim_accum := 0.0
var _anim_idx := 0
func _play_slot_anim() -> void:
	if cur_key == "":
		return
	var a := _cur_slot_anim()
	var frv = a.get("frames", [])
	var fr: Array = frv if frv is Array else []
	if fr.is_empty():
		return
	_anim_playing = true
	_anim_idx = 0
	_anim_accum = 0.0
	if anim_play_state != null:
		anim_play_state.text = "▶ 正在播放：%s · %s方向" % [
			RULEZ.ACTION_LABELS.get(String(art_sel.get("act", "idle")), ""),
			RULEZ.DIR_LABELS.get(String(art_sel.get("dir", "down")), "")]
func _stop_anim_play() -> void:
	_anim_playing = false
	if anim_play_state != null:
		anim_play_state.text = "■ 已停止"
func _process(delta: float) -> void:
	if not _anim_playing or cur_key == "" or anim_frame_idx == null:
		return
	var a := _cur_slot_anim()
	var frv = a.get("frames", [])
	var fr: Array = frv if frv is Array else []
	if fr.is_empty():
		_anim_playing = false
		return
	var fps := maxf(1.0, float(a.get("fps", 8.0)))
	_anim_accum += delta * fps
	if _anim_accum < 1.0:
		return
	_anim_accum = 0.0
	_anim_idx += 1
	if _anim_idx >= fr.size():
		if bool(a.get("loop", true)):
			_anim_idx = 0
		else:
			_anim_idx = fr.size() - 1
			_anim_playing = false
			if anim_play_state != null:
				anim_play_state.text = "■ 播放完毕（非循环）"
	anim_frame_idx.set_value_no_signal(float(_anim_idx))
	_show_anim_frame(_anim_idx)
func _play_all_anims() -> void:
	if cur_key == "":
		return
	# 依次切到每个有图的动作并播放
	var tw := create_tween()
	for act in RULEZ.ACTIONS:
		for d in RULEZ.DIRS:
			tw.tween_callback(func() -> void:
				art_sel["act"] = act
				art_sel["dir"] = d
				_refresh_anim_matrix(false)
				_play_slot_anim())
			tw.tween_interval(1.2)
func _import_sheet(sheet: String) -> void:
	if cur_key == "":
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = "导入%s" % RULEZ.SHEET_LABELS.get(sheet, sheet)
	dlg.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; 图片"])
	add_child(dlg)
	dlg.file_selected.connect(func(path: String) -> void:
		var art: Dictionary = data.generals[cur_key]["ed_art"]
		var res = data.import_sheet_to(path, cur_key, sheet, int(art.get("frame_w", 64)), int(art.get("frame_h", 64)))
		if bool(res.get("ok", false)):
			_mark_dirty()
			_refresh_anim_matrix()
		status(("✔ " if bool(res.get("ok", false)) else "✖ ") + String(res.get("msg", "")))
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered_ratio(0.7)
func _import_anim_slot() -> void:
	if cur_key == "":
		return
	var a := _cur_slot_anim()
	_import_sheet(String(a.get("sheet", "mov")))
func _import_legacy_sheet() -> void:
	if cur_key == "":
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = "选择 atk64.png / mov64.png / spc64.png 中的任意一张（多选可一次导入）"
	dlg.filters = PackedStringArray(["*.png ; PNG"])
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	add_child(dlg)
	dlg.files_selected.connect(func(paths: PackedStringArray) -> void:
		var res := data.import_all_sheets(Array(paths), cur_key)
		if bool(res.get("ok", false)):
			_mark_dirty()
			_refresh_anim_matrix()
		status(String(res.get("msg", "")))
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered_ratio(0.7)
# ------------------------------------------------------------
# ⑩ 扩展与补充
# ------------------------------------------------------------
func _page_ext() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "扩展"
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	v.add_child(THEME.label("扩展与补充项", 16, THEME.ACCENT))
	v.add_child(THEME.hint(
		"这些是常见战棋系统里还需要配置、但你原文没列全的项。已标注【生效】的会真实影响演算台与小战场；" +
		"标注【占位】的只保存/导出，等你确认规则后再接引擎。"))
	var s1 := _section("身份 / 稀有度 / 阵营")
	v.add_child(s1)
	var g1 := VBoxContainer.new()
	s1.add_child(g1)
	_ext_opt(g1, "性别", "gender", ["男", "女"])
	_ext_spin(g1, "品质（1~5）", "quality", 1, 5)
	_ext_line(g1, "阵营", "faction")
	_ext_line(g1, "称号 / 别名", "title")
	var s2 := _section("装备【占位】")
	v.add_child(s2)
	var g2 := VBoxContainer.new()
	s2.add_child(g2)
	_ext_line(g2, "武器", "weapon")
	_ext_line(g2, "防具", "armor")
	_ext_line(g2, "兵符 / 饰品", "accessory")
	_ext_line(g2, "武器特效说明", "weapon_effect")
	_ext_line(g2, "防具特效说明", "armor_effect")
	_ext_line(g2, "饰品特效说明", "accessory_effect")
	var s3 := _section("战斗系数【生效】")
	v.add_child(s3)
	var g3 := VBoxContainer.new()
	s3.add_child(g3)
	_ext_spin(g3, "附加暴击率 %", "crit_bonus", 0, 100, 0.01)
	_ext_spin(g3, "附加暴击伤害 %", "crit_damage", 0, 300, 0.01)
	_ext_spin(g3, "增伤 %", "damage_bonus", -100, 300, 0.01)
	_ext_spin(g3, "减伤 %", "damage_cut", 0, 90, 0.01)
	_ext_spin(g3, "移动力加成", "move_bonus", -5, 10)
	_ext_spin(g3, "释放距离加成", "reach_bonus", 0, 5)
	_ext_spin(g3, "士气", "morale", 0, 200)
	_ext_spin(g3, "技能威力系数", "skill_power", 0.1, 5, 0.05)
	var s4 := _section("AI 与表现【占位】")
	v.add_child(s4)
	var g4 := VBoxContainer.new()
	s4.add_child(g4)
	_ext_spin(g4, "AI 进攻权重", "ai_weight", 0, 5, 0.1)
	_ext_line(g4, "语音 / CV 资源", "voice")
	_ext_line(g4, "登场台词", "battle_quote")
	_ext_line(g4, "解锁条件", "unlock_text")
	var s5 := _section("被动效果开关【占位】",
		"勾选后保存到导出数据，供游戏侧按需实现（例如「可反击」「无视地形」）。")
	v.add_child(s5)
	var toggles := ["可反击", "无视地形", "飞行单位", "不可被合击", "死亡后复活一次", "免疫控制"]
	var trow := HFlowContainer.new()
	for t in toggles:
		var cb := CheckBox.new()
		cb.text = t
		cb.toggled.connect(func(on: bool) -> void:
			if cur_key == "" or busy:
				return
			data.generals[cur_key]["ed_ext"]["passive_toggles"][t] = on
			_mark_dirty())
		trow.add_child(cb)
		cb.name = "tg_" + t
	s5.add_child(trow)
	var s6 := _section("自定义字段【占位】",
		"写键=值，一行一条；会原样放进导出的 ed_ext.custom_fields，供你的游戏自定义读取。")
	v.add_child(s6)
	var cf := TextEdit.new()
	cf.custom_minimum_size = Vector2(0, 100)
	cf.name = "custom_fields"
	cf.text_changed.connect(func() -> void:
		if cur_key == "" or busy:
			return
		var d := {}
		for line in cf.text.split("\n"):
			if line.contains("="):
				var kv := line.split("=", true, 1)
				d[kv[0].strip_edges()] = kv[1].strip_edges()
		data.generals[cur_key]["ed_ext"]["custom_fields"] = d
		_mark_dirty())
	s6.add_child(cf)
	var s7 := _section("启用状态")
	v.add_child(s7)
	var en := CheckBox.new()
	en.text = "该武将参与导出与小战场"
	en.name = "enabled_cb"
	en.toggled.connect(func(on: bool) -> void:
		if cur_key == "" or busy:
			return
		data.generals[cur_key]["ed_enabled"] = on
		_mark_dirty()
		refresh_list())
	s7.add_child(en)
	return sc
func _ext_line(parent: Control, label: String, key: String) -> LineEdit:
	var e := LineEdit.new()
	e.text_changed.connect(func(t: String) -> void:
		if cur_key != "" and not busy:
			data.generals[cur_key]["ed_ext"][key] = t
			_mark_dirty())
	_form_row(parent, label, e)
	ext_widgets[key] = e
	return e
func _ext_spin(parent: Control, label: String, key: String, mn: float, mx: float, step: float = 1.0) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.custom_minimum_size = Vector2(110, 0)
	s.value_changed.connect(func(val: float) -> void:
		if cur_key != "" and not busy:
			var v := val
			if step < 1.0:
				v = val  # 已是小数
			data.generals[cur_key]["ed_ext"][key] = v
			_mark_dirty()
			if key in ["damage_bonus", "damage_cut", "crit_bonus", "move_bonus"]:
				_update_stat_preview())
	_form_row(parent, label, s)
	ext_widgets[key] = s
	return s
func _ext_opt(parent: Control, label: String, key: String, opts: Array) -> OptionButton:
	var o := OptionButton.new()
	for it in opts:
		o.add_item(String(it))
	o.item_selected.connect(func(i: int) -> void:
		if cur_key != "" and not busy:
			data.generals[cur_key]["ed_ext"][key] = String(opts[i])
			_mark_dirty())
	_form_row(parent, label, o)
	ext_widgets[key] = o
	return o
# ------------------------------------------------------------
# ⑪ 全局设定
# ------------------------------------------------------------
func _page_settings() -> Control:
	var sc := ScrollContainer.new()
	sc.name = "设定"
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	v.add_child(THEME.label("全局设定（对所有武将生效）", 16, THEME.ACCENT))
	v.add_child(THEME.hint("修改后点「💾 保存」写入 data/editor/settings.json，并随导出数据一起交给游戏。"))
	var s1 := _section("等级 / 星级上限")
	v.add_child(s1)
	var g1 := VBoxContainer.new()
	s1.add_child(g1)
	_set_spin(g1, "等级上限", "max_level", 1, 200)
	_set_spin(g1, "星级上限", "max_star", 1, 20)
	_set_spin(g1, "每星全属性 %", "star_stat_pct", 0, 100, 0.01, true)
	_set_spin(g1, "每星额外兵力", "star_hp_bonus", 0, 500)
	_set_spin(g1, "每星额外移动", "star_move", 0, 5)
	_set_spin(g1, "抽卡命中同名概率", "gacha_rate_same", 0, 1, 0.01)
	# ---------------- 升星规则 ----------------
	var s_star := _section("升星规则",
		"升星时各星做什么、消耗多少同名武将，都在这里。技能星/天赋星/属性星分别填星号。")
	v.add_child(s_star)
	var gs := VBoxContainer.new()
	s_star.add_child(gs)
	_set_text(gs, "技能升阶星（逗号分隔）", "star_rule_skill_stars", "2,3,4,6,7,9")
	_set_text(gs, "天赋升阶星（逗号分隔）", "star_rule_talent_stars", "5,10")
	_set_spin(gs, "属性加成比例 %", "star_rule_bonus_pct", 0, 200, 0.01, true)
	_set_sub_spin(gs, "每星消耗同名武将", "star_rule", "cost_per_star", 0, 20)
	# ---------------- 武将升级 = 升五维 ----------------
	var s_fg := _section("武将升级：五维成长",
		"武将每升 1 级，五维各 +N（可分别设置）。这些五维会参与「五维派生」（若开启）并影响魅力暴击/爆伤。")
	v.add_child(s_fg)
	var gfg := VBoxContainer.new()
	s_fg.add_child(gfg)
	_set_sub_spin(gfg, "武力 / 级", "five_growth", "wu", 0, 10)
	_set_sub_spin(gfg, "智力 / 级", "five_growth", "zhi", 0, 10)
	_set_sub_spin(gfg, "统率 / 级", "five_growth", "tong", 0, 10)
	_set_sub_spin(gfg, "政治 / 级", "five_growth", "zheng", 0, 10)
	_set_sub_spin(gfg, "魅力 / 级", "five_growth", "mei", 0, 10)
	_set_sub_spin(gfg, "五维上限", "five_growth", "cap", 1, 999)
	var s_au := _section("兵种升级（预留 · 默认不加属性）",
		"兵种升级的功效后续再设置。现在只保留等级与升级点数（点数上限 = min(五维和 × 系数, (等级-1) × 每级点数)）。" +
		"下面的「每点→」全部为 0 时，兵种升级不会改变任何面板数值。")
	v.add_child(s_au)
	var gau := VBoxContainer.new()
	s_au.add_child(gau)
	_set_sub_spin(gau, "兵种等级上限", "arm_upgrade", "max_lv", 1, 99)
	_set_sub_spin(gau, "五维系数", "arm_upgrade", "five_pool", 0, 5, 0.05)
	_set_sub_spin(gau, "每级点数", "arm_upgrade", "per_lv_points", 0, 10)
	_set_sub_spin(gau, "每点→兵力", "arm_upgrade", "point_hp", 0, 100)
	_set_sub_spin(gau, "每点→物攻", "arm_upgrade", "point_atk", 0, 20)
	_set_sub_spin(gau, "每点→物防", "arm_upgrade", "point_def", 0, 20)
	_set_sub_spin(gau, "每点→谋攻", "arm_upgrade", "point_matk", 0, 20)
	_set_sub_spin(gau, "每点→谋防", "arm_upgrade", "point_mdef", 0, 20)
	_set_sub_spin(gau, "每点→幸运", "arm_upgrade", "point_luck", 0, 20)
	_set_sub_spin(gau, "每 N 级 +1 移动（0=不加）", "arm_upgrade", "lv_move_every", 0, 50)
	_set_sub_spin(gau, "每 N 级 +1 射程（0=不加）", "arm_upgrade", "lv_range_every", 0, 50)
	var s2 := _section("兵种修正（面板系数 + 移动/射程加成）",
		"倍数类：兵力/物攻/物防/谋防；加减类：移动力、攻击范围（射程）。")
	v.add_child(s2)
	var g2 := GridContainer.new()
	g2.columns = 7
	s2.add_child(g2)
	g2.add_child(THEME.label("兵种", 12, THEME.MUTED))
	for h in ["兵力×", "物攻×", "物防×", "谋防×", "移动+", "射程+"]:
		g2.add_child(THEME.label(h, 12, THEME.MUTED))
	for arm in ["盾", "枪", "弓", "骑"]:
		g2.add_child(THEME.label(RULEZ.arm_name(arm), 13))
		for stat in ["hp", "atk", "def", "mdef", "move", "range"]:
			var sp := SpinBox.new()
			var additive: bool = stat in ["move", "range"]
			sp.min_value = -5 if additive else 0
			sp.max_value = 10 if additive else 5
			sp.step = 1 if additive else 0.05
			sp.custom_minimum_size = Vector2(76, 0)
			sp.value_changed.connect(func(val: float) -> void:
				RULEZ.settings["arm_mods"][arm][stat] = val
				_mark_dirty()
				_refresh_arm_info()
				_update_stat_preview()
				_update_growth_preview())
			g2.add_child(sp)
			set_widgets["arm_%s_%s" % [arm, stat]] = sp
	var s3 := _section("克制与暴击")
	v.add_child(s3)
	var g3 := VBoxContainer.new()
	s3.add_child(g3)
	_set_spin(g3, "克制增伤 %", "arm_counter_bonus", 0, 200, 0.01, true)
	_set_spin(g3, "被克减伤 %", "arm_counter_reduce", 0, 90, 0.01, true)
	_set_spin(g3, "每点魅力暴击率（幸运/运势已合并）", "crit_per_mei", 0, 0.05, 0.0005)
	_set_spin(g3, "暴击伤害倍率（基础）", "crit_damage", 1, 5, 0.05)
	_set_spin(g3, "每点魅力暴击伤害", "mei_crit_dmg_per", 0, 0.05, 0.001)
	_set_spin(g3, "伤害随机浮动 %", "damage_variance", 0, 50, 0.01, true)
	_set_spin(g3, "最低伤害", "min_damage", 0, 100)
	_set_spin(g3, "破防保底系数", "damage_floor_k", 0, 1, 0.01)
	_set_spin(g3, "普攻倍率", "mult_basic", 0, 5, 0.05)
	_set_spin(g3, "反击倍率", "mult_counter", 0, 3, 0.05)
	_set_spin(g3, "合击倍率", "mult_combo", 0, 3, 0.05)
	_set_spin(g3, "追击倍率", "mult_pursuit", 0, 3, 0.05)
	_set_spin(g3, "治疗系数默认", "heal_mult_default", 0, 5, 0.05)
	_set_spin(g3, "斗气每层增伤 %", "douqi_per_stack", 0, 50, 0.01, true)
	_set_spin(g3, "无双状态倍率", "wushuang_mult", 1, 3, 0.05)
	s3.add_child(THEME.hint("魅力已接入：最终暴击率 = 幸运×系数 + 魅力×以上系数 + 附加暴击率；最终暴击伤害 = 基础倍率 + 魅力×以上系数 + 附加暴伤。"))
	s3.add_child(THEME.hint("伤害公式（三望）：攻防基础 = 攻×(1+攻击加成-攻击降低)×克制 − 防×(1-防御降低)×(1-无视防御)，" +
		"不低于 攻×克制×破防保底系数+1；再乘 攻山倍率、暴击乘区(仅暴击)、克制增伤、攻山类增伤、物/谋元增伤、通用增减伤、最终增减伤。" +
		"暴击率 = (运势−敌方运势)×0.1% + 暴击率 − 抗暴率。固伤无视防御与常规增减伤。"))
	var s4 := _section("五维派生（扩展）")
	v.add_child(s4)
	var cb := CheckBox.new()
	cb.text = "启用：五维按权重影响物攻 / 谋攻 / 物防 / 谋防 / 幸运"
	cb.button_pressed = RULEZ.get_b("derive_five")
	cb.toggled.connect(func(on: bool) -> void:
		RULEZ.settings["derive_five"] = on
		_mark_dirty()
		_update_stat_preview())
	s4.add_child(cb)
	var g4 := VBoxContainer.new()
	s4.add_child(g4)
	_set_spin(g4, "权重（每点五维 %）", "five_weight", 0, 5, 0.01)
	var s5 := _section("数据来源（可从旧工程或其他副本同步）")
	v.add_child(s5)
	var g5 := HBoxContainer.new()
	g5.add_theme_constant_override("separation", 6)
	s5.add_child(g5)
	var ds := LineEdit.new()
	ds.text = data.ds_url
	ds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.name = "ds_url"
	ds.text_changed.connect(func(t: String) -> void:
		data.ds_url = t
		_mark_dirty())
	g5.add_child(ds)
	var pull := THEME.button("重新载入项目数据", 13)
	pull.tooltip_text = "从 res://data/editor/ 重新读取（丢弃未保存改动）"
	pull.pressed.connect(func() -> void:
		data.load_all()
		refresh_list()
		if not data.order.is_empty():
			select_general(data.order[0])
		status("已重新载入数据"))
	g5.add_child(pull)
	var imp := THEME.button("从旧工程目录导入…", 13)
	imp.pressed.connect(_import_from_dir)
	g5.add_child(imp)
	var reset := THEME.button("恢复全部默认设定", 13)
	reset.pressed.connect(func() -> void:
		RULEZ.settings = RULEZ.DEFAULTS.duplicate(true)
		_mark_dirty()
		load_general(cur_key)
		status("全局设定已恢复默认"))
	v.add_child(reset)
	return sc
func _set_sub_spin(parent: Control, label: String, group: String, key: String, mn: float, mx: float,
		step: float = 1.0) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = mn
	sp.max_value = mx
	sp.step = step
	sp.custom_minimum_size = Vector2(120, 0)
	sp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sp.value_changed.connect(func(val: float) -> void:
		if not (RULEZ.settings.get(group) is Dictionary):
			RULEZ.settings[group] = {}
		(RULEZ.settings[group] as Dictionary)[key] = val
		_mark_dirty())
	_form_row(parent, label, sp)
	set_widgets["%s.%s" % [group, key]] = sp
	return sp
func _set_text(parent: Control, label: String, key: String, default_val: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = String(RULEZ.settings.get(key, default_val))
	e.text_changed.connect(func(t: String) -> void:
		RULEZ.settings[key] = t
		_mark_dirty())
	_form_row(parent, label, e)
	set_widgets[key] = e
	return e
func _set_spin(parent: Control, label: String, key: String, mn: float, mx: float,
		step: float = 1.0, is_pct: bool = false) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = mn
	sp.max_value = mx
	sp.step = step
	sp.custom_minimum_size = Vector2(110, 0)
	sp.value_changed.connect(func(val: float) -> void:
		RULEZ.settings[key] = val
		_mark_dirty())
	_form_row(parent, label, sp)
	set_widgets[key + ("_pct" if is_pct else "")] = sp
	return sp
func _import_from_dir() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = "选择旧工程的 data 目录（含 generals.json）"
	add_child(dlg)
	dlg.dir_selected.connect(func(dir: String) -> void:
		var ok := _do_import_dir(dir)
		status("导入%s：%s" % ["成功" if ok else "失败", dir])
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered_ratio(0.6)
func _do_import_dir(dir: String) -> bool:
	var p := dir.rstrip("/") + "/generals.json"
	var g = EdData.read_json(p)
	if not (g is Dictionary):
		return false
	var cnt := 0
	for k in (g as Dictionary).keys():
		var key := String(k)
		generals_import_one(key, g[key])
		cnt += 1
	var sp := dir.rstrip("/") + "/skills.json"
	var s = EdData.read_json(sp)
	if s is Dictionary:
		for k in (s as Dictionary).keys():
			data.skills[String(k)] = s[k]
	var tp := dir.rstrip("/") + "/talents.json"
	var t = EdData.read_json(tp)
	if t is Dictionary:
		for k in (t as Dictionary).keys():
			data.talents[String(k)] = t[k]
	data.dirty = true
	refresh_list()
	status("已从 %s 导入 %d 名武将" % [dir, cnt])
	return true
# ------------------------------------------------------------
# 通用：列表刷新 / 选中 / 保存 / 导出 / 沙盒
# ------------------------------------------------------------
func refresh_list() -> void:
	if list_box == null:
		return
	for c in list_box.get_children():
		c.queue_free()
	var q := search_edit.text.strip_edges().to_lower()
	var f := filter_opt.selected
	var n := 0
	for key in data.order:
		var g: Dictionary = data.generals[key]
		var nm := String(g.get("name", key))
		var hay := (nm + " " + key + " " + String(g.get("troop", "")) + " " +
			String((g.get("ed_ext", {}) as Dictionary).get("faction", "")) + " " +
			" ".join(g.get("ed_tags", []))).to_lower()
		if q != "" and not hay.contains(q):
			continue
		var enabled := bool(g.get("ed_enabled", true))
		if f == 1 and not enabled:
			continue
		if f == 2 and enabled:
			continue
		var b := THEME.button("", 13)
		var arm := String(g.get("arm", "盾"))
		var color_hex := String(g.get("color", "#3b82f6")).replace("#", "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   %s Lv%d %d★" % ["●", nm, int(g.get("ed_level", 1)), int(g.get("ed_star", 1))]
		b.add_theme_color_override("font_color", Color.from_string("#" + color_hex, THEME.TEXT) if enabled else Color("#4b5563"))
		b.tooltip_text = "%s · %s兵 · %s\nid=%s  key=%s" % [nm, arm, String(g.get("troop", "")),
			str(g.get("id", "")), key]
		b.custom_minimum_size = Vector2(0, 30)
		b.set_meta("key", key)
		b.pressed.connect(func() -> void: select_general(key))
		if key == cur_key:
			b.add_theme_color_override("font_color", THEME.ACCENT)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("#14304a")
			sb.set_corner_radius_all(6)
			b.add_theme_stylebox_override("normal", sb)
		list_box.add_child(b)
		n += 1
	count_label.text = "  %d / %d" % [n, data.order.size()]
func select_general(key: String) -> void:
	if not data.generals.has(key):
		return
	cur_key = key
	_range_ctx["owner"] = key
	_range_ctx["sid"] = "basic"
	load_general(key)
	refresh_list()
	var i := data.order.find(key)
	status("已选中：%s（%s）" % [data.name_of(key), key])
func load_general(key: String) -> void:
	if key == "" or not data.generals.has(key):
		return
	busy = true
	var g: Dictionary = data.generals[key]
	var ext: Dictionary = g.get("ed_ext", {})
	var art: Dictionary = g.get("ed_art", {})
	f_name.text = String(g.get("name", ""))
	f_key.text = key
	f_id.value = int(g.get("id", 1))
	f_troop.text = String(g.get("troop", ""))
	f_color.color = Color.from_string(String(g.get("color", "#3b82f6")), Color("#3b82f6"))
	f_note.text = String(g.get("ed_note", ""))
	f_tags.text = ", ".join(g.get("ed_tags", []))
	var stats: Dictionary = g.get("stats", {})
	for k in stat_spins.keys():
		(stat_spins[k] as SpinBox).value = int(stats.get(k, 0))
	var fives: Dictionary = ext.get("fives", {})
	for k in RULEZ.FIVE_KEYS:
		if five_spins.has(k):
			(five_spins[k] as SpinBox).value = int(fives.get(k, 70))
	var five_bar = five_spins.get("_bar")
	if five_bar != null:
		(five_bar as Label).text = _five_bar(fives)
	# 成长
	for n in find_children("grow_*", "SpinBox", true, false):
		var k2 := String(n.name).substr(5)
		(n as SpinBox).value = float(RULEZ.get_d("growth").get(k2, 1))
	for n in find_children("rate_*", "SpinBox", true, false):
		var k3 := String(n.name).substr(5)
		(n as SpinBox).value = float((ext.get("growth_rates", {}) as Dictionary).get(k3, 1.0))
	var curve := String(ext.get("level_curve", "linear"))
	curve_opt.selected = maxi(0, ["linear", "fast", "slow"].find(curve))
	# 兵种
	var arm := String(g.get("arm", "盾"))
	arm_opt.selected = maxi(0, ["盾", "枪", "弓", "骑"].find(arm))
	var arm2 := String(ext.get("arm2", ""))
	arm2_opt.selected = 0 if arm2 == "" else (["盾", "枪", "弓", "骑"].find(arm2) + 1)
	# 天赋
	var tid := String(g.get("talent", ""))
	var keys: Array = data.talents.keys()
	keys.sort()
	var to_idx := 0
	if tid != "":
		var at := keys.find(tid)
		to_idx = at + 1 if at >= 0 else 0
	talent_opt.selected = to_idx
	talent_lv_spin.value = int(g.get("ed_talent_lv", 1))
	# 扩展
	for k in ext_widgets.keys():
		var w = ext_widgets[k]
		var v = ext.get(k)
		if w is LineEdit:
			(w as LineEdit).text = String(v) if v != null else ""
		elif w is SpinBox:
			var fv := float(v) if v != null else 0.0
			if k == "unlock_text":
				pass
			(w as SpinBox).value = fv
		elif w is OptionButton:
			var opts: Array = []
			var o := w as OptionButton
			for i in o.item_count:
				opts.append(o.get_item_text(i))
			var idx2 := opts.find(String(v) if v != null else "")
			o.selected = maxi(0, idx2)
	var cf := find_child("custom_fields", true, false)
	if cf is TextEdit:
		var lines: Array = []
		var d: Dictionary = ext.get("custom_fields", {})
		for kk in d.keys():
			lines.append("%s=%s" % [kk, d[kk]])
		(cf as TextEdit).text = "\n".join(lines)
	var toggles: Dictionary = ext.get("passive_toggles", {})
	for n in find_children("tg_*", "CheckBox", true, false):
		var tn := String(n.name).substr(3)
		(n as CheckBox).button_pressed = bool(toggles.get(tn, false))
	var en := find_child("enabled_cb", true, false)
	if en is CheckBox:
		(en as CheckBox).button_pressed = bool(g.get("ed_enabled", true))
	# 图片
	portrait_tex.texture = _load_tex(String(g.get("portrait", "")))
	illust_tex.texture = _load_tex(String(art.get("illust_path", "")))
	art_portrait_tex.texture = _load_tex(String(art.get("portrait_path", g.get("portrait", ""))))
	art_illust_tex.texture = _load_tex(String(art.get("illust_path", "")))
	busy = false
	_refresh_anim_matrix()
	_update_stat_preview()
	_update_growth_preview()
	_refresh_arm_info()
	_refresh_star_ui()
	_update_five_growth_label()
	_refresh_talent_desc()
	refresh_skill_list()
	_refresh_range_page()
	_refresh_library()
	_load_settings_widgets()
func _five_bar(fives: Dictionary) -> String:
	var s := ""
	var peak := 0
	var pk := ""
	for k in RULEZ.FIVE_KEYS:
		if int(fives.get(k, 0)) > peak:
			peak = int(fives.get(k, 0))
			pk = String(RULEZ.FIVE_LABELS[k])
	for k in RULEZ.FIVE_KEYS:
		var v := int(fives.get(k, 0))
		var n := int(round(float(v) / 10.0))
		s += "%s %s %d\n" % [RULEZ.FIVE_LABELS[k], "█".repeat(n) + "·".repeat(10 - n), v]
	return s + "\n最高：%s %d" % [pk, peak]
func _load_settings_widgets() -> void:
	busy = true
	for k in set_widgets.keys():
		var w = set_widgets[k]
		var key := String(k)
		# 嵌套键 arm_upgrade.max_lv
		if key.contains("."):
			var parts := key.split(".", true, 1)
			var grp: Dictionary = RULEZ.settings.get(parts[0], {}) if RULEZ.settings.get(parts[0]) is Dictionary else {}
			if w is SpinBox:
				(w as SpinBox).value = float(grp.get(parts[1], 0))
			continue
		if w is LineEdit:
			var lv = RULEZ.settings.get(key, "")
			if lv is String:
				(w as LineEdit).text = String(lv)
			continue
		if not (w is SpinBox):
			continue
		if key.ends_with("_pct"):
			key = key.substr(0, key.length() - 4)
		var val = RULEZ.settings.get(key, RULEZ.DEFAULTS.get(key, 0))
		if val is Dictionary:
			continue
		(w as SpinBox).value = float(val)
	# 兵种基础移动 / 攻击范围（让界面显示真实值）
	for arm in ["盾", "枪", "弓", "骑"]:
		var mk := "arm_%s_base_move" % arm
		var rk := "arm_%s_base_range" % arm
		if set_widgets.has(mk) and set_widgets[mk] is SpinBox:
			(set_widgets[mk] as SpinBox).set_value_no_signal(float(RULEZ.arm_base_move(arm)))
		if set_widgets.has(rk) and set_widgets[rk] is SpinBox:
			(set_widgets[rk] as SpinBox).set_value_no_signal(float(RULEZ.arm_base_range(arm)))
	var ds := find_child("ds_url", true, false)
	if ds is LineEdit:
		(ds as LineEdit).text = data.ds_url
	busy = false
func _refresh_library() -> void:
	var lib_box := find_child("lib_box", true, false)
	if not (lib_box is VBoxContainer):
		return
	for c in lib_box.get_children():
		c.queue_free()
	if data.library.is_empty():
		(lib_box as VBoxContainer).add_child(THEME.hint("还没有导入过图片。"))
		return
	for src in data.library.keys():
		var meta: Dictionary = data.library[src]
		var b := THEME.button("[%s] %s" % [meta.get("kind", "?"), String(src).get_file()], 12)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "%s\n→ %s" % [src, meta.get("res", "")]
		var res_path := String(meta.get("res", ""))
		b.pressed.connect(func() -> void:
			if cur_key == "":
				return
			var kind := String(meta.get("kind", "portrait"))
			data.generals[cur_key]["ed_art"]["%s_path" % kind] = res_path
			if kind == "portrait":
				data.generals[cur_key]["portrait"] = res_path
			_mark_dirty()
			load_general(cur_key))
		(lib_box as VBoxContainer).add_child(b)
func _on_new_general() -> void:
	var key := data.new_general_key("新武将")
	data.add_general(key)
	refresh_list()
	select_general(key)
	status("已新建武将：" + key)
func _on_dup_general() -> void:
	if cur_key == "":
		return
	var k := data.duplicate_general(cur_key)
	refresh_list()
	select_general(k)
	status("已复制武将：" + k)
func _on_del_general() -> void:
	if cur_key == "":
		return
	var nm := data.name_of(cur_key)
	data.remove_general(cur_key)
	cur_key = ""
	refresh_list()
	if not data.order.is_empty():
		select_general(data.order[0])
	status("已删除武将：" + nm)
func _on_rename_key() -> void:
	if cur_key == "":
		return
	var win := Window.new()
	win.title = "重命名 key（导出唯一标识）"
	win.size = Vector2i(420, 140)
	add_child(win)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_top = 10
	v.offset_right = -10
	v.offset_bottom = -10
	win.add_child(v)
	var e := LineEdit.new()
	e.text = cur_key
	v.add_child(e)
	var b := THEME.button("确定", 13)
	b.pressed.connect(func() -> void:
		if data.rename_general_key(cur_key, e.text):
			var nk := e.text.strip_edges()
			cur_key = nk
			_range_ctx["owner"] = nk
			_mark_dirty()
			load_general(nk)
			refresh_list()
			status("key 已改为 " + nk)
		else:
			status("重命名失败：key 为空或已存在")
		win.queue_free())
	v.add_child(b)
	win.popup_centered()
func _mark_dirty() -> void:
	data.dirty = true
	if status_label != null and not status_label.text.begins_with("●"):
		status_label.text = "● " + status_label.text
func status(t: String) -> void:
	if status_label != null:
		status_label.text = t
func _on_save() -> void:
	if data.save_all():
		status("✔ 已保存到 res://data/editor/（武将 %d 名 / 技策 %d 条 / 天赋 %d 条）" % [
			data.order.size(), data.skills.size(), data.talents.size()])
	else:
		status("✖ 保存失败")
func _on_export() -> void:
	var win := Window.new()
	win.title = "导出给战棋游戏"
	win.size = Vector2i(620, 520)
	add_child(win)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 12
	v.offset_right = -12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 8)
	win.add_child(v)
	v.add_child(THEME.label("导出内容", 15, THEME.ACCENT))
	v.add_child(THEME.hint(
		"完整：包含 ed_* 编辑器字段与全局设定（推荐给自己的游戏用）。\n" +
		"旧工程兼容：剥离 ed_* 字段，结构与 sango_wsz_proto/data/*.json 一致，可直接替换旧工程数据。\n" +
		"精简战斗包：只保留战斗必需字段 + 兵种系数与克制表。"))
	var mode := OptionButton.new()
	mode.add_item("完整（含编辑器字段）", 0)
	mode.add_item("旧工程兼容（剥离 ed_*）", 1)
	mode.add_item("精简战斗包", 2)
	v.add_child(mode)
	var inc_ranges := CheckBox.new()
	inc_ranges.text = "附带技能范围覆盖文件 range_override.json（旧工程可直接读）"
	inc_ranges.button_pressed = true
	v.add_child(inc_ranges)
	var inc_art := CheckBox.new()
	inc_art.text = "附带图片（把导入的头像/立绘/精灵图复制到导出目录 assets/）"
	inc_art.button_pressed = true
	v.add_child(inc_art)
	var out := LineEdit.new()
	out.text = "user://export"
	v.add_child(THEME.label("导出目录", 13, THEME.MUTED))
	v.add_child(out)
	var log := TextEdit.new()
	log.custom_minimum_size = Vector2(0, 120)
	log.editable = false
	v.add_child(log)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	v.add_child(btns)
	var b1 := THEME.button("导出到目录", 14)
	b1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b1.pressed.connect(func() -> void:
		var dir := out.text.strip_edges()
		if dir == "":
			log.text = "请填写导出目录"
			return
		var lines := _do_export(dir, int(mode.selected), inc_ranges.button_pressed, inc_art.button_pressed)
		log.text = "\n".join(lines))
	btns.add_child(b1)
	var b2 := THEME.button("选目录…", 14)
	b2.pressed.connect(func() -> void:
		var dlg := FileDialog.new()
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		add_child(dlg)
		dlg.dir_selected.connect(func(d: String) -> void:
			out.text = d
			dlg.queue_free())
		dlg.canceled.connect(func() -> void: dlg.queue_free())
		dlg.popup_centered_ratio(0.6))
	btns.add_child(b2)
	var b3 := THEME.button("复制 JSON 到剪贴板", 14)
	b3.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(data.export_json_text(["full", "legacy", "mini"][int(mode.selected)]))
		log.text = "已复制 JSON 到剪贴板")
	btns.add_child(b3)
	var b4 := THEME.button("关闭", 14)
	b4.pressed.connect(func() -> void: win.queue_free())
	btns.add_child(b4)
	win.popup_centered()
func _do_export(dir: String, mode_i: int, with_ranges: bool, with_art: bool) -> Array:
	var lines: Array = []
	var modes := ["full", "legacy", "mini"]
	var mode: String = modes[clampi(mode_i, 0, 2)]
	DirAccess.make_dir_recursive_absolute(dir)
	var written: Array[String] = data.export_to_dir(dir, mode)
	for w in written:
		lines.append("✔ " + w)
	if with_ranges:
		var ro := data.export_range_override()
		if not ro.is_empty():
			var p := dir.rstrip("/") + "/range_override.json"
			if EdData.write_json(p, ro):
				lines.append("✔ " + p)
	if with_art:
		var art_dir := dir.rstrip("/") + "/assets/imported"
		DirAccess.make_dir_recursive_absolute(art_dir)
		var n := 0
		for key in data.order:
			var art: Dictionary = data.generals[key].get("ed_art", {})
			for kind in ["portrait_path", "illust_path", "sprite_path"]:
				var src := String(art.get(kind, ""))
				if src.begins_with("res://") and FileAccess.file_exists(src):
					var dst := art_dir + "/" + src.get_file()
					if not FileAccess.file_exists(dst):
						DirAccess.copy_absolute(src, dst)
						n += 1
		lines.append("✔ 复制图片 %d 张 → %s" % [n, art_dir])
	lines.append("完成：%d 名武将 / %d 条技策（模式：%s）" % [data.order.size(), data.skills.size(), mode])
	status(lines[lines.size() - 1])
	return lines
func _on_open_sandbox(mode: String) -> void:
	if sandbox != null and is_instance_valid(sandbox):
		sandbox.queue_free()
	sandbox = SANDBOX.instantiate()
	sandbox.set("data", data)
	sandbox.set("start_mode", mode)
	sandbox.set("focus_key", cur_key)
	add_child(sandbox)
	sandbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
# 供 sandbox 回写
func generals_import_one(key: String, raw: Dictionary) -> void:
	if not data.generals.has(key):
		data.order.append(key)
	data.generals[key] = data._normalize_general(key, raw)
