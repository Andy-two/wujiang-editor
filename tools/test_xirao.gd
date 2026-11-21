extends SceneTree

# 验证赵云的「袭扰」：主动攻击 +8% 物攻，之后获得「继续移动」
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
	RULEZ.settings["use_official_panel"] = false
	var data = ED.new()
	data.load_all()
	var bt = EdBattle.new(13, 11)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)

	print("===== 1. 技能存在并已挂到赵云 =====")
	var d: Dictionary = data.get_skill("xirao")
	_check("技能「袭扰」存在", not d.is_empty())
	_check("是被动技能", String(d.get("kind", "")) == "passive", String(d.get("kind", "")))
	_check("描述含 8%", String(d.get("desc", "")).contains("8%"), String(d.get("desc", "")))
	_check("描述含 继续移动", String(d.get("desc", "")).contains("继续移动"))
	var zy: Dictionary = data.generals["zhao_yun"]
	_check("赵云技能列表含 xirao", (zy.get("skills", []) as Array).has("xirao"),
		str(zy.get("skills", [])))

	print("===== 2. 普攻 +8% 物攻 =====")
	# 造两个赵云：一个带袭扰，一个不带，比较同一目标伤害
	var t_with = data.unit_template("zhao_yun", 50, 5, "")
	var t_without = data.unit_template("zhao_yun", 50, 5, "")
	t_without["skills"] = []
	var foe_t = data.unit_template("jia_xu", 50, 5, "")
	foe_t["stats"]["max_hp"] = 999999
	foe_t["stats"]["hp"] = 999999

	var bt1 = EdBattle.new(13, 11)
	bt1.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	bt1.set_seed(12345)
	var a1 = bt1.add_unit(t_with, Vector2i(5, 5), 0)
	var f1 = bt1.add_unit(foe_t, Vector2i(6, 5), 1)
	var r1: Dictionary = bt1.basic_attack(a1, f1)
	var dmg_with := int(r1.get("dmg", 0))

	var bt2 = EdBattle.new(13, 11)
	bt2.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	bt2.set_seed(12345)
	var a2 = bt2.add_unit(t_without, Vector2i(5, 5), 0)
	var f2 = bt2.add_unit(foe_t, Vector2i(6, 5), 1)
	var r2: Dictionary = bt2.basic_attack(a2, f2)
	var dmg_without := int(r2.get("dmg", 0))

	print("  带袭扰 %d 伤害 / 不带 %d 伤害" % [dmg_with, dmg_without])
	_check("带袭扰伤害更高", dmg_with > dmg_without, "%d vs %d" % [dmg_with, dmg_without])
	var ratio := float(dmg_with) / float(maxi(1, dmg_without))
	print("  实际增幅: %.3f 倍（目标 1.08）" % ratio)
	_check("增幅接近 8%", absf(ratio - 1.08) < 0.06, "%.3f" % ratio)

	print("===== 3. 攻击后可继续移动 =====")
	_check("攻击后 done 被重置", bool(a1["done"]) == false, str(a1["done"]))
	_check("标记 extra_move_only", bool(a1.get("extra_move_only", false)))

	print("===== 4. 继续移动时不能再攻击/放技 =====")
	var r3: Dictionary = bt1.basic_attack(a1, f1)
	_check("再攻击被拒绝", bool(r3.get("ok", true)) == false, str(r3.get("msg", "")))
	var r4: Dictionary = bt1.cast_skill(a1, "zhao_didan", Vector2i(6, 4))
	_check("放技被拒绝", bool(r4.get("ok", true)) == false, str(r4.get("msg", "")))

	print("===== 5. 移动后行动结束 =====")
	var mc: Dictionary = bt1.move_cells(a1)
	var moved := false
	for cell in mc.keys():
		var rm: Dictionary = bt1.try_move(a1, cell)
		if bool(rm.get("ok", false)):
			moved = true
			break
	_check("能移动", moved)
	_check("移动后 done=true", bool(a1["done"]), str(a1["done"]))
	_check("标记已清除", bool(a1.get("extra_move_only", false)) == false)

	print("===== 6. 吕布的鬼哭神嚎仍保留融合袭扰 =====")
	var gk: Dictionary = data.get_skill("guiku")
	_check("guiku 仍含 ed_merged_passives 袭扰",
		(gk.get("ed_merged_passives", []) as Array).has("袭扰"),
		str(gk.get("ed_merged_passives", [])))

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
