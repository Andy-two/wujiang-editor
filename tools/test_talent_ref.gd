extends SceneTree

# 验证通用机制：天赋通过 ref_skill 引用被动技能，效果被注入并触发
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

	print("===== 1. 新类型注册 =====")
	_check("SFX_REF_SKILL 存在", RULEZ.SFX_REF_SKILL == "ref_skill")
	_check("在 SFX_TYPES 里", RULEZ.SFX_TYPES.has("ref_skill"))
	_check("有中文标签", str(RULEZ.SFX_LABELS.get("ref_skill", "")) == "引用被动技能",
		str(RULEZ.SFX_LABELS.get("ref_skill", "")))
	var dflt: Dictionary = RULEZ.default_sfx("ref_skill")
	_check("默认块有 value 字段", dflt.has("value"), JSON.stringify(dflt))
	var txt := RULEZ.sfx_text({"type": "ref_skill", "value": "wanren", "skill_name": "万人敌"})
	_check("文案可读", txt.contains("万人敌"), txt)

	print("===== 2. 天赋引用被动技能：效果被注入 =====")
	# 在内存里改赵云的天赋，加一个 ref_skill 引用「万人敌」
	var tid := String(data.generals["zhao_yun"].get("talent", ""))
	var td: Dictionary = data.get_talent(tid)
	var fxlist: Array = td.get("ed_fx_list", []).duplicate(true)
	fxlist.append({"type": "ref_skill", "value": "wanren", "skill_name": "万人敌", "min_lv": 1.0})
	td["ed_fx_list"] = fxlist

	var bt = EdBattle.new(13, 11)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	bt.set_seed(42)
	var t = data.unit_template("zhao_yun", 50, 5, "")
	t["skill_lv"] = {}
	var u = bt.add_unit(t, Vector2i(6, 6), 0)
	bt._apply_talent_effects()

	var ref_ids: Array = u.get("ref_skill_ids", [])
	_check("记录了引用技能 id", ref_ids.has("wanren"), str(ref_ids))
	var taps: Array = u.get("talent_passives", [])
	var from_wanren := 0
	for tp in taps:
		var tpd: Dictionary = tp
		if str(tpd.get("_from", "")) == "万人敌":
			from_wanren += 1
	_check("万人敌效果块被注入天赋被动", from_wanren > 0,
		"注入 %d 个，天赋被动共 %d 个" % [from_wanren, taps.size()])
	var has_on_hit := false
	for tp in taps:
		var tpd: Dictionary = tp
		if str(tpd.get("_from", "")) == "万人敌" and str(tpd.get("trigger", "")) == "on_hit":
			has_on_hit = true
	_check("注入的 on_hit 触发块存在", has_on_hit)

	print("===== 3. 引用不存在的技能不出错 =====")
	fxlist.append({"type": "ref_skill", "value": "NOT_EXIST", "skill_name": "", "min_lv": 1.0})
	td["ed_fx_list"] = fxlist
	var bt2 = EdBattle.new(13, 11)
	bt2.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var u2 = bt2.add_unit(data.unit_template("zhao_yun", 50, 5, ""), Vector2i(6, 6), 0)
	bt2._apply_talent_effects()
	_check("坏引用被安全忽略", not (u2.get("ref_skill_ids", []) as Array).has("NOT_EXIST"),
		str(u2.get("ref_skill_ids", [])))

	print("===== 4. 引用非被动技能不出错 =====")
	fxlist.append({"type": "ref_skill", "value": "guan_qinglong", "skill_name": "青龙斩月", "min_lv": 1.0})
	td["ed_fx_list"] = fxlist
	var bt3 = EdBattle.new(13, 11)
	bt3.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var u3 = bt3.add_unit(data.unit_template("zhao_yun", 50, 5, ""), Vector2i(6, 6), 0)
	bt3._apply_talent_effects()
	_check("主动技能引用被忽略", not (u3.get("ref_skill_ids", []) as Array).has("guan_qinglong"),
		str(u3.get("ref_skill_ids", [])))

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
