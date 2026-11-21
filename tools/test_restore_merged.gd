extends SceneTree

# 验证：合并被动还原 + 范围零改动
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

	print("===== 1. 被动技能已恢复进库 =====")
	for pair in [["guan_yanyue", "偃月阵"], ["9220071", "游刃八方"],
			["xingcai_zudi", "阻敌"], ["xirao", "袭扰"], ["youlian", "犹怜"]]:
		var sid := String(pair[0])
		var d: Dictionary = data.get_skill(sid)
		_check("技能 %s 在库" % sid, not d.is_empty())
		_check("  名字正确 %s" % pair[1], String(d.get("name", "")) == String(pair[1]),
			String(d.get("name", "")))
		_check("  类型是被动", String(d.get("kind", "")) == "passive", String(d.get("kind", "")))

	print("===== 2. 已挂到对应武将 =====")
	for pair in [["guan_yu", "guan_yanyue"], ["zhang_fei", "9220071"],
			["zhao_yun", "xingcai_zudi"], ["lu_bu", "xirao"], ["diao_chan", "youlian"]]:
		var key := String(pair[0])
		var sid := String(pair[1])
		var g: Dictionary = data.generals[key]
		_check("%s 拥有 %s" % [g.get("name", key), sid],
			(g.get("skills", []) as Array).has(sid), str(g.get("skills", [])))

	print("===== 3. 融合标记已移除 =====")
	for host in ["qianli", "wanren", "zhao_didan", "guiku", "wuying"]:
		var d: Dictionary = data.get_skill(host)
		var mp = d.get("ed_merged_passives")
		var mf = d.get("ed_merged_from")
		_check("%s 无融合标记" % host, not mp and not mf,
			"mp=%s mf=%s" % [str(mp), str(mf)])

	print("===== 4. 范围数据仍在（重点） =====")
	# 吕布/貂蝉/关羽的范围不能有损失
	for pair in [["lu_bu", "yuanmen", 5, 4], ["lu_bu", "guiku", 5, 6],
			["lu_bu", "liehuo", 1, 13], ["diao_chan", "pianruo", 13, 1],
			["diao_chan", "chenyu", 1, 25], ["guan_yu", "guan_qinglong", -1, -1]]:
		var key := String(pair[0])
		var sid := String(pair[1])
		var g: Dictionary = data.generals[key]
		var er: Dictionary = g.get("ed_ranges", {}) if g.get("ed_ranges") is Dictionary else {}
		_check("%s.%s 范围条目存在" % [key, sid], er.has(sid), str(er.keys()))
		if int(pair[2]) > 0:
			var e: Dictionary = er.get(sid, {})
			var cn := RULEZ.parse_area(e.get("cast", [])).size()
			var an := RULEZ.parse_area(e.get("area", [])).size()
			_check("  形状 cast=%d area=%d 未变" % [int(pair[2]), int(pair[3])],
				cn == int(pair[2]) and an == int(pair[3]), "%d/%d" % [cn, an])

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
