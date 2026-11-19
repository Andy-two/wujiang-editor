extends SceneTree

# 副将数值层：韬略解析 + 修正量计算 自测
const RULEZ = preload("res://scripts/core/rules.gd")


func _init() -> void:
	var fails := 0
	var total := 0

	# ---- 1. pct_in ----
	var cases := [
		["提升1.5%物攻", 0.015],
		["战斗中伤害提升2%", 0.02],
		["提升3%暴击伤害", 0.03],
		["战斗中提升2%暴击抗性", 0.02],
	]
	for c in cases:
		total += 1
		var got := RULEZ.pct_in(String(c[0]))
		if absf(got - float(c[1])) > 0.0001:
			fails += 1
			print("FAIL pct_in(%s) = %f, 期望 %f" % [c[0], got, c[1]])
	print("pct_in: %d/%d" % [total - fails, total])

	# ---- 2. 全部 22 条韬略文案都要能解析 ----
	var ALL := [
		"提升1.5%物攻", "战斗中受到伤害减免2%", "提升1.5%谋攻", "提升1.5%兵力",
		"战斗中伤害提升2%", "战斗中受到技能伤害减免1.5%", "战斗中提升3%暴击伤害",
		"提升1.5%物防", "战斗中技能伤害提升1.5%", "克制伤害提升1.5%",
		"战斗中提升20点运势", "反击伤害增加1.5%", "提升1.5%谋防",
		"提升1.5%固定伤害", "战斗中普攻伤害提升1.5%", "受到反击伤害降低1.5%",
		"战斗中提升2%暴击抗性", "受到治疗效果提升3%", "合击伤害增加1.5%",
		"战斗中提升2%治疗效果",
		"重击：战斗中伤害提升2%", "强击：战斗中提升3%暴击伤害",
	]
	var hit := 0
	var miss: Array = []
	for t in ALL:
		var p := RULEZ.parse_taolue(String(t))
		if p.is_empty():
			miss.append(t)
		else:
			hit += 1
	print("韬略解析: %d/%d" % [hit, ALL.size()])
	if not miss.is_empty():
		fails += miss.size()
		for m in miss:
			print("  未识别: %s" % m)

	# ---- 3. 逐条核对映射到的乘区 ----
	var want := {
		"提升1.5%物攻": ["stat_atk", 0.015],
		"提升1.5%谋攻": ["stat_matk", 0.015],
		"提升1.5%物防": ["stat_def", 0.015],
		"提升1.5%谋防": ["stat_mdef", 0.015],
		"提升1.5%兵力": ["stat_hp", 0.015],
		"战斗中伤害提升2%": ["damage_bonus", 0.02],
		"战斗中受到伤害减免2%": ["damage_cut", 0.02],
		"战斗中提升3%暴击伤害": ["crit_damage", 0.03],
		"战斗中提升2%暴击抗性": ["crit_resist", 0.02],
		"战斗中技能伤害提升1.5%": ["skill_damage", 0.015],
		"战斗中受到技能伤害减免1.5%": ["skill_cut", 0.015],
		"战斗中普攻伤害提升1.5%": ["normal_damage", 0.015],
		"战斗中提升2%治疗效果": ["heal_bonus", 0.02],
		"克制伤害提升1.5%": ["restrict_damage", 0.015],
		"反击伤害增加1.5%": ["counter_damage", 0.015],
		"受到反击伤害降低1.5%": ["counter_cut", 0.015],
		"合击伤害增加1.5%": ["combo_damage", 0.015],
		"提升1.5%固定伤害": ["fixed_damage", 0.015],
		"受到治疗效果提升3%": ["heal_taken", 0.03],
		"战斗中提升20点运势": ["fortune_add", 20.0],
	}
	for t in want.keys():
		total += 1
		var p := RULEZ.parse_taolue(String(t))
		if p.is_empty():
			fails += 1
			print("FAIL 未解析: %s" % t)
			continue
		if String(p["key"]) != String(want[t][0]):
			fails += 1
			print("FAIL %s -> 乘区 %s, 期望 %s" % [t, p["key"], want[t][0]])
		elif absf(float(p["value"]) - float(want[t][1])) > 0.0001:
			fails += 1
			print("FAIL %s -> 值 %f, 期望 %f" % [t, p["value"], want[t][1]])
	print("乘区映射: 已检查 %d 条" % want.size())

	# ---- 4. 前缀文案 ----
	total += 2
	var p1 := RULEZ.parse_taolue("重击：战斗中伤害提升2%")
	if String(p1.get("key", "")) != "damage_bonus" or absf(float(p1.get("value", 0)) - 0.02) > 0.0001:
		fails += 1
		print("FAIL 前缀文案「重击：...」解析错误: %s" % p1)
	var p2 := RULEZ.parse_taolue("强击：战斗中提升3%暴击伤害")
	if String(p2.get("key", "")) != "crit_damage" or absf(float(p2.get("value", 0)) - 0.03) > 0.0001:
		fails += 1
		print("FAIL 前缀文案「强击：...」解析错误: %s" % p2)

	# ---- 5. vice_modifiers ----
	total += 3
	var v := {"stats": {"hp": 1.5}, "dmg": 2,
		"taolue": ["提升1.5%兵力", "战斗中伤害提升2%"]}
	var mod := RULEZ.vice_modifiers(v)
	# stat_hp = 1.5%(taolue) + 1.5%(stats.hp) = 0.03
	if absf(float(mod["stat"].get("hp", 0)) - 0.03) > 0.0001:
		fails += 1
		print("FAIL vice_modifiers stat.hp = %f, 期望 0.03" % float(mod["stat"].get("hp", 0)))
	# damage_bonus = 2%(taolue) + 2%(dmg) = 0.04
	if absf(float(mod["mul"].get("damage_bonus", 0)) - 0.04) > 0.0001:
		fails += 1
		print("FAIL vice_modifiers mul.damage_bonus = %f, 期望 0.04" % float(mod["mul"].get("damage_bonus", 0)))
	if absf(float(mod["dmg"]) - 0.02) > 0.0001:
		fails += 1
		print("FAIL vice_modifiers dmg = %f, 期望 0.02" % float(mod["dmg"]))

	# ---- 5b. 固定属性 attr 按等级插值 ----
	total += 3
	var vattr := {"base_attr": {"hp": 19, "atk": 9, "cri": 2},
		"max_attr": {"hp": 454, "atk": 228, "cri": 49}}
	# Lv1 = 基础值
	var ma1 := RULEZ.vice_modifiers(vattr, 1)
	if int(ma1["flat"].get("hp", 0)) != 19 or int(ma1["flat"].get("atk", 0)) != 9:
		fails += 1
		print("FAIL Lv1 固定属性 = %s, 期望 hp=19 atk=9" % str(ma1["flat"]))
	# Lv25 = 满级值
	var ma25 := RULEZ.vice_modifiers(vattr, 25)
	if int(ma25["flat"].get("hp", 0)) != 454 or int(ma25["flat"].get("atk", 0)) != 228:
		fails += 1
		print("FAIL Lv25 固定属性 = %s, 期望 hp=454 atk=228" % str(ma25["flat"]))
	# Lv13 = 中点（19 + (454-19)*0.5 = 236.5 -> 237 或 236）
	var ma13 := RULEZ.vice_modifiers(vattr, 13)
	var mid_hp := int(ma13["flat"].get("hp", 0))
	if mid_hp < 235 or mid_hp > 238:
		fails += 1
		print("FAIL Lv13 固定属性 hp = %d, 期望约 237" % mid_hp)
	print("固定属性插值: Lv1 hp=%d, Lv13 hp=%d, Lv25 hp=%d" % [
		int(ma1["flat"].get("hp", 0)), mid_hp, int(ma25["flat"].get("hp", 0))])

	# ---- 6. 空副将 ----
	total += 1
	var m2 := RULEZ.vice_modifiers({})
	if not (m2["stat"] as Dictionary).is_empty() or not (m2["mul"] as Dictionary).is_empty() \
			or not (m2["flat"] as Dictionary).is_empty():
		fails += 1
		print("FAIL 空副将应返回空修正: %s" % m2)

	# ---- 7. 未知文案不崩 ----
	total += 1
	var p3 := RULEZ.parse_taolue("这是一条未知文案")
	if not p3.is_empty():
		fails += 1
		print("FAIL 未知文案应返回空字典: %s" % p3)

	print("")
	if fails == 0:
		print("全部通过")
	else:
		print("失败 %d 项" % fails)
	quit(0 if fails == 0 else 1)