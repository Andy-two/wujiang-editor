extends RefCounted
class_name EdBattle

# ============================================================
# 小战场引擎：可操作测试用，也可被演算台调用
#   - 方格地图、障碍、移动（BFS）、普攻 + 反击、技能（释放距离/作用范围形状）
#   - 敌方 AI：靠近并攻击最近敌人，技能优先
#   - 天赋「占位效果」：按天赋 Lv 提供通用被动（增伤/减伤/暴击/射程），
#     与旧工程里写死的专属天赋逻辑区分，可在「天赋」页查看说明
# 所有数值计算走 EdRules，保证与验算台一致。
# ============================================================

const RULEZ = preload("res://scripts/core/rules.gd")

signal log_line(text: String, tone: String)
signal changed()
# 动画事件：uid / 动作(idle|walk|attack|hurt|die) / 朝向(down|left|right|up) / 数据
signal anim_event(uid: int, act: String, dir: String, info: Dictionary)
# 技能特效事件：技能id / 位置列表 / 技能数据
signal fx_event(sid: String, cells: Array, skill: Dictionary)

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var gw := 12
var gh := 10
var blocked: Dictionary = {}       # Vector2i -> true
var units: Array = []
var turn_side := 0                 # 0 = 我方, 1 = 敌军
var round_no := 1
var ended := false
var result := ""
var _next_uid := 1
var rng_seed := -1
var _talent_applied := false


func _init(w: int = 12, h: int = 10) -> void:
	gw = w
	gh = h


func set_seed(s: int) -> void:
	rng_seed = s
	if s >= 0:
		RULEZ.RNG.seed = s


# ------------------------------------------------------------
# 单位
# ------------------------------------------------------------
func add_unit(t: Dictionary, pos: Vector2i, side: int) -> Dictionary:
	var st: Dictionary = t.get("stats", {})
	var u := {
		"uid": _next_uid,
		"key": String(t.get("key", "")),
		"name": String(t.get("name", "?")),
		"side": side,
		"arm": String(t.get("arm", "盾")),
		"color": String(t.get("color", "#3b82f6")),
		"level": int(t.get("level", 1)),
		"star": int(t.get("star", 1)),
		"talent": String(t.get("talent", "")),
		"talent_lv": int(t.get("talent_lv", 1)),
		"skills": (t.get("skills", []) as Array).duplicate(),
		"skill_lv": (t.get("skill_lv", {}) as Dictionary).duplicate(),
		"ext": (t.get("ext", {}) as Dictionary).duplicate(true),
		"max_hp": int(st.get("max_hp", st.get("hp", 100))),
		"hp": int(st.get("max_hp", st.get("hp", 100))),
		"atk": int(st.get("atk", 10)),
		"def": int(st.get("def", 10)),
		"matk": int(st.get("matk", 10)),
		"mdef": int(st.get("mdef", 10)),
		"luck": int(st.get("luck", 50)),
		"move": int(st.get("move", 4)),
		"atk_range": int(st.get("range", 1)),
		"pos": pos,
		"alive": true,
		"done": false,
		"cd": {},
		"buffs": [],
		"debuffs": [],
		"extra_action": false,
		"douqi": 0,
		"wushuang": 0,
		"moved_tiles": 0,
		"face": "down",          # 当前朝向
		"anim": "idle",          # 当前动作
		"anim_ver": 0,           # 动作切换计数（供视图判断重播）
		"anim_hold": 0.0,        # 一次性动作剩余播放时间
		"art": {},
	}
	for sid in u["skills"]:
		u["cd"][String(sid)] = 0
	_next_uid += 1
	units.append(u)
	return u


func clear_units() -> void:
	units.clear()
	_next_uid = 1


# 取该单位的动画表（动作_朝向 -> 槽位）
func unit_art(u) -> Dictionary:
	if u == null:
		return {}
	var cache: Dictionary = _data_ref.get("art_cache", {})
	var a = cache.get(String(u.get("key", "")), {})
	if a is Dictionary:
		var d: Dictionary = a
		return d
	return {}


func has_anim(u, act: String, dir: String) -> bool:
	var art := unit_art(u)
	var sheets: Dictionary = {}
	var g: Dictionary = _data_ref.get("generals", {}).get(String(u.get("key", "")), {})
	var ea = g.get("ed_art", {})
	if ea is Dictionary and (ea as Dictionary).get("sheets") is Dictionary:
		sheets = (ea as Dictionary)["sheets"]
	var slot := "%s_%s" % [act, dir]
	var check := func(sl: String) -> bool:
		if not art.has(sl):
			return false
		var sh := String((art[sl] as Dictionary).get("sheet", "mov"))
		return String(sheets.get(sh, "")) != ""
	if check.call(slot):
		return true
	# 「右」缺失时镜像「左」
	if dir == "right" and check.call("%s_left" % act):
		return true
	return false


func _face_towards(u, target: Vector2i) -> void:
	var d := RULEZ.face_dir(u["pos"], (target if target != u["pos"] else u["pos"] + Vector2i(0, 1)))
	var dir := "down"
	if d.y > 0:
		dir = "down"
	elif d.y < 0:
		dir = "up"
	elif d.x > 0:
		dir = "right"
	else:
		dir = "left"
	_set_anim(u, "idle", dir)


func _set_anim(u, act: String, dir: String = "") -> void:
	if u == null:
		return
	if dir != "":
		u["face"] = dir
	u["anim"] = act
	u["anim_ver"] = int(u.get("anim_ver", 0)) + 1
	u["anim_t"] = Time.get_ticks_msec() / 1000.0
	anim_event.emit(int(u["uid"]), act, String(u["face"]), {})


func unit_at(p: Vector2i):
	for u in units:
		if u["alive"] and u["pos"] == p:
			return u
	return null


func get_unit(uid: int):
	for u in units:
		if int(u["uid"]) == uid:
			return u
	return null


func alive(side: int) -> Array:
	var out: Array = []
	for u in units:
		if u["alive"] and int(u["side"]) == side:
			out.append(u)
	return out


func enemies_of(side: int) -> Array:
	var out: Array = []
	for u in units:
		if u["alive"] and int(u["side"]) != side:
			out.append(u)
	return out


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < gw and p.y < gh


func occupied() -> Dictionary:
	var occ := {}
	for u in units:
		if u["alive"]:
			occ[u["pos"]] = true
	return occ


# ------------------------------------------------------------
# 范围
# ------------------------------------------------------------
func attack_area(u) -> Array:
	var k := String(u.get("key", ""))
	# 1) 武将自定义普攻形状优先
	var ar: Dictionary = _general_ranges(k)
	if ar.has("basic"):
		var b: Array = (ar["basic"] as Dictionary).get("area", [])
		if not b.is_empty():
			return RULEZ.parse_area(b)
	# 2) 兵种攻击范围形状（以你在「⑤ 兵种」里画的为准，不再被射程裁剪）
	var arm_shapes: Dictionary = _data_ref.get("arm_shapes", {})
	var asd: Dictionary = arm_shapes.get(String(u.get("arm", "")), {})
	var aa: Array = asd.get("area", [])
	if not aa.is_empty():
		var area0 := RULEZ.parse_area(aa)
		if int(u.get("wushuang", 0)) > 0:
			area0 = RULEZ.dilate(area0, 1)
		return area0
	# 3) 默认：按射程生成菱形
	var area := RULEZ.diamond(int(u.get("atk_range", 1)))
	if int(u.get("wushuang", 0)) > 0:
		area = RULEZ.dilate(area, 1)
	return area


func _general_ranges(gkey: String) -> Dictionary:
	var cache: Dictionary = _data_ref.get("ed_ranges_cache", {})
	return cache.get(gkey, {})


var _data_ref: Dictionary = {}        # 由外部注入：{"general_ranges": {key: ranges}, "skills": {...}, "talents": {...}}


func bind_data(generals: Dictionary, skills: Dictionary, talents: Dictionary, arm_shapes: Dictionary = {}) -> void:
	var cache := {}
	var art_cache := {}
	for k in generals.keys():
		cache[String(k)] = (generals[k] as Dictionary).get("ed_ranges", {})
		var art = (generals[k] as Dictionary).get("ed_art", {})
		if art is Dictionary and (art as Dictionary).get("anims") is Dictionary:
			art_cache[String(k)] = (art as Dictionary)["anims"]
	_data_ref = {"ed_ranges_cache": cache, "skills": skills, "talents": talents,
		"generals": generals, "art_cache": art_cache, "arm_shapes": arm_shapes}


func skill_def(sid: String) -> Dictionary:
	var sk: Dictionary = _data_ref.get("skills", {})
	return sk.get(sid, {})


# 组技能：返回子技能 id 列表；非组返回空
func group_children(sid: String) -> Array:
	var d := skill_def(sid)
	var arr = d.get("ed_group", [])
	return arr.duplicate() if arr is Array else []


func is_group(sid: String) -> bool:
	return not group_children(sid).is_empty()


# 融合进来的被动效果关键词（供伤害计算识别，例如「袭扰」= 普攻物攻 +8%）
func merged_passives(u) -> Array:
	var out: Array = []
	for sid in (u.get("skills", []) as Array):
		var d := skill_def(String(sid))
		var mp = d.get("ed_merged_passives", [])
		if mp is Array:
			for x in mp:
				out.append(String(x))
	return out


# 从分层数据里取「≤ 当前等级」的最大一层（向上继承）
#   只在 Lv2 画的范围 → 2 级、3 级都用它；Lv3 另画了 → 只有 3 级用 Lv3
func _pick_layer(layers: Dictionary, lv: int, which: String) -> Array:
	if not (layers is Dictionary):
		return []
	var best := -1
	var found: Array = []
	for k in layers.keys():
		var ks := String(k)
		var n := int(ks.replace("lv_", "")) if ks.begins_with("lv_") else int(ks)
		if n <= lv and n > best:
			var layer = layers[k]
			if layer is Dictionary and (layer as Dictionary).has(which):
				var arr = (layer as Dictionary)[which]
				if arr is Array and not (arr as Array).is_empty():
					best = n
					found = arr
	return found


# 技能释放形状 / 作用范围形状：
#   武将 ed_ranges[技能].layers 的分层 > 武将 ed_ranges[技能].cast/area > 技能自带 > 自动生成
func skill_cast_area(u, sid: String) -> Array:
	var er: Dictionary = _general_ranges(String(u.get("key", "")))
	var lv := int(u["skill_lv"].get(sid, 1))
	if er.has(sid):
		var e: Dictionary = er[sid]
		var from_layer := _pick_layer(e.get("layers", {}), lv, "cast")
		if not from_layer.is_empty():
			return RULEZ.parse_area(from_layer)
		if e.has("cast"):
			return RULEZ.parse_area(e["cast"])
	var d := skill_def(sid)
	var l2 := _pick_layer(d.get("ed_layers", {}), lv, "cast")
	if not l2.is_empty():
		return RULEZ.parse_area(l2)
	if d.has("cast"):
		return RULEZ.parse_area(d["cast"])
	return RULEZ.diamond(maxi(1, int(d.get("range", 1))))


func skill_effect_area(u, sid: String) -> Array:
	var er: Dictionary = _general_ranges(String(u.get("key", "")))
	var lv := int(u["skill_lv"].get(sid, 1))
	if er.has(sid):
		var e: Dictionary = er[sid]
		var from_layer := _pick_layer(e.get("layers", {}), lv, "area")
		if not from_layer.is_empty():
			return RULEZ.parse_area(from_layer)
		if e.has("area"):
			return RULEZ.parse_area(e["area"])
	var d := skill_def(sid)
	var l2 := _pick_layer(d.get("ed_layers", {}), lv, "area")
	if not l2.is_empty():
		return RULEZ.parse_area(l2)
	if d.has("area"):
		return RULEZ.parse_area(d["area"])
	var r := int(d.get("radius", 0))
	if r > 0:
		return RULEZ.diamond(r)
	return [Vector2i.ZERO]


func castable_cells(u, sid: String) -> Array:
	# 释放距离形状（朝右）内的格：以自身为原点
	return skill_cast_area(u, sid)


func can_cast_at(u, sid: String, target: Vector2i) -> bool:
	if not in_bounds(target):
		return false
	var dir := RULEZ.face_dir(u["pos"], target)
	# 组技能：任一子技能能打到就允许（弹出选择菜单后再按子技能二次校验）
	var children := group_children(sid)
	if not children.is_empty():
		for c in children:
			var cast_c := RULEZ.rotate_area(skill_cast_area(u, String(c)), dir)
			if cast_c.has(target - u["pos"]):
				return true
		return false
	var cast := RULEZ.rotate_area(skill_cast_area(u, sid), dir)
	if not cast.has(target - u["pos"]):
		return false
	return true
	return true


func effect_cells_at(u, sid: String, target: Vector2i) -> Array:
	var dir := RULEZ.face_dir(u["pos"], target)
	var area := RULEZ.rotate_area(skill_effect_area(u, sid), dir)
	var out: Array = []
	for off in area:
		out.append(target + off)
	return out


# ------------------------------------------------------------
# 行动
# ------------------------------------------------------------
func move_cells(u) -> Dictionary:
	var occ := occupied()
	occ.erase(u["pos"])
	return RULEZ.reachable(u["pos"], int(u["move"]), occ)


func try_move(u, dest: Vector2i) -> Dictionary:
	if u == null or not u["alive"] or bool(u["done"]):
		return {"ok": false, "msg": "该单位无法行动"}
	var cells := move_cells(u)
	if not cells.has(dest):
		return {"ok": false, "msg": "无法到达该格"}
	var old: Vector2i = u["pos"]
	u["pos"] = dest
	u["moved_tiles"] = int(cells[dest])
	_face_towards(u, dest + (dest - old))
	_set_anim(u, "walk", String(u["face"]))
	u["anim_hold"] = 0.5
	_emit("%s 移动到 (%d,%d)" % [u["name"], dest.x, dest.y], "info")
	return {"ok": true}


func basic_attack(attacker, target) -> Dictionary:
	if attacker == null or target == null or not attacker["alive"] or not target["alive"]:
		return {"ok": false}
	if bool(attacker["done"]):
		return {"ok": false, "msg": "已行动"}
	if not attack_area(attacker).has(target["pos"] - attacker["pos"]):
		return {"ok": false, "msg": "超出普攻射程"}
	var arm_mul := RULEZ.arm_multiplier(String(attacker["arm"]), String(target["arm"]))
	_face_towards(attacker, target["pos"])
	# 融合进来的被动（如「袭扰」= 普攻物攻 +8%）——按被融合技能名识别
	var passive_bonus := 1.0
	for pn in merged_passives(attacker):
		if pn.contains("袭扰"):
			passive_bonus *= 1.08
		if pn.contains("奋勇"):
			passive_bonus *= 1.20
	var res := RULEZ.roll_damage(attacker, target, passive_bonus * status_damage_mult(attacker, target), arm_mul, {})
	var dmg := int(res["dmg"])
	dmg = _apply_outgoing(attacker, dmg)
	dmg = _apply_incoming(target, dmg)
	dmg = mini(dmg, int(target["hp"]))
	target["hp"] = int(target["hp"]) - dmg
	_set_anim(attacker, "attack", String(attacker["face"]))
	attacker["anim_hold"] = 0.6
	_set_anim(target, "hurt")
	target["anim_hold"] = 0.35
	_emit("%s 普攻 %s：%d 伤害%s" % [attacker["name"], target["name"], dmg, "（暴击）" if res["crit"] else ""], "hit")
	if int(target["hp"]) <= 0:
		_kill(target, attacker)
	else:
		# 反击：目标若在自己的普攻范围内且是近战则反击（简化规则：普攻范围覆盖攻击者即反击）
		if attack_area(target).has(attacker["pos"] - target["pos"]) and attacker["alive"]:
			_face_towards(target, attacker["pos"])
			var back := RULEZ.roll_damage(target, attacker, RULEZ.get_f("mult_counter"),
				RULEZ.arm_multiplier(String(target["arm"]), String(attacker["arm"])), {})
			var bd := _apply_incoming(attacker, _apply_outgoing(target, int(back["dmg"])))
			bd = mini(bd, int(attacker["hp"]))
			attacker["hp"] = int(attacker["hp"]) - bd
			_set_anim(target, "attack", String(target["face"]))
			target["anim_hold"] = 0.6
			_set_anim(attacker, "hurt")
			attacker["anim_hold"] = 0.35
			_emit("%s 反击 %s：%d 伤害" % [target["name"], attacker["name"], bd], "hit")
			if int(attacker["hp"]) <= 0:
				_kill(attacker, target)
	changed.emit()
	return {"ok": true, "dmg": dmg, "crit": res["crit"]}


func cast_skill(u, sid: String, target: Vector2i, choice: String = "") -> Dictionary:
	if u == null or not u["alive"]:
		return {"ok": false}
	if bool(u["done"]):
		return {"ok": false, "msg": "已行动"}
	var d := skill_def(sid)
	if d.is_empty():
		return {"ok": false, "msg": "未知技能"}
	# ---- 二选一组：若未指定子技能，返回可选列表让 UI 弹菜单 ----
	var children := group_children(sid)
	if not children.is_empty():
		if choice == "":
			var opts: Array = []
			for c in children:
				var cd: Dictionary = skill_def(String(c))
				opts.append({"id": String(c), "name": String(cd.get("name", c)),
					"desc": String(cd.get("desc", "")), "cd": int(u["cd"].get(String(c), 0))})
			return {"ok": false, "need_choice": true, "choices": opts, "group": sid,
				"msg": "请在「%s」的子技能中选择一个" % String(d.get("name", sid))}
		if not children.has(choice):
			return {"ok": false, "msg": "所选技能不在该组内"}
		# 用子技能执行：CD 记在子技能上
		return _cast_one(u, choice, target, sid)
	if String(d.get("kind", "")) == "passive":
		return {"ok": false, "msg": "被动技能无法主动施放"}
	return _cast_one(u, sid, target, "")


func _cast_one(u, sid: String, target: Vector2i, group_id: String) -> Dictionary:
	var d := skill_def(sid)
	if d.is_empty():
		return {"ok": false, "msg": "未知技能"}
	if String(d.get("kind", "")) == "passive":
		return {"ok": false, "msg": "被动技能无法主动施放"}
	if int(u["cd"].get(sid, 0)) > 0:
		return {"ok": false, "msg": "准备中（还剩 %d 回合）" % int(u["cd"][sid])}
	if not can_cast_at(u, sid, target):
		return {"ok": false, "msg": "超出释放距离"}
	u["cd"][sid] = int(d.get("cd", 0))
	var cells := effect_cells_at(u, sid, target)
	var sname := String(d.get("name", sid))
	var hits := 0
	# 朝向 + 施法动作 + 特效事件
	_face_towards(u, target)
	_set_anim(u, "attack", String(u["face"]))
	u["anim_hold"] = 0.6
	if d.get("ed_fx") is Dictionary:
		fx_event.emit(sid, cells, d)
	# 计算作用范围内的敌军 / 友军
	var kind := String(d.get("kind", "single"))
	var foes: Array = []
	var allies: Array = []
	for c in cells:
		if not in_bounds(c):
			continue
		var tu = unit_at(c)
		if tu == null:
			continue
		if int((tu as Dictionary)["side"]) != int(u["side"]):
			foes.append(tu)
		else:
			allies.append(tu)
	if kind == "single" and foes.size() > 1:
		foes = [foes[0]]
	# ---- 按「效果块」依次执行（只执行当前等级已生效的块）----
	var skill_lv := int(u["skill_lv"].get(sid, 1))
	var effects: Array = RULEZ.skill_effects_at(d, skill_lv)
	for fx in effects:
		var t := String(fx.get("type", ""))
		match t:
			RULEZ.SFX_DAMAGE:
				var times := maxi(1, int(fx.get("times", 1)))
				for _r in times:
					if foes.is_empty():
						break
					for tgt in foes:
						if not tgt["alive"]:
							continue
						var magic := bool(fx.get("magic", false)) or float(u["matk"]) > float(u["atk"]) * 1.2
						var am := RULEZ.arm_multiplier(String(u["arm"]), String(tgt["arm"]))
						var res := RULEZ.roll_damage(u, tgt, float(fx.get("value", 1.0)) * status_damage_mult(u, tgt), am,
							{"magic": magic, "ignore_def": float(fx.get("ignore_def", 0.0))})
						var dmg := _apply_incoming(tgt, _apply_outgoing(u, int(res["dmg"])))
						dmg = mini(dmg, int(tgt["hp"]))
						tgt["hp"] = int(tgt["hp"]) - dmg
						hits += 1
						if int(tgt["hp"]) > 0:
							_set_anim(tgt, "hurt")
							tgt["anim_hold"] = 0.35
						_emit("%s 施放「%s」，%s 受到 %d 伤害%s" % [u["name"], sname, tgt["name"], dmg,
							"（暴击）" if res["crit"] else ""], "hit")
						if int(tgt["hp"]) <= 0:
							_kill(tgt, u)
			RULEZ.SFX_HEAL:
				var pool2: Array = allies if not allies.is_empty() else [u]
				for tgt2 in pool2:
					var heal := int(round(float(u["matk"]) * float(fx.get("value", 0.8))
						* float(u["ext"].get("skill_power", 1.0))))
					tgt2["hp"] = mini(int(tgt2["max_hp"]), int(tgt2["hp"]) + heal)
					_emit("%s 施放「%s」，%s 回复 %d 兵力" % [u["name"], sname, tgt2["name"], heal], "heal")
			RULEZ.SFX_DEBUFF:
				var sname2 := String(fx.get("value", ""))
				for tgt3 in foes:
					if tgt3["alive"] and sname2 != "":
						_add_debuff(tgt3, sname2, int(fx.get("turns", 2)), u)
						_emit("  → %s 被施加「%s」" % [tgt3["name"], sname2], "info")
			RULEZ.SFX_BUFF:
				var bname := String(fx.get("value", ""))
				for tgt4 in (allies if not allies.is_empty() else [u]):
					if bname != "":
						_add_buff(tgt4, bname, int(fx.get("turns", 2)), int(fx.get("stacks", 1)))
						_emit("  → %s 获得「%s」" % [tgt4["name"], bname], "info")
			RULEZ.SFX_PUSH:
				for tgt5 in foes:
					if tgt5["alive"]:
						_push(u, tgt5, int(fx.get("value", 1)))
						_emit("  → %s 被击退 %d 格" % [tgt5["name"], int(fx.get("value", 1))], "info")
			RULEZ.SFX_DISPEL:
				for tgt6 in foes:
					if tgt6["alive"]:
						_dispel_buff(tgt6)
						_emit("  → 驱散 %s 的增益" % tgt6["name"], "info")
			RULEZ.SFX_SELF_DISPEL:
				_dispel_debuff(u)
				_emit("  → %s 净化了自身减益" % u["name"], "info")
			RULEZ.SFX_SELF_HEAL:
				var sh := int(round(float(u["max_hp"]) * float(fx.get("value", 0.3))))
				u["hp"] = mini(int(u["max_hp"]), int(u["hp"]) + sh)
				_emit("  → %s 自身回复 %d 兵力" % [u["name"], sh], "heal")
			RULEZ.SFX_CD_DOWN:
				for k in (u["cd"] as Dictionary).keys():
					u["cd"][k] = maxi(0, int(u["cd"][k]) - int(fx.get("value", 1)))
				_emit("  → %s 的所有技策准备期 -%d" % [u["name"], int(fx.get("value", 1))], "info")
			RULEZ.SFX_EXTRA_MOVE:
				u["done"] = false
				_emit("  → %s 获得再移动" % u["name"], "info")
			RULEZ.SFX_FIXED:
				# 固伤：无视防御与常规增减伤，只吃固伤增伤
				for tgt_f in foes:
					if not tgt_f["alive"]:
						continue
					var famt: float = float(fx.get("value", 100))
					# 也支持按目标最大兵力百分比
					if bool(fx.get("by_max_hp", false)):
						famt = float(tgt_f["max_hp"]) * float(fx.get("value_pct", 0.1))
					var fdmg := int(roundf(RULEZ.damage_fixed(famt, {
						"fixed_add": float((u["ext"] as Dictionary).get("fixed_add", 0.0))})))
					fdmg = mini(fdmg, int(tgt_f["hp"]))
					tgt_f["hp"] = int(tgt_f["hp"]) - fdmg
					hits += 1
					_emit("  → %s 受到 %d 固定伤害" % [tgt_f["name"], fdmg], "hit")
					if int(tgt_f["hp"]) <= 0:
						_kill(tgt_f, u)
			RULEZ.SFX_DRAIN:
				var pct := float(fx.get("value", 0.3))
				var dh := int(round(float(hits) * float(u["matk"]) * pct))
				if dh > 0:
					u["hp"] = mini(int(u["max_hp"]), int(u["hp"]) + dh)
					_emit("  → %s 吸血回复 %d 兵力" % [u["name"], dh], "heal")
			RULEZ.SFX_SHIELD:
				var sv := int(fx.get("value", 50))
				for tgt7 in (allies if not allies.is_empty() else [u]):
					_add_buff(tgt7, "护盾", int(fx.get("turns", 2)), sv)
					_emit("  → %s 获得护盾 %d" % [tgt7["name"], sv], "info")
			RULEZ.SFX_DOT:
				for tgt8 in foes:
					if tgt8["alive"]:
						_add_debuff(tgt8, "灼烧", int(fx.get("turns", 3)), u)
						_emit("  → %s 被施加持续伤害" % tgt8["name"], "info")
			RULEZ.SFX_HOT:
				for tgt9 in (allies if not allies.is_empty() else [u]):
					_add_buff(tgt9, "再生", int(fx.get("turns", 3)), int(fx.get("value", 30)))
					_emit("  → %s 获得持续回复" % tgt9["name"], "info")
			RULEZ.SFX_STUN, RULEZ.SFX_TAUNT, RULEZ.SFX_SILENCE, RULEZ.SFX_DISARM:
				var nm_map := {
					RULEZ.SFX_STUN: "眩晕", RULEZ.SFX_TAUNT: "嘲讽",
					RULEZ.SFX_SILENCE: "封技", RULEZ.SFX_DISARM: "缴械"}
				for tgt10 in foes:
					if tgt10["alive"]:
						_add_debuff(tgt10, String(nm_map[t]), int(fx.get("turns", 1)), u)
						_emit("  → %s 被施加「%s」" % [tgt10["name"], String(nm_map[t])], "info")
			RULEZ.SFX_SUMMON:
				var cnt := int(fx.get("value", 1))
				for i2 in cnt:
					var pos2 := _find_free_near(u["pos"])
					if pos2.x >= 0:
						var tpl := {"key": "", "name": "援军", "arm": "盾", "color": "#94a3b8",
							"level": int(u["level"]), "star": 1,
							"stats": {"max_hp": int(u["max_hp"]) / 3, "atk": int(u["atk"]), "def": int(u["def"]),
								"matk": 0, "mdef": int(u["mdef"]), "luck": 50, "move": 4, "range": 1}}
						add_unit(tpl, pos2, int(u["side"]))
						_emit("  → 召唤援军于 %s" % str(pos2), "info")
			RULEZ.SFX_TELEPORT:
				if not foes.is_empty():
					var srcp: Vector2i = u["pos"]
					u["pos"] = foes[0]["pos"]
					foes[0]["pos"] = srcp
					_emit("  → %s 与 %s 交换位置" % [u["name"], foes[0]["name"]], "info")
			RULEZ.SFX_EXTRA_TURN:
				u["done"] = false
				u["extra_action"] = true
				_emit("  → %s 获得额外行动" % u["name"], "info")
			RULEZ.SFX_REVIVE:
				var deader = _find_dead_ally(int(u["side"]))
				if deader != null:
					deader["alive"] = true
					deader["hp"] = int(round(float(deader["max_hp"]) * float(fx.get("value", 0.3))))
					_emit("  → %s 被复活" % deader["name"], "heal")
			RULEZ.SFX_CRIT_UP:
				_add_buff(u, "强运", int(fx.get("turns", 2)), 1)
				_emit("  → %s 暴击率提升" % u["name"], "info")
			RULEZ.SFX_LIFELINK:
				for tgt11 in foes:
					if tgt11["alive"]:
						_add_debuff(tgt11, "联结", int(fx.get("turns", 2)), u)
						_emit("  → %s 被施加伤害分摊" % tgt11["name"], "info")
			RULEZ.SFX_COPY_BUFF, RULEZ.SFX_STEAL_BUFF:
				for tgt12 in foes:
					if not tgt12["alive"] or (tgt12["buffs"] as Array).is_empty():
						continue
					var b0: Dictionary = tgt12["buffs"][0]
					_add_buff(u, String(b0["name"]), int(b0["turns"]), int(b0["stacks"]))
					if t == RULEZ.SFX_STEAL_BUFF:
						(tgt12["buffs"] as Array).remove_at(0)
					_emit("  → %s 获得「%s」" % [u["name"], String(b0["name"])], "info")
					break
	_emit("  作用格：%d" % cells.size(), "info")
	changed.emit()
	return {"ok": true, "hits": hits}


# 找附近空格（召唤用）
func _find_free_near(center: Vector2i) -> Vector2i:
	for r in range(1, 4):
		for off in RULEZ.diamond(r):
			var c2: Vector2i = center + off
			if in_bounds(c2) and not blocked.has(c2) and unit_at(c2) == null:
				return c2
	return Vector2i(-1, -1)


# 找一名已阵亡的友军（复活用）
func _find_dead_ally(side: int):
	for u in units:
		if not u["alive"] and int(u["side"]) == side:
			return u
	return null


func _apply_outgoing(u, dmg: int) -> int:
	# 扩展项：增伤 / 暴伤
	var bonus := float(u["ext"].get("damage_bonus", 0.0))
	return int(round(float(dmg) * (1.0 + bonus)))


# ------------------------------------------------------------
# 状态（增益 / 减益）——供效果块使用
#   减益：低迷/虚弱/识破/破绽等会真实改变伤害
#   增益：昂扬/坚壁/严阵/神威等同样生效
# ------------------------------------------------------------
func _add_debuff(t, name: String, turns: int, src = null) -> void:
	if t == null or not t["alive"]:
		return
	t["debuffs"].append({"name": name, "turns": maxi(1, turns), "src": int(src["uid"]) if src != null else -1})


func _add_buff(t, name: String, turns: int, stacks: int = 1) -> void:
	if t == null or not t["alive"]:
		return
	for b in t["buffs"]:
		if String(b["name"]) == name:
			b["turns"] = maxi(int(b["turns"]), turns)
			b["stacks"] = maxi(int(b["stacks"]), stacks)
			return
	t["buffs"].append({"name": name, "turns": maxi(1, turns), "stacks": maxi(1, stacks)})


func _has_debuff(t, name: String) -> bool:
	for b in t["debuffs"]:
		if String(b["name"]) == name:
			return true
	return false


func _has_buff(t, name: String) -> bool:
	for b in t["buffs"]:
		if String(b["name"]) == name:
			return true
	return false


func _dispel_buff(t) -> void:
	if t == null:
		return
	if (t["buffs"] as Array).is_empty():
		return
	(t["buffs"] as Array).remove_at(0)


func _dispel_debuff(t) -> void:
	if t == null:
		return
	for i in range((t["debuffs"] as Array).size() - 1, -1, -1):
		var d: Dictionary = t["debuffs"][i]
		if bool(d.get("dispellable", true)):
			t["debuffs"].remove_at(i)
			break


func _push(u, t, n: int) -> void:
	if t == null or not t["alive"]:
		return
	var dir := Vector2i.ZERO
	var dx := int(signi(t["pos"].x - u["pos"].x)) if t["pos"].x != u["pos"].x else 0
	var dy := int(signi(t["pos"].y - u["pos"].y)) if t["pos"].y != u["pos"].y else 0
	if absi(t["pos"].x - u["pos"].x) >= absi(t["pos"].y - u["pos"].y):
		dir = Vector2i(dx, 0)
	else:
		dir = Vector2i(0, dy)
	if dir == Vector2i.ZERO:
		dir = Vector2i(1, 0)
	for i in n:
		var nxt: Vector2i = t["pos"] + dir
		if not in_bounds(nxt) or blocked.has(nxt) or unit_at(nxt) != null:
			break
		t["pos"] = nxt


# 回合结束推进状态层数
func _tick_statuses(u) -> void:
	for arr_key in ["buffs", "debuffs"]:
		var arr: Array = u[arr_key]
		for i in range(arr.size() - 1, -1, -1):
			var b: Dictionary = arr[i]
			b["turns"] = int(b["turns"]) - 1
			if int(b["turns"]) <= 0:
				arr.remove_at(i)


# 状态对伤害的修正（攻击方 / 防御方）
func status_damage_mult(attacker, defender) -> float:
	var m := 1.0
	if attacker != null:
		if _has_debuff(attacker, "低迷") or _has_debuff(attacker, "虚弱"):
			m *= 0.8
		if _has_buff(attacker, "昂扬"):
			m *= 1.10
		if _has_buff(attacker, "神威"):
			m *= 1.15
	if defender != null:
		if _has_debuff(defender, "识破") or _has_debuff(defender, "破绽"):
			m *= 1.10
		if _has_debuff(defender, "定身"):
			m *= 1.0
		if _has_buff(defender, "坚壁"):
			m *= 0.85
		if _has_buff(defender, "严阵"):
			m *= 0.90
	return m


func _apply_incoming(u, dmg: int) -> int:
	var cut := float(u["ext"].get("damage_cut", 0.0))
	return int(maxf(1.0, round(float(dmg) * (1.0 - clampf(cut, 0.0, 0.9)))))


func _kill(u, src) -> void:
	var was_alive: bool = u["alive"]
	u["alive"] = false
	u["hp"] = 0
	if was_alive:
		_set_anim(u, "die", String(u["face"]))
		u["anim_hold"] = 999.0
	_emit("%s 被击败%s" % [u["name"], ("（%s）" % src["name"]) if src != null else ""], "kill")
	_check_end()


# 每帧推进：一次性动作播放完后回到待机
func tick_anim(delta: float) -> void:
	for u in units:
		var hold := float(u.get("anim_hold", 0.0))
		if hold > 0.0:
			hold -= delta
			u["anim_hold"] = hold
			if hold <= 0.0 and u["alive"] and String(u["anim"]) != "idle":
				_set_anim(u, "idle")


func _check_end() -> void:
	var p := alive(0).size()
	var e := alive(1).size()
	if e == 0:
		ended = true
		result = "victory"
		_emit("★ 战斗胜利：敌军全灭", "win")
	elif p == 0:
		ended = true
		result = "defeat"
		_emit("✖ 战斗失败：我军全灭", "lose")


# ------------------------------------------------------------
# 回合
# ------------------------------------------------------------
func end_unit_turn(u) -> void:
	if u != null:
		u["done"] = true
	changed.emit()


func start_side(side: int) -> void:
	ended = false
	result = ""
	turn_side = side
	# 第 1 回合开始：应用天赋效果（按天赋等级过滤）
	if round_no == 1 and side == 0 and not _talent_applied:
		_talent_applied = true
		_apply_talent_effects()
	for u in units:
		if int(u["side"]) == side and u["alive"]:
			u["done"] = false
			for sid in (u["cd"] as Dictionary).keys():
				u["cd"][sid] = maxi(0, int(u["cd"][sid]) - 1)
			_tick_statuses(u)
	_emit("—— %s 行动 ——" % ("我方" if side == 0 else "敌军"), "round")
	changed.emit()


# 天赋效果：战斗开始时按「天赋等级」过滤后对自身生效（与技能效果块同一套规则）
func _apply_talent_effects() -> void:
	var talents: Dictionary = _data_ref.get("talents", {})
	for u in units:
		if not u["alive"]:
			continue
		var tid := String(u.get("talent", ""))
		if tid == "":
			continue
		var td: Dictionary = talents.get(tid, {})
		if td.is_empty():
			continue
		var fx_raw = td.get("ed_fx_list", [])
		if not (fx_raw is Array) or (fx_raw as Array).is_empty():
			continue
		var lv := int(u.get("talent_lv", 1))
		var fx_list: Array = RULEZ.effects_for_level(fx_raw, lv)
		for fx in fx_list:
			var t := String((fx as Dictionary).get("type", ""))
			match t:
				RULEZ.SFX_BUFF:
					var bn := String(fx.get("value", ""))
					if bn != "":
						_add_buff(u, bn, int(fx.get("turns", 99)), int(fx.get("stacks", 1)))
				RULEZ.SFX_SHIELD:
					_add_buff(u, "护盾", int(fx.get("turns", 2)), int(fx.get("value", 50)))
				RULEZ.SFX_SELF_HEAL:
					var sh := int(round(float(u["max_hp"]) * float(fx.get("value", 0.1))))
					u["hp"] = mini(int(u["max_hp"]), int(u["hp"]) + sh)
				RULEZ.SFX_CRIT_UP:
					_add_buff(u, "强运", int(fx.get("turns", 99)), 1)
		if not fx_list.is_empty():
			_emit("%s 的天赋「%s」(Lv%d) 生效：%d 个效果" % [u["name"],
				String(td.get("name", tid)), lv, fx_list.size()], "info")


func next_side() -> void:
	if ended:
		return
	if turn_side == 0:
		start_side(1)
	else:
		round_no += 1
		start_side(0)


func side_all_done(side: int) -> bool:
	for u in units:
		if u["alive"] and int(u["side"]) == side and not bool(u["done"]):
			return false
	return true


func _emit(text: String, tone: String) -> void:
	log_line.emit(text, tone)


# ------------------------------------------------------------
# 敌方 AI（同步执行，便于测试）
# ------------------------------------------------------------
func run_ai() -> void:
	if ended:
		return
	var ai := alive(1).duplicate()
	for u in ai:
		if ended:
			break
		if not u["alive"]:
			continue
		_ai_act(u)
	if not ended:
		_emit("—— 敌军行动结束 ——", "round")


func _ai_act(u) -> void:
	var foes := alive(0)
	if foes.is_empty():
		return
	var best = null
	var best_score := -9999.0
	for f in foes:
		var sc := -float(RULEZ.mdist(u["pos"], f["pos"]))
		if sc > best_score:
			best_score = sc
			best = f
	if best == null:
		return
	# 1) 能普攻就直接打
	if attack_area(u).has(best["pos"] - u["pos"]):
		basic_attack(u, best)
		u["done"] = true
		return
	# 2) 尝试技能
	for sid in u["skills"]:
		var d := skill_def(String(sid))
		if d.is_empty() or String(d.get("kind", "")) == "passive":
			continue
		if int(u["cd"].get(String(sid), 0)) > 0:
			continue
		# 找技能范围内能命中敌人的落点
		var cells: Dictionary = move_cells(u)
		var moved := false
		if cells.size() > 1:
			var dest: Vector2i = u["pos"]
			var bd := 999
			for c in cells.keys():
				var cc: Vector2i = c
				if cc == u["pos"]:
					continue
				if unit_at(cc) != null:
					continue
				var dd := RULEZ.mdist(cc, best["pos"])
				if dd < bd:
					bd = dd
					dest = cc
			if bd < RULEZ.mdist(u["pos"], best["pos"]):
				u["pos"] = dest
				moved = true
		if moved:
			_emit("%s 移动接近" % u["name"], "info")
		if can_cast_at(u, String(sid), best["pos"]):
			cast_skill(u, String(sid), best["pos"])
			u["done"] = true
			return
	# 3) 靠近
	var cells2: Dictionary = move_cells(u)
	var dest2: Vector2i = u["pos"]
	var bd2 := RULEZ.mdist(u["pos"], best["pos"])
	for c in cells2.keys():
		var cc2: Vector2i = c
		if unit_at(cc2) != null:
			continue
		var dd2 := RULEZ.mdist(cc2, best["pos"])
		if dd2 < bd2:
			bd2 = dd2
			dest2 = cc2
	if dest2 != u["pos"]:
		u["pos"] = dest2
		_emit("%s 向 %s 靠近" % [u["name"], best["name"]], "info")
	u["done"] = true
	if attack_area(u).has(best["pos"] - u["pos"]):
		basic_attack(u, best)
