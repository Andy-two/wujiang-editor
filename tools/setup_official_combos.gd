extends SceneTree

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

# 官方组合技：host -> [子技能名...]
const COMBOS := {
	"pang_jianyan": ["星夜奇袭", "设伏擒将", "别图后举"],
	"liang_chunqiang": ["舌战群儒", "武侯怒斥"],
	"canglan_cao_cao_s2": ["突阵", "奋阵", "列阵"],
	"canglan_cao_cao_s3": ["展旗令", "擂鼓令", "鸣金令"],
	"off_奇门遁甲": ["石兵八阵", "雾锁江天"],
	"off_运筹帷幄": ["虚势慑敌", "鼓风煽焰"],
}


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	# 建立「名称 → id」索引
	var by_name := {}
	for sid in data.skills.keys():
		by_name[String((data.skills[sid] as Dictionary).get("name", sid))] = String(sid)
	var made := 0
	var missing: Array = []
	for host in COMBOS.keys():
		if not data.skills.has(host):
			missing.append("缺组合本体:" + String(host))
			continue
		var kids: Array = []
		for nm in COMBOS[host]:
			if by_name.has(nm):
				kids.append(by_name[nm])
			else:
				missing.append("%s/%s" % [host, nm])
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
			made += 1
			print("组合技: ", data.skill_name(host), " = ", str(kids))
	data.dirty = true
	data.save_all()
	print("已建立组合技: ", made)
	if not missing.is_empty():
		print("未找到: ", str(missing))
	quit(0)
