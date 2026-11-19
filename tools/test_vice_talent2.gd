extends SceneTree

# 副将天赋机制 · 第二批 20 个（触发型）测试
#   验证：触发块正确进入战斗单位，且在各时机真正产生效果
#   覆盖：暴击后固伤 / 击杀回血 / 受击反伤 / 行动结束回血战意 /
#         受反击回血 / 攻击时暴击提升
# 用法: godot --headless --path . --script res://tools/test_vice_talent2.gd

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


var d = ED.new()


func _mk(b: EB, side: int, pos: Vector2i, vice_id: int, hp: int = 500) -> Dictionary:
	var g: Dictionary = d.generals["guan_yu"]
	var ext: Dictionary = g["ed_ext"]
	ext["vice_id"] = vice_id
	ext["vice_lv"] = 25
	# 走 unit_template 才会解析副将天赋 mech / 触发块
	var t: Dictionary = d.unit_template("guan_yu").duplicate(true)
	ext["vice_id"] = 0
	ext.erase("vice_lv")
	# 覆盖为测试用面板（保持 ext 里已解析好的天赋加成）
	t["name"] = ("我方" if side == 0 else "敌军") + str(b.units.size())
	t["stats"] = {"max_hp": hp, "atk": 100, "def": 50, "matk": 100, "mdef": 10,
		"luck": 50, "move": 4, "range": 1}
	return b.add_unit(t, pos, side)


func _init() -> void:
	print("========== 副将天赋机制测试（第二批20个） ==========")
	d.load_all()
	var b = EB.new()
	b.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)

	# ---- 1. 触发块进入战斗单位 ----
	print("---- 触发块挂载 ----")
	var u = _mk(b, 0, Vector2i(4, 4), 1203)  # 李通 裂伤
	var ext: Dictionary = u["ext"]
	var vfx: Array = ext.get("vice_talent_fx", [])
	_check("裂伤触发块进入单位ext", not vfx.is_empty(), "块数 %d" % vfx.size())
	if not vfx.is_empty():
		var fd: Dictionary = vfx[0]
		_check("触发时机为 on_crit", str(fd.get("trigger", "")) == "on_crit")
		_check("固伤按物攻25%", bool(fd.get("of_atk", false)) and absf(float(fd.get("value", 0)) - 0.25) < 1e-6)

	# ---- 2. 暴击后固伤（李通） ----
	print("---- 暴击后固伤 ----")
	var foe = _mk(b, 1, Vector2i(5, 4), 0, 2000)
	var hp0 := int(foe["hp"])
	b.passive_on("on_crit", u, {"target": foe})
	# 物攻100 * 25% = 25
	_check("裂伤暴击后造成25固伤", int(foe["hp"]) == hp0 - 25,
		"%d → %d" % [hp0, int(foe["hp"])])

	# ---- 3. 击杀后回血（蹋顿） ----
	print("---- 击杀后回血 ----")
	var b2 = EB.new(); b2.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u2 = _mk(b2, 0, Vector2i(4, 4), 1223, 500)
	u2["hp"] = 100
	b2.passive_on("on_kill", u2, {"target": null})
	_check("扫蛮击杀后回10%兵(50)", int(u2["hp"]) == 150, "兵力 %d" % int(u2["hp"]))

	# ---- 4. 受击后对攻击者固伤（朱灵 物防40%） ----
	print("---- 受击后反伤 ----")
	var b3 = EB.new(); b3.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u3 = _mk(b3, 0, Vector2i(4, 4), 1205, 500)
	var attacker = _mk(b3, 1, Vector2i(5, 4), 0, 2000)
	var ahp0 := int(attacker["hp"])
	# 真实游戏 on_hurt 传 {"source": attacker}，target_source 让反伤命中攻击者
	b3.passive_on("on_hurt", u3, {"source": attacker})
	# 物防50 * 40% = 20
	_check("韧守受击后反伤20", int(attacker["hp"]) == ahp0 - 20,
		"%d → %d" % [ahp0, int(attacker["hp"])])

	# ---- 5. 行动结束：赵娥未攻击得战意 ----
	print("---- 行动结束战意 ----")
	var b4 = EB.new(); b4.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u4 = _mk(b4, 0, Vector2i(4, 4), 1234)
	var z0 := int(u4["zhanyi"])
	b4.end_unit_turn(u4)  # 未攻击
	_check("枕戈未攻击得18战意", int(u4["zhanyi"]) == z0 + 18,
		"%d → %d" % [z0, int(u4["zhanyi"])])
	# 攻击后不再获得
	var b5 = EB.new(); b5.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u5 = _mk(b5, 0, Vector2i(4, 4), 1234)
	u5["_turn_attacked"] = true
	var z1 := int(u5["zhanyi"])
	b5.end_unit_turn(u5)
	_check("枕戈攻击后不得战意", int(u5["zhanyi"]) == z1)

	# ---- 6. 行动结束回血（戏志才 兵力<50%） ----
	print("---- 行动结束回血 ----")
	var b6 = EB.new(); b6.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u6 = _mk(b6, 0, Vector2i(4, 4), 1211, 500)
	u6["hp"] = 200  # 40% < 50%
	b6.end_unit_turn(u6)
	_check("残谋兵力<50%回10%兵", int(u6["hp"]) == 250, "兵力 %d" % int(u6["hp"]))
	var b7 = EB.new(); b7.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u7 = _mk(b7, 0, Vector2i(4, 4), 1211, 500)
	u7["hp"] = 400  # 80% > 50%
	b7.end_unit_turn(u7)
	_check("残谋兵力充足不回血", int(u7["hp"]) == 400)

	# ---- 7. 给最低兵力友军回血（糜芮） ----
	print("---- 给友军回血 ----")
	var b8 = EB.new(); b8.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u8 = _mk(b8, 0, Vector2i(4, 4), 1239, 500)
	var low = _mk(b8, 0, Vector2i(4, 5), 0, 500)
	low["hp"] = 100
	b8.end_unit_turn(u8)
	_check("慈援给最低兵力友军回50", int(low["hp"]) == 150, "兵力 %d" % int(low["hp"]))

	# ---- 8. 攻击时暴击提升（常驻 mech） ----
	print("---- 攻击时暴击提升 ----")
	var cases: Dictionary = {}
	cases[1245] = ["锐矢", 0.20]
	cases[1313] = ["扶汉", 0.20]
	cases[1232] = ["荡寇", 0.10]
	cases[1326] = ["趁虚", 0.18]
	cases[1306] = ["震击", 0.20]
	cases[1262] = ["砺锋", 0.40]
	cases[1312] = ["虎跃", 0.24]
	cases[1282] = ["反行", 0.22]
	for vid in cases.keys():
		var tv := _mk(b, 0, Vector2i(4, 4), int(vid))
		var ev: Dictionary = tv["ext"]
		var arr: Array = cases[vid]
		var want := float(arr[1])
		_check("%d %s 暴击率+%.0f%%" % [int(vid), arr[0], want * 100.0],
			float(ev.get("crit_bonus", 0.0)) >= want - 1e-6,
			"实际 %.3f" % float(ev.get("crit_bonus", 0.0)))

	# ---- 9. 第二批 20 个全部配置 ----
	print("---- 全量校验 ----")
	var b1c := 0
	var b2c := 0
	for vid in d.vices.keys():
		var vv: Dictionary = d.vices[vid]
		var bt := int(vv.get("talent_mech_batch", 0))
		if bt == 1: b1c += 1
		if bt == 2:
			b2c += 1
			var ok_cfg = not (vv.get("talent_triggers", []) as Array).is_empty() \
				or not (vv.get("talent_mech", []) as Array).is_empty()
			_check("%d 机制配置完整" % int(vid), ok_cfg)
	_check("第一批20个", b1c == 20, "实际 %d" % b1c)
	_check("第二批20个", b2c == 20, "实际 %d" % b2c)

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)
