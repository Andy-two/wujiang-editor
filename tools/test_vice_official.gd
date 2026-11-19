extends SceneTree

# 副将官方数据对齐校验：
#   对照 sparknexa 官方 wiki API 抓取的快照数据，验证 vice_generals.json
#   的基础属性 / 满级属性 / 天赋 / 韬略 / 羁绊 完整对齐。
#   快照内嵌在测试里，避免运行时依赖网络。

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

var fails := 0
var total := 0


func ok(cond: bool, msg: String) -> void:
	total += 1
	if not cond:
		fails += 1
		print("  FAIL ", msg)


# 官方快照：id -> {name, base, max, tf_initial, tf_max, taolue, jiban_members}
const SNAPSHOT := {
	1201: {"name": "鲍信", "base": [0, 0, 6, 3, 19, 0], "max": [0, 0, 151, 75, 454, 0],
		"tf_initial": "每回合受到的首次伤害降低6%。", "tf_max": "每回合受到的首次伤害降低15%。",
		"taolue": ["提升1.5%兵力", "战斗中伤害提升2%"], "jiban": []},
	1335: {"name": "董袭", "base": [9, 0, 0, 0, 19, 2], "max": [228, 0, 0, 0, 454, 49],
		"tf_initial": "施放战法后，双攻提升3%（最多叠加4层），持续4回合。",
		"tf_max": "施放战法后，双攻提升6%（最多叠加4层），持续4回合。",
		"taolue": ["战斗中伤害提升2%", "战斗中提升3%暴击伤害"], "jiban": []},
	1329: {"name": "华佗", "base": [0, 9, 3, 0, 19, 0], "max": [0, 209, 75, 0, 454, 0],
		"tf_initial": "护盾量提升13%，为我方部队添加护盾时，为其驱散1个减益，并使其下次主动攻击造成伤害提升6%。",
		"tf_max": "护盾量提升25%，为我方部队添加护盾时，为其驱散1个减益，并使其下次主动攻击造成伤害提升12%。",
		"taolue": ["提升1.5%谋攻", "提升1.5%兵力"], "jiban": [1329, 1330]},
	1308: {"name": "关平", "base": [], "max": [], "tf_initial": "", "tf_max": "",
		"taolue": [], "jiban": [1288, 1308]},
}


func _init() -> void:
	var d = ED.new()
	d.load_all()
	print("副将总数: %d" % d.vices.size())

	# ---------- 1. 全量字段完整性 ----------
	print("[1] 全量字段完整性")
	var attr_ok := 0
	var tf_ok := 0
	var tl_ok := 0
	var jb_cnt := 0
	var rec_cnt := 0
	for k in d.vices.keys():
		var v: Dictionary = d.vices[k]
		var ba: Dictionary = v.get("base_attr", {})
		var ma: Dictionary = v.get("max_attr", {})
		if not ba.is_empty() and not ma.is_empty():
			attr_ok += 1
		if not String((v.get("talent_max", {}) as Dictionary).get("name", "")).is_empty():
			tf_ok += 1
		if not (v.get("taolue", []) as Array).is_empty():
			tl_ok += 1
		if not (v.get("jiban", {}) as Dictionary).is_empty():
			jb_cnt += 1
		rec_cnt += (v.get("recommends", []) as Array).size()
	ok(attr_ok == 109, "基础/满级属性应 109 条，实际 %d" % attr_ok)
	ok(tf_ok == 109, "满级天赋应 109 条，实际 %d" % tf_ok)
	ok(tl_ok == 87, "韬略应 87 条，实际 %d" % tl_ok)
	ok(jb_cnt == 24, "羁绊副将应 24 条，实际 %d" % jb_cnt)
	ok(rec_cnt == 409, "推荐关系应 409 条，实际 %d" % rec_cnt)
	print("  属性 %d  天赋 %d  韬略 %d  羁绊副将 %d  推荐 %d" % [attr_ok, tf_ok, tl_ok, jb_cnt, rec_cnt])

	# ---------- 2. 快照逐条核对 ----------
	print("[2] 官方快照逐条核对")
	var keys := ["atk", "matk", "def", "mdef", "hp", "cri"]
	for vid in SNAPSHOT.keys():
		var snap: Dictionary = SNAPSHOT[vid]
		var v: Dictionary = d.vices.get(str(vid), {})
		if v.is_empty():
			ok(false, "缺少副将 %d" % int(vid))
			continue
		ok(String(v["name"]) == String(snap["name"]), "%d 名字应为 %s" % [int(vid), snap["name"]])
		# 属性
		var snap_base: Array = snap["base"]
		if not snap_base.is_empty():
			var ba: Dictionary = v["base_attr"]
			var ma: Dictionary = v["max_attr"]
			for i in keys.size():
				var k2 := String(keys[i])
				ok(int(ba.get(k2, 0)) == int(snap_base[i]),
					"%d base.%s 应为 %d，实际 %d" % [int(vid), k2, snap_base[i], int(ba.get(k2, 0))])
				ok(int(ma.get(k2, 0)) == int(snap["max"][i]),
					"%d max.%s 应为 %d，实际 %d" % [int(vid), k2, snap["max"][i], int(ma.get(k2, 0))])
		# 天赋
		if String(snap["tf_initial"]) != "":
			var itf: Dictionary = v["talent_initial"]
			var mtf: Dictionary = v["talent_max"]
			ok(String(itf["des"]) == String(snap["tf_initial"]), "%d 初始天赋文案不符" % int(vid))
			ok(String(mtf["des"]) == String(snap["tf_max"]), "%d 满级天赋文案不符" % int(vid))
		# 韬略
		var snap_tl: Array = snap["taolue"]
		if not snap_tl.is_empty():
			var tl: Array = v["taolue"]
			ok(tl.size() == snap_tl.size(), "%d 韬略条数应为 %d" % [int(vid), snap_tl.size()])
			for i in snap_tl.size():
				ok(String(tl[i]) == String(snap_tl[i]), "%d 韬略[%d] 不符" % [int(vid), i])
		# 羁绊
		var snap_jb: Array = snap["jiban"]
		if not snap_jb.is_empty():
			var jb: Dictionary = v.get("jiban", {})
			var ms: Array = jb.get("members", [])
			var ms_int: Array = []
			for m in ms:
				ms_int.append(int(m))
			ms_int.sort()
			var want := snap_jb.duplicate()
			want.sort()
			ok(ms_int == want, "%d 羁绊成员应为 %s，实际 %s" % [int(vid), str(want), str(ms_int)])

	# ---------- 3. bonds.json 羁绊组 ----------
	print("[3] bonds.json 羁绊组")
	var bond_keys: Array = d.bonds.keys()
	ok(bond_keys.size() == 12, "羁绊组应 12 条，实际 %d" % bond_keys.size())
	var implemented := 0
	for bid in bond_keys:
		var cfg: Dictionary = d.bonds[bid]
		ok(String(cfg.get("source", "")) == "official_api", "%s 应标注官方来源" % String(bid))
		ok((cfg.get("members", []) as Array).size() == 2, "%s 应 2 名成员" % String(bid))
		if not (cfg.get("fx", []) as Array).is_empty():
			implemented += 1
	ok(implemented == 2, "已实装羁绊应 2 组，实际 %d" % implemented)
	print("  12 组羁绊，其中已实装 %d 组" % implemented)

	# ---------- 4. 固定属性插值 ----------
	print("[4] 固定属性等级插值")
	var g: Dictionary = d.generals["guan_yu"]
	var ext: Dictionary = g["ed_ext"]
	ext["vice_id"] = 1335
	ext["vice_lv"] = 1
	var t1: Dictionary = d.unit_template("guan_yu")
	ext["vice_lv"] = 25
	var t25: Dictionary = d.unit_template("guan_yu")
	ext["vice_id"] = 0
	ext.erase("vice_lv")
	# 关羽基线兵力（未挂副将）
	ext["vice_id"] = 0
	var t0: Dictionary = d.unit_template("guan_yu")
	var hp1 := int(t1["stats"]["max_hp"]) - int(t0["stats"]["max_hp"])
	var hp25 := int(t25["stats"]["max_hp"]) - int(t0["stats"]["max_hp"])
	ok(hp1 == 19, "Lv1 兵力加成应为 +19，实际 %d" % hp1)
	ok(hp25 == 454, "Lv25 兵力加成应为 +454，实际 %d" % hp25)
	print("  董袭兵力加成: Lv1 +%d, Lv25 +%d" % [hp1, hp25])

	print("")
	if fails == 0:
		print("全部通过（%d 项）" % total)
	else:
		print("失败 %d / %d 项" % [fails, total])
	quit(0 if fails == 0 else 1)
