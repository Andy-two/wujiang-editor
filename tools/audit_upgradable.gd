extends SceneTree

# 可升阶技能机制覆盖率审计
#   逐级比较「本级新引入的机制描述」是否有对应等级的效果块承载
# 用法: godot --headless --path . --script res://tools/audit_upgradable.gd

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

# 空集哨兵：GDScript 的 const 字典里不能用 [] 字面量
const NONE := "__NONE__"

# 机制关键词 -> 承载它的效果块类型（空数组 = 引擎完全没有该机制）
const MECH := {
	"造成伤害": ["damage"], "造成物攻": ["damage"], "造成谋攻": ["damage"],
	"回复": ["heal", "self_heal"], "治疗": ["heal", "self_heal"],
	"驱散": ["dispel", "self_dispel"], "解除": ["self_dispel"],
	"眩晕": ["stun"], "定身": ["stun"], "嘲讽": ["taunt"], "封技": ["silence"],
	"缴械": ["disarm"], "护盾": ["shield"], "吸血": ["drain"],
	"固伤": ["fixed"], "固定伤害": ["fixed"],
	"继续行动": ["extra_turn"], "再行动": ["extra_turn"],
	"继续移动": ["extra_move"], "再移动": ["extra_move"],
	"准备期": ["cd_down"], "冷却": ["cd_down"],
	"复活": ["revive"], "击退": ["push"],
	"位移至": ["teleport"], "突进": ["teleport"], "交换位置": ["teleport"],
	"召唤": ["summon"], "追击": ["pursuit"], "战意": ["zhanyi"],
	"阻挡领域": ["zoc"], "合击": ["combo"], "先攻": ["priority"], "格挡": ["block"],
	"闪避": ["dodge"], "抵抗": ["resist"],
	"免疫控制": ["immunity"], "免疫属性减益": ["immunity"],
	"免疫移动减益": ["immunity"], "免疫地形减益": ["immunity"],
	"牵制": ["debuff"], "撕裂": ["debuff"], "溃逃": ["debuff"],
	"中毒": ["debuff"], "破甲": ["debuff"], "灰心": ["debuff"], "胆怯": ["debuff"],
	"定心": ["debuff"], "锐心": ["debuff"], "减防": ["debuff"],
	"减伤": ["debuff", "block"], "增伤": ["debuff", "crit_up"],
	"无视": ["damage"], "重复": ["damage"], "层": ["debuff", "buff", "resource"],
	# 引擎完全没有（用 NONE 表示空集）
	"溅射": ["splash"], "转移": [NONE], "地形": [NONE], "营寨": [NONE],
	"粮仓": [NONE], "收获": [NONE], "特殊地形": [NONE], "连决": [NONE],
}


func _text_of(s: Dictionary, lvl: int) -> String:
	var lv: Array = s.get("lv", []) if s.get("lv") is Array else []
	if lvl - 1 >= lv.size():
		return ""
	return String(lv[lvl - 1])


func _hit_kw(text: String) -> Array:
	var out: Array = []
	for kw in MECH.keys():
		if text.contains(String(kw)):
			out.append(String(kw))
	return out


func _fx_at(fx_list: Array, lvl: int) -> Array:
	var out: Array = []
	for f in fx_list:
		if f is Dictionary and int(f.get("min_lv", 1)) <= lvl:
			out.append(f)
	return out


func _covered(kw: String, blocks: Array, text: String = "") -> bool:
	# 语义化判定：某些描述里的关键词并非由同名效果块承载
	# 例：「抵抗每回合首次受到的『缴械』」由 resist 承载；「回复X点战意」由 zhanyi 承载
	if kw == "缴械" and text.contains("抵抗"):
		if _has_type(blocks, "resist"):
			return true
	if kw == "眩晕" and text.contains("抵抗"):
		if _has_type(blocks, "resist"):
			return true
	if kw == "定身" and text.contains("抵抗"):
		if _has_type(blocks, "resist"):
			return true
	if kw == "牵制" and text.contains("抵抗"):
		if _has_type(blocks, "resist"):
			return true
	if kw == "回复" and text.contains("战意"):
		if _has_type(blocks, "zhanyi"):
			return true
	if kw == "造成物攻" and text.contains("追击"):
		if _has_type(blocks, "pursuit"):
			return true
	if kw == "造成谋攻" and text.contains("追击"):
		if _has_type(blocks, "pursuit"):
			return true
	if kw == "造成伤害" and text.contains("造成伤害"):
		if _has_type(blocks, "damage"):
			return true
	if kw == "无视" and text.contains("阻挡领域"):
		return true   # 「无视阻挡领域」由 ignore_zoc 承载
	if kw == "阻挡领域" and text.contains("无视"):
		return true
	if kw == "地形" and text.contains("免疫地形"):
		if _has_type(blocks, "immunity"):
			return true
	if kw == "回复" and text.contains("回复量"):
		if _has_type(blocks, "buff"):
			return true
	if kw == "回复" and text.contains("战意回复"):
		if _has_type(blocks, "buff"):
			return true
	# 带条件参数的块（require_status / scope / set_flag / repeat_by）也算承载
	for b in blocks:
		if str(b.get("require_status", "")) != "":
			return true
		if str(b.get("scope", "")) != "":
			return true
		if str(b.get("set_flag", "")) != "":
			return true
		if str(b.get("repeat_by", "")) != "":
			return true
		if str(b.get("trigger", "")) == "on_hit" and str(b.get("type")) in ["crit_up", "dispel", "buff", "damage"]:
			return true
		if str(b.get("trigger", "")) == "on_cast" and str(b.get("type")) in ["buff", "crit_up"]:
			return true
	match kw:
		"无视":
			for b in blocks:
				if String(b.get("type")) == "damage" and float(b.get("ignore_def", 0.0)) > 0.0:
					return true
			return false
		"重复":
			for b in blocks:
				if String(b.get("type")) == "damage" and int(b.get("times", 1)) > 1:
					return true
			return false
		"层":
			return _has_type(blocks, "debuff") or _has_type(blocks, "buff") \
				or _has_type(blocks, "resource")
	for b in blocks:
		var bt := String(b.get("type"))
		for want in (MECH[kw] as Array):
			if String(want) == NONE:
				continue
			if bt == String(want):
				return true
	return false


func _has_type(blocks: Array, t: String) -> bool:
	for b in blocks:
		if String(b.get("type")) == t:
			return true
	return false


func _init() -> void:
	var data = ED.new()
	data.load_all()
	var skills: Dictionary = data.skills

	var upg: Array = []
	for sid in skills.keys():
		var s: Dictionary = skills[sid]
		if not (s.get("lv") is Array):
			continue
		var lv: Array = s.get("lv")
		if lv.size() < 2:
			continue
		var uniq := {}
		for x in lv:
			uniq[String(x)] = true
		if uniq.size() == 1:
			continue
		upg.append(sid)

	var total_lv := 0
	var gaps: Array = []
	for sid in upg:
		var s: Dictionary = skills[sid]
		var fx_list: Array = s.get("ed_fx_list", []) if s.get("ed_fx_list") is Array else []
		for lvl in range(2, (s.get("lv") as Array).size() + 1):
			total_lv += 1
			var cur: Array = _hit_kw(_text_of(s, lvl))
			var prev: Array = _hit_kw(_text_of(s, lvl - 1))
			for k in cur:
				if prev.has(k):
					continue
				if _covered(k, _fx_at(fx_list, lvl), _text_of(s, lvl)):
					continue
				if _covered(k, _fx_at(fx_list, 99), _text_of(s, lvl)):
					continue
				gaps.append({"sid": sid, "name": String(s.get("name", sid)), "lv": lvl,
					"kw": k, "text": _text_of(s, lvl)})

	print("========== 可升阶技能机制覆盖率 ==========")
	print("技能总数: %d | 可升阶: %d | 检查等级条目: %d" % [skills.size(), upg.size(), total_lv])
	print("缺口: %d 处，涉及 %d 个技能" % [gaps.size(), _uniq_count(gaps, "sid")])
	var pct := 100.0 * float(total_lv - gaps.size()) / float(maxi(1, total_lv))
	print("覆盖率: %.1f%%" % pct)
	print()

	# 按机制汇总
	var by_kw := {}
	for g in gaps:
		var k := String((g as Dictionary)["kw"])
		by_kw[k] = int(by_kw.get(k, 0)) + 1
	var keys: Array = by_kw.keys()
	keys.sort()
	for k in keys:
		print("  %-12s %3d 次" % [k, int(by_kw[k])])
	print()

	# 明细
	for g in gaps:
		var d: Dictionary = g
		print("  %-22s %-12s Lv%d 「%s」" % [String(d["sid"]), String(d["name"]),
			int(d["lv"]), String(d["kw"])])
		var dt := String(d["text"])
		print("      %s" % dt.substr(0, 120))
	quit(0)


func _uniq_count(arr: Array, key: String) -> int:
	var s := {}
	for a in arr:
		s[String((a as Dictionary)[key])] = true
	return s.size()
