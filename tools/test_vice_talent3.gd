extends SceneTree

# 副将天赋机制 · 第三批 20 个（叠层属性 + 常驻增伤）测试
#   验证：叠层定义写入 ext.stack_attrs、触发加层、层数动态影响伤害属性；
#         常驻增伤/减伤/属性正确进入 ext 乘区。
# 用法: godot --headless --path . --script res://tools/test_vice_talent3.gd

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


func _init() -> void:
	print("========== 副将天赋机制测试（第三批20个） ==========")
	d.load_all()

	# ---- 1. 叠层定义进入 ext ----
	print("---- 叠层定义 ----")
	var t1204 := _tmpl(1204)
	var e1204: Dictionary = t1204["ext"]
	var sa: Dictionary = e1204.get("stack_attrs", {})
	_check("叠锋定义进入 stack_attrs", sa.has("叠锋"), str(sa))
	if sa.has("叠锋"):
		var cfg: Dictionary = sa["叠锋"]
		_check("叠锋每层物攻3%上限5", String(cfg.get("stat","")) == "atk" \
			and absf(float(cfg.get("pct",0)) - 0.03) < 1e-6 \
			and int(cfg.get("max",0)) == 5, str(cfg))
	# 触发块进入 ext
	var vfx: Array = e1204.get("vice_talent_fx", [])
	_check("叠锋触发块存在", not vfx.is_empty())

	# ---- 2. stack_stat_mult 按层数返回倍率 ----
	print("---- 叠层属性倍率 ----")
	var fake_unit := {"res": {}, "ext": {"stack_attrs": {"叠锋": {"stat":"atk","pct":0.03,"max":5}}}}
	_check("0层倍率=1", absf(RULEZ.stack_stat_mult(fake_unit, "atk") - 1.0) < 1e-6)
	fake_unit["res"] = {"叠锋": 3}
	_check("3层物攻+9%", absf(RULEZ.stack_stat_mult(fake_unit, "atk") - 1.09) < 1e-6,
		str(RULEZ.stack_stat_mult(fake_unit, "atk")))
	fake_unit["res"] = {"叠锋": 9}
	_check("超过上限按5层=+15%", absf(RULEZ.stack_stat_mult(fake_unit, "atk") - 1.15) < 1e-6,
		str(RULEZ.stack_stat_mult(fake_unit, "atk")))
	_check("叠锋不影响谋攻", absf(RULEZ.stack_stat_mult(fake_unit, "matk") - 1.0) < 1e-6)

	# ---- 3. 触发加层（战斗引擎） ----
	print("---- 触发加层 ----")
	var b = EB.new()
	b.bind_data(d.generals, d.skills, d.talents, d.get_arm_shapes(), d.bonds)
	var g: Dictionary = d.generals["guan_yu"]
	(g["ed_ext"] as Dictionary)["vice_id"] = 1204
	(g["ed_ext"] as Dictionary)["vice_lv"] = 25
	var tp: Dictionary = d.unit_template("guan_yu")
	(g["ed_ext"] as Dictionary)["vice_id"] = 0
	(g["ed_ext"] as Dictionary).erase("vice_lv")
	tp["stats"] = {"max_hp":500,"atk":100,"def":50,"matk":100,"mdef":10,"luck":50,"move":4,"range":1}
	var u = b.add_unit(tp, Vector2i(4,4), 0)
	_check("初始0层", b.get_resource(u, "叠锋") == 0)
	b.passive_on("on_hit", u, {})
	_check("造成伤害后1层", b.get_resource(u, "叠锋") == 1)
	b.passive_on("on_hit", u, {})
	b.passive_on("on_hit", u, {})
	_check("3次后3层", b.get_resource(u, "叠锋") == 3)
	for i in 10:
		b.passive_on("on_hit", u, {})
	_check("不超过上限5层", b.get_resource(u, "叠锋") == 5, "层数 %d" % b.get_resource(u,"叠锋"))

	# ---- 4. 叠层真实影响伤害 ----
	print("---- 叠层影响伤害 ----")
	var target := {"atk":10,"def":0,"matk":0,"mdef":0,"ext":{},"res":{},"side":1}
	var atk0 := RULEZ.damage_direct({"atk":100,"def":0,"ext":{},"res":{}}, target, {"power_mult":1.0})
	var atk5 := RULEZ.damage_direct({"atk":100,"def":0,"ext":{"stack_attrs":{"叠锋":{"stat":"atk","pct":0.03,"max":5}}},"res":{"叠锋":5}}, target, {"power_mult":1.0})
	_check("5层叠锋伤害高于0层", float(atk5["dmg"]) > float(atk0["dmg"]),
		"%.0f -> %.0f" % [float(atk0["dmg"]), float(atk5["dmg"])])

	# ---- 5. 常驻增伤/减伤/属性 ----
	print("---- 常驻增伤 ----")
	var base := _tmpl(0)
	var be: Dictionary = base["ext"]
	var dmg_cases := {1322:"fixed_damage", 1333:"skill_damage", 1310:"skill_damage", 1304:"skill_damage"}
	for vid in dmg_cases.keys():
		var key := String(dmg_cases[vid])
		var tv := _tmpl(int(vid))
		var ev: Dictionary = tv["ext"]
		var delta := float(ev.get(key,0.0)) - float(be.get(key,0.0))
		_check("%d %s 增伤>0" % [int(vid), key], delta > 0.0, "delta %.3f" % delta)
	var gen_cases := [1317, 1218, 1258]
	for vid in gen_cases:
		var tv2 := _tmpl(int(vid))
		var ev2: Dictionary = tv2["ext"]
		var gd := float(ev2.get("damage_bonus",0.0)) - float(be.get("damage_bonus",0.0))
		_check("%d 通用增伤>0" % int(vid), gd > 0.0, "delta %.3f" % gd)
	var cut_cases := [1317, 1259, 1310, 1304, 1218]
	for vid in cut_cases:
		var tv3 := _tmpl(int(vid))
		var ev3: Dictionary = tv3["ext"]
		var cd := float(ev3.get("damage_cut",0.0)) - float(be.get("damage_cut",0.0))
		_check("%d 减伤>0" % int(vid), cd > 0.0, "delta %.3f" % cd)

	# ---- 6. 三批各20个 + 全量配置 ----
	print("---- 全量校验 ----")
	var b1:=0; var b2:=0; var b3:=0
	for vid in d.vices.keys():
		var vv: Dictionary = d.vices[vid]
		var bt := int(vv.get("talent_mech_batch",0))
		if bt==1: b1+=1
		elif bt==2: b2+=1
		elif bt==3:
			b3+=1
			var okc = not (vv.get("talent_triggers",[]) as Array).is_empty() \
				or not (vv.get("talent_mech",[]) as Array).is_empty()
			_check("%d 配置完整" % int(vid), okc)
	_check("第一批20", b1==20, "%d"%b1)
	_check("第二批20", b2==20, "%d"%b2)
	_check("第三批20", b3==20, "%d"%b3)

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)
