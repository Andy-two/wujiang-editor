extends SceneTree

# 验证技能库排序：被动优先，袭扰能被快速找到
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

	print("===== 1. 袭扰存在于技能库 =====")
	_check("skills 含 xirao", data.skills.has("xirao"))
	var d: Dictionary = data.get_skill("xirao")
	_check("名字是袭扰", String(d.get("name", "")) == "袭扰", String(d.get("name", "")))
	_check("类型是被动", String(d.get("kind", "")) == "passive", String(d.get("kind", "")))

	print("===== 2. 被动优先排序后袭扰靠前 =====")
	var ids: Array = []
	for sid in data.skills.keys():
		ids.append(String(sid))
	ids.sort_custom(func(a, b) -> bool:
		var da: Dictionary = data.skills.get(a, {})
		var db: Dictionary = data.skills.get(b, {})
		var pa := String(da.get("kind", "")) == "passive"
		var pb := String(db.get("kind", "")) == "passive"
		if pa != pb:
			return pa
		return String(da.get("name", a)) < String(db.get("name", b)))
	var pos := ids.find("xirao")
	print("  袭扰排序后位置 = %d / %d（旧逻辑是 333，最末）" % [pos, ids.size()])
	_check("袭扰位置明显靠前（<100）", pos >= 0 and pos < 100, str(pos))
	_check("不被 400 条上限截断", pos < 400, str(pos))

	print("===== 3. 被动都排在主动之前 =====")
	var first_active := -1
	var last_passive := -1
	for i in ids.size():
		var k := String(ids[i])
		var kk := String((data.skills[k] as Dictionary).get("kind", ""))
		if kk == "passive":
			last_passive = i
		elif first_active < 0:
			first_active = i
	print("  最后一个被动=%d，第一个主动=%d" % [last_passive, first_active])
	_check("所有被动都在主动之前", last_passive < first_active,
		"%d vs %d" % [last_passive, first_active])

	print("===== 4. 搜索能找到袭扰 =====")
	var hit_name := false
	var hit_id := false
	for sid in data.skills.keys():
		var dd: Dictionary = data.skills[sid]
		var hay := (String(dd.get("name", sid)) + " " + String(sid) + " " +
			String(dd.get("kind", ""))).to_lower()
		if hay.contains("袭扰"):
			hit_name = true
		if hay.contains("xirao"):
			hit_id = true
	_check("搜「袭扰」能命中", hit_name)
	_check("搜「xirao」能命中", hit_id)

	print("===== 5. 赵云拥有该技能 =====")
	var zy: Dictionary = data.generals["zhao_yun"]
	_check("赵云技能列表含 xirao", (zy.get("skills", []) as Array).has("xirao"),
		str(zy.get("skills", [])))

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
