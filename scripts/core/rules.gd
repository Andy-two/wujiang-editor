extends RefCounted
class_name EdRules

# ============================================================
# 战棋武将规则引擎（与 sango_wsz_proto / battle_state.gd 对齐）
#   - 面板数值：基础值 → 等级成长 → 星级倍率 → 兵种修正 → 天赋面板加成
#   - 五维（武/智/统/政/魅）：默认不参与战斗（扩展项，可开关）
#   - 伤害：atk*atk/(atk+def)*倍率 → 兵种克制 → 天赋/技能修正 → 暴击 → 随机浮动
#   - 范围：cast（释放距离）/ area（作用范围）逐格形状，支持旋转
# 所有可调参数集中在 EdRules 常量里，编辑器「全局设定」页可改并保存到 settings.json
# ============================================================

const ARMS := ["盾", "枪", "弓", "骑"]
const ARM_NAMES := {"盾": "盾兵", "枪": "枪兵", "弓": "弓兵", "骑": "骑兵"}
const ARM_ORDER := "盾→枪→马"
const FIVE_LABELS := {"wu": "武力", "zhi": "智力", "tong": "统率", "zheng": "政治", "mei": "魅力"}
const FIVE_KEYS := ["wu", "zhi", "tong", "zheng", "mei"]
const STAT_LABELS := {
	"hp": "兵力", "max_hp": "兵力", "atk": "物攻", "def": "物防", "matk": "谋攻", "mdef": "谋防",
	"luck": "幸运", "move": "移动", "range": "射程",
}
const SKILL_KINDS := ["single", "aoe", "control", "heal", "support", "self", "passive"]
const SKILL_KIND_NAMES := {
	"single": "单体伤害", "aoe": "范围伤害", "control": "伤害+控制", "heal": "治疗",
	"support": "支援", "self": "自身/增益", "passive": "被动",
}

# ---------------- 全局可调参数（settings.json） ----------------
const DEFAULTS := {
	"max_level": 50,
	"max_star": 10,
	"star_hp_bonus": 10.0,
	"star_stat_pct": 0.08,
	"star_move": 0,
	"arm_mods": {
		"盾": {"hp": 1.15, "def": 1.25, "mdef": 1.10, "atk": 0.95, "move": 0, "range": 0},
		"枪": {"hp": 1.05, "def": 1.05, "mdef": 1.00, "atk": 1.05, "move": 0, "range": 0},
		"弓": {"hp": 0.90, "def": 0.90, "mdef": 0.90, "atk": 1.10, "move": 0, "range": 0},
		"骑": {"hp": 1.00, "def": 0.95, "mdef": 0.95, "atk": 1.10, "move": 1, "range": 0},
	},
	"arm_counter": {"枪": ["骑"], "骑": ["弓"], "弓": ["盾"], "盾": ["枪"]},
	"arm_counter_bonus": 0.25,
	"arm_counter_reduce": 0.10,
	"crit_per_luck": 0.0,
	# 合并后的暴击系数：每点魅力 = 0.7% 暴击率（幸运与运势已合并为魅力一种属性）
	"crit_per_mei": 0.007,
	"crit_damage": 1.5,
	"mei_crit_per": 0.002,
	"mei_crit_dmg_per": 0.005,
	"damage_variance": 0.05,
	"min_damage": 1,
	# 破防保底系数：攻防基础不低于 攻×克制×该系数 + 1
	"damage_floor_k": 0.05,
	# 各类攻击倍率（公式表）
	"mult_basic": 1.0,
	"mult_counter": 0.8,
	"mult_combo": 0.5,
	"mult_pursuit": 1.0,
	# —— P3 机制参数 ——
	"max_combo_per_round": 2,   # 每单位每回合最多触发几次合击
	"combo_need_adjacent": 1,   # 合击是否要求与攻击者相邻（1=是）
	"heal_mult_default": 0.8,
	"douqi_per_stack": 0.05,
	"wushuang_mult": 1.15,
	"derive_five": true,
	"five_weight": 1.0,
	"growth": {"level_atk": 1, "level_def": 1, "level_matk": 1, "level_mdef": 1, "level_hp": 4},
	"growth_rate": {"wu": 1.0, "zhi": 1.0, "tong": 1.0, "zheng": 1.0, "mei": 1.0},
	"default_move": 4,
	"default_range": 1,
	# 动画默认值（精灵图导入用）
	"anim_fps_idle": 4.0,
	"anim_fps_walk": 8.0,
	"anim_fps_attack": 12.0,
	"anim_frame_w": 64,
	"anim_frame_h": 64,
	"anim_default_frames": 4,
}

# 动作（顺序即编辑器与导出里的顺序）
const ACTIONS := ["idle", "walk", "attack", "hurt", "die"]
const ACTION_LABELS := {
	"idle": "待机", "walk": "移动", "attack": "攻击", "hurt": "受击", "die": "死亡",
}
const ACTION_FPS_KEY := {"idle": "anim_fps_idle", "walk": "anim_fps_walk", "attack": "anim_fps_attack",
	"hurt": "anim_fps_attack", "die": "anim_fps_idle"}
# 朝向
const DIRS := ["down", "left", "right", "up"]
const DIR_LABELS := {"down": "下", "left": "左", "right": "右", "up": "上"}
const DIR_ARROWS := {"down": "↓", "left": "←", "right": "→", "up": "↑"}

# ------------------------------------------------------------
# 像素武将角色动画接入说明（旧工程 board_view.gd 采用的规格，1-based 帧号，自上而下）
#   atk64.png  12 帧 = 3 方向 × 各 4 帧：1-4 正面(下) / 5-8 背面(上) / 9-12 侧面(左，右用镜像)
#   mov64.png  11 帧：1-2 正面走 / 3-4 背面走 / 5-6 侧面走 / 7 正面待机 / 8 背面待机 /
#              9 侧面待机 / 10-11 受伤
#   spc64.png   5 帧独立单帧：1-3 防守(正/背/侧) / 4 受击 / 5 升级
#   「待机」= 对应方向的两帧慢速循环（7↔1 / 8↔3 / 9↔5）
# ------------------------------------------------------------
const SHEET_ATK := "atk"
const SHEET_MOV := "mov"
const SHEET_SPC := "spc"
const SHEET_LABELS := {"atk": "攻击图 atk64", "mov": "移动图 mov64", "spc": "特殊图 spc64"}

# 旧规格默认动作表：动作 -> 朝向 -> {sheet, frames(1-based 帧号数组), fps, loop}
static func legacy_anim_spec() -> Dictionary:
	return {
		"attack": {
			"down": {"sheet": SHEET_ATK, "frames": [1, 2, 3, 4], "fps": 12.0, "loop": false},
			"up": {"sheet": SHEET_ATK, "frames": [5, 6, 7, 8], "fps": 12.0, "loop": false},
			"left": {"sheet": SHEET_ATK, "frames": [9, 10, 11, 12], "fps": 12.0, "loop": false},
			"right": {"sheet": SHEET_ATK, "frames": [9, 10, 11, 12], "fps": 12.0, "loop": false, "mirror": true},
		},
		"walk": {
			"down": {"sheet": SHEET_MOV, "frames": [1, 2], "fps": 8.0, "loop": true},
			"up": {"sheet": SHEET_MOV, "frames": [3, 4], "fps": 8.0, "loop": true},
			"left": {"sheet": SHEET_MOV, "frames": [5, 6], "fps": 8.0, "loop": true},
			"right": {"sheet": SHEET_MOV, "frames": [5, 6], "fps": 8.0, "loop": true, "mirror": true},
		},
		"idle": {
			"down": {"sheet": SHEET_MOV, "frames": [7, 1], "fps": 2.0, "loop": true},
			"up": {"sheet": SHEET_MOV, "frames": [8, 3], "fps": 2.0, "loop": true},
			"left": {"sheet": SHEET_MOV, "frames": [9, 5], "fps": 2.0, "loop": true},
			"right": {"sheet": SHEET_MOV, "frames": [9, 5], "fps": 2.0, "loop": true, "mirror": true},
		},
		"hurt": {
			"down": {"sheet": SHEET_SPC, "frames": [4], "fps": 10.0, "loop": false},
			"up": {"sheet": SHEET_SPC, "frames": [4], "fps": 10.0, "loop": false},
			"left": {"sheet": SHEET_SPC, "frames": [4], "fps": 10.0, "loop": false},
			"right": {"sheet": SHEET_SPC, "frames": [4], "fps": 10.0, "loop": false, "mirror": true},
		},
		"die": {
			"down": {"sheet": SHEET_SPC, "frames": [4], "fps": 8.0, "loop": false},
			"up": {"sheet": SHEET_SPC, "frames": [4], "fps": 8.0, "loop": false},
			"left": {"sheet": SHEET_SPC, "frames": [4], "fps": 8.0, "loop": false},
			"right": {"sheet": SHEET_SPC, "frames": [4], "fps": 8.0, "loop": false, "mirror": true},
		},
	}

# 每级成长：每「等级」+1 点；每 5 级额外 +1 点（旧工程规则）
const GROWTH_EXTRA_EVERY := 5

# ============================================================
# 兵种基础表：移动力 / 攻击范围（射程）/ 面板系数
#   换兵种时武将「继承」兵种的移动与攻击范围；
#   只有技能/天赋明确写了加成时，才在兵种值上叠加。
# ============================================================
const ARM_BASE := {
	"盾": {"move": 5, "range": 1, "hp": 1.15, "atk": 0.95, "def": 1.25, "mdef": 1.10},
	"枪": {"move": 5, "range": 1, "hp": 1.05, "atk": 1.05, "def": 1.05, "mdef": 1.00},
	"弓": {"move": 4, "range": 2, "hp": 0.90, "atk": 1.10, "def": 0.90, "mdef": 0.90},
	"骑": {"move": 6, "range": 1, "hp": 1.00, "atk": 1.10, "def": 0.95, "mdef": 0.95},
}
const ARM_DEFAULT_MOVE := {"盾": 5, "枪": 5, "弓": 4, "骑": 6}
const ARM_DEFAULT_RANGE := {"盾": 1, "枪": 1, "弓": 2, "骑": 1}

# 兵种升级：升级点数由五维决定；每级可分配点数、每点加多少，均可调
const ARM_UPGRADE_DEFAULTS := {
	"max_lv": 20,                      # 兵种等级上限
	"five_pool": 0.5,                  # 总点数 = (五维之和)×该系数
	"per_lv_points": 1,                # 每级可得点数
	"point_hp": 0,                     # 每点 → 兵力（默认 0：兵种升级不加属性）
	"point_atk": 0,                    # 每点 → 物攻
	"point_def": 0,                    # 每点 → 物防
	"point_matk": 0,                   # 每点 → 谋攻
	"point_mdef": 0,                   # 每点 → 谋防
	"point_luck": 0,                   # 每点 → 幸运
	"lv_move_every": 0,                # 0 = 不加（每 N 级 +1 移动，后续再定）
	"lv_range_every": 0,               # 0 = 不加
}

# ============================================================
# 武将升级：每级增加五维（武/智/统/政/魅），不再直接加兵力攻防
# ============================================================
const FIVE_GROWTH_DEFAULTS := {
	"per_level": 1,                    # 每级五维各 +1
	"wu": 1, "zhi": 1, "tong": 1, "zheng": 1, "mei": 1,
	"cap": 100,                        # 五维上限
}

# ============================================================
# 升星规则（可调）
#   初始 1 星；2/3/4/6/7/9 星升「技能」（自选一个主动技能 +1 阶，最高 Lv3）；
#   5/10 星升「天赋」；8 星属性 +8%；每星都是消耗 1 个同名武将
# ============================================================
const STAR_DEFAULTS := {
	"max_star": 10,
	"skill_stars": [2, 3, 4, 6, 7, 9],
	"talent_stars": [5, 10],
	"stat_bonus_stars": {"8": 0.08},
	"stat_bonus_pct": 0.08,
	"cost_per_star": 1,                # 每星固定消耗同名武将数
	"cost_common": 1,                  # 兼容旧配置
	"cost_rare": 1,                    # 兼容旧配置
	"gacha_same_pity": 100,            # 抽卡保底（抽次数）——游戏侧使用
	"star_stat_pct": 0.08,             # 每星全属性 %
	"star_hp_bonus": 10,
}

# 扩展项占位：五维 → 属性映射（开关开启后才生效）
const FIVE_FOCUS := ["wu", "zhi", "tong", "zheng", "mei"]
const FIVE_FOCUS_LABELS := {
	"wu": "武·物攻", "zhi": "智·谋攻", "tong": "统·物防",
	"zheng": "政·谋防", "mei": "魅·幸运",
}

static var settings: Dictionary = DEFAULTS.duplicate(true)
static var RNG := RandomNumberGenerator.new()


static func load_settings(path: String = "res://data/editor/settings.json") -> Dictionary:
	settings = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_merge(settings, parsed)
	# 兵种基础值 / 兵种升级 / 升星规则 的默认值也并进 settings，
	# 这样界面读取、保存都能拿到完整数据（旧 settings.json 缺这些键也不会变 0）
	if not (settings.get("arm_base_move") is Dictionary):
		settings["arm_base_move"] = {}
	if not (settings.get("arm_base_range") is Dictionary):
		settings["arm_base_range"] = {}
	for arm in ["盾", "枪", "弓", "骑"]:
		var am: Dictionary = settings["arm_base_move"]
		if not am.has(arm) or int(am[arm]) <= 0:
			am[arm] = int(ARM_DEFAULT_MOVE.get(arm, 4))
		settings["arm_base_move"] = am
		var ar: Dictionary = settings["arm_base_range"]
		if not ar.has(arm):
			ar[arm] = int(ARM_DEFAULT_RANGE.get(arm, 1))
		settings["arm_base_range"] = ar
	# 兵种升级参数
	var au: Dictionary = settings.get("arm_upgrade", {}) if settings.get("arm_upgrade") is Dictionary else {}
	for k in ARM_UPGRADE_DEFAULTS.keys():
		if not au.has(k):
			au[k] = ARM_UPGRADE_DEFAULTS[k]
	settings["arm_upgrade"] = au
	# 升星规则
	var sr: Dictionary = settings.get("star_rule", {}) if settings.get("star_rule") is Dictionary else {}
	for k in STAR_DEFAULTS.keys():
		if not sr.has(k):
			sr[k] = STAR_DEFAULTS[k]
	settings["star_rule"] = sr
	# 抽卡命中率
	if not settings.has("gacha_rate_same"):
		settings["gacha_rate_same"] = 0.05
	# 武将升级五维成长
	var fg: Dictionary = settings.get("five_growth", {}) if settings.get("five_growth") is Dictionary else {}
	for k in FIVE_GROWTH_DEFAULTS.keys():
		if not fg.has(k):
			fg[k] = FIVE_GROWTH_DEFAULTS[k]
	settings["five_growth"] = fg
	return settings


# ============================================================
# 五维 → 面板属性换算（统帅体系）
#   武力 → 物攻 / 兵力(少量)
#   智力 → 谋攻 / 谋防
#   统率 → 兵力 / 物防
#   政治 → 谋防 / 兵力(少量)
#   魅力 → 幸运(暴击率) / 暴击伤害
# ============================================================
const FIVE_TO_STAT := {
	"atk_wu": 1.30, "matk_zhi": 1.30,
	"hp_tong": 12.0, "hp_wu": 2.0, "hp_zheng": 1.5,
	"def_tong": 0.55, "mdef_zheng": 0.52, "mdef_zhi": 0.18,
	"luck_mei": 0.62,
}


static func stat_from_fives(fives: Dictionary) -> Dictionary:
	var f := FIVE_TO_STAT
	var wu := float(fives.get("wu", 0))
	var zhi := float(fives.get("zhi", 0))
	var tong := float(fives.get("tong", 0))
	var zheng := float(fives.get("zheng", 0))
	var mei := float(fives.get("mei", 0))
	return {
		"atk": int(round(wu * float(f["atk_wu"]))),
		"matk": int(round(zhi * float(f["matk_zhi"]))),
		"max_hp": int(round(tong * float(f["hp_tong"]) + wu * float(f["hp_wu"]) + zheng * float(f["hp_zheng"]))),
		"def": int(round(tong * float(f["def_tong"]))),
		"mdef": int(round(zheng * float(f["mdef_zheng"]) + zhi * float(f["mdef_zhi"]))),
		# 幸运 = 魅力（已与运势合并为一种属性），面板上仅作展示
		"luck": clampi(int(round(mei)), 1, 200),
	}


# 成长曲线：五维越高成长越快（S/A/B/C 档）
#   返回倍率：五维 90+ → 1.35，70~89 → 1.2，50~69 → 1.05，30~49 → 0.95，<30 → 0.85
static func growth_mult_by_five(v: float) -> float:
	if v >= 90.0:
		return 1.35
	elif v >= 70.0:
		return 1.20
	elif v >= 50.0:
		return 1.05
	elif v >= 30.0:
		return 0.95
	return 0.85


# 某项属性每级成长量（受对应五维影响）
static func level_growth_for(base_fives: Dictionary, stat: String) -> float:
	var fg: Dictionary = settings.get("five_growth", {}) if settings.get("five_growth") is Dictionary else {}
	var per := float(fg.get("per_level", 1))
	match stat:
		"atk":
			return per * float(FIVE_TO_STAT["atk_wu"]) * growth_mult_by_five(float(base_fives.get("wu", 50)))
		"matk":
			return per * float(FIVE_TO_STAT["matk_zhi"]) * growth_mult_by_five(float(base_fives.get("zhi", 50)))
		"max_hp":
			return per * float(FIVE_TO_STAT["hp_tong"]) * growth_mult_by_five(float(base_fives.get("tong", 50)))
		"def":
			return per * float(FIVE_TO_STAT["def_tong"]) * growth_mult_by_five(float(base_fives.get("tong", 50)))
		"mdef":
			return per * float(FIVE_TO_STAT["mdef_zheng"]) * growth_mult_by_five(float(base_fives.get("zheng", 50)))
		"luck":
			return per * float(FIVE_TO_STAT["luck_mei"]) * growth_mult_by_five(float(base_fives.get("mei", 50)))
	return per


# ============================================================
# 战力（Combat Power）：综合面板、五维、技能、星级
# ============================================================
static func combat_power(t: Dictionary) -> int:
	var st: Dictionary = t.get("stats", {}) if t.get("stats") is Dictionary else {}
	var fives: Dictionary = t.get("fives", {}) if t.get("fives") is Dictionary else {}
	var lv := int(t.get("level", 1))
	var star := int(t.get("star", 1))
	# 1) 面板战力
	var p_hp := float(st.get("max_hp", 0)) * 0.6
	var p_atk := float(st.get("atk", 0)) * 4.0
	var p_def := float(st.get("def", 0)) * 3.0
	var p_matk := float(st.get("matk", 0)) * 4.0
	var p_mdef := float(st.get("mdef", 0)) * 3.0
	var p_luck := float(st.get("luck", 0)) * 1.5
	var p_move := float(st.get("move", 0)) * 12.0
	var p_range := float(st.get("range", 0)) * 18.0
	var base_power := p_hp + p_atk + p_def + p_matk + p_mdef + p_luck + p_move + p_range
	# 2) 五维战力（质变项）
	var five_sum := 0.0
	for k in ["wu", "zhi", "tong", "zheng", "mei"]:
		five_sum += float(fives.get(k, 0))
	var five_power := five_sum * 14.0
	# 3) 技能战力
	var skills: Array = t.get("skills", []) if t.get("skills") is Array else []
	var skill_power := 0.0
	var slv: Dictionary = t.get("skill_lv", {}) if t.get("skill_lv") is Dictionary else {}
	for sid in skills:
		skill_power += 40.0 + 25.0 * float(int(slv.get(String(sid), 1)))
	# 4) 等级系数 + 星级系数（升星大幅提升）
	var lv_mult := 1.0 + float(lv - 1) * 0.012
	var star_mult := 1.0 + pow(float(star - 1), 1.55) * 0.16
	var total := (base_power + five_power + skill_power) * lv_mult * star_mult
	return int(round(total))


# 等级/星级下的战力（给界面做预览与对比）
static func power_at(t: Dictionary, lv: int, star: int) -> int:
	var tt: Dictionary = t.duplicate(true)
	tt["level"] = lv
	tt["star"] = star
	# 按等级缩放主要面板（简化：用每级成长率）
	var g := 1.0 + float(lv - 1) * 0.045
	var st: Dictionary = tt.get("stats", {})
	for k in ["atk", "matk", "def", "mdef", "luck"]:
		st[k] = int(round(float(st.get(k, 0)) * g))
	st["max_hp"] = int(round(float(st.get("max_hp", 0)) * g))
	tt["stats"] = st
	# 星级加成
	var sb := 1.0 + pow(float(star - 1), 1.55) * 0.05
	for k in ["atk", "matk", "def", "mdef"]:
		st[k] = int(round(float(st.get(k, 0)) * sb))
	st["max_hp"] = int(round(float(st.get("max_hp", 0)) * sb))
	tt["stats"] = st
	return combat_power(tt)


# 武将升级带来的五维成长：等级 Lv 时五维各加多少
static func five_growth_of(lv: int) -> Dictionary:
	var fg: Dictionary = settings.get("five_growth", {}) if settings.get("five_growth") is Dictionary else {}
	var per := maxi(0, int(lv) - 1)
	var out := {}
	for k in ["wu", "zhi", "tong", "zheng", "mei"]:
		out[k] = per * int(fg.get(k, fg.get("per_level", 1)))
	return out


# 等级 Lv 时的五维（基础五维 + 升级成长，封顶）
static func fives_at(base_fives: Dictionary, lv: int) -> Dictionary:
	var fg: Dictionary = settings.get("five_growth", {}) if settings.get("five_growth") is Dictionary else {}
	var cap := int(fg.get("cap", 100))
	var add := five_growth_of(lv)
	var out := {}
	for k in ["wu", "zhi", "tong", "zheng", "mei"]:
		out[k] = clampi(int(base_fives.get(k, 0)) + int(add.get(k, 0)), 0, maxi(cap, int(base_fives.get(k, 0))))
	return out


static func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over.keys():
		if base.get(k) is Dictionary and over[k] is Dictionary:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]


static func get_i(key: String) -> int:
	return int(settings.get(key, DEFAULTS.get(key, 0)))


static func get_f(key: String) -> float:
	return float(settings.get(key, DEFAULTS.get(key, 0.0)))


static func get_d(key: String) -> Dictionary:
	var v = settings.get(key, {})
	return v if v is Dictionary else {}


static func get_b(key: String) -> bool:
	return bool(settings.get(key, DEFAULTS.get(key, false)))


static func get_s(key: String) -> String:
	return String(settings.get(key, DEFAULTS.get(key, "")))


static func max_level() -> int:
	return maxi(1, get_i("max_level"))


static func max_star() -> int:
	return maxi(1, get_i("max_star"))


static func arm_mods(arm: String) -> Dictionary:
	var mods := get_d("arm_mods")
	var base := {"hp": 1.0, "def": 1.0, "mdef": 1.0, "atk": 1.0, "move": 0, "range": 0}
	var ab: Dictionary = ARM_BASE.get(arm, {})
	for k in ["hp", "atk", "def", "mdef"]:
		if ab.has(k):
			base[k] = ab[k]
	var v = mods.get(arm, null)
	if v is Dictionary:
		var d: Dictionary = v
		for k in d.keys():
			base[k] = d[k]
	return base


# 兵种基础移动 / 攻击范围（换兵种时武将继承这两个值）
static func arm_base_move(arm: String) -> int:
	var m := get_d("arm_base_move")
	if m.has(arm):
		return int(m[arm])
	return int(ARM_DEFAULT_MOVE.get(arm, 4))


static func arm_base_range(arm: String) -> int:
	var m := get_d("arm_base_range")
	if m.has(arm):
		return int(m[arm])
	return int(ARM_DEFAULT_RANGE.get(arm, 1))


# ---------------- 兵种升级 ----------------
# 说明：兵种升级「不直接加兵力/攻防」等面板数值，具体功效后续再设计；
# 这里只保留等级、升级点数（点数上限与五维挂钩）与每 N 级的移动/射程小步进，
# 属性加成默认全为 0，等定好功效后在「⑪ 全局设定」里再开。
static func arm_up() -> Dictionary:
	var out := ARM_UPGRADE_DEFAULTS.duplicate(true)
	var over := get_d("arm_upgrade")
	if over is Dictionary:
		for k in (over as Dictionary).keys():
			out[k] = over[k]
	return out


# 升到某等级「累计」可分配点数 = min(五维总和×系数, (等级-1)×每级点数)
static func arm_points_total(fives: Dictionary, lv: int) -> int:
	var up := arm_up()
	var sum5 := 0
	for k in ["wu", "zhi", "tong", "zheng", "mei"]:
		sum5 += int(fives.get(k, 0))
	var pool := int(floor(float(sum5) * float(up.get("five_pool", 0.5))))
	var from_lv := maxi(0, int(lv) - 1) * int(up.get("per_lv_points", 1))
	return mini(pool, from_lv)


# 兵种升级加成：spend = {hp:点数, atk:..., def:..., matk:..., mdef:..., luck:...}
static func arm_upgrade_stats(lv: int, spend: Dictionary) -> Dictionary:
	var up := arm_up()
	return {
		"max_hp": int(spend.get("hp", 0)) * int(up.get("point_hp", 0)),
		"atk": int(spend.get("atk", 0)) * int(up.get("point_atk", 0)),
		"def": int(spend.get("def", 0)) * int(up.get("point_def", 0)),
		"matk": int(spend.get("matk", 0)) * int(up.get("point_matk", 0)),
		"mdef": int(spend.get("mdef", 0)) * int(up.get("point_mdef", 0)),
		"luck": int(spend.get("luck", 0)) * int(up.get("point_luck", 0)),
		"move": (int(int(lv) / maxi(1, int(up.get("lv_move_every", 5)))) if int(up.get("lv_move_every", 0)) > 0 else 0),
		"range": (int(int(lv) / maxi(1, int(up.get("lv_range_every", 10)))) if int(up.get("lv_range_every", 0)) > 0 else 0),
	}


# ============================================================
# 副将（vice）数值层
#   副将数据见 data/vice_generals.json，每个副将的数值成分为：
#     ① taolue   韬略文案（如「提升1.5%物攻」），纯数值加成
#     ② stats    属性百分比加成（hp/atk/def/matk/mdef）
#     ③ dmg      伤害加成百分比
#   本段只负责把①②③换算成「对主将模板的修正量」，不含任何机制效果。
# ============================================================

# 韬略文案 -> 修正键。值为「乘区键」，对应的数值从文案里的百分数解析。
#   属性类：stat_hp / stat_atk / stat_def / stat_matk / stat_mdef
#   战斗类：damage_bonus（通用增伤）/ damage_cut（通用减伤）
#           crit_damage（暴伤加成）/ crit_resist（暴击抗性）
#           skill_damage（技策伤害）/ normal_damage（普攻伤害）
#           counter_damage（反击伤害）/ combo_damage（合击伤害）
#           fixed_damage（固伤伤害）/ restrict_damage（克制伤害）
#           skill_cut（受技策伤害减免）/ counter_cut（受反击减免）
#           heal_bonus（治疗加成）/ heal_taken（受疗加成）
#           fortune_add（运势加点，非百分比）
#   注意：这里只登记「这条文案影响哪个乘区」，具体数值从文案里正则解析，
#         这样数据侧改文案数值时不用动代码。
const VICE_TAOLUE_KEYS := {
	# 顺序敏感：先匹配「具体的」，再匹配「泛化的」。
	# 因为 parse_taolue 用 contains 且取第一个命中，例如
	# 「战斗中技能伤害提升1.5%」必须命中 skill_damage 而不是 damage_bonus。
	"受到技能伤害减免": "skill_cut",
	"受到伤害减免": "damage_cut",
	"受到反击伤害降低": "counter_cut",
	"受到治疗效果提升": "heal_taken",
	"技能伤害提升": "skill_damage",
	"普攻伤害提升": "normal_damage",
	"克制伤害提升": "restrict_damage",
	"反击伤害增加": "counter_damage",
	"合击伤害增加": "combo_damage",
	"固定伤害": "fixed_damage",
	"暴击抗性": "crit_resist",
	"暴击伤害": "crit_damage",
	"治疗效果": "heal_bonus",
	"伤害提升": "damage_bonus",
	"点运势": "fortune_add",
	"运势": "fortune_add",
	"兵力": "stat_hp",
	"物攻": "stat_atk",
	"谋攻": "stat_matk",
	"物防": "stat_def",
	"谋防": "stat_mdef",
}


# 从文案里取第一个百分数（「提升1.5%物攻」-> 0.015）；取不到返回 -1
static func pct_in(text: String) -> float:
	var re := RegEx.new()
	re.compile("([0-9]+(?:\\.[0-9]+)?)%")
	var m := re.search(text)
	if m == null:
		return -1.0
	return float(m.get_string(1)) / 100.0


# 从文案里取第一个不带 % 的整数（「战斗中提升20点运势」-> 20）
static func int_in(text: String) -> int:
	var re := RegEx.new()
	re.compile("([0-9]+)")
	var m := re.search(text)
	if m == null:
		return 0
	return int(m.get_string(1))


# 解析一条韬略文案 -> {"key": 乘区键, "value": 数值}，无法识别返回空字典
#   文案可能带前缀（如「重击：战斗中伤害提升2%」），所以用 contains 匹配
static func parse_taolue(text: String) -> Dictionary:
	var t := text.strip_edges()
	for pat in VICE_TAOLUE_KEYS.keys():
		if not t.contains(String(pat)):
			continue
		var key := String(VICE_TAOLUE_KEYS[pat])
		if key == "fortune_add":
			return {"key": key, "value": float(int_in(t))}
		var p := pct_in(t)
		if p < 0.0:
			return {}
		return {"key": key, "value": p}
	return {}


# 把一个副将数据换算成修正量字典
#   {"stat": {stat_hp: 0.015, ...}, "mul": {damage_bonus: 0.02, ...}, "dmg": 0.03}
static func vice_modifiers(vice: Dictionary, lv: int = 1) -> Dictionary:
	var stat := {}
	var mul := {}
	var flat := {}
	# ① taolue（韬略百分比加成，来自文案）
	for line in (vice.get("taolue", []) as Array):
		var p := parse_taolue(String(line))
		if p.is_empty():
			continue
		var key := String(p["key"])
		var val := float(p["value"])
		if key.begins_with("stat_"):
			var sk := key.substr(5)
			stat[sk] = float(stat.get(sk, 0.0)) + val
		else:
			mul[key] = float(mul.get(key, 0.0)) + val
	# ② 固定属性 base_attr / max_attr（官方 API）：
	#    按副将等级在 1 级值与满级值之间线性插值，满级约 25 级。
	#    这是「固定数值加成」，不是百分比，单独放进 flat。
	var base: Dictionary = vice.get("base_attr", {}) if vice.get("base_attr") is Dictionary else {}
	var maxa: Dictionary = vice.get("max_attr", {}) if vice.get("max_attr") is Dictionary else {}
	var lvc := clampi(lv, 1, 25)
	var t := float(lvc - 1) / 24.0
	for k in ["hp", "atk", "def", "matk", "mdef", "cri"]:
		var b := float(base.get(k, 0.0))
		var m := float(maxa.get(k, 0.0))
		if b == 0.0 and m == 0.0:
			continue
		flat[k] = int(round(b + (m - b) * t))
	# ③ 兼容旧字段 stats / dmg（百分比，若数据里还保留）
	var vs: Dictionary = vice.get("stats", {}) if vice.get("stats") is Dictionary else {}
	for k2 in vs.keys():
		var sk2 := String(k2)
		stat[sk2] = float(stat.get(sk2, 0.0)) + float(vs[k2]) / 100.0
	var dmg := float(vice.get("dmg", 0.0)) / 100.0
	if dmg != 0.0:
		mul["damage_bonus"] = float(mul.get("damage_bonus", 0.0)) + dmg
	return {"stat": stat, "mul": mul, "flat": flat, "dmg": dmg}


# ---------------- 升星 ----------------
static func star_rule() -> Dictionary:
	var out := STAR_DEFAULTS.duplicate(true)
	var over := get_d("star_rule")
	if over is Dictionary:
		for k in (over as Dictionary).keys():
			out[k] = over[k]
	return out


# 升到 to_star 星时升什么：talent / skill / stat / none
static func star_upgrade_kind(to_star: int) -> String:
	var r := star_rule()
	# JSON 读回来的星号可能是浮点（2.0），统一按 int 比较
	for x in (r.get("talent_stars", []) as Array):
		if int(x) == int(to_star):
			return "talent"
	for x in (r.get("skill_stars", []) as Array):
		if int(x) == int(to_star):
			return "skill"
	var sb = r.get("stat_bonus_stars", {})
	if sb is Dictionary and (sb as Dictionary).has(str(int(to_star))):
		return "stat"
	return "none"


static func star_label(to_star: int) -> String:
	match star_upgrade_kind(to_star):
		"talent":
			return "天赋升阶"
		"skill":
			return "技能升阶"
		"stat":
			return "属性提升"
	return "无"


static func star_cost(_to_star: int) -> int:
	# 每星升级条件都是 1 个同名武将
	return int(star_rule().get("cost_per_star", 1))


# ============================================================
# 技能「效果块」系统：技能的实际效果由若干效果块按顺序执行
# ============================================================
const SFX_DAMAGE := "damage"          # 造成伤害（物/谋，倍率）
const SFX_HEAL := "heal"              # 为友军回复兵力
const SFX_DEBUFF := "debuff"          # 对敌军施加状态
const SFX_BUFF := "buff"              # 对友军施加增益
const SFX_PUSH := "push"              # 击退
const SFX_DISPEL := "dispel"          # 驱散敌方增益
const SFX_SELF_DISPEL := "self_dispel" # 净化自身减益
const SFX_SELF_HEAL := "self_heal"    # 自身回复
const SFX_CD_DOWN := "cd_down"        # 自身技策准备期 -N
const SFX_EXTRA_MOVE := "extra_move"  # 获得再移动
# —— 扩充：常见战棋机制 ——
const SFX_DRAIN := "drain"            # 吸血（造成伤害的百分比回复自身）
const SFX_SHIELD := "shield"          # 套护盾
const SFX_DOT := "dot"                # 持续伤害
const SFX_HOT := "hot"                # 持续回复
const SFX_STUN := "stun"              # 眩晕（跳过行动）
const SFX_TAUNT := "taunt"            # 嘲讽
const SFX_SILENCE := "silence"        # 封技
const SFX_DISARM := "disarm"          # 缴械
const SFX_SUMMON := "summon"          # 召唤援军
const SFX_TELEPORT := "teleport"      # 位移 / 换位
const SFX_EXTRA_TURN := "extra_turn"  # 额外行动一次
const SFX_REVIVE := "revive"          # 复活
const SFX_CRIT_UP := "crit_up"        # 提升暴击率
const SFX_LIFELINK := "lifelink"      # 伤害分摊
const SFX_COPY_BUFF := "copy_buff"    # 复制目标增益
const SFX_STEAL_BUFF := "steal_buff"  # 偷取目标增益
const SFX_FIXED := "fixed"            # 固伤（无视防御与常规增伤）
const SFX_NO_COUNTER := "no_counter"  # 本次攻击无法被反击
# —— P0 机制 ——
const SFX_PURSUIT := "pursuit"        # 追击（附加一次额外伤害，不触发合击/反击）
const SFX_ZHANYI := "zhanyi"          # 战意回复（正）/ 降低（负）
# —— P1 机制 ——
const SFX_COUNTER_UP := "counter_up"  # 反击增强（倍率/减伤/次数）
const SFX_SWITCH := "switch_skill"    # 技能形态切换（切换为 / 升级至）
# —— P2 机制 ——
const SFX_RESOURCE := "resource"      # 资源层数（智/深谋/斗气/机巧/备战/武魂…）
const SFX_CONSUME := "consume"        # 消耗资源
const SFX_ZOC := "zoc"                # 阻挡领域（ZOC）
# —— P3 机制 ——
const SFX_PRIORITY := "priority"      # 先攻（抢先出手：本回合首次行动优先）
const SFX_BLOCK := "block"           # 格挡（按概率免伤 / 减伤）
const SFX_DODGE := "dodge"            # 闪避（按概率完全回避一次攻击）
const SFX_IMMUNITY := "immunity"      # 免疫（免疫控制 / 属性减益 / 移动减益 / 地形减益）
const SFX_RESIST := "resist"          # 抵抗（每回合首次抵抗某类减益）
const SFX_COMBO := "combo"            # 合击（对同目标的相邻友军联合攻击）
# —— P5 机制 ——
const SFX_SPLASH := "splash"          # 溅射（对目标周围一圈的其它敌人造成伤害）
# —— P6 机制 ——
const SFX_TRANSFER := "transfer"      # 转移（把降低的战意转移给友军）
const SFX_FACILITY := "facility"      # 设施（可交互的召唤物，如粮仓/营寨）
const SFX_STEAL := "steal"            # 偷取（战意/资源）
const SFX_MUST_LAST := "must_last"    # 必定后手攻击
const SFX_LIFELINK_HIT := "lifesteal" # 攻心（造成的伤害按比例回血）
const SFX_EXECUTE := "execute"        # 处决/斩杀（低血秒杀）
const SFX_TRAIT := "trait"            # 按性格/兵种筛选生效
const SFX_FIRST_STRIKE := "first_strike"  # 先攻（兼容旧数据）

const SFX_TYPES := [SFX_DAMAGE, SFX_HEAL, SFX_DEBUFF, SFX_BUFF, SFX_PUSH,
	SFX_DISPEL, SFX_SELF_DISPEL, SFX_SELF_HEAL, SFX_CD_DOWN, SFX_EXTRA_MOVE,
	SFX_DRAIN, SFX_SHIELD, SFX_DOT, SFX_HOT, SFX_STUN, SFX_TAUNT,
	SFX_SILENCE, SFX_DISARM, SFX_SUMMON, SFX_TELEPORT, SFX_EXTRA_TURN,
	SFX_REVIVE, SFX_CRIT_UP, SFX_LIFELINK, SFX_COPY_BUFF, SFX_STEAL_BUFF, SFX_FIXED,
	SFX_NO_COUNTER, SFX_PURSUIT, SFX_ZHANYI, SFX_COUNTER_UP, SFX_SWITCH,
	SFX_RESOURCE, SFX_CONSUME, SFX_ZOC,
	SFX_PRIORITY, SFX_BLOCK, SFX_DODGE, SFX_IMMUNITY, SFX_RESIST, SFX_COMBO,
	SFX_SPLASH, SFX_TRANSFER, SFX_FACILITY]

# 资源名（用于层数系统）
const RESOURCES := ["智", "深谋", "斗气", "机巧", "备战", "武魂", "凤羽", "凤衣", "威严", "被动层数"]
const SFX_LABELS := {
	SFX_DAMAGE: "造成伤害", SFX_HEAL: "治疗友军", SFX_DEBUFF: "施加减益状态",
	SFX_BUFF: "施加增益状态", SFX_PUSH: "击退", SFX_DISPEL: "驱散敌方增益",
	SFX_SELF_DISPEL: "净化自身减益", SFX_SELF_HEAL: "自身回复", SFX_CD_DOWN: "自身准备期 -N",
	SFX_EXTRA_MOVE: "获得再移动",
	SFX_DRAIN: "吸血（伤害转回复）", SFX_SHIELD: "套护盾", SFX_DOT: "持续伤害",
	SFX_HOT: "持续回复", SFX_STUN: "眩晕（跳过行动）", SFX_TAUNT: "嘲讽",
	SFX_SILENCE: "封技", SFX_DISARM: "缴械", SFX_SUMMON: "召唤援军",
	SFX_TELEPORT: "位移 / 换位", SFX_EXTRA_TURN: "额外行动一次", SFX_REVIVE: "复活",
	SFX_CRIT_UP: "提升暴击率", SFX_LIFELINK: "伤害分摊", SFX_COPY_BUFF: "复制目标增益",
	SFX_STEAL_BUFF: "偷取目标增益",
	SFX_FIXED: "固定伤害（无视防御）",
	SFX_NO_COUNTER: "本次攻击无法被反击",
	SFX_PURSUIT: "追击（附加一次伤害）",
	SFX_ZHANYI: "战意变化",
	SFX_COUNTER_UP: "反击增强",
	SFX_SWITCH: "技能形态切换",
	SFX_RESOURCE: "资源层数",
	SFX_CONSUME: "消耗资源",
	SFX_ZOC: "阻挡领域",
	SFX_PRIORITY: "先攻",
	SFX_BLOCK: "格挡",
	SFX_DODGE: "闪避",
	SFX_IMMUNITY: "免疫",
	SFX_RESIST: "抵抗",
	SFX_COMBO: "合击",
	SFX_SPLASH: "溅射",
	SFX_TRANSFER: "转移",
	SFX_FACILITY: "设施",
}
# 常用状态名（可自由输入其它名字）
const COMMON_STATUS := ["低迷", "虚弱", "定身", "眩晕", "撕裂", "溃逃", "缴械", "封技",
	"识破", "破绽", "苍引", "牵制·贰", "迷阵", "挑衅", "惊慌", "胆怯",
	"昂扬", "坚壁", "严阵", "护盾", "装填", "神威", "龙行",
	# 官方技能里出现的状态（按截图补充）
	"坚甲·壹", "坚甲·贰", "破甲·壹", "破甲·贰", "破竹·壹", "破竹·贰",
	"强运·壹", "强运·贰", "灰心·壹", "灰心·贰", "疾行·壹", "疾行·贰",
	"奋兵·壹", "奋兵·贰", "破军·壹", "破军·贰", "回锋·壹", "回锋·贰",
	"偷袭", "恶路移动", "奋勇·壹", "奋勇·贰", "胄击", "冲阵",
	"展旗·壹", "擂鼓·壹", "鸣金·壹", "将令", "胆怯·贰", "低迷·贰",
	"破坏", "阻挡领域", "继续行动", "继续移动",
	# 小乔 / 大乔 系（按截图补充）
	"风蚀", "风护", "风牢", "火牢", "印·风旋",
	"激昂", "定心·贰", "昂扬·壹", "严阵·壹",
	# 孙权 / 周瑜 系（按截图补充）
	"妙策·壹", "失智·壹", "高级护盾", "灼烧", "业刃", "连营", "火势", "余烬",
	"印·业火",
	# 孙策 / 张星彩 系（按截图补充）
	"备战", "怯战", "虎踞", "凤羽", "凤衣", "牵制·叁", "牵制·壹",
	"虚弱·壹", "钝兵·壹",
	# 黄月英 / 马云禄 系（按截图补充）
	"架设", "机巧", "溃逃", "撕裂", "溃散", "闪避", "苍引", "牵制·肆",
	# 牵招 / 魏延 系（按截图补充）
	"地劣", "缠缚", "拒锐", "战威", "穿坚", "高垒", "松懈·壹", "牵制·贰",
	"缴械", "封技",
	# 庞统 / 孙尚香 / 黄忠 系（按截图补充）
	"连环", "高级失智", "枭姬卫", "警戒区域", "寒步",
	# 黄忠 / 马超 系（按截图补充）
	"逸待", "推锋", "蓄锐", "标定", "暴露", "压制", "破绽·贰",
	"强运·壹", "奋兵·壹",
	# 马超 / 诸葛亮 系（按截图补充）
	"勇驾", "哀士", "混乱",
	# 赵云 / 张飞 / 关羽 系（按截图补充）
	"龙行", "龙胆", "格挡", "高级低迷", "高级奋勇", "武魂",
	# 刘禅 / 张春华 / 吕玲绮 / 蔡文姬 系（按截图补充）
	"可升级减益", "丧智·壹", "丧智·贰", "固厄", "断局",
	"余韵：归旋", "余韵：离愁", "余韵：忘忧", "专注", "牵绊",
	"高级昂扬", "高级坚甲", "高级严阵", "高级胆怯", "高级虚弱",
	# 陈到 / 张绣 / 甄宓 / 司马懿 / 陈群 系（按截图补充）
	"寒芒", "游龙", "深谋", "溃局", "绝阵一级", "绝阵二级", "绝阵三级",
	"虞视", "疑忌", "断粮", "武略", "营寨", "特殊地形",
	# 庞德 / 马超 / 陈群 系（按截图补充）
	"棺梓", "山峙", "协守", "死志", "镇军", "松懈·贰", "破绽·壹",
	# 许褚 / 贾诩 / 张辽 / 荀攸 系（按截图补充）
	"裸衣", "鏖战", "坚韧·贰", "免疫控制", "免疫属性减益",
	"哗变", "中毒", "智", "破军", "高级低迷", "高级松懈",
	# 郭嘉 / 典韦 / 曹洪 系（按截图补充）
	"御敌", "折冲", "恶", "威严", "迟钝", "重创", "断粮", "失智·贰",
	# 程昱 / 荀彧 / 曹仁 系（按截图补充）
	"刚毅", "诡谋", "天人之勇", "节命", "免疫移动减益",
	# 夏侯渊 / 夏侯惇 / 曹操 系（按截图补充）
	"鞭策", "先攻", "胆怯·壹", "虚弱·壹", "胆怯·贰", "虚弱·贰",
	# 刘备 / 甘梅 / 糜竺 / 简雍 系（按截图补充）
	"集智·壹", "倒戈", "低迷·壹",
	# 陈群 / 陈登 系（按截图补充）
	"免疫地形减益", "奋强", "粮仓",
	# 刘晔 / 李典 / 曹洪 系（按截图补充）
	"流火", "炼狱", "增援", "松懈·壹", "高级断粮",
	"偷袭", "恶路移动"]

static func default_sfx(type: String) -> Dictionary:
	match type:
		SFX_DAMAGE:
			return {"type": type, "value": 1.0, "magic": false, "times": 1, "ignore_def": 0.0}
		SFX_HEAL:
			return {"type": type, "value": 0.8}
		SFX_DEBUFF:
			return {"type": type, "value": "", "turns": 2, "stacks": 1}
		SFX_BUFF:
			return {"type": type, "value": "", "turns": 2, "stacks": 1}
		SFX_PUSH:
			return {"type": type, "value": 1}
		SFX_SELF_HEAL:
			return {"type": type, "value": 0.3}
		SFX_CD_DOWN:
			return {"type": type, "value": 1}
		SFX_PURSUIT:
			return {"type": type, "value": 0.5, "magic": false, "ignore_def": 0.0}
		SFX_ZHANYI:
			return {"type": type, "value": 10}
		SFX_COUNTER_UP:
			return {"type": type, "mul": 0.1, "cut": 0.0, "per_round": 0}
		SFX_SWITCH:
			return {"type": type, "to": ""}
		SFX_RESOURCE:
			return {"type": type, "name": "", "value": 1, "max": 99}
		SFX_CONSUME:
			return {"type": type, "name": ""}
		SFX_ZOC:
			return {"type": type, "value": 1}
		SFX_PRIORITY:
			return {"type": type, "value": 1}
		SFX_BLOCK:
			return {"type": type, "value": 0.2, "turns": 2}
		SFX_DODGE:
			return {"type": type, "value": 0.2, "turns": 2}
		SFX_IMMUNITY:
			return {"type": type, "value": "控制", "turns": 2}
		SFX_RESIST:
			return {"type": type, "value": "眩晕", "turns": 2}
		SFX_SPLASH:
			return {"type": type, "value": 0.5, "radius": 1, "shape": "circle",
				"magic": false, "ignore_def": 0.0}
		SFX_TRANSFER:
			return {"type": type, "value": 10, "radius": 3}
		SFX_FACILITY:
			return {"type": type, "value": "粮仓", "turns": 3, "uses": 2,
				"heal_pct": 0.15, "buff": "奋强", "buff_turns": 2, "extra_turn": true}
		SFX_COMBO:
			return {"type": type, "value": 1}
		_:
			return {"type": type, "value": 0}

# 效果块的可读描述（给界面显示）
static func sfx_text(fx: Dictionary) -> String:
	var t := String(fx.get("type", ""))
	match t:
		SFX_DAMAGE:
			var times := int(fx.get("times", 1))
			return "造成%s%.0f%%伤害%s" % ["谋攻" if bool(fx.get("magic", false)) else "物攻",
				float(fx.get("value", 1.0)) * 100.0, (" ×%d 次" % times) if times > 1 else ""]
		SFX_HEAL:
			return "治疗友军（谋攻 %.0f%%）" % (float(fx.get("value", 0.8)) * 100.0)
		SFX_DEBUFF:
			return "施加「%s」%d回合%s" % [String(fx.get("value", "")), int(fx.get("turns", 2)),
				(" ×%d层" % int(fx.get("stacks", 1))) if int(fx.get("stacks", 1)) > 1 else ""]
		SFX_BUFF:
			return "施加「%s」%d回合" % [String(fx.get("value", "")), int(fx.get("turns", 2))]
		SFX_PUSH:
			return "击退 %d 格" % int(fx.get("value", 1))
		SFX_SELF_HEAL:
			return "自身回复兵力 %.0f%%" % (float(fx.get("value", 0.3)) * 100.0)
		SFX_CD_DOWN:
			return "自身准备期 -%d" % int(fx.get("value", 1))
		SFX_DISPEL:
			return "驱散敌方 %d 个增益" % int(fx.get("value", 1))
		SFX_SELF_DISPEL:
			return "净化自身 %d 个减益" % int(fx.get("value", 1))
		SFX_EXTRA_MOVE:
			return "获得再移动"
		SFX_DRAIN:
			return "吸血回复（伤害的 %.0f%%）" % (float(fx.get("value", 0.3)) * 100.0)
		SFX_SHIELD:
			return "套护盾 %d（%d回合）" % [int(fx.get("value", 50)), int(fx.get("turns", 2))]
		SFX_DOT:
			return "持续伤害 %d 回合" % int(fx.get("turns", 3))
		SFX_HOT:
			return "持续回复 %d 回合" % int(fx.get("turns", 3))
		SFX_STUN:
			return "眩晕 %d 回合" % int(fx.get("turns", 1))
		SFX_TAUNT:
			return "嘲讽 %d 回合" % int(fx.get("turns", 1))
		SFX_SILENCE:
			return "封技 %d 回合" % int(fx.get("turns", 1))
		SFX_DISARM:
			return "缴械 %d 回合" % int(fx.get("turns", 1))
		SFX_SUMMON:
			return "召唤 %d 名援军" % int(fx.get("value", 1))
		SFX_TELEPORT:
			return "与目标交换位置"
		SFX_EXTRA_TURN:
			return "获得额外行动"
		SFX_REVIVE:
			return "复活友军（%.0f%% 兵力）" % (float(fx.get("value", 0.3)) * 100.0)
		SFX_CRIT_UP:
			return "暴击率提升 %d 回合" % int(fx.get("turns", 2))
		SFX_LIFELINK:
			return "伤害分摊 %d 回合" % int(fx.get("turns", 2))
		SFX_COPY_BUFF:
			return "复制目标 1 个增益"
		SFX_STEAL_BUFF:
			return "偷取目标 1 个增益"
		SFX_FIXED:
			return "固定伤害 %d（无视防御）" % int(fx.get("value", 100))
		SFX_NO_COUNTER:
			return "本次攻击无法被反击"
		SFX_PURSUIT:
			return "追击：额外造成%s%.0f%%伤害%s" % ["谋攻" if bool(fx.get("magic", false)) else "物攻",
				float(fx.get("value", 0.5)) * 100.0,
				("（无视%.0f%%防御）" % (float(fx.get("ignore_def", 0.0)) * 100.0)) if float(fx.get("ignore_def", 0.0)) > 0.0 else ""]
		SFX_ZHANYI:
			var zv := int(fx.get("value", 10))
			return ("回复 %d 点战意" % zv) if zv >= 0 else ("降低 %d 点战意" % -zv)
		SFX_COUNTER_UP:
			var parts: Array = []
			var mul := float(fx.get("mul", 0.0))
			if mul != 0.0:
				parts.append("反击伤害%s%.0f%%" % ["+" if mul > 0.0 else "", mul * 100.0])
			var cut := float(fx.get("cut", 0.0))
			if cut != 0.0:
				parts.append("受反击伤害-%.0f%%" % (cut * 100.0))
			var per := int(fx.get("per_round", 0))
			if per > 0:
				parts.append("每回合可反击%d次" % per)
			return "反击增强：" + ("、".join(parts) if not parts.is_empty() else "（无参数）")
		SFX_SWITCH:
			return "切换技能形态为「%s」" % String(fx.get("to", ""))
		SFX_RESOURCE:
			var rn := String(fx.get("name", ""))
			var rv := int(fx.get("value", 1))
			return ("获得 %d 层「%s」" % [rv, rn]) if rv >= 0 else ("失去 %d 层「%s」" % [-rv, rn])
		SFX_CONSUME:
			return "消耗所有「%s」" % String(fx.get("name", ""))
		SFX_ZOC:
			return "获得 %d 格「阻挡领域」" % int(fx.get("value", 1))
		SFX_PRIORITY:
			return "获得「先攻」（本回合行动优先）"
		SFX_BLOCK:
			return "获得「格挡」：受到伤害降低 %.0f%%，持续 %d 回合" % [
				float(fx.get("value", 0.2)) * 100.0, int(fx.get("turns", 2))]
		SFX_DODGE:
			return "获得「闪避」：%.0f%% 概率回避一次攻击，持续 %d 回合" % [
				float(fx.get("value", 0.2)) * 100.0, int(fx.get("turns", 2))]
		SFX_IMMUNITY:
			return "获得「免疫%s」，持续 %d 回合" % [String(fx.get("value", "控制")),
				int(fx.get("turns", 2))]
		SFX_RESIST:
			return "获得「抵抗%s」：每回合首次受到该类减益时抵消，持续 %d 回合" % [
				String(fx.get("value", "眩晕")), int(fx.get("turns", 2))]
		SFX_COMBO:
			return "可触发合击（相邻友军对同一目标联合攻击）"
		SFX_SPLASH:
			var shp := String(fx.get("shape", "circle"))
			return "溅射：对目标周围 %d 圈（%s）的其它敌人造成%s%.0f%%伤害" % [
				int(fx.get("radius", 1)), "方形圈" if shp == "circle" else "十字",
				"谋攻" if bool(fx.get("magic", false)) else "物攻",
				float(fx.get("value", 0.5)) * 100.0]
		SFX_TRANSFER:
			return "转移：把降低的 %d 点战意转给 %d 格内的我方部队" % [
				int(fx.get("value", 10)), int(fx.get("radius", 3))]
		SFX_FACILITY:
			var uf := int(fx.get("uses", 2))
			return "召唤设施「%s」（%d 回合，可收获 %d 次：回复兵力上限%.0f%%并施加「%s」）" % [
				String(fx.get("value", "粮仓")), int(fx.get("turns", 3)), uf,
				float(fx.get("heal_pct", 0.15)) * 100.0, String(fx.get("buff", "奋强"))]
	return t


# 只取在某个技能等级下生效的效果块
#   min_lv = 该效果块从第几级开始生效（在 Lv2 时添加 → min_lv=2，则 Lv1 不生效）
static func effects_for_level(effects: Array, lv: int) -> Array:
	var out: Array = []
	for fx in effects:
		if not (fx is Dictionary):
			continue
		var need := int((fx as Dictionary).get("min_lv", 1))
		if int(lv) >= maxi(1, need):
			out.append(fx)
	return out


static func skill_effects_at(d: Dictionary, lv: int) -> Array:
	return effects_for_level(skill_effects(d), lv)


# ============================================================
# 技能等级上限
#   max=3 时是当前的 Lv1~Lv3；设为 4 即启用「四阶」预留位
#   四阶还没录入内容时，Lv4 沿用 Lv3 的效果（不会崩、不会变弱）
# ============================================================
static func max_skill_lv() -> int:
	return clampi(int(settings.get("max_skill_lv", 4)), 1, 9)


static func skill_lv_label(lv: int) -> String:
	match int(lv):
		1:
			return "一阶"
		2:
			return "二阶"
		3:
			return "三阶"
		4:
			return "四阶"
		5:
			return "五阶"
	return "Lv%d" % int(lv)


# 取某技能在某级下的描述文字；超出已录入的等级时沿用最后一级
static func skill_text_at(d: Dictionary, lv: int) -> String:
	var lvs: Array = d.get("lv", []) if d.get("lv") is Array else []
	var idx := clampi(int(lv), 1, maxi(1, lvs.size())) - 1
	if idx >= 0 and idx < lvs.size():
		var t := String(lvs[idx])
		if t != "":
			return t
	# 回退：取最后一条非空的
	for i in range(lvs.size() - 1, -1, -1):
		var s := String(lvs[i])
		if s != "":
			return s
	return String(d.get("desc", ""))


# 该技能最多能升到几级（已录入的有效等级数，至少 3）
static func skill_lv_cap(d: Dictionary) -> int:
	var lvs: Array = d.get("lv", []) if d.get("lv") is Array else []
	var n := maxi(3, lvs.size())
	return clampi(n, 1, max_skill_lv())


# 解析技能效果块：没有 ed_fx_list 的旧技能，按 kind 生成等效的默认效果块
static func skill_effects(d: Dictionary) -> Array:
	var lst = d.get("ed_fx_list", [])
	# 明确写了空数组 = 用户删光了效果，不再回退生成默认块
	if lst is Array and (lst as Array).is_empty() and d.has("ed_fx_list"):
		return []
	if lst is Array and not (lst as Array).is_empty():
		var out: Array = []
		for x in lst:
			if x is Dictionary:
				out.append(x)
		if not out.is_empty():
			return out
	var kind := String(d.get("kind", "single"))
	var out2: Array = []
	if kind == "heal" or kind == "support":
		var h := default_sfx(SFX_HEAL)
		h["value"] = float(d.get("heal", 0.8))
		out2.append(h)
	elif kind == "passive":
		pass
	else:
		var dm := default_sfx(SFX_DAMAGE)
		dm["value"] = float(d.get("mult", 1.0))
		dm["magic"] = bool(d.get("magic", false))
		out2.append(dm)
		if kind == "control":
			var db := default_sfx(SFX_DEBUFF)
			db["value"] = "低迷"
			db["turns"] = 2
			out2.append(db)
	return out2


static func arm_counter() -> Dictionary:
	return get_d("arm_counter")


static func arm_name(arm: String) -> String:
	return String(ARM_NAMES.get(arm, arm))


# 兵种克制：attacker 打 defender → 倍率
static func arm_multiplier(a: String, d: String) -> float:
	if a == "" or d == "":
		return 1.0
	var beats: Array = arm_counter().get(a, [])
	if beats.has(d):
		return 1.0 + get_f("arm_counter_bonus")
	var reverse: Array = arm_counter().get(d, [])
	if reverse.has(a):
		return 1.0 - get_f("arm_counter_reduce")
	return 1.0


# ============================================================
# 等级 / 星级成长
# ============================================================
static func level_add(lv: int) -> Dictionary:
	var g := get_d("growth")
	var grow := float(maxi(0, lv - 1))
	var extra := floorf(grow / float(GROWTH_EXTRA_EVERY))
	return {
		"hp": int(grow * float(g.get("level_hp", 4))),
		"atk": int(grow * float(g.get("level_atk", 1)) + extra),
		"def": int(grow * float(g.get("level_def", 1)) + extra),
		"matk": int(grow * float(g.get("level_matk", 1)) + extra),
		"mdef": int(grow * float(g.get("level_mdef", 1)) + extra),
	}


# 单级成长曲线（升级一次增加的数值），用于验算台展示
static func per_level_gain(lv_from: int) -> Dictionary:
	var a := level_add(lv_from)
	var b := level_add(lv_from + 1)
	var out := {}
	for k in a.keys():
		out[k] = int(b[k]) - int(a[k])
	return out


static func apply_growth(base: Dictionary, stats: Dictionary, lv: int, star: int,
		arm: String, rates: Dictionary = {}, tags: Array = []) -> Dictionary:
	var add := level_add(lv)
	var mult := 1.0 + float(maxi(0, star - 1)) * get_f("star_stat_pct")
	var add_hp := float(add["hp"]) + float(maxi(0, star - 1)) * get_f("star_hp_bonus")
	var am := arm_mods(arm)
	var g := get_d("growth")
	var out := {}
	# 成长率（扩展项）：每级成长 × 成长率
	var rate_hp := 1.0
	if not rates.is_empty():
		rate_hp = float(rates.get("hp", 1.0))
	out["max_hp"] = int(round((float(int(base.get("hp", stats.get("hp", 100)))) + add_hp * rate_hp) * mult * float(am.get("hp", 1.0))))
	out["atk"] = int(round((float(int(base.get("atk", 0))) + float(add["atk"])) * mult * float(am.get("atk", 1.0))))
	out["def"] = int(round((float(int(base.get("def", 0))) + float(add["def"])) * mult * float(am.get("def", 1.0))))
	out["matk"] = int(round((float(int(base.get("matk", 0))) + float(add["matk"])) * mult))
	out["mdef"] = int(round((float(int(base.get("mdef", 0))) + float(add["mdef"])) * mult * float(am.get("mdef", 1.0))))
	out["luck"] = int(base.get("luck", stats.get("luck", 50)))
	out["move"] = int(base.get("move", stats.get("move", get_i("default_move")))) + int(am.get("move", 0))
	out["range"] = int(base.get("range", stats.get("range", get_i("default_range")))) + int(am.get("range", 0))
	if out["move"] < 0:
		out["move"] = 0
	if out["range"] < 0:
		out["range"] = 0
	# 扩展项：成长标签（每级额外成长）
	for tag in tags:
		match String(tag):
			"atk+":
				out["atk"] = int(round(float(out["atk"]) * (1.0 + 0.01 * float(maxi(0, lv - 1)))))
			"def+":
				out["def"] = int(round(float(out["def"]) * (1.0 + 0.01 * float(maxi(0, lv - 1)))))
			"hp+":
				out["max_hp"] = int(round(float(out["max_hp"]) * (1.0 + 0.01 * float(maxi(0, lv - 1)))))
	# 扩展项：五维派生属性（开关开启才生效）
	if bool(settings.get("derive_five", false)):
		var five: Dictionary = base.get("five", {}) if base.get("five") is Dictionary else {}
		if not five.is_empty():
			var w := get_f("five_weight")
			out["atk"] = int(round(float(out["atk"]) * (1.0 + w * float(int(five.get("wu", 0))) / 100.0)))
			out["matk"] = int(round(float(out["matk"]) * (1.0 + w * float(int(five.get("zhi", 0))) / 100.0)))
			out["def"] = int(round(float(out["def"]) * (1.0 + w * float(int(five.get("tong", 0))) / 100.0)))
			out["mdef"] = int(round(float(out["mdef"]) * (1.0 + w * float(int(five.get("zheng", 0))) / 100.0)))
			out["luck"] = int(out["luck"] + w * float(int(five.get("mei", 0))) * 0.2)
	if out["max_hp"] < 1:
		out["max_hp"] = 1
	return out


# ============================================================
# ============================================================
# 伤害公式（按「三望伤害计算公式」重做）
#   直伤：攻防基础 = 攻×(1+攻击加成-攻击降低)×克制 - 防×(1-防御降低)×(1-无视防御)
#         保底 = 攻×(1+加成-降低)×克制×保底系数 + 1
#   再乘：攻山倍率、暴伤乘区(仅暴击)、克制增伤、攻山类增伤、物/谋元增伤、
#         通用增减伤、最终增减伤
#   暴击判定：暴击率 = (运势-敌方运势)×0.1% + 暴击率 - 抗暴率，独立于伤害乘区
#   固伤：无视防御与常规增减伤，只吃「固伤增伤」
# ============================================================

# 伤害乘区（可叠加，单位：倍率增减）
static func _mul(ext: Dictionary, key: String) -> float:
	return float(ext.get(key, 0.0))


# 按伤害来源类型取增伤键（副将韬略）
#   kind: skill / normal / counter / combo / pursue / fixed
#   返回该类型专属的增伤倍率
static func _kind_add(ext: Dictionary, kind: String, bucket: String) -> float:
	match kind:
		"skill":
			return float(ext.get("skill_damage", 0.0))
		"normal":
			return float(ext.get("normal_damage", 0.0))
		"counter":
			return float(ext.get("counter_damage", 0.0))
		"combo":
			return float(ext.get("combo_damage", 0.0))
		"pursue":
			return float(ext.get("pursue_damage", 0.0))
		"fixed":
			return float(ext.get("fixed_damage", 0.0))
	return 0.0


# 按伤害来源类型取减伤键（受技策伤害减免 / 受反击伤害降低）
static func _kind_cut(ext: Dictionary, kind: String) -> float:
	match kind:
		"skill":
			return -float(ext.get("skill_cut", 0.0))
		"counter":
			return -float(ext.get("counter_cut", 0.0))
	return 0.0


# 直伤公式。ctx 可选键：
#   attack_add / attack_cut   攻击加成 / 攻击降低（倍率，如 0.2 = +20%）
#   def_cut / ignore_def      防御降低 / 无视防御
#   multi_hit_add             攻山类增伤（普攻/追击/反击/技策/战法）
#   restrict_add              克制增伤
#   elem_add                  物/谋元素增伤
#   general_add / general_cut 通用增伤 / 通用减伤
#   final_add                 最终增减伤
#   power_mult                攻山倍率（普攻 100%、技策标注倍率等）
#   fixed                     固伤（无视防御与常规增伤）
static func damage_direct(attacker: Dictionary, target: Dictionary, opt: Dictionary = {}) -> Dictionary:
	var ia := int(opt.get("magic", false))
	var atk_base := float(attacker.get("matk", 0)) if ia == 1 else float(attacker.get("atk", 0))
	var def_base := float(target.get("mdef", 0)) if ia == 1 else float(target.get("def", 0))
	# 攻击端加成
	var atk_add := float(opt.get("attack_add", 0.0))
	atk_base *= (1.0 + atk_add)
	# 克制系数
	var restrict := float(opt.get("restrict_mult", 1.0))
	atk_base *= restrict
	# 防御端
	var def_cut := clampf(float(opt.get("def_cut", 0.0)), 0.0, 0.9)
	var ignore_def := clampf(float(opt.get("ignore_def", 0.0)), 0.0, 1.0)
	def_base *= (1.0 - def_cut)
	def_base *= (1.0 - ignore_def)
	var raw := atk_base - def_base
	# 保底：攻击×克制×保底系数 + 1，最低 1
	var floor_k := get_f("damage_floor_k")
	raw = maxf(raw, atk_base * floor_k + 1.0)
	# 攻山倍率
	raw *= float(opt.get("power_mult", 1.0))
	# 暴击乘区（独立，不参与增伤叠加）
	var crit := bool(opt.get("crit", false))
	var crit_mult := 1.0
	if crit:
		crit_mult = float(opt.get("crit_mult", get_f("crit_damage")))
		raw *= crit_mult
	# 各类增伤乘区（乘算）
	var mult_area := 1.0
	mult_area *= 1.0 + float(opt.get("restrict_add", 0.0))
	mult_area *= 1.0 + float(opt.get("multi_hit_add", 0.0))
	mult_area *= 1.0 + float(opt.get("elem_add", 0.0))
	mult_area *= 1.0 + float(opt.get("general_add", 0.0)) - float(opt.get("general_cut", 0.0))
	mult_area *= 1.0 + float(opt.get("final_add", 0.0))
	# 按伤害来源类型的增伤（副将韬略：技能伤害 / 普攻伤害 / 反击伤害 / 合击伤害 / 克制伤害）
	mult_area *= 1.0 + float(opt.get("kind_add", 0.0))
	mult_area *= 1.0 + float(opt.get("kind_cut", 0.0))
	raw *= maxf(0.0, mult_area)
	return {"dmg": raw, "crit": crit, "crit_mult": crit_mult, "atk_base": atk_base, "def_base": def_base}


# 固伤：无视防御与常规增减伤，只吃固伤增伤
static func damage_fixed(amount: float, opt: Dictionary = {}) -> float:
	return maxf(1.0, amount * (1.0 + float(opt.get("fixed_add", 0.0))))


# 暴击判定：暴击率 = (运势-敌方运势)×0.1% + 暴击率 - 抗暴率
static func crit_roll(attacker: Dictionary, target: Dictionary, opt: Dictionary = {}) -> bool:
	if opt.has("crit") and opt["crit"] != null:
		return bool(opt["crit"])
	if opt.get("no_crit", false):
		return false
	# 运势 = 魅力（幸运与运势已合并）
	var fa := float(attacker.get("fortune", mei_of(attacker)))
	var ft := float(target.get("fortune", mei_of(target)))
	var fortune := fa - ft
	var c := fortune * 0.001
	c += crit_chance_of(attacker)
	c -= float(target.get("crit_resist", 0.0)) + float((target.get("ext", {}) as Dictionary).get("crit_resist", 0.0))
	return RNG.randf() < clampf(c, 0.0, 1.0)


# 伤害公式
# ============================================================
static func damage(atk_v: float, def_v: float, mult: float, armor_mul: float = 1.0) -> float:
	atk_v = maxf(0.0, atk_v)
	return atk_v * atk_v / maxf(1.0, atk_v + def_v) * mult * armor_mul


static func crit_chance(luck: float) -> float:
	return clampf(luck * get_f("crit_per_luck"), 0.0, 1.0)


# ---------------- 魅力 → 暴击率 / 暴击伤害（默认开启） ----------------
static func five_of(unit: Dictionary) -> Dictionary:
	# 优先用随等级成长后的五维（unit_template 输出的 fives）
	var f = unit.get("fives")
	if f is Dictionary and not (f as Dictionary).is_empty():
		return f
	var ext = unit.get("ext", {})
	if ext is Dictionary and (ext as Dictionary).get("fives") is Dictionary:
		return ext["fives"]
	return {}


static func mei_of(unit: Dictionary) -> int:
	return int(five_of(unit).get("mei", 0))


# 最终暴击率 = 幸运×系数 + 魅力×系数 + 额外暴击加成
# 最终暴击率 = 魅力×系数 + 运势差×0.1% + 附加暴击（上限 100%）
# 幸运已与运势合并进魅力，不再单独参与
static func crit_chance_of(unit: Dictionary) -> float:
	var c := float(mei_of(unit)) * get_f("crit_per_mei")
	c += float(unit.get("crit_bonus", 0.0))
	# 副将韬略「战斗中提升N%暴击率」等附加暴击并入 ext.crit_bonus
	c += float((unit.get("ext", {}) as Dictionary).get("crit_bonus", 0.0))
	return clampf(c, 0.0, 1.0)


# 最终暴击伤害倍率 = 基础倍率 + 魅力×系数 + 额外暴伤
static func crit_mult_of(unit: Dictionary) -> float:
	var m := get_f("crit_damage") + float(mei_of(unit)) * get_f("mei_crit_dmg_per") \
		+ float(unit.get("crit_damage", 0.0))
	# 副将韬略「战斗中提升N%暴击伤害」并入 ext.crit_damage
	m += float((unit.get("ext", {}) as Dictionary).get("crit_damage", 0.0))
	return m


# 一次伤害结算（确定性部分 + 可选随机浮动 / 暴击）
# opt: magic, ignore_def, crit(bool|null=掷骰), no_variance
static func roll_damage(attacker: Dictionary, target: Dictionary, mult: float,
		arm_mul: float = 1.0, opt: Dictionary = {}) -> Dictionary:
	# 攻击加成：斗气 / 无双 / 扩展增伤
	var atk_add := get_f("douqi_per_stack") * float(attacker.get("douqi", 0))
	if int(attacker.get("wushuang", 0)) > 0:
		atk_add += get_f("wushuang_mult") - 1.0
	# 暴击判定（独立乘区）
	var crit := crit_roll(attacker, target, opt)
	var crit_mult := crit_mult_of(attacker)
	var ext_a: Dictionary = attacker.get("ext", {}) if attacker.get("ext") is Dictionary else {}
	var ext_t: Dictionary = target.get("ext", {}) if target.get("ext") is Dictionary else {}
	var kind := String(opt.get("kind", ""))
	var res := damage_direct(attacker, target, {
		"magic": bool(opt.get("magic", false)),
		"attack_add": atk_add + _mul(ext_a, "attack_add"),
		"def_cut": _mul(ext_t, "def_cut"),
		"ignore_def": float(opt.get("ignore_def", 0.0)),
		"restrict_mult": arm_mul,
		"restrict_add": _mul(ext_a, "restrict_add") + _kind_add(ext_a, kind, "restrict_damage"),
		"multi_hit_add": _mul(ext_a, "multi_hit_add"),
		"elem_add": float(opt.get("elem_add", 0.0)) + _mul(ext_a, "elem_add"),
		"general_add": _mul(ext_a, "damage_bonus"),
		"general_cut": _mul(ext_t, "damage_cut"),
		"final_add": _mul(ext_a, "final_add"),
		"kind_add": _kind_add(ext_a, kind, "damage_bonus_kind"),
		"kind_cut": _kind_cut(ext_t, kind),
		"power_mult": mult,
		"crit": crit,
		"crit_mult": crit_mult,
	})
	var raw: float = float(res["dmg"])
	# 随机浮动
	if not opt.get("no_variance", false):
		var var_amt: float = get_f("damage_variance")
		if var_amt > 0.0:
			raw *= RNG.randf_range(1.0 - var_amt, 1.0 + var_amt)
	raw = maxf(float(get_i("min_damage")), raw)
	return {
		"dmg": int(roundf(raw)),
		"crit": crit,
		"crit_mult": crit_mult,
		"raw": raw,
	}


# 期望伤害（不掷骰，用于验算台对比）：直伤 × (1 + (暴击倍率-1) × 暴击率)
static func expected_damage(attacker: Dictionary, target: Dictionary, mult: float,
		arm_mul: float = 1.0, magic: bool = false, kind: String = "") -> int:
	var atk_add := get_f("douqi_per_stack") * float(attacker.get("douqi", 0))
	if int(attacker.get("wushuang", 0)) > 0:
		atk_add += get_f("wushuang_mult") - 1.0
	var ext_a: Dictionary = attacker.get("ext", {}) if attacker.get("ext") is Dictionary else {}
	var ext_t: Dictionary = target.get("ext", {}) if target.get("ext") is Dictionary else {}
	var res := damage_direct(attacker, target, {
		"magic": magic,
		"attack_add": atk_add + _mul(ext_a, "attack_add"),
		"def_cut": _mul(ext_t, "def_cut"),
		"restrict_mult": arm_mul,
		"restrict_add": _mul(ext_a, "restrict_add"),
		"multi_hit_add": _mul(ext_a, "multi_hit_add"),
		"elem_add": _mul(ext_a, "elem_add"),
		"general_add": _mul(ext_a, "damage_bonus"),
		"general_cut": _mul(ext_t, "damage_cut"),
		"kind_add": _kind_add(ext_a, kind, ""),
		"kind_cut": _kind_cut(ext_t, kind),
		"final_add": _mul(ext_a, "final_add"),
		"power_mult": mult,
		"crit": false,
	})
	var base: float = float(res["dmg"])
	var cc := crit_chance_of(attacker)
	var expect := base * (1.0 + (crit_mult_of(attacker) - 1.0) * cc)
	return int(maxf(float(get_i("min_damage")), roundf(expect)))


# ============================================================
# 范围（形状）
# ============================================================
static func diamond(r: int) -> Array:
	var out: Array = []
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if absi(x) + absi(y) <= r:
				out.append(Vector2i(x, y))
	return out


static func dilate(area: Array, n: int) -> Array:
	var set := {}
	for c in area:
		set[c] = true
	for _i in n:
		var add: Array = []
		for c in set.keys():
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not set.has(c + d):
					add.append(c + d)
		for c in add:
			set[c] = true
	return set.keys()


# 溅射范围（以某点为中心的偏移格）
#   shape = "diamond"：曼哈顿距离 ≤ radius（十字形，radius=1 时为上下左右 4 格）
#   shape = "circle"  ：切比雪夫距离 ≤ radius（方形，radius=1 时为周围 8 格「一圈」）
# 不含中心格自身
static func splash_cells(radius: int, shape: String) -> Array:
	var r := maxi(1, radius)
	var out: Array = []
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x == 0 and y == 0:
				continue
			if shape == "circle":
				if maxi(absi(x), absi(y)) > r:
					continue
			else:
				if absi(x) + absi(y) > r:
					continue
			out.append(Vector2i(x, y))
	return out


static func face_dir(from_pos: Vector2i, to_pos: Vector2i) -> Vector2i:
	var d := to_pos - from_pos
	if d == Vector2i.ZERO:
		return Vector2i(1, 0)
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


static func rotate_area(area: Array, dir: Vector2i) -> Array:
	if dir == Vector2i(1, 0):
		return area.duplicate()
	var out: Array = []
	for off in area:
		match dir:
			Vector2i(-1, 0):
				out.append(Vector2i(-off.x, -off.y))
			Vector2i(0, 1):
				out.append(Vector2i(-off.y, off.x))
			Vector2i(0, -1):
				out.append(Vector2i(off.y, -off.x))
			_:
				out.append(off)
	return out


static func area_to_raw(area: Array) -> Array:
	var arr: Array = []
	for c in area:
		arr.append([int(c.x), int(c.y)])
	return arr


static func parse_area(raw: Array) -> Array:
	var out: Array = []
	for c in raw:
		if c is Array and (c as Array).size() >= 2:
			out.append(Vector2i(int(c[0]), int(c[1])))
		elif c is Vector2i:
			out.append(c)
	return out


static func mdist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func area_radius(area: Array) -> int:
	var m := 0
	for off in area:
		m = maxi(m, absi(off.x) + absi(off.y))
	return m


# 移动可达格（障碍 / 单位占据不可通过）
static func reachable(start: Vector2i, move: int, blocked: Dictionary) -> Dictionary:
	var dist := {start: 0}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		var cd := int(dist[cur])
		if cd >= move:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + d
			if blocked.has(nxt) or dist.has(nxt):
				continue
			dist[nxt] = cd + 1
			frontier.append(nxt)
	return dist
