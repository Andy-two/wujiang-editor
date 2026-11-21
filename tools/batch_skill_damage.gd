extends SceneTree

# 批量：所有武将 满级满阶 有被动 vs 无被动，普攻 + 技能伤害对比
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const EB = preload("res://scripts/core/ed_battle.gd")

var out: Array = []


func _foe(data) -> Dictionary:
	var ft = data.unit_template("jia_xu", 60, 5, "")
	# 用合理的高血量靶子（够高不被秒，又不会让「按最大兵力%」的固伤失真）
	ft["stats"]["max_hp"] = 30000
	ft["stats"]["hp"] = 30000
	ft["skills"] = []
	var e = ft.get("ext", {})
	e.erase("passive_impls")
	e.erase("cond_attrs")
	e.erase("magic_cut")
	e.erase("full_hp_cut")
	ft["ext"] = e
	return ft


func _template(data, key: String, with_passive: bool) -> Dictionary:
	var t = data.unit_template(key, 60, 5, "")
	var sids: Array = []
	for sid in (g_key_skills(data, key)):
		sids.append(String(sid))
	if not with_passive:
		var keep: Array = []
		for sid in sids:
			var d: Dictionary = data.skills.get(sid, {})
			if String(d.get("kind", "")) != "passive":
				keep.append(sid)
		t["skills"] = keep
		var e: Dictionary = t.get("ext", {})
		e.erase("passive_impls")
		e.erase("cond_attrs")
		e.erase("magic_cut")
		e.erase("full_hp_cut")
		t["ext"] = e
	# 满阶：所有技能 Lv4、天赋 Lv4
	var slv: Dictionary = {}
	for sid in (t.get("skills", []) as Array):
		slv[String(sid)] = 4
	t["skill_lv"] = slv
	t["talent_lv"] = 4
	return t


func g_key_skills(data, key: String) -> Array:
	var g: Dictionary = data.generals.get(key, {})
	return g.get("skills", []) if g.has("skills") else []


# 找一个「可主动施放的纯伤害技能」：跳过被动，组合技返回其第一个可施放子技能
# 返回 [技能id, choice]：choice 非空表示子技能
func _damage_skill(data, key: String) -> Array:
	for sid in g_key_skills(data, key):
		var d: Dictionary = data.skills.get(String(sid), {})
		if String(d.get("kind", "")) == "passive":
			continue
		# self 技能的 damage 多是响应型，主动施放打不到目标，跳过
		if String(d.get("kind", "")) == "self":
			continue
		var has_dmg := false
		for fx in (d.get("ed_fx_list", []) as Array):
			if not (fx is Dictionary):
				continue
			if String((fx as Dictionary).get("type", "")) == RULEZ.SFX_DAMAGE:
				has_dmg = true
				break
		if not has_dmg:
			continue
		if data.is_group(String(sid)):
			# 组合技：找第一个有伤害的子技能
			for kid in data.selectable_children(String(sid)):
				var kd: Dictionary = data.skills.get(String(kid), {})
				if String(kd.get("kind", "")) == "passive":
					continue
				for fx2 in (kd.get("ed_fx_list", []) as Array):
					if fx2 is Dictionary and String((fx2 as Dictionary).get("type", "")) == RULEZ.SFX_DAMAGE:
						return [String(sid), String(kid)]
			continue
		return [String(sid), ""]
	return ["", ""]


func _measure(data, key: String, with_passive: bool, mode: String, sid: String) -> int:
	var bt = EB.new(21, 21)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	bt.set_seed(7777)
	var t = _template(data, key, with_passive)
	var u = bt.add_unit(t, Vector2i(10, 10), 0)
	var f = bt.add_unit(_foe(data), Vector2i(11, 10), 1)
	bt._apply_passive_startup()
	bt._refresh_all_cond_mult()
	var hp0 := int(f["hp"])
	if mode == "basic":
		bt.basic_attack(u, f)
	else:
		var parts := sid.split("|")
		var real_sid := parts[0]
		var choice := ""
		if parts.size() > 1:
			choice = parts[1]
		if real_sid == "":
			return 0
		# 组合技用子技能的具体释放范围；普通技能用自身范围
		var area_sid := choice if choice != "" else real_sid
		# 落点取释放范围首格；在「落点 + 作用范围每一格」都放靶子，
		# 这样无论引擎把作用格旋转到哪个朝向，都至少有一个靶子被打中
		var ca: Array = bt.skill_cast_area(u, area_sid)
		if ca.is_empty():
			return -2
		var c0 = ca[0]
		var land: Vector2i = u["pos"] + (c0 if c0 is Vector2i else Vector2i(int(c0.x), int(c0.y)))
		f["pos"] = land
		# 记录靶子们的初始血量（主靶 + 作用格上的额外靶）
		var targets: Array = [f]
		var ea: Array = bt.skill_effect_area(u, area_sid)
		for e in ea:
			var eo: Vector2i = e if e is Vector2i else Vector2i(int(e.x), int(e.y))
			if eo == Vector2i.ZERO:
				continue
			var extra = bt.add_unit(_foe(data), land + eo, 1)
			targets.append(extra)
		var rr: Dictionary = bt.cast_skill(u, real_sid, land, choice)
		if not bool(rr.get("ok", false)):
			return -3
		var thp := 0
		for tg in targets:
			thp += int((tg as Dictionary).get("hp", 0))
		return clampi(hp0 * targets.size() - thp, 0, hp0 * targets.size())
	var dmg := hp0 - int(f["hp"])
	return clampi(dmg, 0, hp0)


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()

	out.append("武将id\t名称\t普攻有\t普攻无\t普攻差\t技能id\t技能名\t技能有\t技能无\t技能差")
	var dmg_skill_count := 0
	for key in data.order:
		var k := String(key)
		var ds: Array = _damage_skill(data, k)
		var sid := String(ds[0])
		var choice := String(ds[1])
		var measure_sid := sid + ("|" + choice if choice != "" else "")
		if sid != "":
			dmg_skill_count += 1
		var b_on := _measure(data, k, true, "basic", "")
		var b_off := _measure(data, k, false, "basic", "")
		var s_on := _measure(data, k, true, "skill", measure_sid)
		var s_off := _measure(data, k, false, "skill", measure_sid)
		var show_sid := sid + ("→" + choice if choice != "" else "")
		out.append("%s\t%s\t%d\t%d\t%d\t%s\t%s\t%d\t%d\t%d" % [
			k, data.name_of(k), b_on, b_off, b_on - b_off,
			show_sid, (data.get_skill(sid) as Dictionary).get("name", "-") if sid != "" else "-",
			s_on, s_off, s_on - s_off])

	var f = FileAccess.open("res://data/stats/passive_damage_skill.tsv", FileAccess.WRITE)
	if f != null:
		for ln in out:
			f.store_line(ln)
		f.close()
	print("完成：%d 武将，其中 %d 名有主动伤害技能" % [data.order.size(), dmg_skill_count])
	for ln in out:
		print(ln)
	quit(0)
