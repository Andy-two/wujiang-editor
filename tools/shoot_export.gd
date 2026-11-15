extends Node

# 打开「导出给游戏」窗口并截图，用于交付文档

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screens"))
	var editor = load("res://scenes/Editor.tscn").instantiate()
	add_child(editor)
	await get_tree().create_timer(1.0).timeout
	editor.call("_on_export")
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://docs/screens/97_export.png")
	print("shot export")
	# 测试真实导出到 user://
	var lines: Array = editor.call("_do_export", "user://export_demo", 1, true, true)
	for l in lines:
		print("  " + String(l))
	# 检查产物
	var dir := ProjectSettings.globalize_path("user://export_demo")
	print("导出目录：" + dir)
	for f in DirAccess.get_files_at(dir):
		print("  - " + f)
	get_tree().quit()
