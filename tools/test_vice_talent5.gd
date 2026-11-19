extends SceneTree

# 副将天赋机制 · 第五批（收尾批 29 个）测试
#   验证：每回合首次减伤、新增触发事件、以及 109/109 全覆盖
# 用法: godot --headless --path . --script res://tools/test_vice_talent5.gd

const ED = preload("res://scripts/core/ed_data.gd")
const EB = preload("res://scripts/core/ed_battle.gd")
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

func _tmpl(vice_id: int) -> Dictionary:
	var g: Dictionary = d.generals["guan_yu"]
	var ext: Dictionary = g["ed_ext"]
	ext["vice_id"] = vice_id
	ext["vice_lv"] = 25
	var t: Dictionary = d.unit_template("guan_yu").duplicate(true)
	ext["vice_id"] = 0
	ext.erase("vice_lv")
	return t

func _mk(b: EB, vice_id: int, pos: Vector2i, side: int = 0) -> Dictionary:
	var t := _tmpl(vice_id)
	t["name"] = "T%d_%d" % [vice_id, b.units.size()]
	t["stats"] = {"max_hp":500,"atk":100,"def":50,"matk":100,"mdef":10,"luck":50,"move":4,"range":1}
	var u = b.add_unit(t, pos, side)
	u["hp"] = 500
	return u

func _init() -> void:
	print("========== 副将天赋机制测试（第五批收尾） ==========")
	d.load_all()

	# ---- 1. 每回合首次减伤（鲍信/毛玠） ----
	print("---- 每回合首次减伤 ----")
	var b = EB.new()
	b.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var u1201 = _mk(b, 1201, Vector2i(4,4))
	var e: Dictionary = u1201["ext"]
	_check("御锋 first_hit_cut=15%", absf(float(e.get("first_hit_cut",0)) - 0.15) < 1e-6,
		str(e.get("first_hit_cut")))
	var d1 := b._apply_incoming(u1201, 100)
	_check("首次伤害减15%=85", d1 == 85, "实际 %d" % d1)
	var d2 := b._apply_incoming(u1201, 100)
	_check("第二次伤害不减=100", d2 == 100, "实际 %d" % d2)
	# 下回合重置
	u1201["_first_hit_used"] = false
	var d3 := b._apply_incoming(u1201, 100)
	_check("重置后再次减伤=85", d3 == 85, "实际 %d" % d3)
	# 毛玠 11%
	var u1221 = _mk(b, 1221, Vector2i(6,4))
	_check("先佐 first_hit_cut=11%", absf(float((u1221["ext"] as Dictionary).get("first_hit_cut",0)) - 0.11) < 1e-6)

	# ---- 2. 移动2格条件（臧霸长驱） ----
	print("---- 移动格数条件 ----")
	var b2 = EB.new(); b2.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1213 = _mk(b2, 1213, Vector2i(4,4))
	var vfx: Array = (u1213["ext"] as Dictionary).get("vice_talent_fx", [])
	_check("长驱触发块存在", not vfx.is_empty())
	if not vfx.is_empty():
		_check("长驱min_move=2", int((vfx[0] as Dictionary).get("min_move",0)) == 2)
	var foe = _mk(b2, 0, Vector2i(5,4), 1)
	foe["hp"] = 2000
	var hp0 := int(foe["hp"])
	b2.passive_on("on_attack_before", u1213, {"target":foe,"move_tiles":0})
	_check("未移动2格不触发", int(foe["hp"]) == hp0)
	b2.passive_on("on_attack_before", u1213, {"target":foe,"move_tiles":3})
	_check("移动2格后固伤", int(foe["hp"]) < hp0, "%d→%d"%[hp0,int(foe["hp"])])

	# ---- 3. 施加减益触发（司马干威逼） ----
	print("---- 施加减益触发 ----")
	var b3 = EB.new(); b3.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1327 = _mk(b3, 1327, Vector2i(4,4))
	var tgt = _mk(b3, 0, Vector2i(5,4), 1)
	tgt["hp"] = 2000
	var t0 := int(tgt["hp"])
	b3._add_debuff(tgt, "虚弱", 2, u1327)
	_check("施加减益后触发固伤", int(tgt["hp"]) < t0, "%d→%d"%[t0,int(tgt["hp"])])

	# ---- 4. 击退触发（周循审时） ----
	print("---- 击退触发叠层 ----")
	var b4 = EB.new(); b4.bind_data(d.generals,d.skills,d.talents,d.get_arm_shapes(),d.bonds)
	var u1323 = _mk(b4, 1323, Vector2i(4,4))
	var tgt4 = _mk(b4, 0, Vector2i(5,4), 1)
	_check("审时初始0层", b4.get_resource(u1323,"审时") == 0)
	b4._push(u1323, tgt4, 1)
	_check("击退后审时+1层", b4.get_resource(u1323,"审时") == 1)

	# ---- 5. 常驻类抽查 ----
	print("---- 常驻类抽查 ----")
	# 增伤键经 dmg_map 映射：dmg_normal->normal_damage, dmg_restrict->restrict_damage
	var cases := {
		1257: ["normal_damage", 0.08],
		1226: ["restrict_damage", 0.12],
	}
	for vid in cases.keys():
		var tv := _tmpl(int(vid))
		var arr: Array = cases[vid]
		var key := String(arr[0])
		var want := float(arr[1])
		var ev: Dictionary = tv["ext"]
		_check("%d 常驻增伤存在" % int(vid), float(ev.get(key,0)) >= want - 1e-6,
			str(ev.get(key)))
	# 属性类从 mech 解析结果校验
	var m1210 := RULEZ.vice_talent_mech(d.vices["1210"], 25)
	_check("1210 常驻谋攻+8%", float(m1210.get("stat_matk",0)) >= 0.08 - 1e-6)

	# ---- 6. 全量覆盖：109/109 ----
	print("---- 全量覆盖校验 ----")
	var total := 0
	var batch_counts: Dictionary = {}
	for vid in d.vices.keys():
		total += 1
		var vv: Dictionary = d.vices[vid]
		var bt := int(vv.get("talent_mech_batch", 0))
		batch_counts[bt] = int(batch_counts.get(bt, 0)) + 1
		# 每个天赋必须有某种机制
		var has = not (vv.get("talent_mech",[]) as Array).is_empty() \
			or not (vv.get("talent_triggers",[]) as Array).is_empty() \
			or not (vv.get("talent_cond_attrs",[]) as Array).is_empty() \
			or not (vv.get("talent_stack_attrs",{}) as Dictionary).is_empty()
		if not has:
			_check("%d 有机制" % int(vid), false)
	_check("副将总数109", total == 109, "实际 %d" % total)
	_check("无未实装天赋", int(batch_counts.get(0,0)) == 0, "未做 %d" % int(batch_counts.get(0,0)))
	for bt in [1,2,3,4]:
		print("  批次%d: %d 个" % [bt, int(batch_counts.get(bt,0))])
	print("  批次5(收尾): %d 个" % int(batch_counts.get(5,0)))
	_check("批次1-4各20", int(batch_counts.get(1,0))==20 and int(batch_counts.get(2,0))==20 \
		and int(batch_counts.get(3,0))==20 and int(batch_counts.get(4,0))==20)
	_check("批次5共29", int(batch_counts.get(5,0))==29, "%d"%int(batch_counts.get(5,0)))

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails: print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)
