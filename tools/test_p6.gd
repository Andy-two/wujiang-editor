extends SceneTree

# P6 机制专项测试：转移 / 设施（粮仓）
#   ① 转移：把敌军战意转给友军
#   ② 转移：友军战意已满时不转移
#   ③ 设施：召唤后可被收获，次数递减
#   ④ 设施：持续时间到期消失
#   ⑤ 设施：多等级只生效最高级
# 用法: godot --headless --path . --script res://tools/test_p6.gd

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


func _mk(b: EB, side: int, pos: Vector2i, hp: int = 300, zhanyi: int = 0) -> Dictionary:
	var t := {"key": "", "name": ("我方" if side == 0 else "敌军") + str(b.units.size()),
		"arm": "盾", "color": "#3b82f6", "level": 1, "star": 1,
		"stats": {"max_hp": hp, "atk": 30, "def": 10, "matk": 10, "mdef": 10,
			"luck": 50, "move": 4, "range": 1},
		"skills": []}
	var u = b.add_unit(t, pos, side)
	u["zhanyi"] = zhanyi
	return u


func _init() -> void:
	print("========== P6 机制专项测试 ==========")
	_test_transfer()
	_test_facility()
	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)


# ---------------- 转移 ----------------
func _test_transfer() -> void:
	print("---- 转移：把降低的战意转给友军 ----")
	var b = EB.new()
	var caster = _mk(b, 0, Vector2i(4, 4))
	var foe = _mk(b, 1, Vector2i(5, 4), 300, 60)     # 战意 60
	var ally = _mk(b, 0, Vector2i(4, 5), 300, 10)    # 战意 10
	var far_ally = _mk(b, 0, Vector2i(10, 10), 300, 0)  # 范围外

	var moved: int = b.transfer_zhanyi(caster, 10, 3)
	_check("转移成功", moved == 10, "实际转移 %d" % moved)
	_check("敌军战意减少 10", int(foe["zhanyi"]) == 50,
		"%d → %d" % [60, int(foe["zhanyi"])])
	_check("友军战意增加 10", int(ally["zhanyi"]) == 20,
		"%d → %d" % [10, int(ally["zhanyi"])])
	_check("范围外友军未获得战意", int(far_ally["zhanyi"]) == 0,
		"%d → %d" % [0, int(far_ally["zhanyi"])])

	# 友军战意已满
	var b2 = EB.new()
	var c2 = _mk(b2, 0, Vector2i(4, 4))
	var f2 = _mk(b2, 1, Vector2i(5, 4), 300, 60)
	var a2 = _mk(b2, 0, Vector2i(4, 5), 300, 100)   # 战意已满
	var moved2: int = b2.transfer_zhanyi(c2, 10, 3)
	_check("友军战意满时不转移", moved2 == 0, "实际转移 %d" % moved2)
	_check("友军战意满时敌军战意不变", int(f2["zhanyi"]) == 60)

	# 范围内无友军
	var b3 = EB.new()
	var c3 = _mk(b3, 0, Vector2i(4, 4))
	var f3 = _mk(b3, 1, Vector2i(5, 4), 300, 60)
	var moved3: int = b3.transfer_zhanyi(c3, 10, 3)
	_check("无友军可接收时不转移", moved3 == 0)

	# 优先给战意最低的友军
	var b4 = EB.new()
	var c4 = _mk(b4, 0, Vector2i(4, 4))
	var f4 = _mk(b4, 1, Vector2i(5, 4), 300, 60)
	var low = _mk(b4, 0, Vector2i(4, 5), 300, 5)
	var high = _mk(b4, 0, Vector2i(4, 3), 300, 50)
	b4.transfer_zhanyi(c4, 10, 3)
	_check("优先给战意最低的友军", int(low["zhanyi"]) == 15 and int(high["zhanyi"]) == 50,
		"low=%d high=%d" % [int(low["zhanyi"]), int(high["zhanyi"])])


# ---------------- 设施 ----------------
func _test_facility() -> void:
	print("---- 设施（粮仓）：召唤 / 收获 / 持续时间 ----")
	var b = EB.new()
	var caster = _mk(b, 0, Vector2i(4, 4), 100)
	var fx := {"type": "facility", "value": "粮仓", "turns": 3, "uses": 2,
		"heal_pct": 0.15, "buff": "奋强", "buff_turns": 2, "extra_turn": true}

	var pos := Vector2i(5, 4)
	b.add_facility("粮仓", pos, 0, fx)
	_check("设施已召唤", b.facilities.size() == 1)
	_check("设施名称正确", String(b.facilities[0]["name"]) == "粮仓")
	_check("设施剩余次数为 2", int(b.facilities[0]["uses"]) == 2)

	# 单位站上去收获
	var farmer = _mk(b, 0, pos, 100)
	farmer["hp"] = 50
	var r: Dictionary = b.harvest_facility(farmer, b.facilities[0])
	_check("收获成功", bool(r.get("ok", false)), str(r.get("msg", "")))
	_check("收获回复了兵力", int(farmer["hp"]) == 65,
		"50 → %d（期望 65 = 100*15%% + 50）" % int(farmer["hp"]))
	_check("收获施加了「奋强」", b._has_buff(farmer, "奋强"))
	_check("收获消耗 1 次", int(b.facilities[0]["uses"]) == 1)

	# 再收获一次，次数用尽
	var farmer2 = _mk(b, 0, pos, 100)
	b.harvest_facility(farmer2, b.facilities[0])
	_check("次数用尽后无法收获", int(b.facilities[0]["uses"]) == 0)
	var r2: Dictionary = b.harvest_facility(farmer2, b.facilities[0])
	_check("次数用尽时收获失败", not bool(r2.get("ok", false)))

	# 敌方不能收获
	var b2 = EB.new()
	var c2 = _mk(b2, 0, Vector2i(4, 4))
	var p2 := Vector2i(5, 4)
	b2.add_facility("粮仓", p2, 0, fx)
	var enemy = _mk(b2, 1, p2, 100)
	var r3: Dictionary = b2.harvest_facility(enemy, b2.facilities[0])
	_check("敌方无法收获己方设施", not bool(r3.get("ok", false)))

	# 持续时间到期消失
	var b3 = EB.new()
	b3.add_facility("粮仓", Vector2i(5, 4), 0, fx)
	b3._tick_facilities()
	b3._tick_facilities()
	_check("设施持续时间递减", int(b3.facilities[0]["turns"]) == 1)
	b3._tick_facilities()
	_check("设施到期后消失", b3.facilities.is_empty())

	# 数据校验
	var data = ED.new()
	data.load_all()
	var kt = data.skills.get("off_开屯护民", {})
	var fx_list: Array = kt.get("ed_fx_list", [])
	var fac := _count_type(fx_list, "facility")
	_check("开屯护民配了设施块", fac >= 1, "实际 %d" % fac)
	var has_summon := _count_type(fx_list, "summon") > 0
	_check("开屯护民不再召唤援军", not has_summon)
	var wuying = data.skills.get("wuying", {})
	_check("舞影配了转移块",
		_count_type(wuying.get("ed_fx_list", []), "transfer") >= 1)
	_check("transfer 在效果块类型列表中", RULEZ.SFX_TYPES.has(RULEZ.SFX_TRANSFER))
	_check("facility 在效果块类型列表中", RULEZ.SFX_TYPES.has(RULEZ.SFX_FACILITY))
	_check("transfer 有界面标签", RULEZ.SFX_LABELS.has(RULEZ.SFX_TRANSFER))
	_check("facility 有界面标签", RULEZ.SFX_LABELS.has(RULEZ.SFX_FACILITY))
	_check("facility 有可读文案",
		String(RULEZ.sfx_text(RULEZ.default_sfx(RULEZ.SFX_FACILITY))).contains("设施"))


func _count_type(fx_list: Array, t: String) -> int:
	var n := 0
	for f in fx_list:
		if f is Dictionary and String(f.get("type", "")) == t:
			n += 1
	return n

