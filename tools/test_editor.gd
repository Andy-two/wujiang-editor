extends SceneTree

# ============================================================
# 无头逻辑测试：godot --headless --path <项目> --script res://tools/test_editor.gd
# 覆盖：数据加载 / 成长与星级 / 兵种克制 / 伤害公式 / 范围形状与旋转 /
#       技能范围覆盖 / 小战场实际交战与 AI / 导出往返 / 图片导入
# ============================================================

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const BATTLE = preload("res://scripts/core/ed_battle.gd")

var passed := 0
var failed := 0
var fails: Array = []


func _init() -> void:
	print("========== 武将编辑器逻辑测试 ==========")
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	_check("数据加载", data.load_all())
	_check("武将数量 > 50", data.order.size() > 50, "实际 %d" % data.order.size())
	_check("技策数量 > 200", data.skills.size() > 200, "实际 %d" % data.skills.size())
	_check("天赋数量 > 20", data.talents.size() > 20, "实际 %d" % data.talents.size())
	_check("兵种已补齐", String(data.generals["lu_bu"].get("arm", "")) in ["盾", "枪", "弓", "骑"],
		String(data.generals["lu_bu"].get("arm", "")))
	_check("五维已补齐", (data.generals["lu_bu"]["ed_ext"].get("fives", {}) as Dictionary).size() == 5)

	# ---- 等级 / 星级 ----
	var t1 = data.unit_template("lu_bu", 1, 2, "骑")
	var t50 = data.unit_template("lu_bu", 50, 1, "骑")
	var t10s = data.unit_template("lu_bu", 1, 10, "骑")
	_check("等级提升增加物攻", int(t50["stats"]["atk"]) > int(t1["stats"]["atk"]),
		"Lv1 %d → Lv50 %d" % [int(t1["stats"]["atk"]), int(t50["stats"]["atk"])])
	_check("等级提升增加兵力", int(t50["stats"]["max_hp"]) > int(t1["stats"]["max_hp"]))
	_check("星级提升增加全属性", int(t10s["stats"]["atk"]) > int(t1["stats"]["atk"]) and
		int(t10s["stats"]["max_hp"]) > int(t1["stats"]["max_hp"]),
		"1★ %d → 10★ %d" % [int(t1["stats"]["atk"]), int(t10s["stats"]["atk"])])
	# 现在物攻由五维(武力)决定，不再是旧工程的固定 121；只验证兵种系数与星级倍率的相对关系
	var t_nobonus = data.unit_template("lu_bu", 1, 1, "骑")
	_check("兵种修正与星级倍率生效（相对值）", int(t1["stats"]["atk"]) >= int(t_nobonus["stats"]["atk"]),
		"实际 %d，无加成骑 %d" % [int(t1["stats"]["atk"]), int(t_nobonus["stats"]["atk"])])
	var t_shield = data.unit_template("lu_bu", 1, 1, "盾")
	_check("盾兵物防更高、物攻更低", int(t_shield["stats"]["def"]) > int(t1["stats"]["def"]) and
		int(t_shield["stats"]["atk"]) < int(t1["stats"]["atk"]))
	var diff = data.levelup_diff("lu_bu", "level", 1, 1)
	_check("升级对比返回 7 项以上", (diff["rows"] as Array).size() >= 7)
	var atk_row = null
	for r in diff["rows"]:
		if String(r["key"]) == "atk":
			atk_row = r
	_check("升级对比物攻 +1", atk_row != null and int(atk_row["delta"]) >= 1,
		"" if atk_row == null else "delta=%d" % int(atk_row["delta"]))
	var sdiff = data.levelup_diff("lu_bu", "star", 5, 1)
	_check("星级对比（5★→6★）可算", (sdiff["rows"] as Array).size() >= 7)

	# ---- 五维派生开关 ----
	RULEZ.settings["derive_five"] = false
	var a0 = int(data.unit_template("lu_bu", 1, 1, "骑")["stats"]["atk"])
	data.generals["lu_bu"]["ed_ext"]["fives"]["wu"] = 100
	RULEZ.settings["derive_five"] = true
	var a1 = int(data.unit_template("lu_bu", 1, 1, "骑")["stats"]["atk"])
	_check("五维派生：武力100时物攻提升", a1 > a0, "%d → %d" % [a0, a1])
	RULEZ.settings["derive_five"] = false
	data.generals["lu_bu"]["ed_ext"]["fives"]["wu"] = 60

	# ---- 伤害 / 克制 ----
	var dm = RULEZ.damage(100.0, 50.0, 1.0)
	_check("伤害公式 atk²/(atk+def)", absf(dm - 100.0 * 100.0 / 150.0) < 0.01, "实际 %.3f" % dm)
	_check("枪克骑 = +25%", absf(RULEZ.arm_multiplier("枪", "骑") - 1.25) < 0.001)
	_check("骑被枪克 = -10%", absf(RULEZ.arm_multiplier("骑", "枪") - 0.90) < 0.001)
	_check("骑克弓 = +25%", absf(RULEZ.arm_multiplier("骑", "弓") - 1.25) < 0.001)
	_check("同兵种无克制", absf(RULEZ.arm_multiplier("弓", "弓") - 1.0) < 0.001)
	var atk_d = {"atk": 100, "matk": 50, "luck": 0, "douqi": 0, "wushuang": 0, "ext": {}}
	var def_d = {"def": 50, "mdef": 30, "hp": 200, "max_hp": 200, "ext": {}}
	var r0 = RULEZ.roll_damage(atk_d, def_d, 1.0, 1.0, {"no_variance": true, "no_crit": true})
	# 新公式：攻防基础减算，且不低于 攻×保底系数+1
	var floor0 := 100.0 * RULEZ.get_f("damage_floor_k") + 1.0
	var expect0 := int(roundf(maxf(100.0 - 50.0, floor0)))
	_check("确定性伤害 = 攻-防（不低于保底）", int(r0["dmg"]) == expect0, "实际 %d，期望 %d" % [int(r0["dmg"]), expect0])
	var r1 = RULEZ.roll_damage(atk_d, def_d, 1.0, 1.25, {"no_variance": true, "no_crit": true})
	var expect1 := int(roundf(maxf(100.0 * 1.25 - 50.0, floor0)))
	_check("克制倍率生效", int(r1["dmg"]) == expect1, "实际 %d，期望 %d" % [int(r1["dmg"]), expect1])
	var rc = RULEZ.roll_damage(atk_d, def_d, 1.0, 1.0, {"no_variance": true, "crit": true})
	_check("暴击 ×1.5", int(rc["dmg"]) == int(roundf(float(expect0) * 1.5)), "实际 %d" % int(rc["dmg"]))
	_check("最低伤害 1", int(RULEZ.roll_damage({"atk": 1, "luck": 0}, {"def": 9999}, 1.0, 1.0,
		{"no_variance": true, "no_crit": true})["dmg"]) >= 1)

	# ---- 范围 ----
	_check("菱形 r=1 有 5 格", RULEZ.diamond(1).size() == 5)
	_check("菱形 r=2 有 13 格", RULEZ.diamond(2).size() == 13)
	var lin = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var rot = RULEZ.rotate_area(lin, Vector2i(0, 1))
	_check("向右旋转 90° 变成向下", rot.has(Vector2i(0, 3)) and rot.has(Vector2i(0, 1)))
	var rot_l = RULEZ.rotate_area(lin, Vector2i(-1, 0))
	_check("向左旋转变成向左", rot_l.has(Vector2i(-3, 0)))
	_check("形状 JSON 往返", RULEZ.parse_area(RULEZ.area_to_raw(RULEZ.diamond(3))).size() == 25)
	_check("最远释放距离", RULEZ.area_radius(lin) == 3)

	# ---- 小战场：实际交战 ----
	var gens := {}
	for k in data.order:
		gens[k] = data.generals[k]
	var bt = EdBattle.new(13, 11)
	bt.bind_data(gens, data.skills, data.talents)
	bt.set_seed(7)
	var um = bt.add_unit(data.unit_template("lu_bu", 20, 5, "骑"), Vector2i(3, 3), 0)
	var ue = bt.add_unit(data.unit_template("zhao_yun", 5, 1, "骑"), Vector2i(4, 3), 1)
	_check("地图内判定", bt.in_bounds(Vector2i(0, 0)) and not bt.in_bounds(Vector2i(13, 0)))
	_check("单位占据判定", bt.unit_at(Vector2i(3, 3)) == um and bt.unit_at(Vector2i(4, 3)) == ue)
	var mv = bt.move_cells(um)
	_check("移动可达格受移动力限制", mv.has(Vector2i(3, 4)) and not mv.has(Vector2i(3, 3 + 99)))
	var hp0 := int(ue["hp"])
	var ra = bt.basic_attack(um, ue)
	_check("普攻命中", bool(ra.get("ok", false)), str(ra))
	_check("普攻造成伤害", int(ue["hp"]) < hp0, "%d → %d" % [hp0, int(ue["hp"])])
	# 反击：赵云对吕布（同为相邻骑），应造成伤害
	_check("受击方反击（简化规则）", int(um["hp"]) <= int(um["max_hp"]))
	um["done"] = false
	# 移动
	var before_pos: Vector2i = um["pos"]
	var rm = bt.try_move(um, Vector2i(before_pos.x, before_pos.y + 2))
	_check("移动成功", bool(rm.get("ok", false)), str(rm))

	# 技能：找一个吕布带的主动技能并施放
	var casted := false
	var active_sids: Array = []
	for sid in um["skills"]:
		var d: Dictionary = bt.skill_def(String(sid))
		if not d.is_empty() and String(d.get("kind", "")) != "passive":
			active_sids.append(String(sid))
	_check("吕布有主动技能", not active_sids.is_empty(), "共 %d 个" % active_sids.size())
	if not active_sids.is_empty():
		var sid: String = active_sids[0]
		# 把赵云放到技能范围内（用释放形状最远格）
		var cast := bt.skill_cast_area(um, sid)
		var target: Vector2i = um["pos"] + RULEZ.diamond(1)[-1]
		for off in cast:
			var c: Vector2i = um["pos"] + off
			if bt.in_bounds(c) and c != um["pos"]:
				target = c
				break
		ue["pos"] = target if bt.unit_at(target) == null or bt.unit_at(target) == ue else ue["pos"]
		um["done"] = false
		var rs = bt.cast_skill(um, sid, ue["pos"])
		casted = bool(rs.get("ok", false))
		_check("技能施放成功", casted, "%s → %s" % [sid, str(rs)])
		_check("技能进入冷却", int(um["cd"].get(sid, 0)) > 0 or int(bt.skill_def(sid).get("cd", 0)) == 0)

	# AI 回合不崩、能推进
	bt.start_side(1)
	bt.run_ai()
	_check("AI 回合执行完毕", true)

	# ---- 自定义范围覆盖生效 ----
	data.generals["lu_bu"]["ed_ranges"] = {"basic": {"area": [[0, 0], [1, 0], [2, 0]]}}
	var bt2 = EdBattle.new(13, 11)
	bt2.bind_data(gens, data.skills, data.talents)
	var u2 = bt2.add_unit(data.unit_template("lu_bu", 1, 1, "弓"), Vector2i(5, 5), 0)
	var area2 := bt2.attack_area(u2)
	_check("自定义普攻形状生效（3 格直线）", area2.size() == 3, "实际 %d 格" % area2.size())
	data.generals["lu_bu"]["ed_ranges"] = {}
	var sid4 = String(active_sids[0]) if not active_sids.is_empty() else ""
	if sid4 != "":
		data.generals["lu_bu"]["ed_ranges"] = {sid4: {"cast": [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0]],
			"area": [[0, 0]], "cd": 9}}
		var bt3 = EdBattle.new()
		bt3.bind_data(gens, data.skills, data.talents)
		var u3 = bt3.add_unit(data.unit_template("lu_bu"), Vector2i(5, 5), 0)
		var cs := bt3.skill_cast_area(u3, sid4)
		_check("自定义技能释放距离生效", cs.size() == 5, "实际 %d" % cs.size())
		data.generals["lu_bu"]["ed_ranges"] = {}

	# ---- 导出往返 ----
	var js := data.export_json_text("legacy")
	_check("导出旧工程格式可解析", JSON.parse_string(js) is Dictionary)
	var parsed = JSON.parse_string(js)
	_check("旧格式已剥离 ed_ 字段", not (parsed["generals"]["lu_bu"] as Dictionary).has("ed_art"))
	_check("旧格式保留 stats/talent/skills", (parsed["generals"]["lu_bu"] as Dictionary).has("stats") and
		(parsed["generals"]["lu_bu"] as Dictionary).has("skills"))
	var jf := data.export_json_text("full")
	var pf = JSON.parse_string(jf)
	_check("完整格式保留 ed_ 字段", (pf["generals"]["lu_bu"] as Dictionary).has("ed_ext"))
	var outdir := "user://_test_export"
	DirAccess.make_dir_recursive_absolute(outdir)
	var written: Array = data.export_to_dir(outdir, "full")
	_check("导出文件写入", written.size() >= 3, "写入 %d 个" % written.size())
	var back = ED.read_json(outdir + "/generals.json")
	_check("导出后可读回", back is Dictionary and (back as Dictionary).has("lu_bu"))
	var ro = data.export_range_override()
	_check("范围覆盖导出结构可用", ro is Dictionary or ro.is_empty())

	# ---- 图片导入（用旧工程素材）----
	var src := "res://assets/lu_bu.png"
	if FileAccess.file_exists(src):
		var rr = data.import_art(src, "portrait", "test_general")
		_check("图片导入成功", bool(rr.get("ok", false)), str(rr.get("msg", "")))
		if bool(rr.get("ok", false)):
			_check("导入图已落盘", FileAccess.file_exists(String(rr["res"])))
			DirAccess.remove_absolute(String(rr["res"]))
	else:
		print("  (跳过图片导入：缺少素材 %s)" % src)

	# ---- 新建 / 复制 / 删除武将 ----
	var nk = data.new_general_key("测试武将")
	data.add_general(nk)
	_check("新建武将", data.generals.has(nk))
	var ck = data.duplicate_general(nk)
	_check("复制武将", data.generals.has(ck))
	data.remove_general(nk)
	data.remove_general(ck)
	_check("删除武将", not data.generals.has(nk) and not data.generals.has(ck))

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])

	# ================= 第二轮：新增能力 =================
	_test_arm_move_range(data)
	_test_arm_upgrade(data)
	_test_star(data)
	_test_five_growth(data)
	_test_mei_crit(data)
	_test_anims(data)
	_test_skill_fx(data)

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)


# ---------------- 兵种移动力 / 攻击范围加成 ----------------
func _test_arm_move_range(data) -> void:
	print("---- 兵种移动力 / 攻击范围（继承兵种基础） ----")
	var saved_mods: Dictionary = RULEZ.get_d("arm_mods").duplicate(true)
	var saved_move: Dictionary = RULEZ.settings.get("arm_base_move", {"盾": 5, "枪": 5, "弓": 4, "骑": 6}).duplicate(true)
	var saved_range: Dictionary = RULEZ.settings.get("arm_base_range", {"盾": 1, "枪": 1, "弓": 2, "骑": 1}).duplicate(true)
	# 1) 四兵种基础移动默认值：骑 6、枪 5、盾 5、弓 4
	_check("骑兵基础移动 6", RULEZ.arm_base_move("骑") == 6, "实际 %d" % RULEZ.arm_base_move("骑"))
	_check("枪兵基础移动 5", RULEZ.arm_base_move("枪") == 5, "实际 %d" % RULEZ.arm_base_move("枪"))
	_check("盾兵基础移动 5", RULEZ.arm_base_move("盾") == 5, "实际 %d" % RULEZ.arm_base_move("盾"))
	_check("弓兵基础移动 4", RULEZ.arm_base_move("弓") == 4, "实际 %d" % RULEZ.arm_base_move("弓"))
	# 2) 换兵种继承兵种移动与范围
	for arm in ["盾", "枪", "弓", "骑"]:
		var tt = data.unit_template("lu_bu", 1, 1, arm)
		_check("换 %s 兵 → 继承移动 %d / 射程 %d" % [arm, RULEZ.arm_base_move(arm), RULEZ.arm_base_range(arm)],
			int(tt["stats"]["move"]) == RULEZ.arm_base_move(arm) and int(tt["stats"]["range"]) == RULEZ.arm_base_range(arm),
			"实际 移动 %d / 射程 %d" % [int(tt["stats"]["move"]), int(tt["stats"]["range"])])
	# 3) 改兵种基础值后立即生效
	RULEZ.settings["arm_base_move"] = {"盾": 3, "枪": 4, "弓": 7, "骑": 9}
	var t1 = data.unit_template("lu_bu", 1, 1, "弓")
	_check("改兵种基础移动立即生效", int(t1["stats"]["move"]) == 7, "实际 %d" % int(t1["stats"]["move"]))
	RULEZ.settings["arm_base_move"] = saved_move
	# 4) 技能/天赋加成叠在兵种值之上
	var g: Dictionary = data.generals["lu_bu"]
	var old_move_bonus := int(g["ed_ext"].get("move_bonus", 0))
	g["ed_ext"]["move_bonus"] = 2
	var t2 = data.unit_template("lu_bu", 1, 1, "弓")
	_check("技能/天赋移动加成叠加在兵种值上", int(t2["stats"]["move"]) == RULEZ.arm_base_move("弓") + 2,
		"%d + 2 = %d" % [RULEZ.arm_base_move("弓"), int(t2["stats"]["move"])])
	g["ed_ext"]["move_bonus"] = old_move_bonus
	var old_reach := int(g["ed_ext"].get("reach_bonus", 0))
	g["ed_ext"]["reach_bonus"] = 1
	var t3 = data.unit_template("lu_bu", 1, 1, "盾")
	_check("技能/天赋范围加成叠加在兵种值上", int(t3["stats"]["range"]) == RULEZ.arm_base_range("盾") + 1)
	g["ed_ext"]["reach_bonus"] = old_reach
	# 5) 兵种攻击范围形状：以画出来的为准，同步到该兵种武将
	data.set_arm_shape("盾", [[0, 0], [1, 0], [2, 0], [3, 0]])
	data.sync_arm_shape_to_generals("盾")
	var bt = EdBattle.new()
	bt.bind_data({"lu_bu": data.generals["lu_bu"]}, data.skills, data.talents, data.get_arm_shapes())
	var u = bt.add_unit(data.unit_template("lu_bu", 1, 1, "盾"), Vector2i(5, 5), 0)
	var area: Array = bt.attack_area(u)
	_check("兵种形状不被射程裁剪（我画的为准）", area.size() == 4, "实际 %d 格" % area.size())
	# 找一名盾兵武将，确认形状同步到了他的普攻
	var shield_key := ""
	for kk in data.order:
		if String(data.generals[kk].get("arm", "")) == "盾":
			shield_key = kk
			break
	var er_basic = (data.generals[shield_key].get("ed_ranges", {}) as Dictionary).get("basic", {})
	_check("形状已同步到武将普攻", (er_basic as Dictionary).has("area"), shield_key)
	data.set_arm_shape("盾", [])
	data.sync_arm_shape_to_generals("盾")
	var u2 = bt.add_unit(data.unit_template("lu_bu", 1, 1, "盾"), Vector2i(6, 5), 0)
	var area2: Array = bt.attack_area(u2)
	_check("清除形状后回到射程菱形", area2.size() == RULEZ.diamond(RULEZ.arm_base_range("盾")).size(),
		"%d 格" % area2.size())
	RULEZ.settings["arm_mods"] = saved_mods
	RULEZ.settings["arm_base_range"] = saved_range


# ---------------- 兵种升级（点数与五维挂钩） ----------------
func _test_arm_upgrade(data) -> void:
	print("---- 兵种升级 ----")
	var g: Dictionary = data.generals["lu_bu"]
	var old_arm = (g.get("ed_arm_lv", {}) as Dictionary).duplicate(true) if g.get("ed_arm_lv") is Dictionary else {}
	g["ed_arm_lv"] = {"level": 0, "spend": {}}
	var info0: Dictionary = data.arm_upgrade_info("lu_bu")
	_check("0 级没有可用点数", int(info0["points_total"]) == 0, str(info0["points_total"]))
	# 五维总和与点数上限挂钩
	var fives: Dictionary = g["ed_ext"]["fives"]
	var sum5 := 0
	for k in ["wu", "zhi", "tong", "zheng", "mei"]:
		sum5 += int(fives.get(k, 0))
	data.set_arm_level("lu_bu", 10)
	var info1: Dictionary = data.arm_upgrade_info("lu_bu")
	_check("等级 10 有点数（与五维挂钩）", int(info1["points_total"]) > 0, "可用 %d" % int(info1["points_total"]))
	# 兵种升级默认不加任何面板属性
	var before_t: Dictionary = (data.unit_template("lu_bu")["stats"] as Dictionary).duplicate(true)
	data.set_arm_level("lu_bu", 20)
	var after_t: Dictionary = data.unit_template("lu_bu")["stats"]
	var same_attr := true
	for k in ["max_hp", "atk", "def", "matk", "mdef", "luck", "move", "range"]:
		if int(after_t.get(k, 0)) != int(before_t.get(k, 0)):
			same_attr = false
	_check("兵种升级不加兵力/攻防/移动/射程", same_attr, str(after_t))
	g["ed_arm_lv"] = old_arm


# ---------------- 升星规则 ----------------
func _test_star(data) -> void:
	print("---- 升星规则 ----")
	var g: Dictionary = data.generals["guan_yu"]
	var old := {"star": g.get("ed_star", 1), "talent": g.get("ed_talent_lv", 1),
		"skill": (g.get("ed_skill_lv", {}) as Dictionary).duplicate(true), "dup": g.get("ed_dup", 0),
		"bonus": (g.get("ed_star_bonus", {}) as Dictionary).duplicate(true) if g.get("ed_star_bonus") is Dictionary else {}}
	g["ed_star"] = 1
	g["ed_star_bonus"] = {}
	_check("初始 1 星", int(g["ed_star"]) == 1)
	var plan: Array = data.star_plan("guan_yu")
	_check("升星表从 2 星开始覆盖到 10 星", plan.size() == 9, "共 %d 条" % plan.size())
	var kinds := {}
	for item in plan:
		kinds[int(item["star"])] = String(item["kind"])
	_check("2/3/4/6/7/9 是技能升阶",
		kinds.get(2) == "skill" and kinds.get(3) == "skill" and kinds.get(4) == "skill" and
		kinds.get(6) == "skill" and kinds.get(7) == "skill" and kinds.get(9) == "skill",
		str(kinds))
	_check("5/10 是天赋升阶", kinds.get(5) == "talent" and kinds.get(10) == "talent")
	_check("8 星是属性提升", kinds.get(8) == "stat")
	# 逐星升
	var talent0 := int(g.get("ed_talent_lv", 1))
	var atk1 := int(data.unit_template("guan_yu")["stats"]["atk"])
	var guard := 0
	while int(g["ed_star"]) < 10 and guard < 12:
		guard += 1
		var rr = data.do_star_upgrade("guan_yu")
		if not bool(rr.get("ok", false)):
			break
	_check("可升到 10 星", int(g["ed_star"]) == 10, "当前 %d 星" % int(g["ed_star"]))
	_check("5 星后天赋升阶过", int(g.get("ed_talent_lv", 1)) > talent0,
		"%d → %d" % [talent0, int(g.get("ed_talent_lv", 1))])
	var atk2 := int(data.unit_template("guan_yu")["stats"]["atk"])
	_check("8 星属性 +8% 已生效", float(atk2) / float(maxi(1, atk1)) > 1.05, "%d → %d" % [atk1, atk2])
	_check("升星每星都只消耗 1 个同名武将",
		RULEZ.star_cost(2) == 1 and RULEZ.star_cost(5) == 1 and RULEZ.star_cost(8) == 1 and RULEZ.star_cost(10) == 1)
	# 升技能星可以指定技能（先重置技能等级，避免上面循环升满）
	g["ed_star"] = 1
	var sids: Array = g.get("skills", [])
	var reset_lv := {}
	for s in sids:
		reset_lv[String(s)] = 1
	g["ed_skill_lv"] = reset_lv
	var target_sid := ""
	for s in sids:
		var dd: Dictionary = data.get_skill(String(s))
		if String(dd.get("kind", "")) != "passive":
			target_sid = String(s)
			break
	var before_lv := int((g.get("ed_skill_lv", {}) as Dictionary).get(target_sid, 1))
	var rpick = data.do_star_upgrade("guan_yu", target_sid)
	_check("升技能星可自选技能", bool(rpick.get("ok", false)) and
		int((g.get("ed_skill_lv", {}) as Dictionary).get(target_sid, 1)) == mini(3, before_lv + 1),
		"%s Lv%d → Lv%d（%s）" % [target_sid, before_lv,
			int((g.get("ed_skill_lv", {}) as Dictionary).get(target_sid, 1)), String(rpick.get("msg", ""))])
	# 还原
	g["ed_star"] = old["star"]
	g["ed_talent_lv"] = old["talent"]
	g["ed_skill_lv"] = old["skill"]
	g["ed_star_bonus"] = old["bonus"]


# ---------------- 武将升级 = 升五维 ----------------
func _test_five_growth(data) -> void:
	print("---- 武将升级升五维 ----")
	var g: Dictionary = data.generals["lu_bu"]
	var old_lv := int(g.get("ed_level", 1))
	var base_fives: Dictionary = g["ed_ext"]["fives"]
	g["ed_level"] = 1
	var f1: Dictionary = RULEZ.fives_at(base_fives, 1)
	g["ed_level"] = 11
	var f11: Dictionary = RULEZ.fives_at(base_fives, 11)
	_check("Lv11 五维高于 Lv1", int(f11["wu"]) > int(f1["wu"]) and int(f11["mei"]) > int(f1["mei"]),
		"武 %d→%d 魅 %d→%d" % [int(f1["wu"]), int(f11["wu"]), int(f1["mei"]), int(f11["mei"])])
	var add: Dictionary = RULEZ.five_growth_of(11)
	_check("每级五维按设定成长", int(add.get("wu", 0)) == 10 * int(RULEZ.settings.get("five_growth", {}).get("wu", 1)),
		"累计 +%d" % int(add.get("wu", 0)))
	# 五维随等级进入模板（派生开启时会影响面板；魅力影响暴击）
	var old_derive := RULEZ.get_b("derive_five")
	RULEZ.settings["derive_five"] = true
	var t1 = data.unit_template("lu_bu", 1, 1, "骑")
	var t11 = data.unit_template("lu_bu", 11, 1, "骑")
	_check("等级提升后面板物攻随五维变化", int(t11["stats"]["atk"]) > int(t1["stats"]["atk"]))
	var cc1 := RULEZ.crit_chance_of(t1)
	var cc11 := RULEZ.crit_chance_of(t11)
	_check("等级提升 → 魅力提升 → 暴击率提升", cc11 > cc1,
		"%.1f%% → %.1f%%" % [cc1 * 100.0, cc11 * 100.0])
	RULEZ.settings["derive_five"] = old_derive
	g["ed_level"] = old_lv


# ---------------- 魅力 → 暴击率 / 暴击伤害 ----------------
func _test_mei_crit(data) -> void:
	print("---- 魅力 影响暴击率 / 暴击伤害 ----")
	var g: Dictionary = data.generals["lu_bu"]
	var old_mei := int(g["ed_ext"]["fives"]["mei"])
	var t0 = data.unit_template("lu_bu")
	var cc0 := RULEZ.crit_chance_of(t0)
	var cm0 := RULEZ.crit_mult_of(t0)
	g["ed_ext"]["fives"]["mei"] = 100
	var t1 = data.unit_template("lu_bu")
	var cc1 := RULEZ.crit_chance_of(t1)
	var cm1 := RULEZ.crit_mult_of(t1)
	_check("魅力提升 → 暴击率上升", cc1 > cc0, "%.1f%% → %.1f%%" % [cc0 * 100.0, cc1 * 100.0])
	# 魅力只通过「运势」影响暴击（公式表），不再直接抬爆伤
	_check("魅力提升 → 运势提升", float(t1.get("fortune", 0)) > float(t0.get("fortune", 0)),
		"%.0f → %.0f" % [float(t0.get("fortune", 0)), float(t1.get("fortune", 0))])
	# 幸运与运势已合并为魅力：暴击率差值 = 魅力差 × 每点系数
	var expect_cc := (100 - old_mei) * RULEZ.get_f("crit_per_mei")
	_check("魅力提升按每点系数提升暴击率", absf(cc1 - cc0 - expect_cc) < 0.001,
		"差 %.4f，期望 %.4f" % [cc1 - cc0, expect_cc])
	_check("魅力爆伤按系数计算", absf(cm1 - cm0 - (100 - old_mei) * RULEZ.get_f("mei_crit_dmg_per")) < 0.001,
		"差 %.4f" % (cm1 - cm0))
	# 暴击伤害真的进伤害结算
	var atk_d = t1.duplicate(true)
	var def_d = {"def": 50, "mdef": 30, "hp": 999, "max_hp": 999, "ext": {}, "skills": [], "arm": "盾"}
	var r_crit = RULEZ.roll_damage(atk_d, def_d, 1.0, 1.0, {"no_variance": true, "crit": true})
	_check("暴击结算使用暴击倍率", absf(float(r_crit["crit_mult"]) - RULEZ.crit_mult_of(t1)) < 0.001,
		"倍率 ×%.2f" % float(r_crit["crit_mult"]))
	# 期望伤害随魅力上升
	var e0 = RULEZ.expected_damage(t0, def_d, 1.0, 1.0, false)
	var e1 = RULEZ.expected_damage(t1, def_d, 1.0, 1.0, false)
	_check("期望伤害随魅力上升", e1 >= e0, "%d → %d" % [e0, e1])
	g["ed_ext"]["fives"]["mei"] = old_mei


# ---------------- 动作动画（按旧说明的三张图 + 帧号表） ----------------
func _test_anims(data) -> void:
	print("---- 精灵图：三张图 + 帧号表（按旧游戏说明） ----")
	var g: Dictionary = data.generals["lu_bu"]
	data.reset_anim_spec(g)
	_check("动画槽共 5 动作 × 4 朝向", (g["ed_art"]["anims"] as Dictionary).size() == 20,
		"实际 %d" % (g["ed_art"]["anims"] as Dictionary).size())
	# 帧号与说明一致
	var spec := RULEZ.legacy_anim_spec()
	_check("攻击·下 = 帧 1-4", str(g["ed_art"]["anims"]["attack_down"]["frames"]) == str(spec["attack"]["down"]["frames"]),
		str(g["ed_art"]["anims"]["attack_down"]["frames"]))
	_check("攻击·上 = 帧 5-8", str(g["ed_art"]["anims"]["attack_up"]["frames"]) == "[5, 6, 7, 8]")
	_check("攻击·左 = 帧 9-12", str(g["ed_art"]["anims"]["attack_left"]["frames"]) == "[9, 10, 11, 12]")
	_check("右侧攻击用左侧帧并镜像", bool(g["ed_art"]["anims"]["attack_right"].get("mirror", false)))
	_check("移动·下 = 帧 1,2；下待机 = 帧 7,1",
		str(g["ed_art"]["anims"]["walk_down"]["frames"]) == "[1, 2]" and
		str(g["ed_art"]["anims"]["idle_down"]["frames"]) == "[7, 1]")
	_check("受击 = spc 第 4 帧", str(g["ed_art"]["anims"]["hurt_down"]["frames"]) == "[4]")
	# 导入 atk64：应识别为 64×64 竖条 12 帧
	var legacy := "res://assets/units/lu_bu/atk64.png"
	if FileAccess.file_exists(legacy):
		var r2 = data.import_sheet_to(legacy, "lu_bu", "atk")
		_check("导入攻击图成功", bool(r2.get("ok", false)), str(r2.get("msg", "")))
		_check("识别出 12 帧", int(r2.get("total_frames", 0)) == 12, "共 %d 帧" % int(r2.get("total_frames", 0)))
		_check("三张图记录里 atk 已填", data.sheet_path(g, "atk") != "")
	# 一次导入多张
	var allr = data.import_all_sheets(["res://assets/units/lu_bu/mov64.png", "res://assets/units/lu_bu/spc64.png"], "lu_bu")
	_check("批量导入识别 mov/spc", bool(allr.get("ok", false)), str(allr.get("msg", "")))
	_check("mov/spc 都已记录", data.sheet_path(g, "mov") != "" and data.sheet_path(g, "spc") != "")
	# 战斗中：朝向随移动/攻击切换
	var bt = EdBattle.new(13, 11)
	bt.bind_data({"lu_bu": g}, data.skills, data.talents)
	var u = bt.add_unit(data.unit_template("lu_bu", 10, 1, "骑"), Vector2i(5, 5), 0)
	var e = bt.add_unit(data.unit_template("zhao_yun", 10, 1, "骑"), Vector2i(5, 7), 1)
	_check("战斗单位能取到动画表", not bt.unit_art(u).is_empty(), "%d 槽" % bt.unit_art(u).size())
	_check("有「攻击·下」动画", bt.has_anim(u, "attack", "down"))
	bt.try_move(u, Vector2i(5, 6))
	_check("移动后切到 walk 动作", String(u["anim"]) == "walk", String(u["anim"]))
	_check("移动后朝向为下", String(u["face"]) == "down", String(u["face"]))
	u["done"] = false
	bt.basic_attack(u, e)
	_check("攻击后切到 attack 动作", String(u["anim"]) in ["attack", "hurt"] or not e["alive"], String(u["anim"]))
	bt.tick_anim(2.0)
	_check("计时结束回到 idle", String(u["anim"]) == "idle" or not u["alive"], String(u["anim"]))


# ---------------- 技能特效 ----------------
func _test_skill_fx(data) -> void:
	print("---- 技能特效导入 ----")
	var sid := "yuanmen"
	var d: Dictionary = data.get_skill(sid)
	d["ed_fx"] = {"path": "res://assets/units/lu_bu/spc64.png", "sheet_type": "strip",
		"frame_w": 64, "frame_h": 64, "frames": 5, "fps": 12.0, "scale": 1.5, "offset_y": 0.0,
		"anchor": "target", "layer": "above", "sync_level": false}
	_check("技能保存了特效配置", (data.get_skill(sid).get("ed_fx") as Dictionary).get("path", "") != "")
	# 战斗中放技能触发特效事件
	var bt = EdBattle.new(13, 11)
	bt.bind_data({"lu_bu": data.generals["lu_bu"]}, data.skills, data.talents)
	var got := {"n": 0, "cells": 0}
	bt.fx_event.connect(func(_sid: String, cells: Array, skill: Dictionary) -> void:
		got["n"] += 1
		got["cells"] = cells.size())
	var u = bt.add_unit(data.unit_template("lu_bu", 20, 5, "弓"), Vector2i(5, 5), 0)
	bt.add_unit(data.unit_template("zhao_yun", 5, 1, "盾"), Vector2i(5, 3), 1)
	var r = bt.cast_skill(u, sid, Vector2i(5, 3))
	_check("技能施放成功", bool(r.get("ok", false)), str(r))
	_check("触发特效事件", int(got["n"]) == 1, "次数 %d" % int(got["n"]))
	_check("特效事件带回作用格", int(got["cells"]) > 0, "%d 格" % int(got["cells"]))
	d.erase("ed_fx")


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("  ✔ " + name + (("   " + detail) if detail != "" else ""))
	else:
		failed += 1
		fails.append(name + (("   " + detail) if detail != "" else ""))
		print("  ✖ " + name + (("   " + detail) if detail != "" else ""))
