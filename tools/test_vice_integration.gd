extends SceneTree

# 副将数值层：接入 unit_template 后的端到端验证
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

var fails := 0
var total := 0


func ok(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("  FAIL ", msg)


func _init() -> void:
	var d = ED.new()
	d.load_all()
	print("副将总数: %d  主将总数: %d" % [d.vices.size(), d.generals.size()])
	print("")

	# ---------- 1. vice_list ----------
	print("[1] 副将列表")
	var vl: Array = d.vice_list()
	ok(vl.size() == 109, "vice_list 应有 109 条，实际 %d" % vl.size())
	ok(int(vl[0]["id"]) < int(vl[vl.size() - 1]["id"]), "应按 ID 升序")
	var v0: Dictionary = vl[0]
	for f in ["id", "name", "quality", "effect_name", "taolue", "stats", "dmg"]:
		ok(v0.has(f), "副将条目缺字段 %s" % f)
	print("  109 条，首条: %s「%s」" % [v0["name"], v0["effect_name"]])

	# ---------- 2. 未挂副将时无变化 ----------
	print("[2] 未挂副将")
	var key := "guan_yu"
	var g: Dictionary = d.generals[key]
	ok(int((g.get("ed_ext", {}) as Dictionary).get("vice_id", 0)) == 0, "关羽初始 vice_id 应为 0")
	var t0: Dictionary = d.unit_template(key)
	ok(d.vice_of(g).is_empty(), "未挂副将时 vice_of 应为空")
	ok(d.vice_mods_for(g).is_empty(), "未挂副将时 vice_mods_for 应为空")
	print("  关羽 Lv%d 兵力=%d 物攻=%d 物防=%d" % [
		int(t0["level"]), int(t0["stats"]["max_hp"]), int(t0["stats"]["atk"]), int(t0["stats"]["def"])])

	# ---------- 3. 挂一个纯 stats 副将 ----------
	print("[3] 挂载副将（stats 加成型）")
	# 找一个只加 stats、无 taolue 的副将
	var target_vice := {}
	for v in vl:
		if (v["taolue"] as Array).is_empty() and not (v["stats"] as Dictionary).is_empty() \
				and float(v["dmg"]) == 0.0:
			target_vice = v
			break
	ok(not target_vice.is_empty(), "应能找到纯 stats 副将")
	if not target_vice.is_empty():
		var vid := int(target_vice["id"])
		(g["ed_ext"] as Dictionary)["vice_id"] = vid
		var t1: Dictionary = d.unit_template(key)
		var vdef: Dictionary = d.vices[str(vid)]
		var vstats: Dictionary = vdef.get("stats", {})
		print("  挂载: %s「%s」stats=%s" % [vdef["name"], vdef["effect_name"], vstats])
		for sk in vstats.keys():
			var want_pct := float(vstats[sk]) / 100.0
			var stat_key := "max_hp" if String(sk) == "hp" else String(sk)
			var before := float(t0["stats"][stat_key])
			var after := float(t1["stats"][stat_key])
			if before <= 0.0:
				continue
			var got_pct := (after / before) - 1.0
			ok(absf(got_pct - want_pct) < 0.02,
				"%s 加成应为 %.4f，实际 %.4f (before=%f after=%f)" % [
					stat_key, want_pct, got_pct, before, after])
			print("    %s: %d -> %d (+%.2f%%, 期望 +%.2f%%)" % [
				stat_key, int(before), int(after), got_pct * 100.0, want_pct * 100.0])
		(g["ed_ext"] as Dictionary)["vice_id"] = 0

	# ---------- 4. 挂韬略副将 ----------
	print("[4] 挂载副将（韬略战斗类）")
	var tv2 := {}
	for v in vl:
		var tl: Array = v["taolue"]
		var hit := false
		for line in tl:
			if String(line).contains("伤害提升") or String(line).contains("物攻"):
				hit = true
		if hit and tl.size() >= 2:
			tv2 = v
			break
	ok(not tv2.is_empty(), "应能找到带战斗类韬略的副将")
	if not tv2.is_empty():
		var vid2 := int(tv2["id"])
		(g["ed_ext"] as Dictionary)["vice_id"] = vid2
		var t2: Dictionary = d.unit_template(key)
		var mod: Dictionary = d.vice_mods_for(g)
		print("  挂载: %s「%s」" % [tv2["name"], tv2["effect_name"]])
		print("    taolue: %s" % str(tv2["taolue"]))
		print("    换算结果 stat=%s mul=%s" % [str(mod.get("stat", {})), str(mod.get("mul", {}))])
		ok(not mod.is_empty(), "vice_mods_for 不应为空")
		# 战斗类乘区应写进 ext
		var vmul: Dictionary = mod.get("mul", {})
		for mk in vmul.keys():
			if String(mk) == "fortune_add":
				continue
			var ext2: Dictionary = t2["ext"]
			ok(float(ext2.get(mk, 0.0)) >= float(vmul[mk]) - 1e-6,
				"ext.%s 应至少为 %f，实际 %f" % [mk, float(vmul[mk]), float(ext2.get(mk, 0.0))])
			print("    ext.%s = %.4f (副将贡献 %.4f)" % [mk, float(ext2.get(mk, 0.0)), float(vmul[mk])])
		(g["ed_ext"] as Dictionary)["vice_id"] = 0

	# ---------- 5. 运势韬略 ----------
	print("[5] 运势类韬略")
	var tvid := 0
	for v in vl:
		for line in (v["taolue"] as Array):
			if String(line).contains("运势"):
				tvid = int(v["id"])
				break
		if tvid > 0:
			break
	if tvid > 0:
		var vd: Dictionary = d.vices[str(tvid)]
		(g["ed_ext"] as Dictionary)["vice_id"] = tvid
		var t3: Dictionary = d.unit_template(key)
		print("  副将 %s: %s" % [vd["name"], str(vd["taolue"])])
		print("    fortune = %.1f" % float(t3["fortune"]))
		var mod3: Dictionary = d.vice_mods_for(g)
		var fa := float((mod3.get("mul", {}) as Dictionary).get("fortune_add", 0.0))
		ok(fa > 0.0, "运势韬略应换算成 fortune_add > 0")
		(g["ed_ext"] as Dictionary)["vice_id"] = 0
	else:
		print("  （无运势类副将，跳过）")

	# ---------- 6. 无效 vice_id 不崩 ----------
	print("[6] 无效 vice_id")
	total += 1
	var g6: Dictionary = d.generals[key]
	(g6["ed_ext"] as Dictionary)["vice_id"] = 99999
	var t6: Dictionary = d.unit_template(key)
	if t6.is_empty():
		fails += 1
		print("  FAIL 无效 vice_id 导致模板为空")
	else:
		print("  无效 vice_id 正常降级，无报错")
	(g6["ed_ext"] as Dictionary)["vice_id"] = 0

	# ---------- 7. 全部 109 个副将都能挂载不崩 ----------
	print("[7] 遍历全部 109 个副将")
	var crash := 0
	for v in vl:
		var gv: Dictionary = d.generals[key]
		(gv["ed_ext"] as Dictionary)["vice_id"] = int(v["id"])
		var tv: Dictionary = d.unit_template(key)
		if tv.is_empty() or not (tv.has("stats")):
			crash += 1
		(gv["ed_ext"] as Dictionary)["vice_id"] = 0
	ok(crash == 0, "有 %d 个副将挂载失败" % crash)
	print("  109 个副将全部挂载成功")

	# ---------- 8. 战斗中使用副将加成的单位 ----------
	print("[8] 战斗引擎接收副将修正")
	var BATTLE = preload("res://scripts/core/ed_battle.gd")
	var b = BATTLE.new()
	# 先取未挂副将时的 ext 基线
	(g["ed_ext"] as Dictionary)["vice_id"] = 0
	var t_base: Dictionary = d.unit_template(key)
	var ext_base: Dictionary = t_base["ext"]
	(g["ed_ext"] as Dictionary)["vice_id"] = int(vl[0]["id"])
	var tv8: Dictionary = d.unit_template(key)
	var u8 = b.add_unit(tv8, Vector2i(1, 1), 0)
	var ext8: Dictionary = u8["ext"]
	var mod8: Dictionary = d.vice_mods_for(g)
	var vmul8: Dictionary = mod8.get("mul", {})
	# 副将的贡献是「叠加在原有基础上」，所以比对增量而非绝对值
	for mk in vmul8.keys():
		if String(mk) == "fortune_add":
			continue
		var delta := float(ext8.get(mk, 0.0)) - float(ext_base.get(mk, 0.0))
		ok(absf(delta - float(vmul8[mk])) < 1e-6,
			"战斗中 ext.%s 增量应为 %f，实际 %f" % [mk, float(vmul8[mk]), delta])
		print("    ext.%s: %.4f -> %.4f (+%.4f, 期望 +%.4f)" % [
			mk, float(ext_base.get(mk, 0.0)), float(ext8.get(mk, 0.0)),
			delta, float(vmul8[mk])])
	print("  战斗中单位 ext 携带副将乘区: %s" % str(vmul8))
	(g["ed_ext"] as Dictionary)["vice_id"] = 0

	print("")
	if fails == 0:
		print("全部通过（%d 项）" % total)
	else:
		print("失败 %d / %d 项" % [fails, total])
	quit(0 if fails == 0 else 1)