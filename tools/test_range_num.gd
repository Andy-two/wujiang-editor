extends SceneTree

# 验证：射程/作用半径数值直调是否真的影响战斗；组合技子技能是否各自独立
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
	print("===== 射程/半径数值直调 =====")
	var g: Dictionary = data.generals["guan_yu"]
	var sid := "guan_qinglong"
	# 先清掉自定义格子，让 range 生效
	var er: Dictionary = g.get("ed_ranges", {}) if g.get("ed_ranges") is Dictionary else {}
	er.erase(sid)
	g["ed_ranges"] = er
	var d: Dictionary = data.get_skill(sid)
	# 记录原值
	var old_range := int(d.get("range", 1))
	var old_radius := int(d.get("radius", 0))
	print("原 range=%d radius=%d" % [old_range, old_radius])

	var bt = EdBattle.new(13, 11)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	var t = data.unit_template("guan_yu", 50, 5, "")
	var u = bt.add_unit(t, Vector2i(6, 6), 0)

	# range=1 时的释放格数
	d["range"] = 1
	var c1: Array = bt.skill_cast_area(u, sid)
	# range=4 时的释放格数
	d["range"] = 4
	var c4: Array = bt.skill_cast_area(u, sid)
	_check("改 range 1→4 后释放格变多", c4.size() > c1.size(),
		"%d 格 → %d 格" % [c1.size(), c4.size()])

	# radius 影响作用格
	d["radius"] = 0
	var a0: Array = bt.skill_effect_area(u, sid)
	d["radius"] = 2
	var a2: Array = bt.skill_effect_area(u, sid)
	_check("改 radius 0→2 后作用格变多", a2.size() > a0.size(),
		"%d 格 → %d 格" % [a0.size(), a2.size()])

	# 恢复
	d["range"] = old_range
	d["radius"] = old_radius

	print("===== 组合技：子技能效果/范围独立，升阶统一 =====")
	# 找一个多选一组合技（ed_group 不含自身）
	var group_sid := ""
	for k in data.skills.keys():
		var ks := String(k)
		if data.is_group(ks) and not data.is_form_switch(ks):
			group_sid = ks
			break
	if group_sid == "":
		print("  （没有多选一组合技，跳过）")
	else:
		var kids: Array = data.selectable_children(group_sid)
		print("组合技 %s 子技能 %d 个" % [data.skill_name(group_sid), kids.size()])
		if kids.size() >= 2:
			var k0 := String(kids[0])
			var k1 := String(kids[1])
			var d0: Dictionary = data.get_skill(k0)
			var d1: Dictionary = data.get_skill(k1)
			var r0 := int(d0.get("range", 1))
			var r1 := int(d1.get("range", 1))
			# 只改子技能0
			d0["range"] = r0 + 3
			_check("改子技能0的 range 不影响子技能1",
				int(data.get_skill(k1).get("range", 1)) == r1,
				"子0 %d→%d，子1 仍 %d" % [r0, r0 + 3, r1])
			d0["range"] = r0
			# 升阶统一：组等级作为子技能下限（必须指定子技能才会走同步分支）
			var t2 = data.unit_template("guan_yu", 50, 5, "")
			t2["skill_lv"] = {group_sid: 3, k0: 1, k1: 1}
			var u2 = bt.add_unit(t2, Vector2i(3, 3), 0)
			bt.cast_skill(u2, group_sid, Vector2i(3, 4), k0)
			_check("组合技升阶统一：组 Lv3 时子技能也被抬到 Lv3",
				int(u2["skill_lv"].get(k0, 1)) >= 3,
				"子0=%d 子1=%d" % [int(u2["skill_lv"].get(k0, 1)), int(u2["skill_lv"].get(k1, 1))])

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
