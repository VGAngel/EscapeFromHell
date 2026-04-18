extends Control


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://Level1.tscn")


func _on_levels_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelSelect.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://Settings.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
