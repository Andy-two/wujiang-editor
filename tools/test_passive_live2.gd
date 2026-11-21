extends SceneTree

# 实测5个还原被动的真实战斗效果
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

var passed := 0
var failed := 0


func _check(n: String, c: bool, d: String = "") -> void:
	if c:
		passed += 1
		print("  ✔ ", n)
	else:
		failed += 1
		print("  ✖ ", n, ("" if d == "" else "（" + d + "）"))


func _mk(data, bt, key, pos):
	return bt.add_unit(data.unit_template(key, 50, 5, ""), pos, 0)


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()

	print("===== 1. 偃月阵：3格内友军受谋略伤害-10% =====")
	var bt = EdBattle.new(13, 11)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var guan = bt.add_unit(data.unit_template("guan_yu", 50, 5, ""), Vector2i(5, 5), 0)
	var ally_near = bt.add_unit(data.unit_template("guan_yu", 50, 5, ""), Vector2i(6, 5), 0)
	ally_near["skills"] = []  # 去掉偃月阵，避免自己影响
	ally_near["ext"] = {}
	var ally_far = bt.add_unit(data.unit_template("guan_yu", 50, 5, ""), Vector2i(11, 9), 0)
	ally_far["skills"] = []
	ally_far["ext"] = {}
	bt._refresh_all_cond_mult()
	var near_cut := float((ally_near.get("ext", {}) as Dictionary).get("magic_cut", 0.0))
	var far_cut := float((ally_far.get("ext", {}) as Dictionary).get("magic_cut", 0.0))
	print("  近友军 magic_cut=%.3f  远友军=%.3f" % [near_cut, far_cut])
	_check("3格内友军获得谋略减伤10%", absf(near_cut - 0.10) < 0.001, str(near_cut))
	_check("3格外友军无减伤", far_cut < 0.001, str(far_cut))

	print("===== 2. 游刃八方：2格内每敌军物攻物防+5%上限10% =====")
	var bt2 = EdBattle.new(13, 11)
	bt2.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var zf = bt2.add_unit(data.unit_template("zhang_fei", 50, 5, ""), Vector2i(5, 5), 0)
	# 放3个敌军在2格内
	for i in 3:
		var foe = bt2.add_unit(data.unit_template("jia_xu", 50, 5, ""), Vector2i(5 + i, 6), 1)
	bt2._refresh_all_cond_mult()
	var cm: Dictionary = zf.get("cond_mult", {})
	var atk_m := float(cm.get("atk", 1.0))
	var def_m := float(cm.get("def", 1.0))
	print("  3敌军时 atk乘数=%.3f def乘数=%.3f（上限1.10）" % [atk_m, def_m])
	_check("物攻+10%封顶", absf(atk_m - 1.10) < 0.001, str(atk_m))
	_check("物防+10%封顶", absf(def_m - 1.10) < 0.001, str(def_m))
	# 只放1个敌军
	var bt2b = EdBattle.new(13, 11)
	bt2b.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var zf2 = bt2b.add_unit(data.unit_template("zhang_fei", 50, 5, ""), Vector2i(5, 5), 0)
	bt2b.add_unit(data.unit_template("jia_xu", 50, 5, ""), Vector2i(6, 5), 1)
	bt2b._refresh_all_cond_mult()
	var atk1 := float((zf2.get("cond_mult", {}) as Dictionary).get("atk", 1.0))
	print("  1敌军时 atk乘数=%.3f" % atk1)
	_check("1敌军时物攻+5%", absf(atk1 - 1.05) < 0.001, str(atk1))

	print("===== 3. 阻敌：zoc + 物防+10% =====")
	var bt3 = EdBattle.new(13, 11)
	bt3.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var zy = bt3.add_unit(data.unit_template("zhao_yun", 50, 5, ""), Vector2i(5, 5), 0)
	bt3._apply_passive_startup()
	bt3._refresh_all_cond_mult()
	var zoc_v := int(zy.get("zoc", 0))
	var def3 := float((zy.get("cond_mult", {}) as Dictionary).get("def", 1.0))
	print("  zoc=%d def乘数=%.3f" % [zoc_v, def3])
	_check("zoc 阻挡领域生效", zoc_v >= 1, str(zoc_v))
	_check("物防+10%", absf(def3 - 1.10) < 0.001, str(def3))

	print("===== 4. 犹怜：满血受伤-25%，掉血后失效 =====")
	var bt4 = EdBattle.new(13, 11)
	bt4.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var dc = bt4.add_unit(data.unit_template("diao_chan", 50, 5, ""), Vector2i(5, 5), 0)
	bt4._refresh_all_cond_mult()
	var cut_full := float((dc.get("ext", {}) as Dictionary).get("full_hp_cut", 0.0))
	_check("满血时 full_hp_cut=0.25", absf(cut_full - 0.25) < 0.001, str(cut_full))
	dc["hp"] = int(dc["max_hp"]) - 1
	bt4._refresh_all_cond_mult()
	var cut_hurt := float((dc.get("ext", {}) as Dictionary).get("full_hp_cut", 0.0))
	_check("掉血后失效", cut_hurt < 0.001, str(cut_hurt))

	print("===== 5. 袭扰（已实装，回归确认） =====")
	var lb: Dictionary = data.get_skill("xirao")
	_check("袭扰有攻击加成字段", float(lb.get("ed_attack_bonus", 0.0)) > 0.0)
	_check("袭扰有再动字段", bool(lb.get("ed_extra_move_on_attack", false)))

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
