extends SceneTree

# 数据准备工具：从旧工程 data/ 复制武将/技策/天赋到 data/editor/，
# 并把 ed_* 扩展字段补齐（五维、成长率、图片、范围覆盖等）。
# 用法：godot --headless --path <项目> --script res://tools/prepare_data.gd

const ED = preload("res://scripts/core/ed_data.gd")

const ARM_BY_KEY := {
	"lu_bu": "骑", "diao_chan": "盾", "guan_yu": "枪", "zhang_fei": "盾",
	"zhao_yun": "骑", "zhuge_liang": "弓",
}
const ARM_DEFAULT_BY_TROOP := {
	"轻骑兵": "骑", "轻骑": "骑", "重骑": "骑", "统领": "骑",
	"弓兵": "弓", "弩兵": "弓", "器械": "弓", "投石车": "弓",
	"长兵": "枪", "策士": "弓", "道士": "弓", "幕僚": "弓", "文人": "弓",
	"军需": "盾", "步兵": "盾", "女兵": "枪", "才女": "弓", "舞者": "弓",
}
const FEMALE := ["diao_chan", "da_qiao", "xiao_qiao", "lv_lingqi", "zhang_chunhua", "zhen_mi",
	"ma_yunlu", "zhang_xingcai", "gan_mei", "huang_yueying", "ji_ling", "cai_wenji",
	"sun_shangxiang", "chen_qiao"]


func _init() -> void:
	var gen_src = ED.read_json("res://data/generals.json")
	var skill_src = ED.read_json("res://data/skills.json")
	var talent_src = ED.read_json("res://data/talents.json")
	if not (gen_src is Dictionary):
		push_error("缺少 data/generals.json")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://data/editor")

	var out := {}
	var count := 0
	for k in (gen_src as Dictionary).keys():
		var key := String(k)
		var g: Dictionary = (gen_src[key] as Dictionary).duplicate(true)
		# ---- 推导兵种 ----
		if String(g.get("arm", "")) not in ED_RULES_ARMS():
			var troop := String(g.get("troop", ""))
			var arm := String(ARM_DEFAULT_BY_TROOP.get(troop, ""))
			if arm == "":
				arm = String(ARM_BY_KEY.get(key, "盾"))
			g["arm"] = arm
		# ---- 五维：按面板属性推导一个合理的初始值（之后可随意改）----
		var st: Dictionary = g.get("stats", {})
		var fives := {
			"wu": clampi(int(round(float(st.get("atk", 50)) / 2.0)), 1, 100),
			"zhi": clampi(int(round(float(st.get("matk", 50)) / 2.0)), 1, 100),
			"tong": clampi(int(round(float(st.get("def", 40)) / 1.5)), 1, 100),
			"zheng": clampi(int(round(float(st.get("mdef", 40)) / 1.5)), 1, 100),
			"mei": clampi(int(st.get("luck", 50)) + 10, 1, 100),
		}
		var ext: Dictionary = {
			"gender": "女" if key in FEMALE else "男",
			"fives": fives,
			"quality": 4 if int(g.get("id", 0)) < 1200 else 5,
			"faction": _faction_of(key),
			"growth_rates": {"hp": 1.0, "atk": 1.0, "def": 1.0, "matk": 1.0, "mdef": 1.0},
			"level_curve": "linear",
			"ai_weight": 1.0,
			"morale": 100,
			"skill_power": 1.0,
		}
		g["ed_ext"] = ext
		g["ed_level"] = 1
		g["ed_star"] = 1
		g["ed_talent_lv"] = int(g.get("talent_lv", 1))
		var slv := {}
		for sid in (g.get("skills", []) as Array):
			slv[String(sid)] = 1
		g["ed_skill_lv"] = slv
		g["ed_art"] = {
			"portrait_path": String(g.get("portrait", "")),
			"illust_path": "",
			"sprite_path": "res://assets/units/lu_bu/atk64.png" if key == "lu_bu" else "",
			"frame_w": 64, "frame_h": 64, "frames": 4, "fps": 8.0,
		}
		g["ed_ranges"] = {}
		g["ed_note"] = ""
		g["ed_tags"] = []
		g["ed_enabled"] = true
		out[key] = g
		count += 1

	ED.write_json("res://data/editor/generals.json", out)
	ED.write_json("res://data/editor/skills.json", skill_src)
	ED.write_json("res://data/editor/talents.json", talent_src)
	ED.write_json("res://data/editor/settings.json", ED_RULES_DEFAULTS())
	print("已准备武将 %d 名 / 技策 %d 条 / 天赋 %d 条" % [
		count, (skill_src as Dictionary).size(), (talent_src as Dictionary).size()])
	quit(0)


func ED_RULES_ARMS() -> Array:
	return ["盾", "枪", "弓", "骑"]


func ED_RULES_DEFAULTS() -> Dictionary:
	var r = load("res://scripts/core/rules.gd")
	return (r.DEFAULTS as Dictionary).duplicate(true)


func _faction_of(key: String) -> String:
	# 按武将 key 粗略归属阵营（可在编辑器里改）
	var wei := ["cao_cao", "canglan_cao_cao", "cao_hong", "cao_ren", "dian_wei", "xu_chu", "xiahou_dun",
		"xiahou_yuan", "zhang_liao", "zhang_he", "xu_huang", "yu_jin", "yue_jin", "guo_jia", "jia_xu",
		"xun_yu", "xun_you", "si_ma_yi", "chen_qun", "gao_shun", "li_dian", "pang_de", "cheng_yu",
		"zhang_xiu", "zhen_mi", "diao_chan", "lv_lingqi", "mi_zhu", "jian_yong"]
	var wu := ["sun_ce", "sun_quan", "zhou_yu", "da_qiao", "xiao_qiao", "gan_mei", "lu_bu", "taishi_ci",
		"sun_shangxiang", "lu_xun"]
	var shu := ["liu_bei", "guan_yu", "zhang_fei", "zhao_yun", "zhuge_liang", "zhang_xingcai", "huang_zhong",
		"ma_chao", "ma_yunlu", "wei_yan", "pang_tong", "huang_yueying", "chen_dao", "chen_deng",
		"ji_ling", "liu_ye", "cai_wenji", "mi_zhu"]
	if key in wei:
		return "魏"
	if key in wu:
		return "吴"
	if key in shu:
		return "蜀"
	return "群"
