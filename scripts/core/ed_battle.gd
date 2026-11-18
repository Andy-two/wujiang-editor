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
		"zhanyi": 0,             # 战意（0~战意上限）
		"zhanyi_max": 100,       # 战意上限
		"counter_mul": 0.0,      # 反击伤害加成（+0.2 = +20%）
		"counter_cut": 0.0,      # 受反击伤害减免
		"counter_per_round": 1,  # 每回合可反击次数
		"counter_used": 0,       # 本回合已反击次数
		"form_state": {},        # 技能形态状态 {原技能id: 当前形态id}
		"res": {},               # 资源层数 {"智": 0, "深谋": 0, ...}
		"zoc": 0,                # 阻挡领域格数（0=无）
		"ignore_zoc": false,      # 移动时无视阻挡领域（如「龙行」）
		"priority": 0,           # 先攻层数（>0 时本回合行动优先）
		"block": 0.0,            # 格挡减伤比例（0.2 = 减伤20%）
		"block_turns": 0,        # 格挡剩余回合
		"dodge": 0.0,            # 闪避概率（0.2 = 20% 回避）
		"dodge_turns": 0,        # 闪避剩余回合
		"immunity": {},          # 免疫 {"控制": 2, "属性减益": 2, ...}（值为剩余回合）
		"resist": {},            # 抵抗 {"眩晕": 2, ...}（每回合首次抵抗该类减益）
		"resist_once": {},       # 本回合已抵抗的减益 {"眩晕": true, ...}（每回合首次抵抗）
		"combo_used": 0,         # 本回合已触发合击次数
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
	var cells := RULEZ.reachable(u["pos"], int(u["move"]), occ)
	# 阻挡领域（ZOC）：进入敌方 ZOC 的格子会消耗全部剩余移动力（该格可进，但不能再往外走）
	# 「无视阻挡领域」（如救危主 Lv2「龙行」）则不受此限制
	if not cells.is_empty() and not bool(u.get("ignore_zoc", false)):
		var side := int(u["side"])
		var z_blocks := {}
		for cell in cells.keys():
			if is_in_enemy_zoc(cell, side):
				z_blocks[cell] = true
		if not z_blocks.is_empty():
			# 重新计算：ZOC 格子可达但代价视为最大
			var max_cost := int(u["move"])
			for zc in z_blocks.keys():
				cells[zc] = maxi(int(cells.get(zc, max_cost)), max_cost)
	return cells


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
	if is_in_enemy_zoc(dest, int(u["side"])):
		_emit("  → 进入敌方「阻挡领域」，移动力耗尽", "info")
	passive_on("on_move", u, {"tiles": int(u["moved_tiles"])})
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
	# P3 闪避：目标可能完全回避这次攻击
	if try_dodge(target, attacker):
		return {"ok": true, "dmg": 0, "crit": false, "dodged": true}
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
	# 被动触发：暴击 / 造成伤害 / 受击
	if bool(res["crit"]):
		passive_on("on_crit", attacker, {"target": target})
	passive_on("on_hit", attacker, {"target": target})
	passive_on("on_hurt", target, {"source": attacker})
	if int(target["hp"]) <= 0:
		_kill(target, attacker)
		passive_on("on_kill", attacker, {"target": target})
	else:
		# P3 合击：攻击者带「合击」标记时，相邻友军对同一目标追加攻击
		if can_combo(attacker) and target["alive"]:
			trigger_combo(attacker, target)
		# 反击：目标若在自己的普攻范围内且是近战则反击（简化规则：普攻范围覆盖攻击者即反击）
		# 若攻击方带「无法被反击」标记（技能 Lv3 等），则跳过反击
		var no_counter := bool(attacker.get("no_counter", false))
		# 每回合反击次数限制
		var can_counter := int(target.get("counter_used", 0)) < int(target.get("counter_per_round", 1))
		if not no_counter and can_counter and attack_area(target).has(attacker["pos"] - target["pos"]) and attacker["alive"]:
			_face_towards(target, attacker["pos"])
			target["counter_used"] = int(target.get("counter_used", 0)) + 1
			# 反击增强：倍率加成
			var c_mul := RULEZ.get_f("mult_counter") * (1.0 + float(target.get("counter_mul", 0.0)))
			var back := RULEZ.roll_damage(target, attacker, c_mul,
				RULEZ.arm_multiplier(String(target["arm"]), String(attacker["arm"])), {})
			# 被反击方可能带减伤
			var raw_bd := _apply_outgoing(target, int(back["dmg"]))
			raw_bd = int(round(float(raw_bd) * (1.0 - float(attacker.get("counter_cut", 0.0)))))
			var bd := _apply_incoming(attacker, raw_bd)
			bd = mini(bd, int(attacker["hp"]))
			attacker["hp"] = int(attacker["hp"]) - bd
			_set_anim(target, "attack", String(target["face"]))
			target["anim_hold"] = 0.6
			_set_anim(attacker, "hurt")
			attacker["anim_hold"] = 0.35
			_emit("%s 反击 %s：%d 伤害" % [target["name"], attacker["name"], bd], "hit")
			# 反击时触发被动
			passive_on("on_counter", target, {"target": attacker})
			passive_on("on_be_countered", attacker, {"source": target})
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
		# 组合技升阶 = 子技能同步升级：组本体的等级作为子技能等级下限
		var host_lv := int(u["skill_lv"].get(sid, 1))
		if host_lv > int(u["skill_lv"].get(choice, 1)):
			u["skill_lv"][choice] = host_lv
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
						# P3 闪避：目标可能完全回避这次技能伤害
						if try_dodge(tgt, u):
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
						# 被动触发（技能伤害同样触发）
						if bool(res["crit"]):
							passive_on("on_crit", u, {"target": tgt})
						passive_on("on_hurt", tgt, {"source": u})
						if int(tgt["hp"]) <= 0:
							_kill(tgt, u)
							passive_on("on_kill", u, {"target": tgt})
						# P3 合击：技能带「合击」标记时，相邻友军对同一目标追加攻击
						elif can_combo(u) and tgt["alive"]:
							trigger_combo(u, tgt)
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
				var dpn := int(fx.get("value", 1))
				for tgt6 in foes:
					if tgt6["alive"]:
						_dispel_buff(tgt6, dpn)
						_emit("  → 驱散 %s 的 %d 个增益" % [tgt6["name"], dpn], "info")
			RULEZ.SFX_SELF_DISPEL:
				var sdn := int(fx.get("value", 1))
				_dispel_debuff(u, sdn)
				_emit("  → %s 净化了自身 %d 个减益" % [u["name"], sdn], "info")
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
				_emit("  → %s 获得再移动" % [u["name"]], "info")
			RULEZ.SFX_NO_COUNTER:
				u["no_counter"] = true
				_emit("  → 本次攻击无法被反击", "info")
			RULEZ.SFX_PURSUIT:
				# 追击：对作用范围内的敌军追加一次伤害（不触发反击）
				var p_tgts: Array = foes if not foes.is_empty() else []
				if p_tgts.is_empty() and target != Vector2i(-1, -1):
					var pt = unit_at(target)
					if pt != null:
						p_tgts = [pt]
				for tgt_p in p_tgts:
					if tgt_p["alive"]:
						do_pursuit(u, tgt_p, fx)
			RULEZ.SFX_COUNTER_UP:
				# 反击增强：倍率/减伤/次数
				counter_boost(u, float(fx.get("mul", 0.0)), float(fx.get("cut", 0.0)),
					int(fx.get("per_round", 0)))
			RULEZ.SFX_SWITCH:
				# 技能形态切换
				switch_form(u, sid, str(fx.get("to", "")))
			RULEZ.SFX_RESOURCE:
				# 资源层数
				var rname := str(fx.get("name", ""))
				var rval := int(fx.get("value", 1))
				var rmax := int(fx.get("max", 99))
				if rname != "":
					add_resource(u, rname, rval, rmax)
			RULEZ.SFX_CONSUME:
				var cname := str(fx.get("name", ""))
				if cname != "":
					consume_resource(u, cname)
			RULEZ.SFX_ZOC:
				u["zoc"] = maxi(int(u.get("zoc", 0)), int(fx.get("value", 1)))
				_emit("  → %s 获得 %d 格「阻挡领域」" % [u["name"], int(u["zoc"])], "info")
			RULEZ.SFX_PRIORITY:
				# 先攻：获得先攻层数（本回合行动优先）
				grant_priority(u, int(fx.get("value", 1)))
			RULEZ.SFX_BLOCK:
				# 格挡：降低受到的伤害
				grant_block(u, float(fx.get("value", 0.2)), int(fx.get("turns", 2)))
			RULEZ.SFX_DODGE:
				# 闪避：按概率回避一次攻击
				grant_dodge(u, float(fx.get("value", 0.2)), int(fx.get("turns", 2)))
			RULEZ.SFX_IMMUNITY:
				# 免疫：控制 / 属性减益 / 移动减益 / 地形减益
				var ikind := str(fx.get("value", "控制"))
				for tgt_i in (allies if not allies.is_empty() else [u]):
					grant_immunity(tgt_i, ikind, int(fx.get("turns", 2)))
			RULEZ.SFX_RESIST:
				# 抵抗：每回合首次抵抗某类减益
				var rkind := str(fx.get("value", "眩晕"))
				for tgt_r in (allies if not allies.is_empty() else [u]):
					grant_resist(tgt_r, rkind, int(fx.get("turns", 2)))
			RULEZ.SFX_COMBO:
				# 合击：本次攻击可触发相邻友军联合攻击
				u["can_combo"] = true
				_emit("  → %s 的本次攻击可触发合击" % u["name"], "info")
			RULEZ.SFX_ZHANYI:
				# 战意：正数回复自身；负数降低敌军（作用范围内的敌军，无命中时取目标点单位）
				var zv := int(fx.get("value", 10))
				if zv >= 0:
					add_zhanyi(u, zv)
				else:
					var z_tgts: Array = foes if not foes.is_empty() else []
					if z_tgts.is_empty() and target != Vector2i(-1, -1):
						var zt = unit_at(target)
						if zt != null:
							z_tgts = [zt]
					if z_tgts.is_empty():
						# 仍未命中则取全场最近的敌军
						var near = null
						var nd := 99
						for t2 in units:
							if not t2["alive"] or int(t2["side"]) == int(u["side"]):
								continue
							var dd := absi(t2["pos"].x - target.x) + absi(t2["pos"].y - target.y)
							if dd < nd:
								nd = dd
								near = t2
						if near != null:
							z_tgts = [near]
					for tgt_z in z_tgts:
						if tgt_z["alive"]:
							add_zhanyi(tgt_z, zv)
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
	# 「无法被反击」只对本次攻击有效，用完即清
	u["no_counter"] = false
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


# ------------------------------------------------------------
# 战意系统
# ------------------------------------------------------------
func add_zhanyi(u, delta: int) -> void:
	if u == null or not u["alive"]:
		return
	var old := int(u.get("zhanyi", 0))
	var mx := int(u.get("zhanyi_max", 100))
	u["zhanyi"] = clampi(old + int(delta), 0, mx)
	var now := int(u["zhanyi"])
	if now == old:
		return
	if delta > 0:
		_emit("  → %s 战意 +%d（%d/%d）" % [u["name"], now - old, now, mx], "info")
	else:
		_emit("  → %s 战意 %d（%d/%d）" % [u["name"], now - old, now, mx], "info")
	# 获得战意时的被动触发（如「临阵决机」每获得10点战意得1层备战）
	if delta > 0:
		passive_on("on_zhanyi", u, {"delta": delta})


# 对范围内战意最高的敌军吸战意
func steal_zhanyi_from(u, amount: int) -> void:
	if u == null or not u["alive"]:
		return
	var best = null
	var best_z := -1
	for t in units:
		if not t["alive"] or int(t["side"]) == int(u["side"]):
			continue
		if int(t.get("zhanyi", 0)) > best_z:
			best_z = int(t["zhanyi"])
			best = t
	if best == null:
		return
	add_zhanyi(best, -amount)
	add_zhanyi(u, amount)


# ------------------------------------------------------------
# 追击：附加一次伤害，不触发反击/合击，可叠加多段
# ------------------------------------------------------------
func do_pursuit(u, tgt, fx: Dictionary) -> int:
	if u == null or tgt == null or not u["alive"] or not tgt["alive"]:
		return 0
	var magic := bool(fx.get("magic", false))
	var am := RULEZ.arm_multiplier(String(u["arm"]), String(tgt["arm"]))
	var res := RULEZ.roll_damage(u, tgt, float(fx.get("value", 0.5)), am, {
		"magic": magic, "ignore_def": float(fx.get("ignore_def", 0.0)),
		"no_counter": true,
	})
	var dmg := _apply_incoming(tgt, _apply_outgoing(u, int(res["dmg"])))
	dmg = mini(dmg, int(tgt["hp"]))
	tgt["hp"] = int(tgt["hp"]) - dmg
	_emit("  → 追击 %s：%d 伤害%s" % [tgt["name"], dmg, "（暴击）" if res["crit"] else ""], "hit")
	if int(tgt["hp"]) <= 0:
		_kill(tgt, u)
		passive_on("on_kill", u, {"target": tgt})
	return dmg


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
	# 免疫拦截：控制 / 属性减益 / 移动减益 / 地形减益
	if debuff_blocked_by_immunity(name, t):
		_emit("  → %s 免疫了「%s」" % [t["name"], name], "info")
		return
	# 抵抗拦截：每回合首次抵抗某类减益（如「抵抗每回合首次受到的眩晕」）
	if try_resist(t, name):
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


# 目标是否拥有指定状态（增益或减益均可）
func _has_status(t, name: String) -> bool:
	if t == null or name == "":
		return false
	for b in t["buffs"]:
		if String(b["name"]) == name:
			return true
	for d in t["debuffs"]:
		if String(d["name"]) == name:
			return true
	return false


func _dispel_buff(t, n: int = 1) -> void:
	if t == null:
		return
	var arr: Array = t["buffs"]
	for _i in maxi(1, n):
		if arr.is_empty():
			break
		arr.remove_at(0)


func _dispel_debuff(t, n: int = 1) -> void:
	if t == null:
		return
	var arr: Array = t["debuffs"]
	var removed := 0
	for i in range(arr.size() - 1, -1, -1):
		if removed >= maxi(1, n):
			break
		var d: Dictionary = arr[i]
		if bool(d.get("dispellable", true)):
			arr.remove_at(i)
			removed += 1


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
	var d := int(maxf(1.0, round(float(dmg) * (1.0 - clampf(cut, 0.0, 0.9)))))
	# P3 格挡：按比例降低受到的伤害
	if u != null and int(u.get("block_turns", 0)) > 0:
		var blk := clampf(float(u.get("block", 0.0)), 0.0, 0.9)
		if blk > 0.0:
			d = maxi(1, int(round(float(d) * (1.0 - blk))))
	return d


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
	# 第 1 回合开始：应用天赋效果（按天赋等级过滤）+ 被动技能开局效果
	if round_no == 1 and side == 0 and not _talent_applied:
		_talent_applied = true
		_apply_talent_effects()
		_apply_passive_startup()
	for u in units:
		if int(u["side"]) == side and u["alive"]:
			u["done"] = false
			u["counter_used"] = 0
			u["combo_used"] = 0
			u["can_combo"] = false
			u["resist_once"] = {}
			for sid in (u["cd"] as Dictionary).keys():
				u["cd"][sid] = maxi(0, int(u["cd"][sid]) - 1)
			_tick_statuses(u)
			_tick_p3_state(u)
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

# ============================================================
# 被动技能系统
#   被动技能的 ed_fx_list 会被收集为「常驻被动」，按类型分三种处理：
#   ① 开局型（buff/shield）：战斗开始时对自身生效
#   ② 属性型（passive_stat）：直接加成到面板（在 unit_template 里算）
#   ③ 触发型：由引擎在各个时机调用 passive_on(event, u, ctx)
# ============================================================
var _passive_cache: Dictionary = {}


# 收集某单位的全部被动效果（按技能等级过滤）
func unit_passives(u) -> Array:
	var key := "%s|%d" % [String(u.get("key", "")), int(u.get("id", 0))]
	if _passive_cache.has(key):
		return _passive_cache[key]
	var out: Array = []
	for sid in (u.get("skills", []) as Array):
		var d := skill_def(String(sid))
		if d.is_empty() or String(d.get("kind", "")) != "passive":
			continue
		var lv := int(u["skill_lv"].get(String(sid), 1))
		for fx in RULEZ.effects_for_level(RULEZ.skill_effects(d), lv):
			var fd: Dictionary = fx
			var cp := fd.duplicate(true)
			cp["_from"] = String(d.get("name", sid))
			out.append(cp)
	_passive_cache[key] = out
	return out


# 战斗开始时应用「开局型」被动
func _apply_passive_startup() -> void:
	for u in units:
		if not u["alive"]:
			continue
		var ps := unit_passives(u)
		var n := 0
		for fx in ps:
			var fd: Dictionary = fx
			var t := str(fd.get("type", ""))
			match t:
				RULEZ.SFX_BUFF:
					var bn := str(fd.get("value", ""))
					if bn != "":
						_add_buff(u, bn, int(fd.get("turns", 99)), int(fd.get("stacks", 1)))
						n += 1
					var sf0 := str(fd.get("set_flag", ""))
					if sf0 != "":
						u[sf0] = true
				RULEZ.SFX_SHIELD:
					_add_buff(u, "护盾", int(fd.get("turns", 99)), int(fd.get("value", 50)))
					n += 1
				RULEZ.SFX_CRIT_UP:
					_add_buff(u, "强运", int(fd.get("turns", 99)), 1)
					n += 1
				RULEZ.SFX_SELF_HEAL:
					var sh := int(round(float(u["max_hp"]) * float(fd.get("value", 0.1))))
					u["hp"] = mini(int(u["max_hp"]), int(u["hp"]) + sh)
					n += 1
				RULEZ.SFX_PRIORITY:
					grant_priority(u, int(fd.get("value", 1)))
					n += 1
				RULEZ.SFX_BLOCK:
					grant_block(u, float(fd.get("value", 0.2)), int(fd.get("turns", 2)))
					n += 1
				RULEZ.SFX_DODGE:
					grant_dodge(u, float(fd.get("value", 0.2)), int(fd.get("turns", 2)))
					n += 1
				RULEZ.SFX_IMMUNITY:
					grant_immunity(u, str(fd.get("value", "控制")), int(fd.get("turns", 2)))
					n += 1
				RULEZ.SFX_RESIST:
					grant_resist(u, str(fd.get("value", "眩晕")), int(fd.get("turns", 2)))
					n += 1
		if n > 0:
			_emit("%s 的被动生效：%d 项（开局型）" % [u["name"], n], "info")


# 触发型被动：在指定时机检查并执行
#   event: "on_crit"(暴击后) / "on_hit"(造成伤害后) / "on_hurt"(受伤后)
#          / "on_kill"(击杀后) / "on_turn_end"(行动结束) / "on_move"(移动后)
func passive_on(event: String, u, ctx: Dictionary = {}) -> void:
	if u == null or not u["alive"]:
		return
	for fx in unit_passives(u):
		var fd: Dictionary = fx
		var trig := str(fd.get("trigger", ""))
		if trig != event:
			continue
		var t := str(fd.get("type", ""))
		var src := str(fd.get("_from", ""))
		match t:
			RULEZ.SFX_SELF_HEAL:
				var sh := int(round(float(u["max_hp"]) * float(fd.get("value", 0.1))))
				u["hp"] = mini(int(u["max_hp"]), int(u["hp"]) + sh)
				_emit("  「%s」触发：%s 回复 %d 兵力" % [src, u["name"], sh], "heal")
			RULEZ.SFX_BUFF:
				var bn := str(fd.get("value", ""))
				if bn != "":
					_add_buff(u, bn, int(fd.get("turns", 2)), int(fd.get("stacks", 1)))
					_emit("  「%s」触发：%s 获得「%s」" % [src, u["name"], bn], "info")
				# 附带标记（如「龙行」附带 ignore_zoc = 移动时无视阻挡领域）
				var sf := str(fd.get("set_flag", ""))
				if sf != "":
					u[sf] = true
			RULEZ.SFX_CD_DOWN:
				for k in (u["cd"] as Dictionary).keys():
					u["cd"][k] = maxi(0, int(u["cd"][k]) - int(fd.get("value", 1)))
				_emit("  「%s」触发：准备期 -%d" % [src, int(fd.get("value", 1))], "info")
			RULEZ.SFX_SHIELD:
				_add_buff(u, "护盾", int(fd.get("turns", 2)), int(fd.get("value", 50)))
				_emit("  「%s」触发：获得护盾" % src, "info")
			RULEZ.SFX_PRIORITY:
				grant_priority(u, int(fd.get("value", 1)))
			RULEZ.SFX_BLOCK:
				grant_block(u, float(fd.get("value", 0.2)), int(fd.get("turns", 2)))
			RULEZ.SFX_DODGE:
				grant_dodge(u, float(fd.get("value", 0.2)), int(fd.get("turns", 2)))
			RULEZ.SFX_IMMUNITY:
				grant_immunity(u, str(fd.get("value", "控制")), int(fd.get("turns", 2)))
			RULEZ.SFX_RESIST:
				grant_resist(u, str(fd.get("value", "眩晕")), int(fd.get("turns", 2)))
			RULEZ.SFX_COMBO:
				u["can_combo"] = true
			_:
				# 对目标施加的被动（如 on_hit 施加减益）
				var tgt = ctx.get("target", null)
				# 条件触发：要求目标拥有指定状态（如「对拥有『撕裂』的敌军造成伤害时…」）
				var req := str(fd.get("require_status", ""))
				if req != "" and tgt != null and not _has_status(tgt, req):
					continue
				if tgt != null and tgt["alive"]:
					if t == RULEZ.SFX_DEBUFF:
						var dn := str(fd.get("value", ""))
						if dn != "":
							_add_debuff(tgt, dn, int(fd.get("turns", 2)), u)
							_emit("  「%s」触发：%s 被施加「%s」" % [src, tgt["name"], dn], "info")
					elif t == RULEZ.SFX_FIXED:
						var fdmg := int(round(float(fd.get("value", 20))))
						fdmg = mini(fdmg, int(tgt["hp"]))
						tgt["hp"] = int(tgt["hp"]) - fdmg
						_emit("  「%s」触发：%s 受到 %d 固定伤害" % [src, tgt["name"], fdmg], "hit")
						if int(tgt["hp"]) <= 0:
							_kill(tgt, u)
					elif t == RULEZ.SFX_PURSUIT:
						# 被动追击（如红缨绕影：闪避后对敌军造成追击）
						do_pursuit(u, tgt, fd)
					elif t == RULEZ.SFX_DAMAGE:
						# 被动伤害（如骁姿绝尘：对移动力更小的敌军造成伤害时无视防御）
						var am2 := RULEZ.arm_multiplier(String(u["arm"]), String(tgt["arm"]))
						var mult2 := float(fd.get("value", 1.0)) * status_damage_mult(u, tgt)
						var r2 := RULEZ.roll_damage(u, tgt, mult2, am2,
							{"magic": bool(fd.get("magic", false)),
							 "ignore_def": float(fd.get("ignore_def", 0.0))})
						var d2 := _apply_incoming(tgt, _apply_outgoing(u, int(r2["dmg"])))
						d2 = mini(d2, int(tgt["hp"]))
						tgt["hp"] = int(tgt["hp"]) - d2
						_emit("  「%s」触发：%s 受到 %d 伤害" % [src, tgt["name"], d2], "hit")
						if int(tgt["hp"]) <= 0:
							_kill(tgt, u)


# 反击增强（便捷入口，效果块与被动都会走这里）
func counter_boost(u, mul: float = 0.0, cut: float = 0.0, per_round: int = 0) -> void:
	if u == null or not u["alive"]:
		return
	if mul != 0.0:
		u["counter_mul"] = float(u.get("counter_mul", 0.0)) + mul
	if cut != 0.0:
		u["counter_cut"] = clampf(float(u.get("counter_cut", 0.0)) + cut, 0.0, 1.0)
	if per_round > 0:
		u["counter_per_round"] = per_round
	_emit("  → %s 反击增强（倍率%+.0f%%，受反击减伤%.0f%%，每回合%d次）" % [
		u["name"], float(u.get("counter_mul", 0.0)) * 100.0,
		float(u.get("counter_cut", 0.0)) * 100.0, int(u.get("counter_per_round", 1))], "info")


# ------------------------------------------------------------
# 资源层数系统（智 / 深谋 / 斗气 / 机巧 / 备战 / 武魂 …）
#   单位 res: {"智": 2, "深谋": 7, ...}
# ------------------------------------------------------------
func add_resource(u, name: String, delta: int, max_n: int = 99) -> void:
	if u == null or not u["alive"] or name == "":
		return
	var r: Dictionary = u.get("res", {}) if u.get("res") is Dictionary else {}
	var old := int(r.get(name, 0))
	var nv := clampi(old + int(delta), 0, maxi(1, max_n))
	r[name] = nv
	u["res"] = r
	if nv != old:
		_emit("  → %s「%s」%+d（现 %d 层）" % [u["name"], name, nv - old, nv], "info")
	if delta > 0 and nv != old:
		passive_on("on_resource", u, {"res": name, "value": nv})


func get_resource(u, name: String) -> int:
	if u == null:
		return 0
	var r: Dictionary = u.get("res", {}) if u.get("res") is Dictionary else {}
	return int(r.get(name, 0))


func consume_resource(u, name: String) -> int:
	var n := get_resource(u, name)
	if n <= 0:
		return 0
	var r: Dictionary = u.get("res", {})
	r[name] = 0
	u["res"] = r
	_emit("  → %s 消耗所有「%s」（%d 层）" % [u["name"], name, n], "info")
	return n


# ------------------------------------------------------------
# 阻挡领域（ZOC）
#   zoc = N 表示周围 N 格内敌军移动进入时会被拦截（消耗全部移动力）
# ------------------------------------------------------------
func zoc_cells_of(u) -> Array:
	var n := int(u.get("zoc", 0))
	if n <= 0 or not u["alive"]:
		return []
	var out: Array = []
	var p: Vector2i = u["pos"]
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) <= n:
				out.append(p + Vector2i(dx, dy))
	return out


# 某格是否处于任一敌军的阻挡领域内
func is_in_enemy_zoc(pos: Vector2i, mover_side: int) -> bool:
	for u in units:
		if not u["alive"] or int(u["side"]) == mover_side:
			continue
		if int(u.get("zoc", 0)) <= 0:
			continue
		var d: Vector2i = pos - u["pos"]
		if absi(d.x) + absi(d.y) <= int(u["zoc"]):
			if d != Vector2i.ZERO:
				return true
	return false


# ------------------------------------------------------------
# P3 机制：先攻 / 格挡 / 闪避 / 免疫 / 合击
# ------------------------------------------------------------

# 每回合推进 P3 的持续性状态（格挡 / 闪避 / 免疫 / 先攻层数）
func _tick_p3_state(u) -> void:
	if u == null:
		return
	# 格挡
	if int(u.get("block_turns", 0)) > 0:
		u["block_turns"] = int(u["block_turns"]) - 1
		if int(u["block_turns"]) <= 0:
			u["block"] = 0.0
	# 闪避
	if int(u.get("dodge_turns", 0)) > 0:
		u["dodge_turns"] = int(u["dodge_turns"]) - 1
		if int(u["dodge_turns"]) <= 0:
			u["dodge"] = 0.0
	# 免疫
	var im: Dictionary = u.get("immunity", {}) if u.get("immunity") is Dictionary else {}
	for k in im.keys():
		im[k] = int(im[k]) - 1
		if int(im[k]) <= 0:
			im.erase(k)
	u["immunity"] = im
	# 抵抗
	var rs: Dictionary = u.get("resist", {}) if u.get("resist") is Dictionary else {}
	for k2 in rs.keys():
		rs[k2] = int(rs[k2]) - 1
		if int(rs[k2]) <= 0:
			rs.erase(k2)
	u["resist"] = rs
	# 先攻层数：每回合递减（先攻只在本回合有效）
	if int(u.get("priority", 0)) > 0:
		u["priority"] = int(u["priority"]) - 1


# ---- 先攻：拥有先攻的单位在自己回合内优先行动 ----
func grant_priority(u, n: int = 1) -> void:
	if u == null or not u["alive"]:
		return
	u["priority"] = int(u.get("priority", 0)) + int(n)
	_emit("  → %s 获得「先攻」%d 层" % [u["name"], int(n)], "info")


# 取当前回合该阵营里拥有先攻、且尚未行动的单位（按先攻层数降序）
func priority_units(side: int) -> Array:
	var out: Array = []
	for u in units:
		if not u["alive"] or int(u["side"]) != side or bool(u["done"]):
			continue
		if int(u.get("priority", 0)) > 0:
			out.append(u)
	out.sort_custom(func(a, b) -> bool:
		return int(a.get("priority", 0)) > int(b.get("priority", 0)))
	return out


# ---- 格挡：按比例降低受到的伤害 ----
func grant_block(u, ratio: float, turns: int) -> void:
	if u == null or not u["alive"]:
		return
	u["block"] = clampf(float(ratio), 0.0, 0.9)
	u["block_turns"] = maxi(int(turns), 1)
	_emit("  → %s 获得「格挡」：减伤 %.0f%%（%d 回合）" % [u["name"], float(ratio) * 100.0,
		int(turns)], "info")


# ---- 闪避：按概率完全回避一次攻击 ----
func grant_dodge(u, ratio: float, turns: int) -> void:
	if u == null or not u["alive"]:
		return
	u["dodge"] = clampf(float(ratio), 0.0, 1.0)
	u["dodge_turns"] = maxi(int(turns), 1)
	_emit("  → %s 获得「闪避」：%.0f%% 回避（%d 回合）" % [u["name"], float(ratio) * 100.0,
		int(turns)], "info")


# 判定一次攻击是否被闪避（命中则消耗一次闪避层）
# 传入 attacker 可触发被闪避方的「on_dodge」被动（如红缨绕影：闪避后追击）
func try_dodge(defender, attacker = null) -> bool:
	if defender == null or not defender["alive"]:
		return false
	if int(defender.get("dodge_turns", 0)) <= 0:
		return false
	var chance := float(defender.get("dodge", 0.0))
	if chance <= 0.0:
		return false
	if randf() < chance:
		_emit("  → %s 闪避了这次攻击" % defender["name"], "info")
		defender["dodge_turns"] = int(defender["dodge_turns"]) - 1
		# 被动触发：闪避后（如「闪避」后对敌军造成追击）
		passive_on("on_dodge", defender, {"source": attacker, "target": attacker})
		return true
	return false


# ---- 抵抗：每回合首次抵抗某类减益（如「抵抗每回合首次受到的眩晕」）----
# 单位 resist 字段：{"眩晕": 2, "缴械": 2, ...}（值为剩余回合）+ resist_once 记录本回合已抵抗过
func grant_resist(u, kind: String, turns: int) -> void:
	if u == null or not u["alive"] or kind == "":
		return
	var r: Dictionary = u.get("resist", {}) if u.get("resist") is Dictionary else {}
	r[kind] = maxi(int(r.get(kind, 0)), int(turns))
	u["resist"] = r
	_emit("  → %s 获得「抵抗%s」（%d 回合，每回合首次）" % [u["name"], kind, int(turns)], "info")


# 尝试抵抗一次减益（成功则拦截）
func try_resist(t, debuff_name: String) -> bool:
	if t == null:
		return false
	var r: Dictionary = t.get("resist", {}) if t.get("resist") is Dictionary else {}
	if r.is_empty():
		return false
	var n := String(debuff_name)
	for kind in r.keys():
		if int(r[kind]) <= 0:
			continue
		# 状态名以该类开头（如「眩晕」「眩晕·贰」），或包含
		if not (n == String(kind) or n.begins_with(String(kind)) or n.contains(String(kind))):
			continue
		# 每回合只能抵抗一次同一类
		var once: Dictionary = t.get("resist_once", {}) if t.get("resist_once") is Dictionary else {}
		if bool(once.get(String(kind), false)):
			continue
		once[String(kind)] = true
		t["resist_once"] = once
		_emit("  → %s 抵抗了「%s」" % [t["name"], n], "info")
		return true
	return false


# ---- 免疫：免疫控制 / 属性减益 / 移动减益 / 地形减益 ----
func grant_immunity(u, kind: String, turns: int) -> void:
	if u == null or not u["alive"] or kind == "":
		return
	var im: Dictionary = u.get("immunity", {}) if u.get("immunity") is Dictionary else {}
	im[kind] = maxi(int(im.get(kind, 0)), int(turns))
	u["immunity"] = im
	_emit("  → %s 获得「免疫%s」（%d 回合）" % [u["name"], kind, int(turns)], "info")


# 某单位是否对某类减益免疫
func is_immune(u, kind: String) -> bool:
	if u == null:
		return false
	var im: Dictionary = u.get("immunity", {}) if u.get("immunity") is Dictionary else {}
	return int(im.get(kind, 0)) > 0


# 减益是否被免疫拦截（控制类：眩晕/定身/封技/嘲讽/缴械；移动类：牵制；属性类：低迷/虚弱等）
func debuff_blocked_by_immunity(debuff_name: String, u) -> bool:
	if u == null:
		return false
	var n := String(debuff_name)
	if n.begins_with("免疫"):
		return false
	var control_kw := ["眩晕", "定身", "封技", "嘲讽", "缴械", "混乱", "失智", "胆怯"]
	var move_kw := ["牵制", "疾行", "禁移"]
	var terrain_kw := ["地形", "沼", "陷"]
	for k in control_kw:
		if n.contains(k) and is_immune(u, "控制"):
			return true
	for k in move_kw:
		if n.contains(k) and is_immune(u, "移动减益"):
			return true
	for k in terrain_kw:
		if n.contains(k) and is_immune(u, "地形减益"):
			return true
	if is_immune(u, "属性减益"):
		var attr_kw := ["低迷", "虚弱", "破绽", "识破", "锐心", "锐气", "虚弱", "减物防", "减谋防",
			"减物攻", "减谋攻", "撕裂", "溃逃", "减防", "减伤"]
		for k in attr_kw:
			if n.contains(k):
				return true
	return false


# ---- 合击：相邻友军对同一目标联合攻击 ----
# 参与条件：① 与攻击者相邻（并肩作战）② 自身能打到该目标（射程内或移动后可达）
# 返回可参与合击的友军列表
func combo_partners(attacker, target) -> Array:
	var out: Array = []
	if attacker == null or target == null:
		return out
	for u in units:
		if u == attacker or not u["alive"]:
			continue
		if int(u["side"]) != int(attacker["side"]):
			continue
		# 必须与攻击者相邻
		var d: Vector2i = u["pos"] - attacker["pos"]
		if absi(d.x) + absi(d.y) != 1:
			continue
		# 且能打到目标：已在普攻范围内，或移动力+射程内可达
		if not _combo_can_reach(u, target):
			continue
		out.append(u)
	return out


# 合击伙伴能否打到目标：普攻范围覆盖，或（移动力 + 射程）可达
func _combo_can_reach(u, target) -> bool:
	if u == null or target == null:
		return false
	var rel: Vector2i = target["pos"] - u["pos"]
	if attack_area(u).has(rel):
		return true
	var dist := absi(rel.x) + absi(rel.y)
	var reach := int(u.get("move", 4)) + int(u.get("atk_range", 1))
	return dist <= reach


# 触发合击：每个伙伴对目标追加一次合击伤害（mult_combo 倍率，不触发反击/合击连锁）
func trigger_combo(attacker, target) -> int:
	var hits := 0
	for p in combo_partners(attacker, target):
		if not p["alive"] or not target["alive"]:
			continue
		if int(p.get("combo_used", 0)) >= int(RULEZ.get_i("max_combo_per_round")):
			continue
		p["combo_used"] = int(p.get("combo_used", 0)) + 1
		var am := RULEZ.arm_multiplier(String(p["arm"]), String(target["arm"]))
		var res := RULEZ.roll_damage(p, target, RULEZ.get_f("mult_combo"),
			am, {})
		var dmg := _apply_incoming(target, _apply_outgoing(p, int(res["dmg"])))
		dmg = mini(dmg, int(target["hp"]))
		target["hp"] = int(target["hp"]) - dmg
		hits += 1
		_set_anim(target, "hurt")
		target["anim_hold"] = 0.35
		_emit("  → %s 与 %s 合击 %s：%d 伤害" % [attacker["name"], p["name"],
			target["name"], dmg], "hit")
		passive_on("on_hit", p, {"target": target})
		passive_on("on_hurt", target, {"source": p})
		if int(target["hp"]) <= 0:
			_kill(target, p)
			break
	return hits


# 该单位是否有「可触发合击」的被动/技能标记
func can_combo(u) -> bool:
	if u == null:
		return false
	# 技能施放期间临时开启的合击标记
	if bool(u.get("can_combo", false)):
		return true
	for fx in unit_passives(u):
		if String((fx as Dictionary).get("type", "")) == RULEZ.SFX_COMBO:
			return true
	return false


# ------------------------------------------------------------
# 技能形态切换（切换为 / 升级至）
#   form_state: { 原始技能id: 当前形态id }
#   switch_skill() 记录当前形态；skill_def_for() 取当前形态的定义
# ------------------------------------------------------------
func switch_form(u, from_sid: String, to_sid: String) -> void:
	if u == null or not u["alive"]:
		return
	if to_sid == "":
		return
	var fs: Dictionary = u.get("form_state", {})
	fs["_cur"] = to_sid
	u["form_state"] = fs
	var td: Dictionary = skill_def(to_sid)
	_emit("  → %s 的技能切换为「%s」" % [u["name"], String(td.get("name", to_sid))], "info")


# 取技能当前实际生效的定义（考虑了形态切换）
#   单位只记录一个「当前形态」_cur；若 _cur 与 sid 属于同一条形态链，则用 _cur 的定义
func skill_def_for(u, sid: String) -> Dictionary:
	var fs: Dictionary = u.get("form_state", {}) if u.get("form_state") is Dictionary else {}
	var cur := String(fs.get("_cur", ""))
	if cur != "" and cur != sid and _same_form_chain(cur, sid):
		var dc := skill_def(cur)
		if not dc.is_empty():
			return dc
	var d0 := skill_def(sid)
	return d0


# 判断两个技能是否属于同一条形态链（直接或间接通过 switch_skill 相连）
func _same_form_chain(a: String, b: String) -> bool:
	if a == b:
		return true
	if _switch_target(a) == b or _switch_target(b) == a:
		return true
	# 两跳：a→x→b 或 b→x→a
	var ta := _switch_target(a)
	var tb := _switch_target(b)
	if ta != "" and _switch_target(ta) == b:
		return true
	if tb != "" and _switch_target(tb) == a:
		return true
	# 同一基础链：都以同一个前缀开头（如 骁姿绝尘/·杰/·超）
	var pa := a.split("_")[0]
	var pb := b.split("_")[0]
	if pa == pb and ("_jie" in a or "_chao" in a or "_jie" in b or "_chao" in b):
		return true
	return false


func _switch_target(sid: String) -> String:
	var d := skill_def(sid)
	for f in RULEZ.skill_effects(d):
		var fd: Dictionary = f
		if str(fd.get("type", "")) == RULEZ.SFX_SWITCH:
			return str(fd.get("to", ""))
	return ""


# 新回合开始时重置反击次数与形态（可保留形态，这里只重置反击次数）
func _reset_turn_state(side: int) -> void:
	for u in units:
		if int(u["side"]) == side and u["alive"]:
			u["counter_used"] = 0


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
	# P3 先攻：拥有先攻的单位优先行动
	var ai := priority_units(1)
	for u in ai:
		if ended:
			break
		if not u["alive"]:
			continue
		_ai_act(u)
	# 其余敌军按原有顺序
	for u2 in alive(1).duplicate():
		if ended:
			break
		if not u2["alive"] or bool(u2["done"]):
			continue
		if ai.has(u2):
			continue
		_ai_act(u2)
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
