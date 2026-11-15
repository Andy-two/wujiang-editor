extends SceneTree

# 数据迁移 + 演示素材：
#   1) 把所有武将的 ed_art 迁移到「三张图 + 帧号表」新结构
#   2) 吕布导入旧素材 atk64/mov64/spc64
# 用法：godot --headless --path <项目> --script res://tools/setup_demo_anims.gd

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	# 迁移所有武将（load_all 里 _migrate_art 已处理，这里再统一复位一次动画规格）
	var n := 0
	for k in data.order:
		var g: Dictionary = data.generals[k]
		var art: Dictionary = g["ed_art"]
		if not (art.get("sheets") is Dictionary):
			art["sheets"] = {"atk": "", "mov": "", "spc": ""}
		if not (art.get("anims") is Dictionary) or (art["anims"] as Dictionary).is_empty():
			data.reset_anim_spec(g)
		n += 1
	print("已迁移 %d 名武将的动画结构" % n)
	# 吕布导入旧素材
	var key := "lu_bu"
	var paths := ["res://assets/units/lu_bu/atk64.png", "res://assets/units/lu_bu/mov64.png",
		"res://assets/units/lu_bu/spc64.png"]
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var base := String(p).get_file().get_basename().to_lower()
		var sheet := "atk" if base.begins_with("atk") else ("mov" if base.begins_with("mov") else "spc")
		var r := data.import_sheet_to(p, key, sheet)
		print("  %s → %s" % [p.get_file(), String(r.get("msg", ""))])
	# 三张图都指向工程内副本，删除旧的外部引用
	var g2: Dictionary = data.generals[key]
	if data.save_all():
		print("已保存。吕布：")
		print("  sheets: ", g2["ed_art"]["sheets"])
		for act in RULEZ.ACTIONS:
			var row := []
			for d in RULEZ.DIRS:
				var a: Dictionary = data.get_anim(g2, "%s_%s" % [act, d])
				row.append("%s:%s/%s" % [d, String(a.get("sheet", "")), str(a.get("frames", []))])
			print("  %s  %s" % [RULEZ.ACTION_LABELS.get(act, act), "  ".join(row)])
	else:
		print("保存失败")
	quit(0)
