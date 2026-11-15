extends Node

# 自动截图：按页签顺序切换并截图，用于交付前目检 UI。
# 用法：godot --path <项目> --script-shots（由 tools/shoot.gd 场景驱动）
# 实际执行：godot --path <项目> res://tools/Shoot.tscn

const SHOT_DIR := "res://docs/screens"

var editor: Control
var idx := 0
var titles: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	editor = load("res://scenes/Editor.tscn").instantiate()
	add_child(editor)
	await get_tree().create_timer(1.0).timeout
	await _run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT_DIR, name])
	print("shot: " + name)


func _run() -> void:
	var tabs: TabContainer = editor.get("tabs")
	# 逐页截图
	for i in tabs.get_tab_count():
		tabs.current_tab = i
		await _wait(0.35)
		await _shot("tab_%02d" % i)
	# 技能页选中第一个技能
	tabs.current_tab = 5
	await _wait(0.3)
	await _shot("06_skills")
	# 精灵图页：选中攻击·下 槽位并播放
	tabs.current_tab = 8
	editor.set("art_sel", {"act": "attack", "dir": "down"})
	editor.call("_refresh_anim_matrix")
	await _wait(0.3)
	editor.call("_play_slot_anim")
	await _wait(0.12)
	await _shot("09_anims")
	# 兵种页：移动/射程加成表
	tabs.current_tab = 4
	await _wait(0.35)
	await _shot("05_arm")
	# 等级/星级页：升星模块
	tabs.current_tab = 3
	await _wait(0.35)
	await _shot("04_growth")
	# 演算台
	tabs.current_tab = 0
	editor.call("_on_open_sandbox", "calc")
	await _wait(1.2)
	var sb = null
	for c in editor.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("sandbox.gd"):
			sb = c
	if sb != null:
		await _shot("98_calc")
		# 小战场
		var stabs: TabContainer = sb.get("tabs")
		stabs.current_tab = 1
		sb.call("_setup_battle")
		await _wait(0.8)
		await _shot("99_battle")
		# 选中第一个我方单位，看技能按钮
		var battle = sb.get("battle")
		for u in battle.units:
			if int(u["side"]) == 0:
				sb.set("sel_uid", int(u["uid"]))
				break
		sb.call("_rebuild_skill_bar")
		await _wait(0.4)
		await _shot("99b_battle_selected")
	print("ALL SHOTS DONE")
	get_tree().quit()
