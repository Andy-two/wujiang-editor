extends SceneTree

# P3 机制专项测试：先攻 / 格挡 / 闪避 / 免疫 / 合击
# 用法: godot --headless --path . --script res://tools/test_p3.gd

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


func _mk(b: EB, side: int, pos: Vector2i, hp: int = 100, atk: int = 10, sk: Array = []) -> Dictionary:
	var t := {"key": "", "name": ("我方" if side == 0 else "敌军") + str(b.units.size()),
		"arm": "盾", "color": "#3b82f6", "level": 1, "star": 1,
		"stats": {"max_hp": hp, "atk": atk, "def": 10, "matk": 10, "mdef": 10,
			"luck": 50, "move": 4, "range": 1},
		"skills": sk.duplicate()}
	return b.add_unit(t, pos, side)


func _init() -> void:
	print("========== P3 机制专项测试 ==========")
	_test_block()
	_test_dodge()
	_test_immunity()
	_test_priority()
	_test_combo()
	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)


# ---------------- 格挡 ----------------
func _test_block() -> void:
	print("---- 格挡：按比例降低受到的伤害 ----")
	var b = EB.new()
	b.rng_seed = 12345
	b.set_seed(12345)
	var atk = _mk(b, 0, Vector2i(3, 3), 100, 40)
	var def = _mk(b, 1, Vector2i(4, 3), 200, 10)

	# 无格挡时打一次，记录基准伤害
	var hp0 := int(def["hp"])
	b.basic_attack(atk, def)
	var base_dmg := hp0 - int(def["hp"])
	_check("无格挡时能造成伤害", base_dmg > 0, "实际 %d" % base_dmg)

	# 给防御方上格挡 50%
	def["hp"] = hp0
	def["alive"] = true
	b.grant_block(def, 0.5, 2)
	b.basic_attack(atk, def)
	var blocked_dmg := hp0 - int(def["hp"])
	_check("格挡 50% 后伤害下降", blocked_dmg < base_dmg,
		"基准 %d → 格挡 %d" % [base_dmg, blocked_dmg])
	_check("格挡减伤比例正确", absf(float(blocked_dmg) - float(base_dmg) * 0.5) <= 2.0,
		"基准 %d → 格挡 %d（期望约 %d）" % [base_dmg, blocked_dmg, int(base_dmg * 0.5)])

	# 格挡到期后失效
	def["hp"] = hp0
	b._tick_p3_state(def)
	b._tick_p3_state(def)
	_check("格挡到期后失效", int(def.get("block_turns", 0)) <= 0 and float(def.get("block", 0.0)) == 0.0)


# ---------------- 闪避 ----------------
func _test_dodge() -> void:
	print("---- 闪避：按概率回避一次攻击 ----")
	var b = EB.new()
	var atk = _mk(b, 0, Vector2i(3, 3), 100, 40)
	var def = _mk(b, 1, Vector2i(4, 3), 200, 10)

	# 闪避 100%：必定回避
	b.grant_dodge(def, 1.0, 3)
	var hp0 := int(def["hp"])
	b.basic_attack(atk, def)
	_check("闪避 100% 时完全回避", int(def["hp"]) == hp0, "血量 %d → %d" % [hp0, int(def["hp"])])

	# 闪避 0%：必定命中
	def["dodge_turns"] = 3
	def["dodge"] = 0.0
	b.basic_attack(atk, def)
	_check("闪避 0% 时必定命中", int(def["hp"]) < hp0, "血量 %d → %d" % [hp0, int(def["hp"])])

	# 闪避到期
	def["dodge_turns"] = 1
	b._tick_p3_state(def)
	_check("闪避到期后失效", int(def.get("dodge_turns", 0)) <= 0)


# ---------------- 免疫 ----------------
func _test_immunity() -> void:
	print("---- 免疫：拦截对应类别的减益 ----")
	var b = EB.new()
	var u = _mk(b, 1, Vector2i(4, 3), 100, 10)

	b.grant_immunity(u, "控制", 3)
	b._add_debuff(u, "眩晕", 2, null)
	_check("免疫控制时眩晕被拦截", not b._has_debuff(u, "眩晕"))
	b._add_debuff(u, "低迷", 2, null)
	_check("免疫控制不拦截属性减益", b._has_debuff(u, "低迷"))

	var u2 = _mk(b, 1, Vector2i(6, 3), 100, 10)
	b.grant_immunity(u2, "属性减益", 3)
	b._add_debuff(u2, "低迷", 2, null)
	_check("免疫属性减益时低迷被拦截", not b._has_debuff(u2, "低迷"))

	var u3 = _mk(b, 1, Vector2i(8, 3), 100, 10)
	b.grant_immunity(u3, "移动减益", 3)
	b._add_debuff(u3, "牵制·贰", 2, null)
	_check("免疫移动减益时牵制被拦截", not b._has_debuff(u3, "牵制·贰"))

	# 免疫到期
	b._tick_p3_state(u)
	b._tick_p3_state(u)
	b._tick_p3_state(u)
	_check("免疫到期后失效", not b.is_immune(u, "控制"))
	b._add_debuff(u, "眩晕", 2, null)
	_check("免疫到期后眩晕可命中", b._has_debuff(u, "眩晕"))


# ---------------- 先攻 ----------------
func _test_priority() -> void:
	print("---- 先攻：拥有先攻的单位优先行动 ----")
	var b = EB.new()
	var a = _mk(b, 1, Vector2i(2, 2), 100, 10)
	var c = _mk(b, 1, Vector2i(3, 2), 100, 10)
	var d = _mk(b, 1, Vector2i(4, 2), 100, 10)

	b.grant_priority(c, 1)
	var prio := b.priority_units(1)
	_check("先攻单位被识别", prio.size() == 1 and prio[0] == c,
		"识别到 %d 个" % prio.size())

	# 多单位先攻时按层数降序
	b.grant_priority(a, 3)
	prio = b.priority_units(1)
	_check("先攻按层数降序排列", prio.size() == 2 and prio[0] == a,
		"顺序 %s" % str([prio[0]["name"] if prio.size() > 0 else "",
			prio[1]["name"] if prio.size() > 1 else ""]))

	# 先攻层数每回合递减
	var p0 := int(c.get("priority", 0))
	b._tick_p3_state(c)
	_check("先攻层数每回合递减", int(c.get("priority", 0)) == p0 - 1,
		"%d → %d" % [p0, int(c.get("priority", 0))])


# ---------------- 合击 ----------------
func _test_combo() -> void:
	print("---- 合击：相邻友军对同一目标联合攻击 ----")
	var b = EB.new()
	b.rng_seed = 999
	b.set_seed(999)
	var main = _mk(b, 0, Vector2i(4, 3), 100, 30)
	var partner = _mk(b, 0, Vector2i(4, 4), 100, 30)
	var foe = _mk(b, 1, Vector2i(5, 3), 300, 10)

	var partners := b.combo_partners(main, foe)
	_check("相邻友军可参与合击", partners.size() == 1 and partners[0] == partner,
		"找到 %d 个" % partners.size())

	# 不相邻的友军不参与
	var far = _mk(b, 0, Vector2i(9, 9), 100, 30)
	partners = b.combo_partners(main, foe)
	_check("不相邻的友军不参与合击", partners.size() == 1,
		"找到 %d 个" % partners.size())

	# 触发合击：目标受到两次伤害
	var hp0 := int(foe["hp"])
	main["can_combo"] = true
	b.basic_attack(main, foe)
	var first_dmg := hp0 - int(foe["hp"])
	_check("合击造成额外伤害", int(foe["hp"]) < hp0,
		"血量 %d → %d" % [hp0, int(foe["hp"])])
	_check("合击计数已累加", int(partner.get("combo_used", 0)) >= 1,
		"combo_used=%d" % int(partner.get("combo_used", 0)))

	# 对照组：关闭合击时，伤害应小于含合击的首次伤害
	var solo = _mk(b, 0, Vector2i(3, 3), 100, 30)
	solo["can_combo"] = false
	foe["hp"] = 300
	foe["alive"] = true
	var hp_solo := int(foe["hp"])
	b.basic_attack(solo, foe)
	var solo_dmg := hp_solo - int(foe["hp"])
	_check("关闭合击时伤害小于含合击", solo_dmg < first_dmg,
		"含合击 %d vs 无合击 %d" % [first_dmg, solo_dmg])

	# 每回合合击次数上限：把伙伴计数打满后，再打一次总伤害应小于首次（含合击）
	partner["combo_used"] = 99
	foe["hp"] = 300
	foe["alive"] = true
	var hp1 := int(foe["hp"])
	b.basic_attack(main, foe)
	var capped_dmg := hp1 - int(foe["hp"])
	_check("超过每回合合击上限后不再合击", capped_dmg < first_dmg,
		"首次(含合击) %d → 上限后 %d" % [first_dmg, capped_dmg])

	# 回合开始重置合击计数（伙伴在我方，故以我方回合为准）
	partner["combo_used"] = 2
	b.start_side(0)
	_check("回合开始重置合击计数", int(partner.get("combo_used", 0)) == 0,
		"combo_used=%d" % int(partner.get("combo_used", 0)))
	# 敌方回合不重置我方计数
	partner["combo_used"] = 2
	b.start_side(1)
	_check("敌方回合不重置我方合击计数", int(partner.get("combo_used", 0)) == 2,
		"combo_used=%d" % int(partner.get("combo_used", 0)))
