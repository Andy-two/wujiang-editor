extends SceneTree

# 7机制 × 维度 专项测试（基准 + 每次只变一个维度）
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const EB = preload("res://scripts/core/ed_battle.gd")

var out: Array = []
var data = ED.new()
const BASE := {"level": 60, "skill_lv": 4, "talent_lv": 4, "star": 5,
	"vice": 0, "shenbing": 0, "passive": true}


func _cfg(o: Dictionary = {}) -> Dictionary:
	var c: Dictionary = BASE.duplicate()
	for k in o.keys():
		c[k] = o[k]
	return c


func _unit(cfg: Dictionary, key: String):
	# 副将 / 神兵 / 被动必须在 unit_template 之前改武将数据，否则模板内部不会读取
	var g: Dictionary = data.generals[key]
	var old_vice = g["ed_ext"].get("vice_id", 0)
	var old_sb = g["ed_ext"].get("shenbing_lv", 0)
	var old_skills: Array = (g.get("skills", []) as Array).duplicate()
	g["ed_ext"]["vice_id"] = int(cfg["vice"])
	g["ed_ext"]["vice_lv"] = 25
	g["ed_ext"]["shenbing_lv"] = int(cfg["shenbing"])
	if not bool(cfg["passive"]):
		var keep: Array = []
		for sid in old_skills:
			var d: Dictionary = data.skills.get(String(sid), {})
			if String(d.get("kind", "")) != "passive":
				keep.append(sid)
		g["skills"] = keep
	var t = data.unit_template(key, int(cfg["level"]), int(cfg["star"]), "")
	# 还原
	g["ed_ext"]["vice_id"] = old_vice
	g["ed_ext"]["shenbing_lv"] = old_sb
	g["skills"] = old_skills
	# 技能阶 / 天赋阶在模板返回后设置（战斗读取 u.skill_lv / u.talent_lv）
	# 神兵专项：保留模板内的神兵升阶结果，不强覆盖
	if not bool(cfg.get("keep_skill_lv", false)):
		var slv: Dictionary = {}
		for sid in (t.get("skills", []) as Array):
			slv[String(sid)] = int(cfg["skill_lv"])
		t["skill_lv"] = slv
	t["talent_lv"] = int(cfg["talent_lv"])
	return t


func _foe(hp: int = 30000):
	var ft = data.unit_template("jia_xu", 60, 5, "")
	ft["stats"]["max_hp"] = hp
	ft["stats"]["hp"] = hp
	ft["skills"] = []
	return ft


func _bt():
	var bt = EB.new(21, 21)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	bt.set_seed(7777)
	return bt


# 技能打多靶总伤害
func _skill_dmg(cfg: Dictionary, key: String, sid: String, choice: String = "") -> int:
	var bt = _bt()
	var u = bt.add_unit(_unit(cfg, key), Vector2i(10, 10), 0)
	var main = bt.add_unit(_foe(), Vector2i(11, 10), 1)
	bt._apply_passive_startup(); bt._refresh_all_cond_mult()
	var area_sid := choice if choice != "" else sid
	var ca: Array = bt.skill_cast_area(u, area_sid)
	if ca.is_empty():
		return -2
	var c0 = ca[0]
	var land: Vector2i = u["pos"] + (c0 if c0 is Vector2i else Vector2i(int(c0.x), int(c0.y)))
	main["pos"] = land
	var targets: Array = [main]
	for e in bt.skill_effect_area(u, area_sid):
		var eo: Vector2i = e if e is Vector2i else Vector2i(int(e.x), int(e.y))
		if eo != Vector2i.ZERO:
			targets.append(bt.add_unit(_foe(), land + eo, 1))
	var hp0 := 30000 * targets.size()
	var rr: Dictionary = bt.cast_skill(u, sid, land, choice)
	if not bool(rr.get("ok", false)):
		return -3
	var thp := 0
	for tg in targets:
		thp += int((tg as Dictionary).get("hp", 0))
	return clampi(hp0 - thp, 0, hp0)


func _basic_dmg(cfg: Dictionary, key: String) -> int:
	var bt = _bt()
	var u = bt.add_unit(_unit(cfg, key), Vector2i(10, 10), 0)
	var f = bt.add_unit(_foe(), Vector2i(11, 10), 1)
	bt._apply_passive_startup(); bt._refresh_all_cond_mult()
	var hp0 := int(f["hp"])
	bt.basic_attack(u, f)
	return clampi(hp0 - int(f["hp"]), 0, hp0)


# 追击：施放石兵八阵后对范围内敌军的追击伤害
func _pursuit_dmg(cfg: Dictionary) -> int:
	return _skill_dmg(cfg, "zhuge_liang", "zhuge_shibing")


# 阵法：偃月阵光环 → 友军受谋略伤害减免（用伤害差表示减伤量）
func _formation_magic_cut(cfg: Dictionary) -> float:
	var bt = _bt()
	var u = bt.add_unit(_unit(cfg, "guan_yu"), Vector2i(10, 10), 0)
	var ally = bt.add_unit(_foe(), Vector2i(11, 10), 0)
	bt._apply_passive_startup(); bt._refresh_all_cond_mult()
	var e: Dictionary = ally.get("ext", {})
	return float(e.get("aura_magic_cut", 0.0))


# DOT：贾诩四胜决机施加溃逃，结算一回合
func _dot_dmg(cfg: Dictionary) -> int:
	var bt = _bt()
	var u = bt.add_unit(_unit(cfg, "jia_xu"), Vector2i(10, 10), 0)
	var f = bt.add_unit(_foe(), Vector2i(11, 10), 1)
	bt._apply_passive_startup(); bt._refresh_all_cond_mult()
	var sid := "jia_xu_s3"
	var ca: Array = bt.skill_cast_area(u, sid)
	if ca.is_empty():
		return -2
	var c0 = ca[0]
	var land: Vector2i = u["pos"] + (c0 if c0 is Vector2i else Vector2i(int(c0.x), int(c0.y)))
	f["pos"] = land
	bt.cast_skill(u, sid, land)
	var hp_before := int(f["hp"])
	bt.end_unit_turn(f)
	return clampi(hp_before - int(f["hp"]), 0, hp_before)


# 治疗：蔡文姬琴音
func _heal_amt(cfg: Dictionary) -> int:
	var bt = _bt()
	var u = bt.add_unit(_unit(cfg, "cai_wenji"), Vector2i(10, 10), 0)
	var ally = bt.add_unit(_foe(), Vector2i(10, 11), 0)
	ally["hp"] = 10000
	bt._apply_passive_startup(); bt._refresh_all_cond_mult()
	var before := int(ally["hp"])
	bt.cast_skill(u, "10274031", ally["pos"])
	return clampi(int(ally["hp"]) - before, 0, 30000)


# 暴击
func _crit(cfg: Dictionary) -> Array:
	var t = _unit(cfg, "ma_chao")
	t["fortune"] = float((t.get("fives", {}) as Dictionary).get("mei", 0))
	return [RULEZ.crit_chance_of(t), RULEZ.crit_mult_of(t)]


func _rec(mech: String, var_name: String, val, metric: String, result, detail: String = "") -> void:
	out.append([mech, var_name, str(val), metric, str(result), detail])


func _dim(mech: String, vn: String, vals: Array, fn: Callable, metric: String) -> void:
	for v in vals:
		var c := _cfg(); c[vn] = v
		_rec(mech, vn, v, metric, fn.call(c))


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	data.load_all()
	RULEZ.settings["use_official_panel"] = true

	var levels := [1, 20, 40, 60]
	var lvs := [1, 2, 3, 4]
	var stars := [1, 3, 5, 7, 10]
	var vices := [0, 1335]
	var talents := [1, 2, 3, 4]
	var sbs := [0, 11, 14, 17, 20]
	var passes := [true, false]

	# 1 吕布群伤
	_dim("吕布群伤", "level", levels, Callable(self, "_m_lubu"), "总伤害")
	_dim("吕布群伤", "skill_lv", lvs, Callable(self, "_m_lubu"), "总伤害")
	_dim("吕布群伤", "star", stars, Callable(self, "_m_lubu"), "总伤害")
	_dim("吕布群伤", "vice", vices, Callable(self, "_m_lubu"), "总伤害")
	_dim("吕布群伤", "talent_lv", talents, Callable(self, "_m_lubu"), "总伤害")
	_dim("吕布群伤", "shenbing", sbs, Callable(self, "_m_lubu"), "总伤害")
	_dim("吕布群伤", "passive", passes, Callable(self, "_m_lubu"), "总伤害")

	# 2 关羽单伤
	_dim("关羽单伤", "level", levels, Callable(self, "_m_guan"), "总伤害")
	_dim("关羽单伤", "skill_lv", lvs, Callable(self, "_m_guan"), "总伤害")
	_dim("关羽单伤", "star", stars, Callable(self, "_m_guan"), "总伤害")
	_dim("关羽单伤", "vice", vices, Callable(self, "_m_guan"), "总伤害")
	_dim("关羽单伤", "talent_lv", talents, Callable(self, "_m_guan"), "总伤害")
	_dim("关羽单伤", "shenbing", sbs, Callable(self, "_m_guan"), "总伤害")
	_dim("关羽单伤", "passive", passes, Callable(self, "_m_guan"), "总伤害")

	# 3 诸葛亮追击
	_dim("诸葛亮追击", "level", levels, Callable(self, "_m_pursuit"), "追击伤害")
	_dim("诸葛亮追击", "skill_lv", lvs, Callable(self, "_m_pursuit"), "追击伤害")
	_dim("诸葛亮追击", "star", stars, Callable(self, "_m_pursuit"), "追击伤害")
	_dim("诸葛亮追击", "vice", vices, Callable(self, "_m_pursuit"), "追击伤害")
	_dim("诸葛亮追击", "talent_lv", talents, Callable(self, "_m_pursuit"), "追击伤害")
	_dim("诸葛亮追击", "shenbing", sbs, Callable(self, "_m_pursuit"), "追击伤害")
	_dim("诸葛亮追击", "passive", passes, Callable(self, "_m_pursuit"), "追击伤害")

	# 4 阵法（偃月阵光环）
	_dim("阵法效果", "level", levels, Callable(self, "_m_form"), "谋略减伤率")
	_dim("阵法效果", "skill_lv", lvs, Callable(self, "_m_form"), "谋略减伤率")
	_dim("阵法效果", "star", stars, Callable(self, "_m_form"), "谋略减伤率")
	_dim("阵法效果", "vice", vices, Callable(self, "_m_form"), "谋略减伤率")
	_dim("阵法效果", "talent_lv", talents, Callable(self, "_m_form"), "谋略减伤率")
	_dim("阵法效果", "shenbing", sbs, Callable(self, "_m_form"), "谋略减伤率")
	_dim("阵法效果", "passive", passes, Callable(self, "_m_form"), "谋略减伤率")

	# 5 贾诩DOT
	_dim("贾诩DOT", "level", levels, Callable(self, "_m_dot"), "DOT伤害")
	_dim("贾诩DOT", "skill_lv", lvs, Callable(self, "_m_dot"), "DOT伤害")
	_dim("贾诩DOT", "star", stars, Callable(self, "_m_dot"), "DOT伤害")
	_dim("贾诩DOT", "vice", vices, Callable(self, "_m_dot"), "DOT伤害")
	_dim("贾诩DOT", "talent_lv", talents, Callable(self, "_m_dot"), "DOT伤害")
	_dim("贾诩DOT", "shenbing", sbs, Callable(self, "_m_dot"), "DOT伤害")
	_dim("贾诩DOT", "passive", passes, Callable(self, "_m_dot"), "DOT伤害")

	# 6 蔡文姬治疗
	_dim("蔡文姬治疗", "level", levels, Callable(self, "_m_heal"), "回血量")
	_dim("蔡文姬治疗", "skill_lv", lvs, Callable(self, "_m_heal"), "回血量")
	_dim("蔡文姬治疗", "star", stars, Callable(self, "_m_heal"), "回血量")
	_dim("蔡文姬治疗", "vice", vices, Callable(self, "_m_heal"), "回血量")
	_dim("蔡文姬治疗", "talent_lv", talents, Callable(self, "_m_heal"), "回血量")
	_dim("蔡文姬治疗", "shenbing", sbs, Callable(self, "_m_heal"), "回血量")
	_dim("蔡文姬治疗", "passive", passes, Callable(self, "_m_heal"), "回血量")

	# 7 马超暴击
	for v in levels:
		var c1 := _cfg(); c1["level"] = v
		var r1: Array = _crit(c1)
		_rec("马超暴击", "level", v, "暴击率", "%.4f" % r1[0])
		_rec("马超暴击", "level", v, "暴伤倍率", "%.4f" % r1[1])
	for v in lvs:
		var c2 := _cfg(); c2["skill_lv"] = v
		var r2: Array = _crit(c2)
		_rec("马超暴击", "skill_lv", v, "暴击率", "%.4f" % r2[0])
		_rec("马超暴击", "skill_lv", v, "暴伤倍率", "%.4f" % r2[1])
	for v in stars:
		var c3 := _cfg(); c3["star"] = v
		var r3: Array = _crit(c3)
		_rec("马超暴击", "star", v, "暴击率", "%.4f" % r3[0])
		_rec("马超暴击", "star", v, "暴伤倍率", "%.4f" % r3[1])
	for v in vices:
		var c4 := _cfg(); c4["vice"] = v
		var r4: Array = _crit(c4)
		_rec("马超暴击", "vice", v, "暴击率", "%.4f" % r4[0])
		_rec("马超暴击", "vice", v, "暴伤倍率", "%.4f" % r4[1])
	for v in talents:
		var c5 := _cfg(); c5["talent_lv"] = v
		var r5: Array = _crit(c5)
		_rec("马超暴击", "talent_lv", v, "暴击率", "%.4f" % r5[0])
		_rec("马超暴击", "talent_lv", v, "暴伤倍率", "%.4f" % r5[1])
	for v in sbs:
		var c6 := _cfg(); c6["shenbing"] = v
		var r6: Array = _crit(c6)
		_rec("马超暴击", "shenbing", v, "暴击率", "%.4f" % r6[0])
		_rec("马超暴击", "shenbing", v, "暴伤倍率", "%.4f" % r6[1])
	for v in passes:
		var c7 := _cfg(); c7["passive"] = v
		var r7: Array = _crit(c7)
		_rec("马超暴击", "passive", v, "暴击率", "%.4f" % r7[0])
		_rec("马超暴击", "passive", v, "暴伤倍率", "%.4f" % r7[1])

	# 神兵专项：基准技能 Lv1 时，神兵升阶（11/14/17→技能4阶）的效果
	for v in sbs:
		var cs := _cfg(); cs["shenbing"] = v; cs["skill_lv"] = 1; cs["keep_skill_lv"] = true
		_rec("神兵升阶专项(关羽Lv1技)", "shenbing", v, "青龙斩月伤害", _m_guan(cs))
	for v in sbs:
		var cs2 := _cfg(); cs2["shenbing"] = v; cs2["skill_lv"] = 1; cs2["keep_skill_lv"] = true
		_rec("神兵升阶专项(蔡文姬Lv1技)", "shenbing", v, "善哉行治疗", _heal_amt(cs2))

	var f = FileAccess.open("res://data/stats/focus_mechanics.tsv", FileAccess.WRITE)
	if f != null:
		f.store_line("mechanic\tvariable\tvalue\tmetric\tresult\tdetail")
		for row in out:
			f.store_line("\t".join(row))
		f.close()
	print("完成：%d 行" % out.size())
	quit(0)


func _m_lubu(cfg): return _skill_dmg(cfg, "lu_bu", "guiku")
func _m_guan(cfg): return _skill_dmg(cfg, "guan_yu", "guan_qinglong")
func _m_pursuit(cfg): return _pursuit_dmg(cfg)
func _m_form(cfg): return _formation_magic_cut(cfg)
func _m_dot(cfg): return _dot_dmg(cfg)
func _m_heal(cfg): return _heal_amt(cfg)
