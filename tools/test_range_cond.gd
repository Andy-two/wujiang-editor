extends SceneTree

# 验证：条件层（无双等状态）能改变技能形状
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


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	var bt = EdBattle.new(13, 11)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)

	var gk := "lu_bu"
	var sid := "guiku"
	var t = data.unit_template(gk, 50, 5, "")
	t["skill_lv"] = {sid: 3}
	bt.clear_units()
	var u = bt.add_unit(t, Vector2i(6, 6), 0)

	print("=== 1. 无条件时用原形状 ===")
	var base_cast: Array = bt.skill_cast_area(u, sid)
	var base_area: Array = bt.skill_effect_area(u, sid)
	print("  原 cast=%d area=%d" % [base_cast.size(), base_area.size()])

	print("=== 2. 加条件层：有无双时作用范围变大 ===")
	var g: Dictionary = data.generals[gk]
	var er: Dictionary = g["ed_ranges"]
	var entry: Dictionary = er[sid]
	# 造一个更大的作用范围（半径3菱形）
	var big: Array = []
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			if absi(dx) + absi(dy) <= 3:
				big.append([float(dx), float(dy)])
	entry["conds"] = [{"when": {"type": "wushuang"}, "cast": [], "area": big}]
	er[sid] = entry
	g["ed_ranges"] = er

	# 无无双
	u["wushuang"] = 0
	var a0: Array = bt.skill_effect_area(u, sid)
	# 有无双
	u["wushuang"] = 1
	var a1: Array = bt.skill_effect_area(u, sid)
	print("  无无双 area=%d，有无双 area=%d" % [a0.size(), a1.size()])
	_check("有无双时作用范围变大", a1.size() > a0.size(), "%d → %d" % [a0.size(), a1.size()])
	_check("无无双时保持原范围", a0.size() == base_area.size(), "%d vs %d" % [a0.size(), base_area.size()])

	print("=== 3. 斗气条件 ===")
	entry["conds"] = [{"when": {"type": "douqi", "min": 3}, "cast": [], "area": big}]
	er[sid] = entry
	g["ed_ranges"] = er
	u["wushuang"] = 0
	u["douqi"] = 2
	var d2: Array = bt.skill_effect_area(u, sid)
	u["douqi"] = 3
	var d3: Array = bt.skill_effect_area(u, sid)
	_check("斗气>=3 才变大", d3.size() > d2.size(), "斗气2=%d 斗气3=%d" % [d2.size(), d3.size()])

	print("=== 4. 表达式解析 ===")
	_check("wushuang", bt.cond_match(u, {"type": "wushuang"}) == (int(u.get("wushuang", 0)) > 0))
	u["wushuang"] = 1
	_check("wushuang 命中", bt.cond_match(u, {"type": "wushuang"}))
	u["wushuang"] = 0
	_check("wushuang 不命中", not bt.cond_match(u, {"type": "wushuang"}))
	u["douqi"] = 5
	_check("douqi>=3 命中", bt.cond_match(u, {"type": "douqi", "min": 3}))
	_check("douqi>=9 不命中", not bt.cond_match(u, {"type": "douqi", "min": 9}))
	u["res"] = {"将令": 2}
	_check("res:将令>=2 命中", bt.cond_match(u, {"type": "res", "name": "将令", "min": 2}))
	_check("res:将令>=3 不命中", not bt.cond_match(u, {"type": "res", "name": "将令", "min": 3}))
	u["hp"] = int(u["max_hp"]) / 2
	_check("hp<=60 命中", bt.cond_match(u, {"type": "hp_pct", "max": 60}))
	_check("always 命中", bt.cond_match(u, {"type": "always"}))

	print("=== 5. 条件层优先级高于升阶分层 ===")
	entry["conds"] = [{"when": {"type": "always"}, "cast": [], "area": big}]
	entry["layers"] = {"lv_3": {"cast": base_cast, "area": [ [0.0, 0.0] ]}}
	er[sid] = entry
	g["ed_ranges"] = er
	u["douqi"] = 0
	u["wushuang"] = 0
	var pri: Array = bt.skill_effect_area(u, sid)
	_check("条件层(always)压过 lv_3 分层", pri.size() == big.size(), "%d vs %d" % [pri.size(), big.size()])

	print("=== 结果：%d 通过，%d 失败 ===" % [passed, failed])
	quit(0)
