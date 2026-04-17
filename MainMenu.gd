extends Control


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://custom_level_for_test_jump.tscn")


func _on_levels_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelSelect.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
