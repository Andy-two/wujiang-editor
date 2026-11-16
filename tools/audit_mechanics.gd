extends SceneTree

# 技能机制覆盖率审计：扫描所有技能描述里的机制关键词，统计引擎实现情况
# 用法: godot --headless --path . --script res://tools/audit_mechanics.gd

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

# 机制关键词 -> 承载它的效果块类型（或 "none" 表示目前无对应实现）
const MECHANISMS := {
	"无法被反击": ["no_counter"],
	"无视": ["damage(ignore_def)"],
	"击退": ["push"],
	"位移至": ["teleport"],
	"突进": ["teleport"],
	"召唤": ["summon"],
	"驱散": ["dispel", "self_dispel"],
	"解除": ["self_dispel"],
	"眩晕": ["stun"],
	"嘲讽": ["taunt"],
	"封技": ["silence"],
	"缴械": ["disarm"],
	"定身": ["stun"],
	"护盾": ["shield"],
	"回复": ["heal", "self_heal"],
	"吸血": ["drain"],
	"持续伤害": ["dot"],
	"固伤": ["fixed"],
	"固定伤害": ["fixed"],
	"继续行动": ["extra_turn"],
	"继续移动": ["extra_move"],
	"再移动": ["extra_move"],
	"再行动": ["extra_turn"],
	"准备期": ["cd_down"],
	"复活": ["revive"],
	"重复": ["damage(times)"],
}


func _init() -> void:
	var data = ED.new()
	data.load_all()
	var total := 0
	var with_fx := 0
	var no_fx: Array = []
	var mech_hits := {}
	for m in MECHANISMS.keys():
		mech_hits[m] = 0

	for sid in data.skills.keys():
		var s: Dictionary = data.skills[sid]
		total += 1
		var fx: Array = s.get("ed_fx_list", []) if s.get("ed_fx_list") is Array else []
		if not fx.is_empty():
			with_fx += 1
		else:
			var kind := String(s.get("kind", ""))
			if kind != "passive":
				(no_fx as Array).append("%s(%s)" % [data.skill_name(String(sid)), String(sid)])
		var text := String(s.get("desc", ""))
		var lvs: Array = s.get("lv", []) if s.get("lv") is Array else []
		for x in lvs:
			text += "\n" + String(x)
		for m in MECHANISMS.keys():
			if text.contains(String(m)):
				mech_hits[m] = int(mech_hits[m]) + 1

	print("=== 技能机制审计 ===")
	print("技能总数: ", total)
	print("有主动效果块的: ", with_fx)
	print("主动技能但无效果块: ", (no_fx as Array).size())
	if (no_fx as Array).size() > 0:
		print("  前 20 个: ", str((no_fx as Array).slice(0, 20)))
	print()
	print("=== 描述中出现的机制统计 ===")
	var keys: Array = MECHANISMS.keys()
	keys.sort()
	for m in keys:
		var n := int(mech_hits[m])
		if n == 0:
			continue
		var impl := ""
		for t in (MECHANISMS[m] as Array):
			impl += String(t) + " "
		print("  %-12s 出现 %3d 次  实现方式: %s" % [String(m), n, impl])
	quit(0)
