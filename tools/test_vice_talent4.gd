extends SceneTree

# 副将天赋机制 · 第四批 20 个（条件属性）测试
#   验证：条件定义进入ext、_update_cond_mult按条件计算、cond_mult影响伤害、
#         战斗刷新时机正确。
# 用法: godot --headless --path . --script res://tools/test_vice_talent4.gd

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

var d = ED.new()

func _tmpl(vice_id: int) -> Dictionary:
	var g: Dictionary = d.generals["guan_yu"]
	var ext: Dictionary = g["ed_ext"]
	ext["vice_id"] = vice_id
	ext["vice_lv"] = 25
	var t: Dictionary = d.unit_template("guan_yu").duplicate(true)
	ext["vice_id"] = 0
	ext.erase("vice_lv")
	return t

func _mk(b: EB, vice_id: int, pos: Vector2i, side: int = 0, hp: int = 500) -> Dictionary:
	var t := _tmpl(vice_id)
	t["name"] = "T%d_%d" % [vice_id, b.units.size()]
	t["stats"] = {"max_hp":hp,"atk":100,"def":50,"matk":100,"mdef":10,"luck":50,"move":4,"range":1}
	var u = b.add_unit(t, pos, side)
	u["hp"] = hp
	return u

func _init() -> void:
	print("========== 副将天赋机制测试（第四批20个） ==========")
	d.load_all()

	# ---- 1. 条件定义进入ext ----
	print("---- 条件定义 ----")
	var t1208 := _tmpl(1208)
	var ca: Array = (t1208["ext"] as Dictionary).get("cond_attrs", [])
	_check("史涣条件定义进入ext", not ca.is_empty(), "块数 %d" % ca.size())
	if not ca.is_empty():
		var c0: Dictionary = ca[0]
		_check("条件为 hp_above 0.8", str(c0.get("cond","")) == "hp_above" \
			and absf(float(c0.get("value",0)) - 0.8) < 1e-6, str(c0))

	# ---- 2. 兵力阈值条件动态计算 ----
	print("---- 兵力阈值 ----")
	var b = EB.new()
	b.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u1208 = _mk(b, 1208, Vector2i(4,4), 0, 500)
	# 满兵 -> 谋防+10%
	u1208["hp"] = 500
	b._update_cond_mult(u1208)
	_check("满兵谋防+10%", absf(float(u1208["cond_mult"].get("mdef",1)) - 1.10) < 1e-6,
		str(u1208["cond_mult"]))
	# 低兵 -> 无加成
	u1208["hp"] = 200
	b._update_cond_mult(u1208)
	_check("低兵无加成", absf(float(u1208["cond_mult"].get("mdef",1)) - 1.0) < 1e-6,
		str(u1208["cond_mult"]))

	# 娄圭 兵力<90%谋攻+8%
	var b2 = EB.new(); b2.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1224 = _mk(b2, 1224, Vector2i(4,4), 0, 500)
	u1224["hp"] = 400  # 80% < 90%
	b2._update_cond_mult(u1224)
	_check("娄圭兵力<90%谋攻+8%", absf(float(u1224["cond_mult"].get("matk",1)) - 1.08) < 1e-6,
		str(u1224["cond_mult"]))
	u1224["hp"] = 500
	b2._update_cond_mult(u1224)
	_check("娄圭满兵无加成", absf(float(u1224["cond_mult"].get("matk",1)) - 1.0) < 1e-6)

	# ---- 3. 范围内无敌/友 ----
	print("---- 范围内无敌友 ----")
	var b3 = EB.new(); b3.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1216 = _mk(b3, 1216, Vector2i(5,5), 0, 500)  # 邹蕙 1格内无敌双攻+15%
	b3._update_cond_mult(u1216)
	_check("无敌军时双攻+15%", absf(float(u1216["cond_mult"].get("atk",1)) - 1.15) < 1e-6)
	# 放一个敌军在2格外（超出1格）不触发
	var _f1 = _mk(b3, 0, Vector2i(8,8), 1, 500)
	b3._update_cond_mult(u1216)
	_check("远敌不触发", absf(float(u1216["cond_mult"].get("atk",1)) - 1.15) < 1e-6)
	# 放一个敌军在相邻
	var _f2 = _mk(b3, 0, Vector2i(5,4), 1, 500)
	b3._update_cond_mult(u1216)
	_check("相邻有敌取消加成", absf(float(u1216["cond_mult"].get("atk",1)) - 1.0) < 1e-6,
		str(u1216["cond_mult"]))

	# 陈宫 1格内无友全属性+15%
	var b4 = EB.new(); b4.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1309 = _mk(b4, 1309, Vector2i(5,5), 0, 500)
	b4._update_cond_mult(u1309)
	_check("陈宫落单全属性+15%", absf(float(u1309["cond_mult"].get("atk",1)) - 1.15) < 1e-6 \
		and absf(float(u1309["cond_mult"].get("def",1)) - 1.15) < 1e-6)
	var _ally = _mk(b4, 0, Vector2i(5,4), 0, 500)
	b4._update_cond_mult(u1309)
	_check("陈宫有友取消加成", absf(float(u1309["cond_mult"].get("atk",1)) - 1.0) < 1e-6)

	# ---- 4. buff数量条件（司马徽） ----
	print("---- 增益数量条件 ----")
	var b5 = EB.new(); b5.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1311 = _mk(b5, 1311, Vector2i(4,4), 0, 500)
	b5._update_cond_mult(u1311)
	_check("无增益无加成", absf(float(u1311["cond_mult"].get("matk",1)) - 1.0) < 1e-6)
	b5._add_buff(u1311, "昂扬", 3, 1)
	b5._add_buff(u1311, "奋勇", 3, 1)
	b5._add_buff(u1311, "严阵", 3, 1)
	b5._update_cond_mult(u1311)
	_check("3增益谋攻+18%", absf(float(u1311["cond_mult"].get("matk",1)) - 1.18) < 1e-6,
		str(u1311["cond_mult"]))

	# ---- 5. 条件属性真实影响伤害 ----
	print("---- 条件属性影响伤害 ----")
	var tgt := {"atk":10,"def":0,"matk":0,"mdef":0,"ext":{},"res":{},"side":1,"cond_mult":{}}
	var a0 := RULEZ.damage_direct({"atk":100,"def":0,"ext":{},"res":{},"cond_mult":{}}, tgt, {"power_mult":1.0})
	var a1 := RULEZ.damage_direct({"atk":100,"def":0,"ext":{},"res":{},"cond_mult":{"atk":1.15}}, tgt, {"power_mult":1.0})
	_check("条件物攻+15%提升伤害", float(a1["dmg"]) > float(a0["dmg"]),
		"%.0f -> %.0f" % [float(a0["dmg"]), float(a1["dmg"])])

	# ---- 6. always条件（常驻近似） ----
	print("---- always条件 ----")
	var t1222 := _tmpl(1222)
	var b6 = EB.new(); b6.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1222 = b6.add_unit(t1222, Vector2i(4,4), 0)
	b6._update_cond_mult(u1222)
	_check("杜若always谋攻+15%", absf(float(u1222["cond_mult"].get("matk",1)) - 1.15) < 1e-6,
		str(u1222["cond_mult"]))

	# ---- 7. 四批各20 + 全量校验 ----
	print("---- 全量校验 ----")
	var cnt1 := 0
	var cnt2 := 0
	var cnt3 := 0
	var cnt4 := 0
	for vid in d.vices.keys():
		var vv: Dictionary = d.vices[vid]
		var bt := int(vv.get("talent_mech_batch", 0))
		if bt == 1:
			cnt1 += 1
		elif bt == 2:
			cnt2 += 1
		elif bt == 3:
			cnt3 += 1
		elif bt == 4:
			cnt4 += 1
			_check("%d 有条件定义" % int(vid), not (vv.get("talent_cond_attrs", []) as Array).is_empty())
	_check("批一20", cnt1 == 20, "%d" % cnt1)
	_check("批二20", cnt2 == 20, "%d" % cnt2)
	_check("批三20", cnt3 == 20, "%d" % cnt3)
	_check("批四20", cnt4 == 20, "%d" % cnt4)

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails: print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)
