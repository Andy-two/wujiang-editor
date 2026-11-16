extends SceneTree

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

# 缺失的官方组合子技能：host -> [子技能名...]
const COMBOS := {
	"pang_jianyan": ["星夜奇袭", "设伏擒将", "别图后举"],
	"canglan_cao_cao_s2": ["突阵", "奋阵", "列阵"],
	"canglan_cao_cao_s3": ["展旗令", "擂鼓令", "鸣金令"],
}


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	var by_name := {}
	for sid in data.skills.keys():
		by_name[String((data.skills[sid] as Dictionary).get("name", sid))] = String(sid)
	var made := 0
	for host in COMBOS.keys():
		if not data.skills.has(host):
			continue
		var kids: Array = []
		for nm in COMBOS[host]:
			if by_name.has(nm):
				kids.append(by_name[nm])
				continue
			# 缺失 → 建占位技能定义（标记待补，便于你在编辑器里补全）
			var nid := "%s_%d" % [String(host), kids.size() + 1]
			var placeholder := {
				"name": String(nm),
				"kind": "single",
				"cd": 2,
				"range": 2,
				"radius": 0,
				"mult": 1.0,
				"desc": "【待补】官方原版中「%s」的效果尚未收录，请在编辑器里补全效果与范围。" % String(nm),
				"lv": ["【待补】%s" % String(nm), "【待补】%s" % String(nm), "【待补】%s" % String(nm)],
				"from_official": false,
				"ed_placeholder": true,
			}
			data.skills[nid] = placeholder
			by_name[String(nm)] = nid
			kids.append(nid)
			made += 1
			print("建占位子技能: ", nm, " -> ", nid)
		if kids.size() >= 2:
			var d: Dictionary = data.skills[host]
			d["ed_group"] = kids
			d["kind"] = ED.GROUP_KIND
			var nm_list: Array = []
			for k in kids:
				nm_list.append("「%s」" % data.skill_name(String(k)))
			var line := "在%s中选择一个技策使用。" % "、".join(nm_list)
			d["desc"] = line
			d["lv"] = [line, line, line]
			data.skills[host] = d
			print("组合技: ", data.skill_name(host), " = ", str(kids))
	data.dirty = true
	data.save_all()
	print("新建占位子技能: ", made)
	quit(0)
