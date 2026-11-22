extends SceneTree

# 端到端验证：导出武将→写文件→清空→从文件导入→逐字段比对
# 全程不动项目数据文件，只在内存和临时文件里操作
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

	print("===== 1. 导出 3 个不同类型的武将 =====")
	var keys := ["lu_bu", "cai_wenji", "zhuge_liang"]
	var packs: Dictionary = {}
	for k in keys:
		var p: Dictionary = data.export_general_pack(k)
		packs[k] = p
		var txt := JSON.stringify(p, "  ")
		# 模拟写文件到临时目录
		var path := "user://pack_%s.json" % k
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(txt)
		f.close()
		_check("导出 %s (%.1f KB)" % [k, float(txt.length()) / 1024.0],
			FileAccess.file_exists(path) and String(p.get("_pack", "")) == "wujiang_general_v1")
	print("  吕布包含 %d 技能 / %d 天赋" % [
		(packs["lu_bu"].get("skills", {}) as Dictionary).size(),
		(packs["lu_bu"].get("talents", {}) as Dictionary).size()])

	print("===== 2. 清空全部武将 =====")
	var n := data.clear_all_generals()
	_check("清空 %d 名武将" % n, n == 56 and data.order.is_empty(), str(n))
	_check("技能库保留", data.skills.size() > 300, str(data.skills.size()))
	_check("天赋库保留", data.talents.size() > 50, str(data.talents.size()))

	print("===== 3. 从文件重新导入 =====")
	for k in keys:
		var path := "user://pack_%s.json" % k
		var f := FileAccess.open(path, FileAccess.READ)
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		_check("%s JSON 可解析" % k, parsed != null and parsed is Dictionary)
		var got := data.import_general_pack(parsed)
		_check("%s 导入成功" % k, got == k, got)

	print("===== 4. 逐字段比对 =====")
	for k in keys:
		var orig: Dictionary = (packs[k] as Dictionary).get("general", {})
		var now: Dictionary = data.generals[k]
		var same_name := String(orig.get("name", "")) == String(now.get("name", ""))
		var same_skills := JSON.stringify(orig.get("skills", [])) == JSON.stringify(now.get("skills", []))
		var same_talent := String(orig.get("talent", "")) == String(now.get("talent", ""))
		var same_stats := JSON.stringify(orig.get("stats", {})) == JSON.stringify(now.get("stats", {}))
		var same_ranges := JSON.stringify(orig.get("ed_ranges", {})) == JSON.stringify(now.get("ed_ranges", {}))
		_check("%s 名字/技能/天赋/属性/范围全一致" % k,
			same_name and same_skills and same_talent and same_stats and same_ranges,
			"名=%s 技=%s 天=%s 属=%s 范=%s" % [str(same_name), str(same_skills), str(same_talent), str(same_stats), str(same_ranges)])

	print("===== 5. 依赖数据完整性 =====")
	_check("吕布技能定义可查", data.skills.has("yuanmen"))
	_check("诸葛亮天赋可查", data.talents.has("liaodi"))
	# 单位模板能正常生成
	var t: Dictionary = data.unit_template("lu_bu", 60, 5, "")
	_check("导入后可生成战斗模板", not t.is_empty() and int((t.get("stats", {}) as Dictionary).get("atk", 0)) > 0)
	_check("模板技能正确", (t.get("skills", []) as Array).has("yuanmen"))

	# 清理临时文件
	for k in keys:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://pack_%s.json" % k))

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
