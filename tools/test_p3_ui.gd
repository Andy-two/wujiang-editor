extends SceneTree

# P3 效果块在编辑器中的可编辑性验证：
# 确认 ① 新类型出现在「添加效果块」下拉 ② 参数控件可生成 ③ 界面文案正确
# 用法: godot --headless --path . --script res://tools/test_p3_ui.gd

const RULEZ = preload("res://scripts/core/rules.gd")

var passed := 0
var failed := 0
var fails: Array = []


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("  ✔ ", name)
	else:
		failed += 1
		fails.append(name + ("" if detail == "" else "（" + detail + "）"))
		print("  ✖ ", name, ("" if detail == "" else "（" + detail + "）"))


func _init() -> void:
	print("========== P3 效果块可编辑性验证 ==========")

	# ① 新类型都在 SFX_TYPES 里（界面下拉由此生成）
	for t in [RULEZ.SFX_PRIORITY, RULEZ.SFX_BLOCK, RULEZ.SFX_DODGE,
			RULEZ.SFX_IMMUNITY, RULEZ.SFX_COMBO]:
		_check("类型 %s 在效果块列表中" % t, RULEZ.SFX_TYPES.has(t))

	# ② 都有界面标签
	for t in [RULEZ.SFX_PRIORITY, RULEZ.SFX_BLOCK, RULEZ.SFX_DODGE,
			RULEZ.SFX_IMMUNITY, RULEZ.SFX_COMBO]:
		_check("类型 %s 有界面标签" % t, RULEZ.SFX_LABELS.has(t),
			String(RULEZ.SFX_LABELS.get(t, "")))

	# ③ 都有默认参数（新建时的初始值）
	for t in [RULEZ.SFX_PRIORITY, RULEZ.SFX_BLOCK, RULEZ.SFX_DODGE,
			RULEZ.SFX_IMMUNITY, RULEZ.SFX_COMBO]:
		var d := RULEZ.default_sfx(t)
		_check("类型 %s 有默认参数" % t, d.has("type") and String(d.get("type", "")) == t)

	# ④ 界面文案可读（sfx_text 不应返回原始类型名）
	var expect_nonempty := {
		RULEZ.SFX_PRIORITY: true, RULEZ.SFX_BLOCK: true, RULEZ.SFX_DODGE: true,
		RULEZ.SFX_IMMUNITY: true, RULEZ.SFX_COMBO: true,
	}
	for t in expect_nonempty.keys():
		var txt := String(RULEZ.sfx_text(RULEZ.default_sfx(String(t))))
		_check("类型 %s 有可读文案" % t, txt != "" and txt != String(t), "文案: " + txt)

	# ⑤ 关键参数被正确渲染
	_check("格挡文案含减伤",
		String(RULEZ.sfx_text(RULEZ.default_sfx(RULEZ.SFX_BLOCK))).contains("伤害降低"))
	_check("闪避文案含回避",
		String(RULEZ.sfx_text(RULEZ.default_sfx(RULEZ.SFX_DODGE))).contains("回避"))
	_check("免疫文案含免疫",
		String(RULEZ.sfx_text(RULEZ.default_sfx(RULEZ.SFX_IMMUNITY))).contains("免疫"))

	# ⑥ 新参数写入 settings.json 的默认值存在（⑪ 全局设定可调）
	_check("settings 有 max_combo_per_round", RULEZ.DEFAULTS.has("max_combo_per_round"))
	_check("settings 有 combo_need_adjacent", RULEZ.DEFAULTS.has("combo_need_adjacent"))
	_check("mult_combo 保持 0.5", absf(float(RULEZ.DEFAULTS.get("mult_combo", 0.0)) - 0.5) < 0.001)

	print("----------------------------------------")
	print("通过 %d 项，失败 %d 项" % [passed, failed])
	for f in fails:
		print("  ✖ " + String(f))
	print("========== 测试结束 ==========")
	quit(0 if failed == 0 else 1)
