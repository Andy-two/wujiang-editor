extends SceneTree

# 批量：所有武将 满级满阶 有被动 vs 无被动，普攻 + 技能伤害对比
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const EB = preload("res://scripts/core/ed_battle.gd")

var out: Array = []


func _foe(data) -> Dictionary:
	var ft = data.unit_template("jia_xu", 60, 5, "")
	ft["stats"]["max_hp"] = 9999999
	ft["stats"]["hp"] = 9999999
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


# 找第一个主动伤害技能
func _damage_skill(data, key: String) -> String:
	for sid in g_key_skills(data, key):
		var d: Dictionary = data.skills.get(String(sid), {})
		if String(d.get("kind", "")) == "passive":
			continue
		for fx in (d.get("ed_fx_list", []) as Array):
			if not (fx is Dictionary):
				continue
			if String((fx as Dictionary).get("type", "")) == RULEZ.SFX_DAMAGE:
				return String(sid)
	return ""


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
		if sid == "":
			return 0
		# 组合技需要先选子技能，跳过
		if data.is_group(sid):
			return -1
		# 目标放到释放范围内第一个格子
		var ca: Array = bt.skill_cast_area(u, sid)
		if ca.is_empty():
			return -2
		var off: Vector2i = ca[0] if ca[0] is Vector2i else Vector2i(int(ca[0].x), int(ca[0].y))
		var tgt: Vector2i = u["pos"] + off
		f["pos"] = tgt
		var rr: Dictionary = bt.cast_skill(u, sid, tgt)
		if not bool(rr.get("ok", false)):
			return -3
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
		var sid := _damage_skill(data, k)
		if sid != "":
			dmg_skill_count += 1
		var b_on := _measure(data, k, true, "basic", "")
		var b_off := _measure(data, k, false, "basic", "")
		var s_on := _measure(data, k, true, "skill", sid)
		var s_off := _measure(data, k, false, "skill", sid)
		out.append("%s\t%s\t%d\t%d\t%d\t%s\t%s\t%d\t%d\t%d" % [
			k, data.name_of(k), b_on, b_off, b_on - b_off,
			sid, (data.get_skill(sid) as Dictionary).get("name", "-") if sid != "" else "-",
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
