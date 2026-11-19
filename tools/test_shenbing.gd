extends SceneTree

# 专属神兵系统测试
#   ① 神兵数据：19 武将、76 节点、4阶文案写入 lv[3]
#   ② 升级规则：神兵 11/14/17 → 3计策4阶；20 → 天赋4阶
#   ③ 4阶效果：min_lv=4 块只在4阶生效
#   ④ 只升不降、未到阈值不生效
# 用法: godot --headless --path . --script res://tools/test_shenbing.gd

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

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

var d = ED.new()

func _init() -> void:
	print("========== 专属神兵系统测试 ==========")
	d.load_all()

	# ---- 1. 数据完整性 ----
	print("---- 数据完整性 ----")
	_check("神兵武将19个", d.shenbings.size() == 19, "实际 %d" % d.shenbings.size())
	var total_skills := 0
	var total_talents := 0
	var lv4_text := 0
	for k in d.shenbings.keys():
		var sb: Dictionary = d.shenbings[k]
		total_skills += (sb.get("skills", []) as Array).size()
		total_talents += (sb.get("talent", []) as Array).size()
	_check("计策节点57", total_skills == 57, "实际 %d" % total_skills)
	_check("天赋节点19", total_talents == 19, "实际 %d" % total_talents)
	# 检查 4阶文案写入
	for sid in d.skills.keys():
		var sk: Dictionary = d.skills[sid]
		if bool(sk.get("shenbing", false)):
			var lv: Array = sk.get("lv", [])
			if lv.size() >= 4 and String(lv[3]) != "":
				lv4_text += 1
	_check("技能4阶文案已写入", lv4_text >= 55, "实际 %d" % lv4_text)

	# ---- 2. 关羽神兵链路 ----
	print("---- 关羽神兵升级链 ----")
	# 未养成：Lv1
	var g: Dictionary = d.generals["guan_yu"]
	var ext: Dictionary = g["ed_ext"]
	ext["shenbing_lv"] = 0
	var t0: Dictionary = d.unit_template("guan_yu")
	_check("未养成 青龙斩月Lv1", int(t0["skill_lv"].get("guan_qinglong", 0)) == 1)
	_check("未养成 天赋Lv1", int(t0["talent_lv"]) == 1)
	# 神兵11级 → 计策1(青龙斩月) 4阶
	ext["shenbing_lv"] = 11
	var t11: Dictionary = d.unit_template("guan_yu")
	_check("神兵11级 青龙斩月4阶", int(t11["skill_lv"].get("guan_qinglong", 0)) == 4,
		"Lv=%d" % int(t11["skill_lv"].get("guan_qinglong", 0)))
	_check("神兵11级 千里单骑仍1阶", int(t11["skill_lv"].get("qianli", 0)) == 1)
	# 神兵14级 → 计策2(千里单骑) 4阶
	ext["shenbing_lv"] = 14
	var t14: Dictionary = d.unit_template("guan_yu")
	_check("神兵14级 千里单骑4阶", int(t14["skill_lv"].get("qianli", 0)) == 4)
	# 神兵17级 → 计策3(威震华夏) 4阶
	ext["shenbing_lv"] = 17
	var t17: Dictionary = d.unit_template("guan_yu")
	_check("神兵17级 威震华夏4阶", int(t17["skill_lv"].get("guan_weizhen", 0)) == 4)
	_check("神兵17级 天赋仍1阶", int(t17["talent_lv"]) == 1)
	# 神兵20级 → 天赋 4阶
	ext["shenbing_lv"] = 20
	var t20: Dictionary = d.unit_template("guan_yu")
	_check("神兵20级 天赋4阶", int(t20["talent_lv"]) == 4, "Lv=%d" % int(t20["talent_lv"]))
	_check("神兵20级 3计策全4阶", int(t20["skill_lv"].get("guan_qinglong",0)) == 4 \
		and int(t20["skill_lv"].get("qianli",0)) == 4 \
		and int(t20["skill_lv"].get("guan_weizhen",0)) == 4)
	ext["shenbing_lv"] = 0

	# ---- 3. 4阶效果块只在4阶生效 ----
	print("---- 4阶效果过滤 ----")
	# 找一个有 min_lv=4 块的神兵技能
	var found := ""
	for sid in d.skills.keys():
		var sk: Dictionary = d.skills[sid]
		for fx in (sk.get("ed_fx_list", []) as Array):
			if int((fx as Dictionary).get("min_lv",0)) == 4:
				found = String(sid)
				break
		if found != "": break
	if found != "":
		var skd: Dictionary = d.skills[found]
		_check("3阶不含4阶块", RULEZ.effects_for_level(skd.get("ed_fx_list",[]), 3).size() \
			< RULEZ.effects_for_level(skd.get("ed_fx_list",[]), 4).size(),
			"%s 3阶%d块 4阶%d块" % [found,
				RULEZ.effects_for_level(skd.get("ed_fx_list",[]),3).size(),
				RULEZ.effects_for_level(skd.get("ed_fx_list",[]),4).size()])
	else:
		print("  （无 min_lv=4 效果块，跳过）")

	# ---- 4. 只升不降 ----
	print("---- 只升不降 ----")
	# 手动把技能等级设为3，神兵20级不应降到4以下（也不应把别的技能改掉）
	(g["ed_skill_lv"] as Dictionary)["qianli"] = 3
	ext["shenbing_lv"] = 20
	var t20b: Dictionary = d.unit_template("guan_yu")
	_check("已有3阶技能升到4阶", int(t20b["skill_lv"].get("qianli",0)) == 4)
	(g["ed_skill_lv"] as Dictionary)["qianli"] = 1
	ext["shenbing_lv"] = 0

	# ---- 5. 无神兵武将不受影响 ----
	print("---- 无神兵武将 ----")
	var g2: Dictionary = d.generals["zhang_fei"]
	# 张飞有神兵，换个没有的
	var no_sb_key := ""
	for k in d.generals.keys():
		if not d.shenbings.has(k):
			no_sb_key = k
			break
	if no_sb_key != "":
		var g3: Dictionary = d.generals[no_sb_key]
		(g3["ed_ext"] as Dictionary)["shenbing_lv"] = 20
		var t3: Dictionary = d.unit_template(no_sb_key)
		_check("无神兵武将20级不受影响", int(t3["talent_lv"]) <= 3)
		(g3["ed_ext"] as Dictionary).erase("shenbing_lv")

	# ---- 6. 全量：19武将都能升4阶 ----
	print("---- 全量校验 ----")
	var okcnt := 0
	for k in d.shenbings.keys():
		if not d.generals.has(k): continue
		var gx: Dictionary = d.generals[k]
		(gx["ed_ext"] as Dictionary)["shenbing_lv"] = 20
		var tx: Dictionary = d.unit_template(k)
		var all4 := true
		for node in (d.shenbings[k].get("skills", []) as Array):
			# 赵云等组合节点含「形态技能」(云大怒/得胜归)，不在武将装备列表，
			# 它们通过主技能升阶切换，只需检查实际装备的技能。
			var node_ok := false
			for skey in ((node as Dictionary).get("keys", []) as Array):
				if tx["skill_lv"].has(String(skey)):
					node_ok = true
					if int(tx["skill_lv"].get(String(skey), 0)) < 4:
						all4 = false
			if not node_ok and not (node as Dictionary).get("keys", []).is_empty():
				# 节点全是形态技能，文案仍写入，跳过等级校验
				pass
		if int(tx["talent_lv"]) >= 4 and all4:
			okcnt += 1
		(gx["ed_ext"] as Dictionary)["shenbing_lv"] = 0
	_check("19武将全可升4阶", okcnt == 19, "实际 %d" % okcnt)

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails: print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)
