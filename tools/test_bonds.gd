extends SceneTree

# 羁绊系统专项测试：12 组羁绊全部能被正确触发并产生效果
#   ① 偃月双锋（暴击后固伤+回血） ② 岐黄相济（免死）
#   ③ 颜良文丑（攻击前范围固伤+回血） ④ 陈宫臧霸（移动2格+攻击前固伤）
#   ⑤ 徐庶司马徽（攻击后固伤+驱散增益） ⑥ 张昭张纮（战法后护盾）
#   ⑦ 诸葛均明远（追击后随机减益，每回合3次） ⑧ 夏侯兰向朗（减益被驱散反伤）
#   ⑨ 张绍夏侯昭（嘲讽目标增伤+坚壁） ⑩ 成廉曹性（范围伤害增伤）
#   ⑪ 杨阜戏志才（消耗兵力换护盾） ⑫ 王允严珩（回战意驱散减益）
# 用法: godot --headless --path . --script res://tools/test_bonds.gd

const ED = preload("res://scripts/core/ed_data.gd")
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


# 建一个携带指定副将的单位
func _mk(b: EB, side: int, pos: Vector2i, vice_id: int, hp: int = 500) -> Dictionary:
	var t := {"key": "", "name": ("我方" if side == 0 else "敌军") + str(b.units.size()),
		"arm": "盾", "color": "#3b82f6", "level": 1, "star": 1,
		"stats": {"max_hp": hp, "atk": 100, "def": 10, "matk": 100, "mdef": 10,
			"luck": 50, "move": 4, "range": 1},
		"skills": [], "ext": {"vice_id": vice_id}}
	return b.add_unit(t, pos, side)


func _init() -> void:
	print("========== 羁绊系统专项测试 ==========")
	var ed = ED.new()
	ed.load_all()
	# 校验 12 组羁绊都已配置 trigger + fx
	_test_bond_config(ed)
	_test_yanyue()
	_test_qihuang()
	_test_yanliang()
	_test_chenggong()
	_test_xushu()
	_test_zhangzhao()
	_test_zhugejun()
	_test_xiahoulan()
	_test_zhangshao()
	_test_chengxing()
	_test_yangfu()
	_test_wangyun()
	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)


func _bind(b: EB, ed: ED) -> void:
	b.bind_data(ed.generals, ed.skills, ed.talents, ed.get_arm_shapes(), ed.bonds)


func _test_bond_config(ed: ED) -> void:
	print("---- 12 组羁绊配置完整性 ----")
	_check("羁绊共 12 组", ed.bonds.size() == 12, "实际 %d" % ed.bonds.size())
	var configured := 0
	for bid in ed.bonds.keys():
		var cfg: Dictionary = ed.bonds[bid]
		var trig = cfg.get("trigger", "")
		var has_trig = (trig is Array and not (trig as Array).is_empty()) or (trig is String and String(trig) != "")
		var has_fx = not (cfg.get("fx", []) as Array).is_empty()
		if has_trig and has_fx:
			configured += 1
	_check("12 组全部配置了 trigger+fx", configured == 12, "实际 %d" % configured)


# ① 偃月双锋：暴击后对目标固伤+回血
func _test_yanyue() -> void:
	print("---- ① 偃月双锋（关平+周仓，暴击后固伤） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1308)   # 关平
	var u2 = _mk(b, 0, Vector2i(4, 5), 1288)  # 周仓
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	var active = b.active_bonds_for(0)
	var has := false
	for c in active:
		if String(c.get("name", "")) == "偃月双锋":
			has = true
	_check("同时携带关平+周仓激活偃月双锋", has)
	# on_crit 触发：造成固伤
	var hp_before := int(foe["hp"])
	b.trigger_bonds("on_crit", u, [foe])
	_check("暴击羁绊造成固伤", int(foe["hp"]) < hp_before,
		"%d → %d" % [hp_before, int(foe["hp"])])


# ② 岐黄相济：免死
func _test_qihuang() -> void:
	print("---- ② 岐黄相济（华佗+张仲景，免死） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1329)
	var u2 = _mk(b, 0, Vector2i(4, 5), 1330)
	var active = b.active_bonds_for(0)
	var has := false
	for c in active:
		if String(c.get("name", "")) == "岐黄相济":
			has = true
	_check("华佗+张仲景激活岐黄相济", has)
	u["hp"] = 0
	b._kill(u, null)
	_check("岐黄相济免除一次死亡", bool(u["alive"]), "存活状态 %s" % str(u["alive"]))
	_check("复活后有兵力", int(u["hp"]) > 0, "兵力 %d" % int(u["hp"]))


# ③ 颜良文丑：攻击前范围固伤+回血
func _test_yanliang() -> void:
	print("---- ③ 颜良文丑（攻击前1圈范围固伤+回血） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(5, 5), 1301)
	var _u2 = _mk(b, 0, Vector2i(5, 6), 1302)
	# 周围两格内的敌军
	var foe1 = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	var foe2 = _mk(b, 1, Vector2i(6, 5), 0, 2000)
	var foe_far = _mk(b, 1, Vector2i(9, 9), 0, 2000)
	u["hp"] = 250  # 留回血空间
	var hp_before := int(foe1["hp"])
	var far_before := int(foe_far["hp"])
	b.trigger_bonds("on_attack_before", u, [foe1])
	_check("颜良文丑对1圈敌军造成固伤", int(foe1["hp"]) < hp_before,
		"%d → %d" % [hp_before, int(foe1["hp"])])
	_check("1圈内另一敌军也受伤", int(foe2["hp"]) < 2000)
	_check("范围外敌军不受伤", int(foe_far["hp"]) == far_before)
	_check("造成伤害后自身回血", int(u["hp"]) > 250, "兵力 %d" % int(u["hp"]))


# ④ 陈宫臧霸：移动2格以上攻击前固伤
func _test_chenggong() -> void:
	print("---- ④ 陈宫臧霸（移动2格+攻击前固伤） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1309)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1213)
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	# 未移动时不触发
	var hp0 := int(foe["hp"])
	b.trigger_bonds("on_attack_before", u, [foe], {"move_tiles": 0})
	_check("未移动2格不触发", int(foe["hp"]) == hp0)
	# 移动2格后触发
	b.trigger_bonds("on_attack_before", u, [foe], {"move_tiles": 3})
	_check("移动2格以上造成固伤", int(foe["hp"]) < hp0,
		"%d → %d" % [hp0, int(foe["hp"])])


# ⑤ 徐庶司马徽：攻击后固伤+驱散增益
func _test_xushu() -> void:
	print("---- ⑤ 徐庶司马徽（攻击后固伤+驱散增益） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1310)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1311)
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	(foe["buffs"] as Array).append({"name": "昂扬", "turns": 3, "stacks": 1})
	var hp0 := int(foe["hp"])
	b.trigger_bonds("on_attack_after", u, [foe])
	_check("攻击后造成固伤", int(foe["hp"]) < hp0)
	_check("驱散敌军1个增益", (foe["buffs"] as Array).is_empty())


# ⑥ 张昭张纮：战法后给兵力最低友军护盾
func _test_zhangzhao() -> void:
	print("---- ⑥ 张昭张纮（战法后给最低兵力友军护盾） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1318)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1319)
	var low = _mk(b, 0, Vector2i(4, 6), 0, 500)
	low["hp"] = 100  # 兵力最低
	b.trigger_bonds("on_skill_after", u, [u, _u2, low])
	var has_shield := false
	for bf in (low["buffs"] as Array):
		if String((bf as Dictionary).get("name", "")) == "护盾":
			has_shield = true
	_check("兵力最低友军获得护盾", has_shield)


# ⑦ 诸葛均明远：追击后随机减益，每大回合3次
func _test_zhugejun() -> void:
	print("---- ⑦ 诸葛均明远（追击后随机减益，每回合3次） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1277)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1299)
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	b.trigger_bonds("on_pursuit_after", u, [foe])
	_check("追击后施加1个减益", (foe["debuffs"] as Array).size() == 1,
		"减益数 %d" % (foe["debuffs"] as Array).size())
	# 触发3次后不再触发（每大回合上限3次）
	b.trigger_bonds("on_pursuit_after", u, [foe])
	b.trigger_bonds("on_pursuit_after", u, [foe])
	var cnt_after3 := (foe["debuffs"] as Array).size()
	b.trigger_bonds("on_pursuit_after", u, [foe])
	_check("每回合最多3次", (foe["debuffs"] as Array).size() == cnt_after3,
		"%d → %d" % [cnt_after3, (foe["debuffs"] as Array).size()])


# ⑧ 夏侯兰向朗：减益被驱散时反伤
func _test_xiahoulan() -> void:
	print("---- ⑧ 夏侯兰向朗（减益被驱散反伤） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1274)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1262)
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	# 给我方减益设置施加者 uid = u，然后模拟该减益在 foe 身上被驱散
	(foe["debuffs"] as Array).append({"name": "识破", "turns": 3, "src": int(u["uid"])})
	var hp0 := int(foe["hp"])
	b._dispel_debuff(foe, 1)
	_check("减益被驱散时反伤", int(foe["hp"]) < hp0,
		"%d → %d" % [hp0, int(foe["hp"])])


# ⑨ 张绍夏侯昭：嘲讽目标反击/追击增伤+坚壁
func _test_zhangshao() -> void:
	print("---- ⑨ 张绍夏侯昭（嘲讽目标增伤+坚壁） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1331)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1215)
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	# 无嘲讽时无增伤
	var m0 := b.bond_damage_mult(u, "counter", false, foe)
	_check("无嘲讽目标无增伤", absf(m0 - 1.0) < 0.001, "倍率 %.3f" % m0)
	# 有嘲讽时增伤
	(foe["debuffs"] as Array).append({"name": "嘲讽", "turns": 3, "src": -1})
	var m1 := b.bond_damage_mult(u, "counter", false, foe)
	_check("嘲讽目标反击增伤18%", absf(m1 - 1.18) < 0.001, "倍率 %.3f" % m1)
	# 施加坚壁
	b._bond_taunt_buff(u, foe)
	var has_jianbi := false
	for bf in (u["buffs"] as Array):
		if String((bf as Dictionary).get("name", "")) == "坚壁":
			has_jianbi = true
	_check("反击嘲讽目标获得坚壁", has_jianbi)


# ⑩ 成廉曹性：范围伤害增伤，单目标额外
func _test_chengxing() -> void:
	print("---- ⑩ 成廉曹性（范围伤害增伤） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1332)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1296)
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	# 范围伤害命中多个：+15%
	var m_multi := b.bond_damage_mult(u, "skill", true, null, 3)
	_check("范围伤害增伤15%", absf(m_multi - 1.15) < 0.001, "倍率 %.3f" % m_multi)
	# 范围伤害只命中1个：+15%+25%=+40%
	var m_single := b.bond_damage_mult(u, "skill", true, null, 1)
	_check("范围只命中1个额外增伤25%", absf(m_single - 1.40) < 0.001, "倍率 %.3f" % m_single)
	# 非范围不增伤
	var m_normal := b.bond_damage_mult(u, "normal", false, null, 1)
	_check("非范围伤害不增伤", absf(m_normal - 1.0) < 0.001, "倍率 %.3f" % m_normal)


# ⑪ 杨阜戏志才：攻击前消耗兵力换护盾
func _test_yangfu() -> void:
	print("---- ⑪ 杨阜戏志才（消耗15%兵力换10%护盾） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1227)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1211)
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	var hp0 := int(u["hp"])  # 500
	b.trigger_bonds("on_attack_before", u, [foe])
	_check("消耗15%兵力", int(u["hp"]) == hp0 - int(round(500.0 * 0.15)),
		"%d → %d" % [hp0, int(u["hp"])])
	var has_shield := false
	for bf in (u["buffs"] as Array):
		if String((bf as Dictionary).get("name", "")) == "护盾":
			has_shield = true
	_check("获得10%兵力护盾", has_shield)


# ⑫ 王允严珩：回复战意时额外驱散减益
func _test_wangyun() -> void:
	print("---- ⑫ 王允严珩（回复战意时驱散减益） ----")
	var b = EB.new()
	var ed = ED.new(); ed.load_all(); _bind(b, ed)
	var u = _mk(b, 0, Vector2i(4, 4), 1303)
	var _u2 = _mk(b, 0, Vector2i(4, 5), 1229)
	(u["debuffs"] as Array).append({"name": "虚弱", "turns": 3, "src": -1})
	b.trigger_bonds("on_zhanyi_given", u, [u])
	_check("回复战意时驱散自身减益", (u["debuffs"] as Array).is_empty())
