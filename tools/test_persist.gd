extends SceneTree

# 持久化闭环测试：改一名武将的等级/星级/属性/范围/技能等级 → 保存 → 重新加载 → 校验一致 → 还原
# 用法：godot --headless --path <项目> --script res://tools/test_persist.gd

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

var fails := 0


func _init() -> void:
	print("========== 持久化闭环测试 ==========")
	var d1 = ED.new()
	_init_ex(d1)
	var key := "diao_chan"
	var before_atk := int(d1.unit_template(key)["stats"]["atk"])
	var before_level := int(d1.generals[key].get("ed_level", 1))
	var before_star := int(d1.generals[key].get("ed_star", 1))
	var before_stats: Dictionary = (d1.generals[key]["stats"] as Dictionary).duplicate(true)
	var before_ranges: Dictionary = (d1.generals[key].get("ed_ranges", {}) as Dictionary).duplicate(true)
	var before_skill_lv: Dictionary = (d1.generals[key].get("ed_skill_lv", {}) as Dictionary).duplicate(true)

	# 修改
	d1.generals[key]["ed_level"] = 33
	d1.generals[key]["ed_star"] = 7
	d1.generals[key]["stats"]["atk"] = 199
	var sids: Array = d1.generals[key]["skills"]
	var first_sid := String(sids[0]) if not sids.is_empty() else ""
	if first_sid != "":
		d1.generals[key]["ed_skill_lv"][first_sid] = 3
	d1.generals[key]["ed_ranges"] = {"basic": {"area": [[0, 0], [1, 0], [2, 0], [0, 1], [0, -1], [1, 1], [1, -1]]}}
	d1.generals[key]["ed_note"] = "持久化测试备注"
	_check("保存成功", d1.save_all())
	var expect_atk := int(d1.unit_template(key)["stats"]["atk"])

	# 重新加载
	var d2 = ED.new()
	_init_ex(d2)
	_check("重新加载成功", not d2.generals.is_empty())
	_check("等级已持久化", int(d2.generals[key]["ed_level"]) == 33, str(d2.generals[key]["ed_level"]))
	_check("星级已持久化", int(d2.generals[key]["ed_star"]) == 7)
	_check("基础物攻已持久化", int(d2.generals[key]["stats"]["atk"]) == 199)
	_check("面板物攻一致", int(d2.unit_template(key)["stats"]["atk"]) == expect_atk,
		"%d vs %d" % [int(d2.unit_template(key)["stats"]["atk"]), expect_atk])
	_check("范围覆盖已持久化", (d2.generals[key]["ed_ranges"] as Dictionary).has("basic"))
	_check("范围格数一致", RULEZ.parse_area((d2.generals[key]["ed_ranges"]["basic"] as Dictionary)["area"]).size() == 7)
	if first_sid != "":
		_check("技能等级已持久化", int(d2.generals[key]["ed_skill_lv"].get(first_sid, 1)) == 3)
	_check("备注已持久化", String(d2.generals[key]["ed_note"]) == "持久化测试备注")

	# 还原
	d2.generals[key]["ed_level"] = before_level
	d2.generals[key]["ed_star"] = before_star
	d2.generals[key]["stats"] = before_stats
	d2.generals[key]["ed_ranges"] = before_ranges
	d2.generals[key]["ed_skill_lv"] = before_skill_lv
	d2.generals[key]["ed_note"] = ""
	d2.save_all()
	var d3 = ED.new()
	_init_ex(d3)
	_check("已还原", int(d3.unit_template(key)["stats"]["atk"]) == before_atk,
		"%d vs %d" % [int(d3.unit_template(key)["stats"]["atk"]), before_atk])
	print("========== 结束，失败 %d 项 ==========" % fails)
	quit(0 if fails == 0 else 1)


func _init_ex(d) -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	d.load_all()


func _check(name: String, ok: bool, detail: String = "") -> void:
	print(("  ✔ " if ok else "  ✖ ") + name + (("   " + detail) if detail != "" else ""))
	if not ok:
		fails += 1
