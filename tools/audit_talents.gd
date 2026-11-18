extends SceneTree

# 天赋机制覆盖率审计
#   天赋结构与技能一致（lv 文案数组 + ed_fx_list 效果块），
#   逐级比较「本级新引入的机制描述」是否有对应等级的效果块承载。
# 用法: godot --headless --path . --script res://tools/audit_talents.gd

const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

const NONE := "__NONE__"

# 机制关键词 -> 承载它的效果块类型
const MECH := {
	"造成伤害": ["damage"], "造成物攻": ["damage"], "造成谋攻": ["damage"],
	"伤害": ["damage"],
	"回复": ["heal", "self_heal"], "治疗": ["heal", "self_heal"],
	"驱散": ["dispel", "self_dispel"], "解除": ["self_dispel"],
	"眩晕": ["stun"], "定身": ["stun"], "嘲讽": ["taunt"], "封技": ["silence"],
	"缴械": ["disarm"], "护盾": ["shield"], "吸血": ["drain"],
	"固伤": ["fixed"], "固定伤害": ["fixed"],
	"继续行动": ["extra_turn"], "再行动": ["extra_turn"],
	"继续移动": ["extra_move"], "再移动": ["extra_move"],
	"冷却": ["cd_down"], "复活": ["revive"], "击退": ["push"],
	"召唤": ["summon"], "追击": ["pursuit"], "战意": ["zhanyi"],
	"阻挡领域": ["zoc"], "合击": ["combo"], "先攻": ["priority"], "格挡": ["block"],
	"闪避": ["dodge"], "抵抗": ["resist"], "免疫": ["immunity"],
	"溅射": ["splash"], "转移": ["transfer"],
	"粮仓": ["facility"], "收获": ["facility"],
	"增益": ["buff"], "减益": ["debuff"], "增伤": ["debuff", "buff"],
	"减伤": ["debuff", "buff", "block"],
	# 「N层」是通用计数词，引擎已有 resource / buff 承载
	"层": ["resource", "buff"],
	# 引擎完全没有的具名状态
	"斗气": [NONE], "无双": [NONE], "武魂": [NONE],
	"拖刀计": [NONE], "龙胆": [NONE], "标定": [NONE], "淬锋": [NONE],
	"撕裂": ["debuff"], "缠缚": [NONE], "枭姬卫": [NONE],
	"形态": [NONE], "暴击": ["crit_up"], "暴击率": ["crit_up"],
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


func _has_type(blocks: Array, t: String) -> bool:
	for b in blocks:
		if String(b.get("type")) == t:
			return true
	return false


func _covered(kw: String, blocks: Array, text: String = "") -> bool:
	# 语义化判定
	if kw == "缴械" and text.contains("抵抗") and _has_type(blocks, "resist"):
		return true
	if kw == "眩晕" and text.contains("抵抗") and _has_type(blocks, "resist"):
		return true
	if kw == "回复" and text.contains("战意") and _has_type(blocks, "zhanyi"):
		return true
	if kw == "造成物攻" and text.contains("追击") and _has_type(blocks, "pursuit"):
		return true
	if kw == "造成谋攻" and text.contains("追击") and _has_type(blocks, "pursuit"):
		return true
	if kw == "阻挡领域" and text.contains("无视"):
		return true
	if kw == "无视" and text.contains("阻挡领域"):
		return true
	# 带条件参数的块也算承载
	for b in blocks:
		for p in ["require_status", "scope", "set_flag", "repeat_by"]:
			if str(b.get(p, "")) != "":
				return true
	for b in blocks:
		var bt := String(b.get("type"))
		for want in (MECH[kw] as Array):
			if String(want) == NONE:
				continue
			if bt == String(want):
				return true
	return false


func _init() -> void:
	var data = ED.new()
	data.load_all()
	var talents: Dictionary = data.talents
	var generals: Dictionary = data.generals
	var _entry_gap: Array = []

	# 只统计「被武将实际使用」的天赋
	var used := {}
	for gk in generals.keys():
		var g: Dictionary = generals[gk]
		var tid := String(g.get("talent", ""))
		if tid != "" and talents.has(tid):
			used[tid] = true

	var total_lv := 0
	var gaps: Array = []
	var no_fx: Array = []
	# 关键词级统计：同一等级条目只计一次（一个等级条目不重复扣分）
	var total_kw := 0
	var gap_kw := 0
	for tid in used.keys():
		var s: Dictionary = talents[tid]
		var fx_list: Array = s.get("ed_fx_list", []) if s.get("ed_fx_list") is Array else []
		if fx_list.is_empty():
			no_fx.append(tid)
		var lv: Array = s.get("lv", []) if s.get("lv") is Array else []
		for lvl in range(1, lv.size() + 1):
			total_lv += 1
			var cur: Array = _hit_kw(_text_of(s, lvl))
			var prev: Array = _hit_kw(_text_of(s, lvl - 1)) if lvl > 1 else []
			var item_total := 0
			var item_gaps: Array = []
			for k in cur:
				if prev.has(k):
					continue
				item_total += 1
				total_kw += 1
				if _covered(k, _fx_at(fx_list, lvl), _text_of(s, lvl)):
					continue
				if _covered(k, _fx_at(fx_list, 99), _text_of(s, lvl)):
					continue
				item_gaps.append(k)
				gaps.append({"tid": tid, "name": String(s.get("name", tid)), "lv": lvl,
					"kw": k, "text": _text_of(s, lvl)})
			gap_kw += item_gaps.size()
			# 条目级：该等级有任何缺口就算未覆盖
			if not item_gaps.is_empty():
				_entry_gap.append(tid)

	print("========== 天赋机制覆盖率 ==========")
	print("天赋总数: %d | 被武将使用: %d | 武将数: %d" % [talents.size(), used.size(), generals.size()])
	print("检查等级条目: %d | 机制关键词条目: %d" % [total_lv, total_kw])
	print("有 ed_fx_list 的天赋: %d / %d" % [used.size() - no_fx.size(), used.size()])
	print("完全无缺口的等级条目: %d / %d" % [total_lv - _entry_gap.size(), total_lv])
	print("缺口: %d 处关键词，涉及 %d 个天赋" % [gaps.size(), _uniq_count(gaps, "tid")])
	print("覆盖率(按关键词): %.1f%%" % (100.0 * float(total_kw - gap_kw) / float(maxi(1, total_kw))))
	print("覆盖率(按等级条目): %.1f%%" % (100.0 * float(total_lv - _entry_gap.size()) / float(maxi(1, total_lv))))
	print()

	var by_kw := {}
	for g in gaps:
		var k := String((g as Dictionary)["kw"])
		by_kw[k] = int(by_kw.get(k, 0)) + 1
	var keys: Array = by_kw.keys()
	keys.sort()
	print("---- 缺失机制（按出现次数）----")
	for k in keys:
		var supported := false
		for want in (MECH[k] as Array):
			if String(want) != NONE:
				supported = true
		print("  %-12s %3d 次  %s" % [k, int(by_kw[k]),
			"（引擎已有类型，缺数据）" if supported else "（引擎无此类型）"])
	print()

	print("---- 缺口明细（前 40 条）----")
	var shown := 0
	for g in gaps:
		if shown >= 40:
			print("  ... 还有 %d 条" % (gaps.size() - shown))
			break
		var d: Dictionary = g
		print("  %-22s %-10s Lv%d 「%s」" % [String(d["tid"]), String(d["name"]),
			int(d["lv"]), String(d["kw"])])
		shown += 1

	# 可选：导出逐天赋明细供后续批量实装
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--dump="):
			_dump(String(a).substr(7), talents, used, gaps, generals)
	quit(0)


func _dump(path: String, talents: Dictionary, used: Dictionary, gaps: Array, generals: Dictionary) -> void:
	var per := {}
	for tid in used.keys():
		var s: Dictionary = talents[tid]
		var users: Array = []
		for gk in generals.keys():
			if String((generals[gk] as Dictionary).get("talent", "")) == tid:
				users.append(String((generals[gk] as Dictionary).get("name", gk)))
		var lv: Array = s.get("lv", []) if s.get("lv") is Array else []
		var fx_list: Array = s.get("ed_fx_list", []) if s.get("ed_fx_list") is Array else []
		var my_gaps: Array = []
		for g in gaps:
			var d: Dictionary = g
			if String(d["tid"]) == tid:
				my_gaps.append({"lv": int(d["lv"]), "kw": String(d["kw"])})
		var supported := 0
		var unsupported := 0
		for g in my_gaps:
			var kw := String((g as Dictionary)["kw"])
			var has_type := false
			for want in (MECH[kw] as Array):
				if String(want) != NONE:
					has_type = true
			if has_type:
				supported += 1
			else:
				unsupported += 1
		per[tid] = {
			"name": String(s.get("name", tid)),
			"users": users,
			"lv": lv,
			"fx_blocks": fx_list.size(),
			"gaps": my_gaps,
			"gap_engine_has_type": supported,
			"gap_engine_missing": unsupported,
		}
	var out := {"total": per.size(), "talents": per}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
		print("\n已导出明细: %s" % path)


func _uniq_count(arr: Array, key: String) -> int:
	var s := {}
	for a in arr:
		s[String((a as Dictionary)[key])] = true
	return s.size()