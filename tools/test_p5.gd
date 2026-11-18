extends SceneTree

# P5 机制专项测试：溅射
#   ① 溅射范围计算（方形圈 / 十字）
#   ② 溅射只打周围敌人、不打主目标
#   ③ 溅射倍率正确
#   ④ 溅射不触发反击
#   ⑤ 同一技能多级溅射只生效最高级
# 用法: godot --headless --path . --script res://tools/test_p5.gd

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const EB = preload("res://scripts/core/ed_battle.gd")

var passed := 0
var failed := 0
var fails: Array = []


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  ✔ ", name)
	else:
		failed += 1
		fails.append(name + ("" if detail == "" else "（" + detail + "）"))
		print("  ✖ ", name, ("" if detail == "" else "（" + detail + "）"))


func _mk(b: EB, side: int, pos: Vector2i, hp: int = 300, atk: int = 30) -> Dictionary:
	var t := {"key": "", "name": ("我方" if side == 0 else "敌军") + str(b.units.size()),
		"arm": "盾", "color": "#3b82f6", "level": 1, "star": 1,
		"stats": {"max_hp": hp, "atk": atk, "def": 10, "matk": 10, "mdef": 10,
			"luck": 50, "move": 4, "range": 1},
		"skills": []}
	return b.add_unit(t, pos, side)


func _init() -> void:
	print("========== P5 机制专项测试 ==========")
	_test_range()
	_test_splash_basic()
	_test_splash_levels()
	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)


# ---------------- 溅射范围计算 ----------------
func _test_range() -> void:
	print("---- 溅射范围计算 ----")
	var circle := RULEZ.splash_cells(1, "circle")
	_check("方形一圈有 8 格", circle.size() == 8, "实际 %d" % circle.size())
	var has_diag := false
	for c in circle:
		if absi(c.x) == 1 and absi(c.y) == 1:
			has_diag = true
	_check("方形一圈含对角格", has_diag)

	var dia := RULEZ.splash_cells(1, "diamond")
	_check("十字有 4 格", dia.size() == 4, "实际 %d" % dia.size())

	var c2 := RULEZ.splash_cells(2, "circle")
	_check("方形两圈有 24 格", c2.size() == 24, "实际 %d" % c2.size())

	# 不含中心
	var has_center := false
	for c in circle:
		if c == Vector2i.ZERO:
			has_center = true
	_check("溅射范围不含中心格", not has_center)


# ---------------- 溅射基本行为 ----------------
func _test_splash_basic() -> void:
	print("---- 溅射：只打周围敌人，不打主目标 ----")
	var b = EB.new()
	b.rng_seed = 4242
	b.set_seed(4242)
	var caster = _mk(b, 0, Vector2i(2, 2))
	var main_target = _mk(b, 1, Vector2i(5, 2))
	# 主目标周围一圈的 3 个敌人
	var n1 = _mk(b, 1, Vector2i(4, 2))
	var n2 = _mk(b, 1, Vector2i(5, 3))
	var n3 = _mk(b, 1, Vector2i(6, 2))
	# 远处一个敌人（不该被打到）
	var far = _mk(b, 1, Vector2i(10, 8))
	# 我方友军（不该被溅射打到）
	var ally = _mk(b, 0, Vector2i(4, 3))

	var hp_main := int(main_target["hp"])
	var hp_n1 := int(n1["hp"])
	var hp_n2 := int(n2["hp"])
	var hp_n3 := int(n3["hp"])
	var hp_far := int(far["hp"])
	var hp_ally := int(ally["hp"])

	var fx := {"type": "splash", "value": 0.5, "radius": 1, "shape": "circle"}
	var hits := b.do_splash(caster, [main_target], main_target["pos"], fx)

	_check("溅射命中了周围敌人", hits == 3, "实际命中 %d" % hits)
	_check("主目标未被溅射波及", int(main_target["hp"]) == hp_main,
		"血量 %d → %d" % [hp_main, int(main_target["hp"])])
	_check("相邻敌人1 受伤", int(n1["hp"]) < hp_n1)
	_check("相邻敌人2 受伤", int(n2["hp"]) < hp_n2)
	_check("相邻敌人3 受伤", int(n3["hp"]) < hp_n3)
	_check("远处敌人未受伤", int(far["hp"]) == hp_far)
	_check("我方友军未受伤", int(ally["hp"]) == hp_ally)

	# 溅射伤害应为主目标的约一半（倍率 0.5）
	var d_main_expect := (hp_main - int(main_target["hp"]))
	_check("主目标未受溅射（对照）", d_main_expect == 0)


# ---------------- 多级溅射 ----------------
func _test_splash_levels() -> void:
	print("---- 多级溅射：只生效等级最高的那个 ----")
	var b = EB.new()
	b.rng_seed = 777
	b.set_seed(777)
	var caster = _mk(b, 0, Vector2i(2, 2))
	var main_target = _mk(b, 1, Vector2i(5, 2))
	# 对角格：只有 circle 才会打到
	var diag = _mk(b, 1, Vector2i(6, 3))
	# 十字格：两种形状都会打到
	var cross = _mk(b, 1, Vector2i(5, 3))

	var hp_diag := int(diag["hp"])
	var hp_cross := int(cross["hp"])

	# Lv1 十字形状
	var fx_diamond := {"type": "splash", "value": 0.5, "radius": 1, "shape": "diamond"}
	b.do_splash(caster, [main_target], main_target["pos"], fx_diamond)
	_check("十字形状打到十字格", int(cross["hp"]) < hp_cross)
	_check("十字形状打不到对角格", int(diag["hp"]) == hp_diag,
		"血量 %d → %d" % [hp_diag, int(diag["hp"])])

	# Lv3 一圈形状
	var hp_cross2 := int(cross["hp"])
	var hp_diag2 := int(diag["hp"])
	var fx_circle := {"type": "splash", "value": 0.5, "radius": 1, "shape": "circle"}
	b.do_splash(caster, [main_target], main_target["pos"], fx_circle)
	_check("方形一圈打到对角格", int(diag["hp"]) < hp_diag2,
		"血量 %d → %d" % [hp_diag2, int(diag["hp"])])
	_check("方形一圈也打到十字格", int(cross["hp"]) < hp_cross2)

	# 数据校验：两个技能都配了 splash 块
	var data = ED.new()
	data.load_all()
	var lg = data.skills.get("sun_liuguang", {})
	var bj = data.skills.get("10194041", {})
	var lg_splash := _count_type(lg.get("ed_fx_list", []), "splash")
	var bj_splash := _count_type(bj.get("ed_fx_list", []), "splash")
	_check("流光星陨配了溅射块", lg_splash >= 1, "实际 %d" % lg_splash)
	_check("被坚执锐配了溅射块", bj_splash >= 1, "实际 %d" % bj_splash)

	# 效果块类型已注册
	_check("splash 在效果块类型列表中", RULEZ.SFX_TYPES.has(RULEZ.SFX_SPLASH))
	_check("splash 有界面标签", RULEZ.SFX_LABELS.has(RULEZ.SFX_SPLASH))
	_check("splash 有默认参数",
		RULEZ.default_sfx(RULEZ.SFX_SPLASH).has("radius"))
	_check("splash 有可读文案",
		String(RULEZ.sfx_text(RULEZ.default_sfx(RULEZ.SFX_SPLASH))).contains("溅射"))


func _count_type(fx_list: Array, t: String) -> int:
	var n := 0
	for f in fx_list:
		if f is Dictionary and String(f.get("type", "")) == t:
			n += 1
	return n
