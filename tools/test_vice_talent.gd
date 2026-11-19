extends SceneTree

# 副将天赋机制 · 第一批 20 个常驻加成测试
#   验证：挂载副将后，天赋常驻加成正确进入主将面板/ext 乘区
#   覆盖：属性% / 普攻/追击/反击伤害 / 治疗 / 增伤减伤 / 暴伤 / 护盾
# 用法: godot --headless --path . --script res://tools/test_vice_talent.gd

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


# 挂载副将并取模板；key 用固定武将
func _tmpl(vice_id: int) -> Dictionary:
	var g: Dictionary = d.generals["guan_yu"]
	var ext: Dictionary = g["ed_ext"]
	ext["vice_id"] = vice_id
	ext["vice_lv"] = 25
	var t: Dictionary = d.unit_template("guan_yu")
	ext["vice_id"] = 0
	ext.erase("vice_lv")
	return t


# 取未挂副将的基线
func _base() -> Dictionary:
	var g: Dictionary = d.generals["guan_yu"]
	(g["ed_ext"] as Dictionary)["vice_id"] = 0
	return d.unit_template("guan_yu")


func _init() -> void:
	print("========== 副将天赋机制测试（第一批20个） ==========")
	d.load_all()
	var base := _base()
	var base_ext: Dictionary = base["ext"]

	# ---- 1. 解析层单测 ----
	print("---- 解析层 ----")
	var v1229: Dictionary = d.vices["1229"]
	var mech := RULEZ.vice_talent_mech(v1229, 25)
	_check("励军解析出 stat_matk=5%", absf(float(mech.get("stat_matk", 0)) - 0.05) < 1e-6,
		str(mech))
	var v1543: Dictionary = d.vices["1543"]
	var mech2 := RULEZ.vice_talent_mech(v1543, 25)
	_check("让梨解析出 stat_matk=10%", absf(float(mech2.get("stat_matk", 0)) - 0.10) < 1e-6)
	var empty := RULEZ.vice_talent_mech({}, 25)
	_check("无天赋数据返回空", empty.is_empty())

	# ---- 2. 属性类天赋（面板倍率） ----
	print("---- 属性类天赋 ----")
	var attr_cases := {
		1229: ["matk", 0.05], 1248: ["matk", 0.05], 1543: ["matk", 0.10],
		1318: ["matk", 0.15], 1319: ["matk", 0.15], 1219: ["max_hp", 0.08],
		1235: ["def", 0.08],
	}
	for vid in attr_cases.keys():
		var arr: Array = attr_cases[vid]
		var stat_key := String(arr[0])
		var want := float(arr[1])
		# 基线不挂副将（无属性加成），挂副将后有固定属性加成，需分离：
		# 用 vice_lv=1 且该副将 base_attr 全 0 的情况验证纯百分比
		var v: Dictionary = d.vices[str(vid)]
		var ba: Dictionary = v.get("base_attr", {})
		var fixed := 0
		if stat_key == "max_hp":
			fixed = int(ba.get("hp", 0))
		else:
			fixed = int(ba.get(stat_key, 0))
		var g: Dictionary = d.generals["guan_yu"]
		var ext: Dictionary = g["ed_ext"]
		ext["vice_id"] = vid
		ext["vice_lv"] = 1
		var t: Dictionary = d.unit_template("guan_yu")
		ext["vice_id"] = 0
		ext.erase("vice_lv")
		var before := float(base["stats"][stat_key])
		var after := float(t["stats"][stat_key]) - float(fixed)
		if before <= 0.0:
			continue
		var got := after / before - 1.0
		_check("%d %s 属性+%d%%" % [vid, v["name"], int(want * 100)],
			absf(got - want) < 0.03, "实际 +%.2f%% (before %.0f after %.0f fixed %d)" % [
				got * 100.0, before, after, fixed])

	# ---- 3. 伤害类型增伤（ext 乘区） ----
	print("---- 伤害类型增伤 ----")
	var dmg_cases := {
		1237: "normal_damage", 1228: "normal_damage", 1275: "pursue_damage",
		1214: "pursue_damage", 1256: "counter_damage",
	}
	for vid in dmg_cases.keys():
		var key := String(dmg_cases[vid])
		var t2 := _tmpl(vid)
		var ext2: Dictionary = t2["ext"]
		var delta := float(ext2.get(key, 0.0)) - float(base_ext.get(key, 0.0))
		_check("%d %s %s 有增伤" % [vid, d.vices[str(vid)]["name"], key],
			delta > 0.0, "delta=%.3f" % delta)

	# ---- 4. 诸葛均潜谋（追击+30%、通用增伤10%、减伤6%） ----
	print("---- 组合天赋 ----")
	var t3 := _tmpl(1277)
	var e3: Dictionary = t3["ext"]
	_check("潜谋 追击伤害+30%",
		absf(float(e3.get("pursue_damage", 0.0)) - 0.30) < 1e-6, str(e3.get("pursue_damage")))
	# 天赋 +10% 会与副将自身韬略叠加（韬略也有增伤），所以断言 >= 天赋值
	_check("潜谋 通用增伤≥10%",
		float(e3.get("damage_bonus", 0.0)) - float(base_ext.get("damage_bonus", 0.0)) >= 0.10 - 1e-6,
		str(e3.get("damage_bonus")))
	_check("潜谋 受到伤害减免≥6%",
		float(e3.get("damage_cut", 0.0)) - float(base_ext.get("damage_cut", 0.0)) >= 0.06 - 1e-6,
		str(e3.get("damage_cut")))

	# ---- 5. 治疗/护盾类 ----
	print("---- 治疗/护盾类 ----")
	for vid in [1271, 1272, 1273, 1303]:
		var tv := _tmpl(vid)
		var ev: Dictionary = tv["ext"]
		var hb := float(ev.get("heal_bonus", 0.0)) - float(base_ext.get("heal_bonus", 0.0))
		_check("%d %s 治疗加成>0" % [vid, d.vices[str(vid)]["name"]], hb > 0.0, "heal=%.3f" % hb)
	var tsh := _tmpl(1272)
	var esh: Dictionary = tsh["ext"]
	_check("预攻 护盾率+15%",
		absf(float(esh.get("shield_bonus", 0.0)) - 0.15) < 1e-6, str(esh.get("shield_bonus")))

	# ---- 6. 增伤减伤类 ----
	print("---- 增伤减伤类 ----")
	var t4 := _tmpl(1264)
	var e4: Dictionary = t4["ext"]
	_check("党立 增伤≥15%",
		float(e4.get("damage_bonus", 0.0)) - float(base_ext.get("damage_bonus", 0.0)) >= 0.15 - 1e-6,
		str(e4.get("damage_bonus")))
	_check("党立 减伤≥15%",
		float(e4.get("damage_cut", 0.0)) - float(base_ext.get("damage_cut", 0.0)) >= 0.15 - 1e-6,
		str(e4.get("damage_cut")))

	# ---- 7. 暴伤类 ----
	print("---- 暴伤类 ----")
	var t5 := _tmpl(1230)
	var e5: Dictionary = t5["ext"]
	_check("铁骑 暴伤加成+12%",
		absf(float(e5.get("crit_damage", 0.0)) - 0.12) < 1e-6, str(e5.get("crit_damage")))

	# ---- 8. 受普攻减伤 ----
	print("---- 受普攻减伤 ----")
	var t6 := _tmpl(1207)
	var e6: Dictionary = t6["ext"]
	_check("严守 受普攻伤害-15%",
		absf(float(e6.get("normal_cut", 0.0)) - 0.15) < 1e-6, str(e6.get("normal_cut")))

	# ---- 9. 20 个天赋全部有 mech 且能被解析 ----
	print("---- 全量校验 ----")
	var batch_cnt := 0
	for vid in d.vices.keys():
		var vv: Dictionary = d.vices[vid]
		if int(vv.get("talent_mech_batch", 0)) == 1:
			batch_cnt += 1
			var mm := RULEZ.vice_talent_mech(vv, 25)
			_check("%d 天赋有可解析机制" % int(vid), not mm.is_empty())
	_check("第一批正好20个", batch_cnt == 20, "实际 %d" % batch_cnt)

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)
