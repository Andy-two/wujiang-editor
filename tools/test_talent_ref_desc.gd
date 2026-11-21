extends SceneTree

# 验证：天赋引用被动技能时，描述显示被动本身效果，而非「获得某被动」
const ED = preload("res://scripts/core/ed_data.gd")
const RULEZ = preload("res://scripts/core/rules.gd")

var passed := 0
var failed := 0


func _check(n: String, c: bool, d: String = "") -> void:
	if c:
		passed += 1
		print("  ✔ ", n)
	else:
		failed += 1
		print("  ✖ ", n, ("" if d == "" else "（" + d + "）"))


func _init() -> void:
	RULEZ.load_settings("res://data/editor/settings.json")
	var data = ED.new()
	data.load_all()

	print("===== 1. sfx_text_ex 展开有描述技能的被动 =====")
	# 偃月阵有 desc：自身3格范围内的我方部队受到谋略伤害降低10%。
	var fx := {"type": "ref_skill", "value": "guan_yanyue", "skill_name": "偃月阵"}
	var old := RULEZ.sfx_text(fx)
	var now := RULEZ.sfx_text_ex(fx, data.skills)
	print("  旧文案: ", old)
	print("  新文案: ", now)
	_check("新文案不再是「获得被动技能」", not now.contains("获得被动技能"), now)
	_check("新文案含被动本身效果（谋略伤害降低）", now.contains("谋略伤害降低"), now)

	print("===== 2. 万人敌（desc 有内容） =====")
	var fx2 := {"type": "ref_skill", "value": "wanren", "skill_name": "万人敌"}
	var now2 := RULEZ.sfx_text_ex(fx2, data.skills)
	print("  新文案: ", now2)
	_check("不显示获得被动", not now2.contains("获得被动技能"), now2)
	_check("文案非空", now2 != "", now2)

	print("===== 3. 无描述技能回退到效果块拼接 =====")
	# 犹怜历史数据有 desc，也测一个纯效果块的
	var fx3 := {"type": "ref_skill", "value": "youlian", "skill_name": "犹怜"}
	var now3 := RULEZ.sfx_text_ex(fx3, data.skills)
	print("  新文案: ", now3)
	_check("文案非空", now3 != "", now3)
	_check("不含「获得被动技能」", not now3.contains("获得被动技能"), now3)

	print("===== 4. 坏引用安全回退 =====")
	var fx4 := {"type": "ref_skill", "value": "NOT_EXIST", "skill_name": ""}
	var now4 := RULEZ.sfx_text_ex(fx4, data.skills)
	print("  坏引用文案: ", now4)
	_check("坏引用不崩且非空", now4 != "")

	print("===== 5. 非 ref_skill 类型走原逻辑 =====")
	var fx5 := {"type": "buff", "value": "昂扬", "turns": 2}
	_check("普通效果文案不变",
		RULEZ.sfx_text_ex(fx5, data.skills) == RULEZ.sfx_text(fx5),
		RULEZ.sfx_text_ex(fx5, data.skills))

	print("===== 结果：%d 通过，%d 失败 =====" % [passed, failed])
	quit(0)
