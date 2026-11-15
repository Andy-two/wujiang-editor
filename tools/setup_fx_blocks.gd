extends SceneTree
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

func _init():
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	var n := 0
	var skip := 0
	for sid in data.skills.keys():
		var d: Dictionary = data.skills[sid]
		if d.get("ed_fx_list") is Array and not (d["ed_fx_list"] as Array).is_empty():
			continue
		if String(d.get("kind", "")) == "passive":
			skip += 1
			continue
		var fx = RULEZ.skill_effects(d)
		if fx.is_empty():
			skip += 1
			continue
		d["ed_fx_list"] = fx
		data.skills[sid] = d
		n += 1
	data.dirty = true
	data.save_all()
	print("已为 ", n, " 个技能生成效果块；跳过 ", skip, " 个（被动/无效果）")
	# 抽查
	for sid in ["guiku", "yuanmen", "zhuge_wusuo", "liang_mougong"]:
		var d2 = data.get_skill(sid)
		print("  ", sid, " ", d2.get("name"), " -> ", str(d2.get("ed_fx_list")))
	quit(0)
