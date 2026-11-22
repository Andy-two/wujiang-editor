extends SceneTree

# 验证开放编辑器核心闭环：导出单武将包 → 清空 → 导入还原
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

	print("===== 1. 导出单武将自包含包 =====")
	var pack: Dictionary = data.export_general_pack("lu_bu")
	_check("包版本正确", String(pack.get("_pack", "")) == "wujiang_general_v1")
	_check("含武将本体", (pack.get("general", {}) as Dictionary).has("name"))
	var skills: Dictionary = pack.get("skills", {})
	_check("含技能依赖", skills.has("yuanmen") and skills.has("guiku"), str(skills.keys()))
	_check("含天赋依赖", (pack.get("talents", {}) as Dictionary).has("sanguo_wushuang"))
	print("  技能 %d 个 / 天赋 %d 个 / 羁绊 %d 条 / 神兵 %d" % [
		skills.size(), (pack.get("talents", {}) as Dictionary).size(),
		(pack.get("bonds", []) as Array).size(), (pack.get("shenbing", {}) as Dictionary).size()])

	print("===== 2. 清空全部武将 =====")
	var orig_count: int = data.order.size()
	var cleared := data.clear_all_generals()
	_check("清空数量正确", cleared == orig_count, "%d vs %d" % [cleared, orig_count])
	_check("武将表为空", data.order.is_empty())
	_check("技能库仍保留", data.skills.size() > 0, str(data.skills.size()))

	print("===== 3. 导入还原 =====")
	var key := data.import_general_pack(pack)
	_check("导入 key 正确", key == "lu_bu", key)
	_check("武将已恢复", data.generals.has("lu_bu"))
	_check("名字正确", String((data.generals["lu_bu"] as Dictionary).get("name", "")) == "吕布")
	_check("技能列表恢复", (data.generals["lu_bu"].get("skills", []) as Array).has("yuanmen"))
	_check("技能定义恢复", data.skills.has("yuanmen"))
	_check("天赋定义恢复", data.talents.has("sanguo_wushuang"))

	print("===== 4. 非法包安全处理 =====")
	var bad := data.import_general_pack({"foo": "bar"})
	_check("非法包返回空", bad == "", bad)
	_check("未新增武将", data.order.size() == 1, str(data.order.size()))

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
