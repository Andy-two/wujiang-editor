extends SceneTree

# 全武将升阶能力审计
# 检查：每个武将是否有 >=3 个可升阶技能；这些技能三阶文案是否各不相同

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()

	var total := 0
	var ok_cnt := 0
	var lack_cnt := 0
	var no_tier_cnt := 0
	var lack_list: Array = []
	var same_list: Array = []

	for k in data.order:
		var g: Dictionary = data.generals[k]
		total += 1
		var skills: Array = g.get("skills", [])
		# 可升阶 = 主动技能（kind != passive），且三阶不全同
		var upgradable: Array = []
		var upgradable_no_tier: Array = []
		for s in skills:
			var sid := String(s)
			var d: Dictionary = data.get_skill(sid)
			if d.is_empty():
				continue
			var lv: Array = d.get("lv", []) if d.get("lv") is Array else []
			var has_tier := lv.size() >= 3 and String(lv[0]) != String(lv[1])
			var is_passive := String(d.get("kind", "")) == "passive"
			if is_passive:
				continue
			if has_tier:
				upgradable.append(sid)
			else:
				upgradable_no_tier.append(sid)

		var nm := String(g.get("name", k))
		if upgradable.size() >= 3:
			ok_cnt += 1
		else:
			lack_cnt += 1
			lack_list.append("%s(%d个)" % [nm, upgradable.size()])

		if upgradable_no_tier.size() > 0:
			no_tier_cnt += 1
			for s2 in upgradable_no_tier:
				var dd: Dictionary = data.get_skill(String(s2))
				same_list.append("%s·%s" % [nm, String(dd.get("name", ""))])

	print("=== 武将升阶能力审计 ===")
	print("武将总数: ", total)
	print("有 ≥3 个可升阶技能的武将: ", ok_cnt)
	print("不足 3 个的武将数: ", lack_cnt)
	if lack_cnt > 0:
		print("  不足的:", str(lack_list))
	print()
	print("存在「三阶相同」主动技能的武将数: ", no_tier_cnt)
	print("三阶相同的主动技能数: ", same_list.size())
	if same_list.size() > 0:
		print("  前 30 个:", str(same_list.slice(0, 30)))
	quit(0)
