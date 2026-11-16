extends RefCounted
class_name EdData

# ============================================================
# 编辑器数据层：武将 / 兵种 / 技能 / 天赋 / 副将 + 编辑器专用附加数据
#   数据目录默认 res://data/editor（项目内自带一份旧工程 56 将 / 294 技策 / 35 天赋的副本）
#   旧工程字段（key/troop/arm/stats/talent/skills/...）保持不变，
#   编辑器新增字段一律用 ed_ 前缀，导出时可选择「剥离 ed_ 字段」还原成旧工程格式。
# ============================================================

const RULEZ = preload("res://scripts/core/rules.gd")

const DATA_DIR := "res://data/editor"
const GENERALS_PATH := "res://data/editor/generals.json"
const SKILLS_PATH := "res://data/editor/skills.json"
const TALENTS_PATH := "res://data/editor/talents.json"
const VICE_PATH := "res://data/vice_generals.json"
const SETTINGS_PATH := "res://data/editor/settings.json"
const LIBRARY_PATH := "res://data/editor/art_library.json"
const DS_URL_PATH := "res://data/editor/datasource.json"
const SHAPES_PATH := "res://data/editor/shapes.json"
const DEFAULT_DS_URL := "https://raw.githubusercontent.com/your-org/sango_wsz/main/data/editor"

# 扩展项默认值（全部可编辑，占位实现）
const EXT_DEFAULTS := {
	"arm2": "",                 # 第二兵种
	"gender": "男",
	"quality": 3,               # 品质：1~5
	"faction": "",              # 阵营
	"weapon": "",               # 武器
	"armor": "",                # 防具
	"accessory": "",            # 兵符 / 饰品
	"weapon_effect": "",
	"armor_effect": "",
	"accessory_effect": "",
	"crit_bonus": 0.0,          # 附加暴击率
	"crit_damage": 0.0,         # 附加暴击伤害
	"damage_bonus": 0.0,        # 增伤
	"damage_cut": 0.0,          # 减伤
	"reach_bonus": 0,           # 释放距离加成
	"move_bonus": 0,            # 移动力加成
	"morale": 100,              # 士气
	"ai_weight": 1.0,           # AI 行为权重（进攻倾向）
	"skill_power": 1.0,         # 技能威力系数
	"level_curve": "linear",    # 成长曲线：linear / fast / slow
	"growth_rates": {},         # 各属性成长率
	"growth_tags": [],          # 每级额外成长标签
	"fives": {"wu": 70, "zhi": 70, "tong": 70, "zheng": 70, "mei": 70},
	"passive_toggles": {},      # 被动效果开关
	"custom_fields": {},        # 自定义键值对
	"stage_fx": {},             # 阶段特效
	"unlock": {},
	"voice": "",
	"battle_quote": "",
	"vice_id": 0,
	"vice_dmg": 0.0,
	"frames": {},               # 精灵图信息（旧）
}

const ACTIONS := ["idle", "walk", "attack", "hurt", "die"]
const DIRS := ["down", "left", "right", "up"]


# ------------------------------------------------------------
# 动画结构（按旧工程《像素武将角色动画接入说明》）
#   ed_art.sheets = {atk:路径, mov:路径, spc:路径}   —— 三张图
#   ed_art.frame  = {w, h, fps_default}              —— 公共切帧参数
#   ed_art.anims["动作_朝向"] = {sheet, frames:[1-based 帧号...], fps, loop, mirror}
# ------------------------------------------------------------
static func empty_anim() -> Dictionary:
	return {"sheet": "mov", "frames": [1], "fps": 8.0, "loop": true, "mirror": false}


static func empty_art() -> Dictionary:
	var a := {
		"portrait_path": "", "illust_path": "",
		"sprite_path": "",
		"sheet_type": "strip",
		"frame_w": 64, "frame_h": 64,
		"sheets": {"atk": "", "mov": "", "spc": ""},
		"anims": {},
	}
	# 用旧规格铺好默认帧表（图未导入也先有帧号定义）
	var spec := RULEZ.legacy_anim_spec()
	for act in spec.keys():
		for d in (spec[act] as Dictionary).keys():
			var t: Dictionary = (spec[act] as Dictionary)[d]
			a["anims"]["%s_%s" % [act, d]] = t.duplicate(true)
	return a


func _migrate_art(art: Dictionary) -> Dictionary:
	var out := empty_art()
	for k in art.keys():
		if k != "anims":
			out[k] = art[k]
	if not (out.get("sheets") is Dictionary):
		out["sheets"] = {"atk": "", "mov": "", "spc": ""}
	else:
		var sh: Dictionary = out["sheets"]
		for k2 in ["atk", "mov", "spc"]:
			if not sh.has(k2):
				sh[k2] = ""
		out["sheets"] = sh
	var anims = art.get("anims", {})
	if anims is Dictionary:
		for k in (anims as Dictionary).keys():
			if out["anims"].has(k):
				var t: Dictionary = (out["anims"][k] as Dictionary).duplicate()
				var v = anims[k]
				if v is Dictionary:
					for kk in (v as Dictionary).keys():
						t[kk] = v[kk]
				out["anims"][k] = t
	# 旧结构（path 字段、单张图）迁移：把 path 放进对应 sheet
	var sp := String(out.get("sprite_path", ""))
	if sp != "" and String((out["sheets"] as Dictionary).get("mov", "")) == "":
		(out["sheets"] as Dictionary)["mov"] = sp
	if anims is Dictionary:
		for k in (anims as Dictionary).keys():
			var v = anims[k]
			if v is Dictionary and String((v as Dictionary).get("path", "")) != "":
				var sk := String((v as Dictionary).get("sheet", "mov"))
				if String((out["sheets"] as Dictionary).get(sk, "")) == "":
					(out["sheets"] as Dictionary)[sk] = String((v as Dictionary)["path"])
	_migrate_anim_numbers(out)
	_fill_default_frames(out)
	return out

var generals: Dictionary = {}      # key -> Dictionary（有序，保持 JSON 原顺序）
var order: Array[String] = []      # 显示顺序
var skills: Dictionary = {}
var talents: Dictionary = {}
var vices: Dictionary = {}
var library: Dictionary = {}       # 美术素材库：abs_path -> 元信息
var _arm_shapes_cache: Dictionary = {}
var _arm_shapes_cache_loaded := false
var ds_url: String = DEFAULT_DS_URL
var dirty := false
var last_error := ""
var last_skill_upgraded := ""      # 上次升星升级了哪个技能（供界面显示）


# ------------------------------------------------------------
# 读写 JSON
# ------------------------------------------------------------
static func read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	return parsed


static func write_json(path: String, data) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()
	return true


# ------------------------------------------------------------
# 加载 / 保存
# ------------------------------------------------------------
func load_all() -> bool:
	last_error = ""
	var g = read_json(GENERALS_PATH)
	if not (g is Dictionary):
		last_error = "无法读取 " + GENERALS_PATH
		return false
	generals.clear()
	order.clear()
	for k in (g as Dictionary).keys():
		generals[String(k)] = _normalize_general(String(k), g[k])
		order.append(String(k))
	var s = read_json(SKILLS_PATH)
	skills = s if s is Dictionary else {}
	var t = read_json(TALENTS_PATH)
	talents = t if t is Dictionary else {}
	var v = read_json(VICE_PATH)
	vices = v if v is Dictionary else {}
	var lib = read_json(LIBRARY_PATH)
	library = lib if lib is Dictionary else {}
	var ds = read_json(DS_URL_PATH)
	if ds is Dictionary:
		ds_url = String(ds.get("url", DEFAULT_DS_URL))
	RULEZ.load_settings(SETTINGS_PATH)
	dirty = false
	return true


# ------------------------------------------------------------
# 撤销：技能合并 / 组合前保存快照，可回退
# ------------------------------------------------------------
var _undo_stack: Array = []


func push_undo(label: String) -> void:
	var snap := {
		"label": label,
		"generals": JSON.stringify(generals),
		"skills": JSON.stringify(skills),
		"talents": JSON.stringify(talents),
		"order": order.duplicate(),
	}
	_undo_stack.append(snap)
	# 最多保留 20 步
	if _undo_stack.size() > 20:
		_undo_stack.remove_at(0)


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func undo_label() -> String:
	if _undo_stack.is_empty():
		return ""
	return String((_undo_stack[-1] as Dictionary).get("label", ""))


# 回退一步，返回被撤销操作的说明
func undo() -> Dictionary:
	if _undo_stack.is_empty():
		return {"ok": false, "msg": "没有可撤销的操作"}
	var snap: Dictionary = _undo_stack.pop_back()
	var g = JSON.parse_string(String(snap["generals"]))
	var s = JSON.parse_string(String(snap["skills"]))
	var t = JSON.parse_string(String(snap["talents"]))
	if not (g is Dictionary) or not (s is Dictionary):
		return {"ok": false, "msg": "快照损坏，无法撤销"}
	generals.clear()
	order.clear()
	for k in (snap["order"] as Array):
		var kk := String(k)
		generals[kk] = _normalize_general(kk, (g as Dictionary).get(kk, {}))
		order.append(kk)
	skills = s
	talents = t if t is Dictionary else {}
	dirty = true
	return {"ok": true, "msg": "已撤销：%s" % String(snap.get("label", ""))}


func save_all() -> bool:
	var ok := true
	ok = _save_generals() and ok
	ok = write_json(SKILLS_PATH, skills) and ok
	ok = write_json(TALENTS_PATH, talents) and ok
	ok = write_json(LIBRARY_PATH, library) and ok
	ok = save_arm_shapes() and ok
	ok = write_json(DS_URL_PATH, {"url": ds_url}) and ok
	ok = write_json(SETTINGS_PATH, RULEZ.settings) and ok
	if ok:
		dirty = false
	return ok


func _save_generals() -> bool:
	var out := {}
	for k in order:
		out[k] = generals[k]
	return write_json(GENERALS_PATH, out)


# 补齐所有扩展字段（旧数据里没有 ed_* 字段）
func _normalize_general(key: String, raw: Dictionary) -> Dictionary:
	var g: Dictionary = raw.duplicate(true)
	if not (g.get("stats") is Dictionary):
		g["stats"] = {}
	var st: Dictionary = g["stats"]
	for k in ["hp", "atk", "def", "matk", "mdef", "luck", "move", "range"]:
		if not st.has(k):
			st[k] = 1 if k == "range" else 50
	if not (g.get("skills") is Array):
		g["skills"] = []
	if not g.has("portrait"):
		g["portrait"] = ""
	if not g.has("name"):
		g["name"] = key
	if not g.has("troop"):
		g["troop"] = ""
	if not g.has("color"):
		g["color"] = "#3b82f6"
	if not g.has("arm"):
		g["arm"] = "盾"
	if not g.has("talent"):
		g["talent"] = ""
	var ext: Dictionary = g.get("ed_ext", {}) if g.get("ed_ext") is Dictionary else {}
	var full := EXT_DEFAULTS.duplicate(true)
	for k in ext.keys():
		if full.get(k) is Dictionary and ext[k] is Dictionary:
			var m: Dictionary = full[k].duplicate(true)
			for kk in ext[k].keys():
				m[kk] = ext[k][kk]
			full[k] = m
		else:
			full[k] = ext[k]
	g["ed_ext"] = full
	if not g.has("ed_level"):
		g["ed_level"] = 1
	if not g.has("ed_star"):
		g["ed_star"] = 1
	if not g.has("ed_skill_lv"):
		g["ed_skill_lv"] = {}
	if not g.has("ed_talent_lv"):
		g["ed_talent_lv"] = int(g.get("talent_lv", 1))
	if not g.has("ed_art") or not (g.get("ed_art") is Dictionary):
		g["ed_art"] = empty_art()
	else:
		g["ed_art"] = _migrate_art(g["ed_art"])
	if not g.has("ed_ranges"):
		g["ed_ranges"] = {}
	if not g.has("ed_note"):
		g["ed_note"] = ""
	if not g.has("ed_tags"):
		g["ed_tags"] = []
	if not g.has("ed_enabled"):
		g["ed_enabled"] = true
	if not (g.get("ed_arm_lv") is Dictionary):
		g["ed_arm_lv"] = {"level": 0, "spend": {}}
	if not (g.get("ed_star_bonus") is Dictionary):
		g["ed_star_bonus"] = {}
	if not g.has("ed_star"):
		g["ed_star"] = 1
	return g


# ------------------------------------------------------------
# 武将
# ------------------------------------------------------------
func keys() -> Array[String]:
	return order


func get_general(key: String) -> Dictionary:
	return generals.get(key, {})


func has_general(key: String) -> bool:
	return generals.has(key)


func name_of(key: String) -> String:
	var g: Dictionary = generals.get(key, {})
	var n := String(g.get("name", ""))
	return n if n != "" else key


func new_general_key(base_name: String) -> String:
	var base := to_pinyin_like(base_name)
	if base == "" or base == "general":
		base = "new_general"
	var k := base
	var i := 2
	while generals.has(k):
		k = "%s_%d" % [base, i]
		i += 1
	return k


func add_general(key: String, tmpl: Dictionary = {}) -> String:
	var g: Dictionary = tmpl.duplicate(true)
	if g.is_empty():
		g = {
			"id": next_general_id(),
			"name": "新武将",
			"troop": "步兵",
			"color": "#3b82f6",
			"portrait": "",
			"stats": {"hp": 120, "atk": 70, "def": 40, "matk": 40, "mdef": 30, "luck": 50, "move": 4, "range": 1},
			"talent": "",
			"talent_lv": 1,
			"skills": [],
			"arm": "盾",
		}
	g = _normalize_general(key, g)
	generals[key] = g
	order.append(key)
	dirty = true
	return key


func duplicate_general(src: String) -> String:
	var key := src + "_copy"
	var i := 2
	while generals.has(key):
		key = "%s_copy%d" % [src, i]
		i += 1
	var g: Dictionary = generals[src].duplicate(true)
	g["name"] = String(g.get("name", src)) + "·副本"
	g["id"] = next_general_id()
	g = _normalize_general(key, g)
	generals[key] = g
	var idx := order.find(src)
	if idx >= 0:
		order.insert(idx + 1, key)
	else:
		order.append(key)
	dirty = true
	return key


func remove_general(key: String) -> void:
	generals.erase(key)
	order.erase(key)
	dirty = true


func move_general(key: String, delta: int) -> void:
	var idx := order.find(key)
	if idx < 0:
		return
	var ni := clampi(idx + delta, 0, order.size() - 1)
	if ni == idx:
		return
	order.remove_at(idx)
	order.insert(ni, key)


func next_general_id() -> int:
	var mx := 0
	for k in order:
		mx = maxi(mx, int(generals[k].get("id", 0)))
	return mx + 1


func rename_general_key(old_key: String, new_key: String) -> bool:
	new_key = new_key.strip_edges()
	if new_key == "" or new_key == old_key or generals.has(new_key):
		return false
	var g: Dictionary = generals[old_key]
	generals.erase(old_key)
	generals[new_key] = g
	var idx := order.find(old_key)
	if idx >= 0:
		order[idx] = new_key
	dirty = true
	return true


# ------------------------------------------------------------
# 技能 / 天赋
# ------------------------------------------------------------
func get_skill(sid: String) -> Dictionary:
	return skills.get(sid, {})


func skill_name(sid: String) -> String:
	var d: Dictionary = skills.get(sid, {})
	var n := String(d.get("name", ""))
	return n if n != "" else sid


func new_skill_id(base := "skill") -> String:
	var i := 1
	var sid := "%s_%d" % [base, i]
	while skills.has(sid):
		i += 1
		sid = "%s_%d" % [base, i]
	return sid


func add_skill(sid: String, d: Dictionary) -> void:
	skills[sid] = d
	dirty = true


# ============================================================
# 技能合并
#   模式一「融合 merge」：把 src 的效果并入 dst（描述合并、被动效果标记、
#     CD/倍率/特效按可选取较优或合并），再把 src 从所有武将里移除并删除技能定义。
#   模式二「二选一组 group」：dst（或新建一个组技能）通过 ed_group 记录若干子技能，
#     点组技能时二选一施放；子技能可从武将技能列表隐藏，但定义保留。
# ============================================================

const GROUP_KIND := "group"


# 融合：src 并入 dst
func merge_skills(src: String, dst: String, keep_src_name: bool = false) -> Dictionary:
	if src == dst:
		return {"ok": false, "msg": "不能把技能合并进自己"}
	if not skills.has(src) or not skills.has(dst):
		return {"ok": false, "msg": "技能不存在"}
	var s: Dictionary = skills[src]
	var d: Dictionary = skills[dst]
	# 去重：已经融合过同名/同描述的技能就不再重复追加
	var from0: Array = d.get("ed_merged_from", []) if d.get("ed_merged_from") is Array else []
	var sd0 := String(s.get("desc", "")).strip_edges()
	if not sd0.is_empty() and String(d.get("desc", "")).contains(sd0):
		# 内容已在描述里，只记录来源，不再重复合并文案
		if not from0.has(src):
			from0.append(src)
		d["ed_merged_from"] = from0
		skills[dst] = d
		for k in order:
			var g2: Dictionary = generals[k]
			if (g2.get("skills", []) as Array).has(src):
				(g2["skills"] as Array).erase(src)
				(g2.get("ed_skill_lv", {}) as Dictionary).erase(src)
		skills.erase(src)
		dirty = true
		return {"ok": true, "msg": "「%s」的内容已存在于「%s」，只登记来源，未重复追加" % [
			String(s.get("name", src)), skill_name(dst)]}
	# 1) 描述合并（追加到目标描述）
	var sd := String(s.get("desc", ""))
	var dd := String(d.get("desc", ""))
	if sd != "":
		d["desc"] = (dd + "\n[合并自「%s」] %s" % [skill_name(src), sd]) if dd != "" else sd
	# 2) 升级文案合并
	var slv: Array = s.get("lv", []) if s.get("lv") is Array else []
	var dlv: Array = d.get("lv", []) if d.get("lv") is Array else []
	if slv.size() == dlv.size():
		var merged: Array = []
		for i in slv.size():
			var a := String(dlv[i])
			var b := String(slv[i])
			merged.append((a + "；" + b) if (a != "" and b != "") else (a if a != "" else b))
		d["lv"] = merged
	# 3) 把源技能的「被动效果关键词」记进目标（供引擎识别），去重
	var passives: Array = d.get("ed_merged_passives", []) if d.get("ed_merged_passives") is Array else []
	var pname := String(s.get("name", src))
	if not passives.has(pname):
		passives.append(pname)
	d["ed_merged_passives"] = passives
	# 4) 若源有特效、目标没有，则继承；两边都有时保留目标
	if s.get("ed_fx") is Dictionary and not (d.get("ed_fx") is Dictionary):
		d["ed_fx"] = (s["ed_fx"] as Dictionary).duplicate(true)
	# 5) 记录来源
	var from: Array = d.get("ed_merged_from", []) if d.get("ed_merged_from") is Array else []
	from.append(src)
	d["ed_merged_from"] = from
	skills[dst] = d
	# 6) 把所有武将的 src 换成 dst（去重），并从技能库删除 src
	var affected := 0
	for k in order:
		var g: Dictionary = generals[k]
		var arr: Array = g.get("skills", [])
		if arr.has(src):
			var new_arr: Array = []
			for x in arr:
				var xs := String(x)
				if xs == src:
					xs = dst
				if not new_arr.has(xs):
					new_arr.append(xs)
			g["skills"] = new_arr
			# 等级沿用被合并技能里较高的
			var sl: Dictionary = g.get("ed_skill_lv", {})
			if int(sl.get(src, 1)) > int(sl.get(dst, 1)):
				sl[dst] = int(sl.get(src, 1))
			sl.erase(src)
			var cd: Dictionary = g.get("ed_ranges", {})
			if cd.has(src) and not cd.has(dst):
				cd[dst] = cd[src]
			cd.erase(src)
			affected += 1
	skills.erase(src)
	dirty = true
	return {"ok": true, "msg": "已把「%s」融合进「%s」（影响 %d 名武将），源技能已删除" % [
		skill_name(src) if s.get("name") else src, skill_name(dst), affected]}


# 二选一组：把若干子技能挂到一个「组技能」下
#   host = "" 时自动新建一个组技能（名称/描述由调用方给）
func make_skill_group(host: String, children: Array, name: String = "", desc: String = "") -> Dictionary:
	if children.size() < 2:
		return {"ok": false, "msg": "至少选 2 个子技能"}
	for c in children:
		if not skills.has(String(c)):
			return {"ok": false, "msg": "子技能不存在：" + String(c)}
	var hid := host
	if hid == "":
		hid = new_skill_id("group")
		var nm := name if name != "" else "组合技策"
		var child_names: Array = []
		for c in children:
			child_names.append("「%s」" % skill_name(String(c)))
		var ds := desc if desc != "" else ("在%s中选择一个技策使用。" % "、".join(child_names))
		skills[hid] = {
			"name": nm, "kind": GROUP_KIND, "cd": 0,
			"desc": ds, "lv": ["", "", ""], "from_official": false,
			"ed_group": children.duplicate(),
		}
	else:
		if not skills.has(hid):
			return {"ok": false, "msg": "组技能不存在"}
		var d: Dictionary = skills[hid]
		d["ed_group"] = children.duplicate()
		d["kind"] = GROUP_KIND
		skills[hid] = d
	dirty = true
	var all_names: Array = []
	for c in children:
		all_names.append(skill_name(String(c)))
	return {"ok": true, "id": hid, "msg": "已建立二选一组「%s」：%s" % [
		skill_name(hid), " / ".join(all_names)]}


# 把子技能放进已有组 / 从组里移除 / 删除组（并还原子技能）
func add_to_group(host: String, child: String) -> Dictionary:
	if not skills.has(host) or not skills.has(child):
		return {"ok": false, "msg": "技能不存在"}
	var d: Dictionary = skills[host]
	var arr: Array = d.get("ed_group", []) if d.get("ed_group") is Array else []
	if not arr.has(child):
		arr.append(child)
	d["ed_group"] = arr
	d["kind"] = GROUP_KIND
	skills[host] = d
	dirty = true
	return {"ok": true, "msg": "已加入组：%s" % skill_name(child)}


func remove_from_group(host: String, child: String) -> Dictionary:
	if not skills.has(host):
		return {"ok": false, "msg": "组不存在"}
	var d: Dictionary = skills[host]
	var arr: Array = d.get("ed_group", []) if d.get("ed_group") is Array else []
	arr.erase(child)
	d["ed_group"] = arr
	skills[host] = d
	dirty = true
	return {"ok": true, "msg": "已从组移除：%s" % skill_name(child)}


# 组的子技能列表
func group_children(host: String) -> Array:
	if not skills.has(host):
		return []
	var d: Dictionary = skills[host]
	var arr = d.get("ed_group", [])
	return arr.duplicate() if arr is Array else []


func is_group(sid: String) -> bool:
	var d: Dictionary = skills.get(sid, {})
	return String(d.get("kind", "")) == GROUP_KIND or (d.get("ed_group") is Array and not (d.get("ed_group") as Array).is_empty())


# 删除技能：从技能库与所有武将中移除
func delete_skill(sid: String) -> Dictionary:
	if not skills.has(sid):
		return {"ok": false, "msg": "技能不存在"}
	var n := 0
	for k in order:
		var g: Dictionary = generals[k]
		var arr: Array = g.get("skills", [])
		if arr.has(sid):
			arr.erase(sid)
			g["skills"] = arr
			(g.get("ed_skill_lv", {}) as Dictionary).erase(sid)
			var er: Dictionary = g.get("ed_ranges", {})
			# 清除该技能范围
			er.erase(sid)
			n += 1
	skills.erase(sid)
	dirty = true
	return {"ok": true, "msg": "已删除技能 %s（从 %d 名武将移除）" % [sid, n]}


# 把技能从某个武将身上移除（保留技能库定义）
func remove_skill_from_general(key: String, sid: String) -> void:
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return
	(g.get("skills", []) as Array).erase(sid)
	(g.get("ed_skill_lv", {}) as Dictionary).erase(sid)
	dirty = true


func get_talent(tid: String) -> Dictionary:
	return talents.get(tid, {})


func talent_name(tid: String) -> String:
	var d: Dictionary = talents.get(tid, {})
	var n := String(d.get("name", ""))
	return n if n != "" else tid


func new_talent_id(base := "talent") -> String:
	var i := 1
	var tid := "%s_%d" % [base, i]
	while talents.has(tid):
		i += 1
		tid = "%s_%d" % [base, i]
	return tid


func add_talent(tid: String, d: Dictionary) -> void:
	talents[tid] = d
	dirty = true


# ------------------------------------------------------------
# 计算：把武将记录变成「战斗单位模板」（验算台 / 小战场共用）
# ------------------------------------------------------------
func unit_template(key: String, lv: int = -1, star: int = -1, arm: String = "") -> Dictionary:
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return {}
	var ext: Dictionary = g.get("ed_ext", {}) if g.get("ed_ext") is Dictionary else {}
	var e_lv: int = int(g.get("ed_level", 1)) if lv < 0 else lv
	var e_star: int = int(g.get("ed_star", 1)) if star < 0 else star
	var e_arm: String = String(g.get("arm", "盾")) if arm == "" else arm
	var lv_c := clampi(e_lv, 1, RULEZ.max_level())
	var st_c := clampi(e_star, 1, RULEZ.max_star())
	var base: Dictionary = (g.get("stats", {}) as Dictionary).duplicate(true)
	var base_fives: Dictionary = ext.get("fives", {}) if ext.get("fives") is Dictionary else {}
	# 武将升级升五维：按等级算出当前五维
	var cur_fives: Dictionary = RULEZ.fives_at(base_fives, lv_c)
	base["five"] = cur_fives
	# 面板属性【完全由五维换算】：兵力/物攻/物防/谋攻/谋防/幸运（暴击）
	var derived: Dictionary = RULEZ.stat_from_fives(cur_fives)
	for k in ["max_hp", "atk", "matk", "def", "mdef", "luck"]:
		base[k] = int(derived[k])
	var rates: Dictionary = ext.get("growth_rates", {})
	var curve := String(ext.get("level_curve", "linear"))
	# 成长曲线也和五维挂钩：高五维 → 高成长倍率
	var gmult := RULEZ.growth_mult_by_five(float(cur_fives.get("wu", 50)))
	var stats := RULEZ.apply_growth(base, base, lv_c, st_c, e_arm, rates, ext.get("growth_tags", []))
	stats["atk"] = int(round(float(stats["atk"]) * gmult))
	stats["matk"] = int(round(float(stats["matk"]) * (0.5 + 0.5 * RULEZ.growth_mult_by_five(float(cur_fives.get("zhi", 50))))))
	if curve == "fast":
		stats["atk"] = int(round(float(stats["atk"]) * (1.0 + 0.02 * float(lv_c - 1))))
		stats["matk"] = int(round(float(stats["matk"]) * (1.0 + 0.02 * float(lv_c - 1))))
	elif curve == "slow":
		stats["atk"] = int(round(float(stats["atk"]) * (1.0 - 0.01 * float(lv_c - 1) * 0.5)))
		stats["matk"] = int(round(float(stats["matk"]) * (1.0 - 0.01 * float(lv_c - 1) * 0.5)))
	# 扩展项：装备/天赋面板加成
	stats["atk"] = int(round(float(stats["atk"]) * (1.0 + float(ext.get("damage_bonus", 0.0)))))
	# 升星额外属性加成（如 8 星全属性 +8%）
	var sb_mult := star_bonus_mult(g)
	if sb_mult != 1.0:
		for k3 in ["max_hp", "atk", "def", "matk", "mdef", "luck"]:
			stats[k3] = int(round(float(stats[k3]) * sb_mult))
	# ---- 移动 / 攻击范围：继承兵种基础，再叠加「兵种升级 + 技能/天赋」加成 ----
	var arm_up_lv := int((g.get("ed_arm_lv", {}) as Dictionary).get("level", 0))
	var arm_spend: Dictionary = (g.get("ed_arm_lv", {}) as Dictionary).get("spend", {})
	var arm_gain := RULEZ.arm_upgrade_stats(arm_up_lv, arm_spend)
	# 兵种升级的属性点
	for k2 in ["atk", "def", "matk", "mdef", "luck"]:
		stats[k2] = int(stats[k2]) + int(arm_gain.get(k2, 0))
	stats["max_hp"] = int(stats["max_hp"]) + int(arm_gain.get("max_hp", 0))
	# 移动 / 射程：兵种基础值 + 兵种升级 + 武将技能天赋加成（ext.move_bonus / 天赋专属）
	stats["move"] = RULEZ.arm_base_move(e_arm) + int(arm_gain.get("move", 0)) + int(ext.get("move_bonus", 0))
	stats["range"] = RULEZ.arm_base_range(e_arm) + int(arm_gain.get("range", 0)) + int(ext.get("reach_bonus", 0))
	# 旧工程天赋面板加成（孙策：移动 +1，谋攻 += 物攻×0.5）
	if String(g.get("talent", "")) == "sun_ce_talent" and int(g.get("ed_talent_lv", 1)) >= 1:
		stats["move"] = int(stats["move"]) + 1
		stats["matk"] = int(stats["matk"]) + int(round(float(stats["atk"]) * 0.5))
	if int(stats["move"]) < 0:
		stats["move"] = 0
	if int(stats["range"]) < 0:
		stats["range"] = 0
	var skill_lvs: Dictionary = {}
	for sid in (g.get("skills", []) as Array):
		skill_lvs[String(sid)] = int((g.get("ed_skill_lv", {}) as Dictionary).get(sid, 1))
	var out: Dictionary = {
		"key": key,
		"name": String(g.get("name", key)),
		"arm": e_arm,
		"troop": String(g.get("troop", "")),
		"color": String(g.get("color", "#3b82f6")),
		"level": lv_c,
		"star": st_c,
		"talent": String(g.get("talent", "")),
		"talent_lv": int(g.get("ed_talent_lv", 1)),
		"skills": (g.get("skills", []) as Array).duplicate(),
		"skill_lv": skill_lvs,
		"stats": stats,
		"fives": cur_fives,
		"ext": ext,
		"crit_bonus": float(ext.get("crit_bonus", 0.0)),
		"crit_damage": float(ext.get("crit_damage", 0.0)),
		"damage_cut": float(ext.get("damage_cut", 0.0)),
		# 运势 = 魅力（公式表：魅力提供运势），可再用 ext.fortune_bonus 调整
		"fortune": float(cur_fives.get("mei", 0)) + float(ext.get("fortune_bonus", 0.0)),
		"crit_resist": float(ext.get("crit_resist", 0.0)),
		"douqi": 0,
		"wushuang": 0,
	}
	out["base_stats"] = base
	out["arm_level"] = arm_up_lv
	out["arm_gain"] = arm_gain
	out["power"] = RULEZ.combat_power(out)
	return out


# ---------------- 兵种攻击范围形状（与技能范围一样的逐格形状） ----------------
func get_arm_shape(arm: String) -> Dictionary:
	var m: Dictionary = get_arm_shapes()
	var v = m.get(arm, {})
	return v if v is Dictionary else {}


func set_arm_shape(arm: String, area: Array) -> void:
	var m: Dictionary = get_arm_shapes()
	m[arm] = {"area": area}
	dirty = true
	_arm_shapes_cache = m


func get_arm_shapes() -> Dictionary:
	if _arm_shapes_cache_loaded:
		return _arm_shapes_cache
	var parsed = read_json(SHAPES_PATH)
	if parsed is Dictionary and (parsed as Dictionary).get("arm_shapes") is Dictionary:
		_arm_shapes_cache = (parsed as Dictionary)["arm_shapes"]
	else:
		_arm_shapes_cache = {}
	_arm_shapes_cache_loaded = true
	return _arm_shapes_cache


func save_arm_shapes() -> bool:
	var parsed = read_json(SHAPES_PATH)
	var out: Dictionary = parsed if parsed is Dictionary else {}
	out["arm_shapes"] = get_arm_shapes()
	return write_json(SHAPES_PATH, out)


# ------------------------------------------------------------
# 兵种普攻范围 → 同步到该兵种所有武将
# ------------------------------------------------------------
func sync_arm_shape_to_generals(arm: String) -> int:
	var shape: Dictionary = get_arm_shape(arm)
	var area: Array = shape.get("area", [])
	var n := 0
	for k in order:
		var g: Dictionary = generals[k]
		if String(g.get("arm", "")) != arm:
			continue
		if not (g.get("ed_ranges") is Dictionary):
			g["ed_ranges"] = {}
		var er: Dictionary = g["ed_ranges"]
		var entry = er.get("basic", {})
		if not (entry is Dictionary):
			entry = {}
		if area.is_empty():
			(entry as Dictionary).erase("area")
		else:
			(entry as Dictionary)["area"] = area.duplicate(true)
		er["basic"] = entry
		g["ed_ranges"] = er
		n += 1
	if n > 0:
		dirty = true
	return n


# 换兵种：把该武将的普攻换成新兵种的形状，移动/射程由 unit_template 按兵种重算
func apply_arm_to_general(key: String, arm: String) -> void:
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return
	g["arm"] = arm
	if not (g.get("ed_ranges") is Dictionary):
		g["ed_ranges"] = {}
	var er: Dictionary = g["ed_ranges"]
	var entry = er.get("basic", {})
	if not (entry is Dictionary):
		entry = {}
	var shape: Dictionary = get_arm_shape(arm)
	var area: Array = shape.get("area", [])
	if area.is_empty():
		(entry as Dictionary).erase("area")
		(entry as Dictionary).erase("layer_1")
		(entry as Dictionary).erase("layer_2")
		(entry as Dictionary).erase("layer_3")
	else:
		(entry as Dictionary)["area"] = area.duplicate(true)
		(entry as Dictionary)["layer_1"] = area.duplicate(true)
		(entry as Dictionary)["layer_2"] = area.duplicate(true)
		(entry as Dictionary)["layer_3"] = area.duplicate(true)
	er["basic"] = entry
	g["ed_ranges"] = er
	dirty = true


# ---------------- 兵种升级 ----------------
func arm_upgrade_info(key: String) -> Dictionary:
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return {}
	var ext: Dictionary = g.get("ed_ext", {}) if g.get("ed_ext") is Dictionary else {}
	var fives: Dictionary = ext.get("fives", {}) if ext.get("fives") is Dictionary else {}
	var au: Dictionary = RULEZ.arm_up().duplicate(true)
	var lv := int((g.get("ed_arm_lv", {}) as Dictionary).get("level", 0))
	var total := RULEZ.arm_points_total(fives, lv)
	var spend: Dictionary = (g.get("ed_arm_lv", {}) as Dictionary).get("spend", {})
	var used := 0
	for k in spend.keys():
		used += int(spend[k])
	return {
		"level": lv, "max_lv": int(au.get("max_lv", 20)),
		"points_total": total, "points_used": used, "points_left": maxi(0, total - used),
		"spend": spend, "up": au, "gain": RULEZ.arm_upgrade_stats(lv, spend),
		"five_sum": _five_sum(fives),
	}


func _five_sum(fives: Dictionary) -> int:
	var s := 0
	for k in ["wu", "zhi", "tong", "zheng", "mei"]:
		s += int(fives.get(k, 0))
	return s


func set_arm_level(key: String, lv: int) -> Dictionary:
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return {"ok": false, "msg": "武将不存在"}
	var info := arm_upgrade_info(key)
	var maxl := int(info.get("max_lv", 20))
	lv = clampi(lv, 0, maxl)
	var box: Dictionary = g.get("ed_arm_lv", {}) if g.get("ed_arm_lv") is Dictionary else {}
	var spend: Dictionary = box.get("spend", {}) if box.get("spend") is Dictionary else {}
	# 升级后点数变少（例如降级），自动回收多余加点
	var total := RULEZ.arm_points_total((g.get("ed_ext", {}) as Dictionary).get("fives", {}), lv)
	var used := 0
	for k in spend.keys():
		used += int(spend[k])
	if used > total:
		var over := used - total
		for k in ["hp", "atk", "def", "matk", "mdef", "luck"]:
			if over <= 0:
				break
			var have := int(spend.get(k, 0))
			var cut := mini(have, over)
			spend[k] = have - cut
			over -= cut
	box["level"] = lv
	box["spend"] = spend
	g["ed_arm_lv"] = box
	dirty = true
	return {"ok": true, "info": arm_upgrade_info(key)}


func add_arm_point(key: String, stat: String, delta: int = 1) -> Dictionary:
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return {"ok": false, "msg": "武将不存在"}
	var info := arm_upgrade_info(key)
	var spend: Dictionary = (g.get("ed_arm_lv", {}) as Dictionary).get("spend", {})
	if not (spend is Dictionary):
		spend = {}
	if delta > 0:
		if int(info["points_left"]) < delta:
			return {"ok": false, "msg": "没有可分配的升级点了"}
		spend[stat] = int(spend.get(stat, 0)) + delta
	else:
		spend[stat] = maxi(0, int(spend.get(stat, 0)) + delta)
	var box: Dictionary = g.get("ed_arm_lv", {}) if g.get("ed_arm_lv") is Dictionary else {}
	box["spend"] = spend
	if not box.has("level"):
		box["level"] = 0
	g["ed_arm_lv"] = box
	dirty = true
	return {"ok": true, "info": arm_upgrade_info(key)}


# ============================================================
# 升星：1 星起；2/3/4/6/7/9 星升技能，5/10 星升天赋，8 星属性 +8%；消耗同名武将
# ============================================================
func star_plan(key: String) -> Array:
	var g: Dictionary = generals.get(key, {})
	var cur := int(g.get("ed_star", 1))
	var rule: Dictionary = RULEZ.star_rule()
	var maxs := int(rule.get("max_star", 10))
	var out: Array = []
	# 从当前状态出发逐星模拟，得到每一星「之后」的技能/天赋等级
	var sim_skill: Dictionary = (g.get("ed_skill_lv", {}) as Dictionary).duplicate(true) if g.get("ed_skill_lv") is Dictionary else {}
	var sim_talent := int(g.get("ed_talent_lv", 1))
	var star_skill_map: Dictionary = g.get("ed_star_skill", {}) if g.get("ed_star_skill") is Dictionary else {}
	var star_lv_map: Dictionary = g.get("ed_star_lv", {}) if g.get("ed_star_lv") is Dictionary else {}
	# 被动技能也可以升阶，所以这里列全部技能
	var active_ids: Array = []
	for s in (g.get("skills", []) as Array):
		active_ids.append(String(s))
	# 目标级数：以「升到 Lv2 / Lv3」为准，但保证每星至少升 1 阶
	#   → 本星前 Lv1 选 Lv2 = Lv2，选 Lv3 = Lv3
	#   → 本星前 Lv2 不管选 2 还是 3，都至少到 Lv3（不会出现 Lv2→Lv2 白费一星）
	var target_lv := func(st: int, cur_lv: int) -> int:
		var want := int(star_lv_map.get(str(st), 2))
		if want < 2 or want > 3:
			want = 2
		return clampi(maxi(want, cur_lv + 1), 2, 3)
	for s in range(cur + 1, maxs + 1):
		var kind := RULEZ.star_upgrade_kind(s)
		var proj := ""
		var skill_before: Dictionary = sim_skill.duplicate(true)
		if kind == "skill":
			var pick := String(star_skill_map.get(str(s), ""))
			# 未设置 / 该技能已满 Lv3 → 自动挑一个未满级的技能，避免白费
			if pick == "" or not active_ids.has(pick) or int(sim_skill.get(pick, 1)) >= 3:
				pick = ""
				for a in active_ids:
					if int(sim_skill.get(a, 1)) < 3:
						pick = a
						break
			if pick != "":
				var lv0 := int(sim_skill.get(pick, 1))
				var lv1 := int(target_lv.call(s, lv0))
				sim_skill[pick] = lv1
				proj = "「%s」Lv%d → Lv%d" % [skill_name(pick), lv0, lv1]
			else:
				proj = "（技能已全部 Lv3，本星无技能可升）"
		elif kind == "talent":
			var tl0 := sim_talent
			sim_talent = mini(3, sim_talent + 1)
			proj = "天赋 Lv%d → Lv%d" % [tl0, sim_talent]
		var desc := _star_desc(kind, s, g)
		if kind == "talent":
			desc = "天赋升 1 阶（本星后 Lv%d）" % sim_talent
		elif kind == "skill" and proj != "":
			desc = "技能升 1 阶"
		out.append({
			"star": s, "kind": kind, "label": RULEZ.star_label(s),
			"cost": RULEZ.star_cost(s),
			"desc": desc,
			"projection": proj,
			"skill_before": skill_before,
			"skill_after": sim_skill.duplicate(true),
			"talent_after": sim_talent,
		})
	return out


func _star_desc(kind: String, star: int, g: Dictionary) -> String:
	match kind:
		"skill":
			return "挑一个主动技能升 1 阶（最高 Lv3）"
		"talent":
			# plan 里会用累积模拟覆盖此文案；这里仅作 do_star 时的回退
			return "天赋升 1 阶"
		"stat":
			var r: Dictionary = RULEZ.star_rule()
			var sb = r.get("stat_bonus_stars", {})
			var pct := float(r.get("stat_bonus_pct", 0.08))
			if sb is Dictionary and (sb as Dictionary).has(str(star)):
				pct = float((sb as Dictionary)[str(star)])
			return "全属性 +%d%%（本星额外加成）" % int(round(pct * 100.0))
	return "无"


# 执行升星：kind = skill 时需指定 skill_id；target_lv = 直接升到几级（2 或 3，0=自动 +1）
func do_star_upgrade(key: String, skill_id: String = "", target_lv: int = 0) -> Dictionary:
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return {"ok": false, "msg": "武将不存在"}
	var cur := int(g.get("ed_star", 1))
	var rule: Dictionary = RULEZ.star_rule()
	if cur >= int(rule.get("max_star", 10)):
		return {"ok": false, "msg": "已是最高星级"}
	var next := cur + 1
	var kind := RULEZ.star_upgrade_kind(next)
	var msg := ""
	if kind == "talent":
		var tl := int(g.get("ed_talent_lv", 1))
		if tl >= 3:
			return {"ok": false, "msg": "天赋已是 Lv3，无法再升阶"}
		g["ed_talent_lv"] = tl + 1
		msg = "天赋升阶 → Lv%d" % (tl + 1)
	elif kind == "skill":
		var sids: Array = g.get("skills", [])
		var pick := skill_id
		if pick != "":
			# 玩家自选：技能必须在武将身上（被动技能也可以升阶）
			if not sids.has(pick):
				return {"ok": false, "msg": "该武将没有这个技能"}
			var lvp := int((g.get("ed_skill_lv", {}) as Dictionary).get(pick, 1))
			if lvp >= 3:
				# 指定的已满级 → 自动改挑一个未满级的
				pick = ""
				for s2 in sids:
					if int((g.get("ed_skill_lv", {}) as Dictionary).get(s2, 1)) < 3:
						pick = String(s2)
						break
		if pick == "":
			for s in sids:
				if int((g.get("ed_skill_lv", {}) as Dictionary).get(s, 1)) < 3:
					pick = String(s)
					break
		if pick == "":
			return {"ok": false, "msg": "没有可升阶的技能（都满级）"}
		var lv := int((g.get("ed_skill_lv", {}) as Dictionary).get(pick, 1))
		# 保证每星至少升 1 阶：目标 = max(所选 2/3, 当前+1)，封顶 3
		var want := 2
		if target_lv >= 2 and target_lv <= 3:
			want = target_lv
		var new_lv := clampi(maxi(want, lv + 1), 2, 3)
		g["ed_skill_lv"][pick] = new_lv
		msg = "技能「%s」Lv%d → Lv%d" % [skill_name(pick), lv, new_lv]
		last_skill_upgraded = pick
	elif kind == "stat":
		# 8 星：属性 +8%（记入 ed_star_bonus，累乘在面板上）
		var sb: Dictionary = g.get("ed_star_bonus", {}) if g.get("ed_star_bonus") is Dictionary else {}
		var r2: Dictionary = RULEZ.star_rule()
		var sbs = r2.get("stat_bonus_stars", {})
		var pct := float(r2.get("stat_bonus_pct", 0.08))
		if sbs is Dictionary and (sbs as Dictionary).has(str(next)):
			pct = float((sbs as Dictionary)[str(next)])
		sb[str(next)] = pct
		g["ed_star_bonus"] = sb
		msg = "全属性 +%d%%" % int(round(pct * 100.0))
	g["ed_star"] = next
	dirty = true
	return {"ok": true, "star": next, "kind": kind, "msg": msg}


# 8 星等额外属性加成总倍率
func star_bonus_mult(g: Dictionary) -> float:
	var sb = g.get("ed_star_bonus", {})
	if not (sb is Dictionary):
		return 1.0
	var m := 1.0
	for k in (sb as Dictionary).keys():
		m *= 1.0 + float((sb as Dictionary)[k])
	return m


# 升一级后的模板（用于「升级效果变化」对比）
func levelup_diff(key: String, attribute: String, from_lv: int, delta: int) -> Dictionary:
	var before: Dictionary
	var after: Dictionary
	if attribute == "star":
		before = unit_template(key, -1, from_lv, "")
		after = unit_template(key, -1, clampi(from_lv + delta, 1, RULEZ.max_star()), "")
	else:
		before = unit_template(key, from_lv, -1, "")
		after = unit_template(key, clampi(from_lv + delta, 1, RULEZ.max_level()), -1, "")
	var rows: Array = []
	for k in ["max_hp", "atk", "def", "matk", "mdef", "luck", "move", "range"]:
		var b := int((before.get("stats", {}) as Dictionary).get(k, 0))
		var a := int((after.get("stats", {}) as Dictionary).get(k, 0))
		rows.append({"key": k, "label": String(RULEZ.STAT_LABELS.get(k, k)), "before": b, "after": a, "delta": a - b})
	return {"before": before, "after": after, "rows": rows}


# ------------------------------------------------------------
# 导出
# ------------------------------------------------------------
# mode: "full" 完整（含 ed_）/ "legacy" 旧工程格式（剥离 ed_）/ "mini" 精简战斗包
func export_data(mode: String = "full") -> Dictionary:
	var gens := {}
	for k in order:
		var g: Dictionary = generals[k].duplicate(true)
		if mode == "legacy" or mode == "mini":
			g.erase("ed_art")
			g.erase("ed_ranges")
			g.erase("ed_ext")
			g.erase("ed_note")
			g.erase("ed_tags")
			g.erase("ed_enabled")
			if mode == "mini":
				g.erase("ed_level")
				g.erase("ed_star")
				g.erase("ed_skill_lv")
				g.erase("ed_talent_lv")
		gens[k] = g
	var out := {
		"version": 2,
		"export_mode": mode,
		"exported_at": Time.get_datetime_string_from_system(false, true),
		"generals": gens,
		"skills": skills.duplicate(true),
		"talents": talents.duplicate(true),
	}
	if mode == "full":
		out["settings"] = RULEZ.settings.duplicate(true)
		out["art_library"] = library.duplicate(true)
	if mode == "mini":
		out["arm"] = RULEZ.get_d("arm_mods")
		out["counter"] = RULEZ.get_d("arm_counter")
	return out


func export_json_text(mode: String = "full") -> String:
	return JSON.stringify(export_data(mode), "  ", false)


# 导出成旧工程可直接使用的目录结构（generals.json / skills.json / talents.json / assets）
func export_to_dir(dir: String, mode: String = "full") -> Array[String]:
	var written: Array[String] = []
	dir = dir.rstrip("/").rstrip("\\")
	var gens := {}
	for k in order:
		var g: Dictionary = (export_data(mode)["generals"] as Dictionary).get(k, {})
		gens[k] = g
	if write_json(dir + "/generals.json", gens):
		written.append(dir + "/generals.json")
	if write_json(dir + "/skills.json", skills):
		written.append(dir + "/skills.json")
	if write_json(dir + "/talents.json", talents):
		written.append(dir + "/talents.json")
	if write_json(dir + "/settings.json", RULEZ.settings):
		written.append(dir + "/settings.json")
	return written


# 范围覆盖（兼容旧工程 data/range_override.json 结构）
func export_range_override() -> Dictionary:
	var out := {}
	for k in order:
		var g: Dictionary = generals[k]
		var er: Dictionary = g.get("ed_ranges", {})
		if er.is_empty():
			continue
		# 普攻形状 → basic.<key>.area
		if er.has("basic"):
			var ae: Dictionary = er["basic"]
			var ent := {}
			if ae.has("area"):
				ent["area"] = ae["area"]
			var layers := {}
			for lk in ae.keys():
				if String(lk).begins_with("layer_"):
					layers["lv_" + String(lk).substr(6)] = ae[lk]
			if not layers.is_empty():
				ent["layers"] = layers
			if not ent.is_empty():
				if not out.has("basic"):
					out["basic"] = {}
				out["basic"][k] = ent
		for sid in er.keys():
			if String(sid) == "basic":
				continue
			var se: Dictionary = er[sid]
			var entry: Dictionary = {"range": int(se.get("range", 1)), "cd": int(se.get("cd", 0))}
			if se.has("cast"):
				entry["cast"] = se["cast"]
			if se.has("area"):
				entry["area"] = se["area"]
			if se.has("radius"):
				entry["radius"] = int(se["radius"])
			out[String(sid)] = entry
	if not out.is_empty():
		out["wushuang_grow"] = 1
	return out


# ------------------------------------------------------------
# 贴图加载：新导入的图片可能还没被 Godot 导入，直接用 Image 解码，
# 并用「路径修改时间」做缓存键，图片换了也能刷新
# ------------------------------------------------------------
var _tex_cache: Dictionary = {}


func load_tex(path: String) -> Texture2D:
	if path == "":
		return null
	var abs := path
	if path.begins_with("res://") or path.begins_with("user://"):
		abs = ProjectSettings.globalize_path(path)
	var stamp := "0"
	if FileAccess.file_exists(abs):
		stamp = str(FileAccess.get_modified_time(abs))
	var key := path + "|" + stamp
	if _tex_cache.has(key):
		return _tex_cache[key]
	var tex: Texture2D = null
	if FileAccess.file_exists(abs) and not path.to_lower().ends_with(".svg"):
		var img := Image.load_from_file(abs)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null and ResourceLoader.exists(path):
		var r = load(path)
		if r is Texture2D:
			tex = r
	_tex_cache[key] = tex
	return tex


# ------------------------------------------------------------
# 图片导入：登记到素材库，并拷进 res://assets/imported/
# ------------------------------------------------------------
func import_art(src_path: String, kind: String, key: String) -> Dictionary:
	var src := src_path
	if not FileAccess.file_exists(src):
		return {"ok": false, "msg": "文件不存在：" + src}
	var ext := src.get_extension().to_lower()
	if not (ext in ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]):
		return {"ok": false, "msg": "不支持的图片格式：" + ext}
	var dst_dir := "res://assets/imported/%s" % kind
	var abs_dir := ProjectSettings.globalize_path(dst_dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var safe := key.replace("/", "_").replace("\\", "_")
	var dst := "%s/%s_%d.png" % [dst_dir, safe, int(Time.get_unix_time_from_system() * 1000.0)]
	var img := Image.load_from_file(src)
	if img == null or img.is_empty():
		return {"ok": false, "msg": "无法解码图片：" + src}
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var abs_dst := ProjectSettings.globalize_path(dst)
	var err := img.save_png(abs_dst)
	if err != OK:
		return {"ok": false, "msg": "写入失败（错误码 %d）：%s" % [err, abs_dst]}
	library[src] = {"kind": kind, "key": key, "res": dst, "size": [img.get_width(), img.get_height()]}
	dirty = true
	return {"ok": true, "res": dst, "size": img.get_size(), "msg": "已导入 %s（%dx%d）" % [dst, img.get_width(), img.get_height()]}


# 清理动画文件名：动作_朝向_序号（用于批量导入多个动作图）
static func anim_slot_key(act: String, dir: String) -> String:
	return "%s_%s" % [act, dir]


func get_anim(g: Dictionary, slot: String) -> Dictionary:
	var art = g.get("ed_art", {})
	if art is Dictionary:
		var anims = (art as Dictionary).get("anims", {})
		if anims is Dictionary and (anims as Dictionary).get(slot) is Dictionary:
			var a: Dictionary = (anims as Dictionary)[slot]
			var base := empty_anim()
			for k in a.keys():
				base[k] = a[k]
			return base
	return empty_anim()


func set_anim(g: Dictionary, slot: String, a: Dictionary) -> void:
	var art = g.get("ed_art", {})
	if not (art is Dictionary):
		return
	if not ((art as Dictionary).get("anims") is Dictionary):
		(art as Dictionary)["anims"] = {}
	((art as Dictionary).get("anims") as Dictionary)[slot] = a
	dirty = true


const SHEET_LABEL := {"atk": "攻击图", "mov": "移动图", "spc": "特殊图"}


# 安全取帧号数组（JSON 读回来是浮点，统一转 int；坏数据回退 [1]）
static func anim_frames(a: Dictionary) -> Array:
	var v = a.get("frames", [])
	var out: Array = []
	if v is Array:
		for x in v:
			var n := int(x)
			if n >= 1:
				out.append(n)
	if out.is_empty():
		out = [1]
	return out


# 空帧表（[1] 占位）视为「没设置过」，用说明里的默认帧号补齐
func _fill_default_frames(art: Dictionary) -> void:
	var spec := RULEZ.legacy_anim_spec()
	for act in spec.keys():
		for d in (spec[act] as Dictionary).keys():
			var slot := "%s_%s" % [act, d]
			var anims: Dictionary = art["anims"]
			var a: Dictionary = anims.get(slot, empty_anim())
			var fr := anim_frames(a)
			if fr.size() == 1 and int(fr[0]) == 1:
				var def: Dictionary = (spec[act] as Dictionary)[d]
				a["sheet"] = def["sheet"]
				a["frames"] = (def["frames"] as Array).duplicate()
				a["fps"] = def["fps"]
				a["loop"] = def["loop"]
				a["mirror"] = bool(def.get("mirror", false))
			anims[slot] = a


# 把读回来的动画数值统一成 int/float/bool
func _migrate_anim_numbers(art: Dictionary) -> void:
	art["frame_w"] = int(art.get("frame_w", 64))
	art["frame_h"] = int(art.get("frame_h", 64))
	var anims = art.get("anims", {})
	if not (anims is Dictionary):
		return
	for slot in (anims as Dictionary).keys():
		var a = (anims as Dictionary)[slot]
		if not (a is Dictionary):
			continue
		var d: Dictionary = a
		d["frames"] = anim_frames(d)
		d["fps"] = float(d.get("fps", 8.0))
		d["loop"] = bool(d.get("loop", true))
		d["mirror"] = bool(d.get("mirror", false))
		d["sheet"] = String(d.get("sheet", "mov"))
		(anims as Dictionary)[slot] = d


# 取某张图表（atk / mov / spc）的图片路径
func sheet_path(g: Dictionary, sheet: String) -> String:
	var art = g.get("ed_art", {})
	if art is Dictionary and (art as Dictionary).get("sheets") is Dictionary:
		return String(((art as Dictionary)["sheets"] as Dictionary).get(sheet, ""))
	return ""


# 导入三张动画图之一（atk / mov / spc），并按 帧宽×帧高 推算总帧数、修正越界帧号
func import_sheet_to(src_path: String, key: String, sheet: String, frame_w: int = 0, frame_h: int = 0) -> Dictionary:
	var r := import_art(src_path, "sprite", key)
	if not bool(r.get("ok", false)):
		return r
	var g: Dictionary = generals.get(key, {})
	if g.is_empty():
		return {"ok": false, "msg": "武将不存在"}
	var art: Dictionary = g["ed_art"]
	if not (art.get("sheets") is Dictionary):
		art["sheets"] = {"atk": "", "mov": "", "spc": ""}
	(art["sheets"] as Dictionary)[sheet] = String(r["res"])
	var sz = r.get("size", null)
	if not (sz is Vector2i):
		dirty = true
		return r
	var w := int(sz.x)
	var h := int(sz.y)
	var fw := frame_w if frame_w > 0 else int(art.get("frame_w", 64))
	var fh := frame_h if frame_h > 0 else int(art.get("frame_h", 64))
	if fw <= 0 or fw > w:
		fw = w
	if fh <= 0 or fh > h:
		fh = h
	# 旧规格：64 宽、N×64 高的竖直帧条
	if w == 64 and h % 64 == 0:
		fw = 64
		fh = 64
	art["frame_w"] = fw
	art["frame_h"] = fh
	if sheet == "mov" and String(art.get("sprite_path", "")) == "":
		art["sprite_path"] = String(r["res"])
	var total := maxi(1, (w / fw) * (h / fh))
	var anims: Dictionary = art["anims"] if art.get("anims") is Dictionary else {}
	for slot in anims.keys():
		var a2: Dictionary = anims[slot]
		if String(a2.get("sheet", "")) != sheet:
			continue
		var fr: Array = []
		for fn in (a2.get("frames", []) as Array):
			var fi := int(fn)
			if fi >= 1 and fi <= total:
				fr.append(fi)
		if fr.is_empty():
			fr = [1]
		a2["frames"] = fr
		anims[slot] = a2
	art["anims"] = anims
	dirty = true
	return {"ok": true, "res": r["res"], "total_frames": total,
		"msg": "已导入%s（%d×%d，按 %d×%d 切帧，共 %d 帧）" % [
			SHEET_LABEL.get(sheet, sheet), w, h, fw, fh, total]}


# 一次导入多张，按文件名前缀识别 atk / mov / spc
func import_all_sheets(paths: Array, key: String) -> Dictionary:
	var got: Array = []
	for pth in paths:
		var src := String(pth)
		if not FileAccess.file_exists(src):
			continue
		var base := src.get_file().get_basename().to_lower()
		var sheet := ""
		if base.begins_with("atk"):
			sheet = "atk"
		elif base.begins_with("mov"):
			sheet = "mov"
		elif base.begins_with("spc"):
			sheet = "spc"
		if sheet == "":
			continue
		var rr := import_sheet_to(src, key, sheet)
		if bool(rr.get("ok", false)):
			got.append("%s→%s" % [src.get_file(), SHEET_LABEL.get(sheet, sheet)])
	if got.is_empty():
		return {"ok": false, "msg": "没有识别到 atk / mov / spc 开头的图片"}
	return {"ok": true, "msg": "已导入：%s" % "，".join(got)}


# 恢复旧规格默认帧表
func reset_anim_spec(g: Dictionary) -> void:
	var art: Dictionary = g["ed_art"]
	art["anims"] = empty_art()["anims"]
	dirty = true


# 生成默认 key：ASCII 字母数字保留，中文字符转 uXXXX，保证唯一且可用于文件名
static func to_pinyin_like(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s.unicode_at(i)
		if (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57):
			out += char(c).to_lower()
		elif c == 95:
			out += "_"
		elif c < 128:
			out += "_"
		else:
			out += "u%04x" % c
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().lstrip("_")
	if out == "":
		out = "general"
	if out.length() > 48:
		out = out.substr(0, 48)
	return out
