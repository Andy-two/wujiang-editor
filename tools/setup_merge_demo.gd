extends SceneTree
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

func _init():
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	print("=== ① 吕布：袭扰 → 鬼哭神嚎 ===")
	var r1 = data.merge_skills("xirao", "guiku")
	print("  ", r1.get("msg", ""))
	# sm_xirao 也一并清掉（同名的通用袭扰）
	if data.skills.has("sm_xirao"):
		var r1b = data.merge_skills("sm_xirao", "guiku")
		print("  ", r1b.get("msg", ""))
	print("  吕布技能: ", data.generals["lu_bu"]["skills"])

	print("=== ② 诸葛亮：唇枪舌剑 = 舌战群儒 + 武侯怒斥 ===")
	# 库里没有这两个，按旧游戏描述补出来
	if not data.skills.has("liang_shezhan"):
		data.skills["liang_shezhan"] = {
			"name": "舌战群儒", "kind": "aoe", "cd": 3, "range": 3, "radius": 1,
			"mult": 0.9, "magic": true,
			"desc": "对范围内的敌军造成谋攻90%的伤害；若范围内敌军≥2，额外施加「低迷」，持续1回合。",
			"lv": ["造成谋攻90%的伤害", "造成谋攻110%的伤害", "造成谋攻130%的伤害并施加「低迷」2回合"],
			"from_official": false,
		}
	if not data.skills.has("liang_wuhou"):
		data.skills["liang_wuhou"] = {
			"name": "武侯怒斥", "kind": "single", "cd": 3, "range": 3, "radius": 0,
			"mult": 1.3, "magic": true,
			"desc": "对单体敌军造成谋攻130%的伤害并击退1格。",
			"lv": ["造成谋攻130%的伤害并击退1格", "造成谋攻150%的伤害并施加「定身」1回合", "造成谋攻170%的伤害并施加「定身」2回合"],
			"from_official": false,
		}
	var r2 = data.make_skill_group("liang_chunqiang", ["liang_shezhan", "liang_wuhou"], "唇枪舌剑",
		"在「舌战群儒」和「武侯怒斥」中选择一个技策使用。")
	print("  ", r2.get("msg", ""))
	print("  子技能: ", data.group_children("liang_chunqiang"))
	print("  诸葛亮技能: ", data.generals["zhuge_liang"]["skills"])

	# ③ 再演示一个「三选一」：奇门遁甲 = 石兵八阵 / 雾锁江天 / 虚势慑敌
	var r3 = data.make_skill_group("off_奇门遁甲", ["zhuge_shibing", "zhuge_wusuo", "zhuge_xushi"], "奇门遁甲",
		"在「石兵八阵」「雾锁江天」「虚势慑敌」中选择一个技策使用。")
	print("=== ③ 三选一示例 ===")
	print("  ", r3.get("msg", ""))
	if data.save_all():
		print("已保存 data/editor/")
	else:
		print("保存失败")
	quit(0)
