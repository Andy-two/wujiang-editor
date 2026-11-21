extends SceneTree

# 批量测所有武将：有被动 vs 无被动的普攻伤害差异
# 固定随机种子、固定目标，输出 TSV
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")
const EB = preload("res://scripts/core/ed_battle.gd")

var out_lines: Array = []


func _one(data, key: String, with_passive: bool, foe_t: Dictionary, seed: int) -> int:
	var bt = EB.new(13, 11)
	bt.bind_data(data.generals, data.skills, data.talents, data.get_arm_shapes(), data.bonds)
	bt.set_seed(seed)
	var t = data.unit_template(key, 50, 5, "")
	if not with_passive:
		# 去掉所有被动技能
		var keep: Array = []
		for sid in (t.get("skills", []) as Array):
			var d: Dictionary = data.skills.get(String(sid), {})
			if String(d.get("kind", "")) != "passive":
				keep.append(sid)
		t["skills"] = keep
		# 清掉由被动产生的光环/条件属性/自定义字段
		var e: Dictionary = t.get("ext", {})
		e.erase("passive_impls")
		e.erase("cond_attrs")
		e.erase("magic_cut")
		e.erase("full_hp_cut")
	var u = bt.add_unit(t, Vector2i(5, 5), 0)
	var f = bt.add_unit(foe_t.duplicate(true), Vector2i(6, 5), 1)
	bt._apply_passive_startup()
	bt._refresh_all_cond_mult()
	var r: Dictionary = bt.basic_attack(u, f)
	return int(r.get("dmg", 0))


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()
	# 固定靶子：高血量，避免被击杀封顶
	var foe_t = data.unit_template("zhang_fei", 60, 10, "")
	foe_t["stats"]["max_hp"] = 999999
	foe_t["stats"]["hp"] = 999999
	foe_t["skills"] = []

	out_lines.append("武将id\t名称\t有被动伤害\t无被动伤害\t差值\t说明")
	var diff_count := 0
	for key in data.order:
		var k := String(key)
		var with_dmg := _one(data, k, true, foe_t, 12345)
		var without_dmg := _one(data, k, false, foe_t, 12345)
		var diff := with_dmg - without_dmg
		var note := ""
		if diff != 0:
			diff_count += 1
			note = "被动生效"
		out_lines.append("%s\t%s\t%d\t%d\t%d\t%s" % [
			k, data.name_of(k), with_dmg, without_dmg, diff, note])
	# 写文件
	var f = FileAccess.open("res://data/stats/passive_damage_all.tsv", FileAccess.WRITE)
	if f != null:
		for ln in out_lines:
			f.store_line(ln)
		f.close()
	print("完成：%d 名武将，%d 名有被动伤害差异" % [data.order.size(), diff_count])
	for ln in out_lines:
		print(ln)
	quit(0)
