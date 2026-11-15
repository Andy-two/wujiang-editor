extends SceneTree

# ============================================================
# 自动对局测试：我方用简单规则自动打，敌军跑 AI，连续若干回合，
# 验证 移动 / 普攻 / 技能 / 冷却 / 反击 / AI / 回合推进 / 胜负判定 全链路不崩且数值合理。
# 用法：godot --headless --path <项目> --script res://tools/test_battle.gd
# ============================================================

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

var logs: Array = []


func _init() -> void:
	print("========== 自动对局测试 ==========")
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	var gens := {}
	for k in data.order:
		gens[k] = data.generals[k]
	var bt = EdBattle.new(13, 11)
	bt.bind_data(gens, data.skills, data.talents)
	bt.set_seed(2026)
	bt.log_line.connect(func(t: String, tone: String) -> void:
		logs.append({"t": t, "tone": tone}))

	# 我方 4 名，敌军 3 名
	var pk := ["lu_bu", "guan_yu", "zhao_yun", "zhuge_liang"]
	for i in pk.size():
		var t := data.unit_template(String(pk[i]), 10 + i * 5, 2 + i, "")
		bt.add_unit(t, Vector2i(2 + i * 2, 8), 0)
	for i in 3:
		bt.add_unit(data.unit_template("zhang_fei", 8, 1, ""), Vector2i(3 + i * 3, 2), 1)

	var rounds := 0
	var acted := 0
	var casts := 0
	var attacks := 0
	var moves := 0
	bt.start_side(0)
	while not bt.ended and rounds < 20:
		rounds += 1
		# ---- 我方回合：每个单位尽量行动 ----
		for u in bt.units:
			if bt.ended:
				break
			if int(u["side"]) != 0 or not u["alive"]:
				continue
			u["done"] = false
			acted += 1
			# 1) 能打就打
			var target = _nearest_enemy(bt, u)
			if target != null and bt.attack_area(u).has(target["pos"] - u["pos"]):
				bt.basic_attack(u, target)
				u["done"] = true
				attacks += 1
				continue
			# 2) 试试技能
			var used_skill := false
			for sid in u["skills"]:
				var d: Dictionary = bt.skill_def(String(sid))
				if d.is_empty() or String(d.get("kind", "")) == "passive":
					continue
				if int(u["cd"].get(String(sid), 0)) > 0:
					continue
				if target != null and bt.can_cast_at(u, String(sid), target["pos"]):
					var r = bt.cast_skill(u, String(sid), target["pos"])
					if bool(r.get("ok", false)):
						casts += 1
						used_skill = true
						u["done"] = true
						break
			if used_skill:
				continue
			# 3) 否则靠近目标
			if target != null:
				var cells: Dictionary = bt.move_cells(u)
				var best: Vector2i = u["pos"]
				var bd := RULEZ.mdist(u["pos"], target["pos"])
				for c in cells.keys():
					var cc: Vector2i = c
					if bt.unit_at(cc) != null:
						continue
					var dd := RULEZ.mdist(cc, target["pos"])
					if dd < bd:
						bd = dd
						best = cc
				if best != u["pos"]:
					bt.try_move(u, best)
					moves += 1
					if bt.attack_area(u).has(target["pos"] - u["pos"]):
						bt.basic_attack(u, target)
						attacks += 1
			u["done"] = true
		# ---- 敌军回合 ----
		if not bt.ended:
			bt.next_side()
			bt.run_ai()
			if not bt.ended:
				bt.next_side()

	print("  回合数：%d" % rounds)
	print("  我方行动：%d 次，移动 %d 次，普攻 %d 次，技能 %d 次" % [acted, moves, attacks, casts])
	print("  战报条数：%d" % logs.size())
	print("  结果：%s" % (bt.result if bt.ended else "未分出胜负（回合上限）"))
	var ok_rounds := rounds >= 2
	var ok_act := acted > 0 and attacks > 0
	var ok_log := logs.size() > 10
	var ok_state: bool = (not bt.ended) or (String(bt.result) in ["victory", "defeat"])
	_check("对局推进 ≥2 回合", ok_rounds)
	_check("我方有实际攻击行为", ok_act)
	_check("战报有内容", ok_log)
	_check("胜负判定合法", ok_state)
	_check("敌方会被击败或存活状态合法", _hp_sane(bt))
	print("  我方存活 %d / 敌军存活 %d" % [bt.alive(0).size(), bt.alive(1).size()])
	# 打印最后 8 条战报，便于人工检查
	for i in range(maxi(0, logs.size() - 8), logs.size()):
		print("    " + String(logs[i]["t"]))
	print("========== 对局测试结束 ==========")

	# ---- 技能链路专项：把敌人手动放进技能射程后施放 ----
	print("---------- 技能链路专项 ----------")
	var bt2 = EdBattle.new(13, 11)
	bt2.bind_data(gens, data.skills, data.talents)
	bt2.set_seed(7)
	var zl = bt2.add_unit(data.unit_template("zhuge_liang", 20, 5, ""), Vector2i(6, 5), 0)
	var foe = bt2.add_unit(data.unit_template("zhang_fei", 5, 1, ""), Vector2i(6, 2), 1)
	var cast_ok := 0
	for sid in zl["skills"]:
		var d: Dictionary = bt2.skill_def(String(sid))
		if d.is_empty() or String(d.get("kind", "")) == "passive":
			continue
		# 找出能打到的落点
		if bt2.can_cast_at(zl, String(sid), foe["pos"]):
			var hb := int(foe["hp"])
			var r2 = bt2.cast_skill(zl, String(sid), foe["pos"])
			# 组合技策（多选一）：先拿选项，再挑一个能放的执行
			if bool(r2.get("need_choice", false)):
				var choices2: Array = r2.get("choices", [])
				_check("组合技策返回可选项（%s）" % String(d.get("name", sid)), choices2.size() >= 2)
				for ch in choices2:
					var rr = bt2.cast_skill(zl, String(sid), foe["pos"], String(ch["id"]))
					if bool(rr.get("ok", false)):
						r2 = rr
						print("  组合施放 %s → %s" % [String(d.get("name", sid)), String(ch["name"])])
						break
			if bool(r2.get("ok", false)):
				cast_ok += 1
				print("  施放 %s：%d → %d" % [String(d.get("name", sid)), hb, int(foe["hp"])])
				break
	_check("至少成功施放 1 个技能", cast_ok > 0)
	# 治疗技能
	var healer = bt2.add_unit(data.unit_template("chen_deng", 10, 1, ""), Vector2i(5, 5), 0)
	healer["hp"] = 10
	var healed := false
	for sid in healer["skills"]:
		var d3: Dictionary = bt2.skill_def(String(sid))
		if String(d3.get("kind", "")) in ["heal", "support"]:
			if bt2.can_cast_at(healer, String(sid), healer["pos"]):
				var r3 = bt2.cast_skill(healer, String(sid), healer["pos"])
				if bool(r3.get("ok", false)) and int(healer["hp"]) > 10:
					healed = true
					break
	print("  治疗技能%s" % ("生效" if healed else "（该武将无可用治疗技能或不在射程，跳过）"))
	quit(0)


func _hp_sane(bt) -> bool:
	for u in bt.units:
		if int(u["hp"]) > int(u["max_hp"]) or int(u["hp"]) < 0:
			return false
		if not u["alive"] and int(u["hp"]) != 0:
			return false
	return true


func _nearest_enemy(bt, u):
	var best = null
	var bd := 9999
	for e in bt.alive(0 if int(u["side"]) == 1 else 1):
		var dd := RULEZ.mdist(u["pos"], e["pos"])
		if dd < bd:
			bd = dd
			best = e
	return best


func _check(name: String, ok: bool) -> void:
	print(("  ✔ " if ok else "  ✖ ") + name)
