extends Control


func _on_level_1_pressed() -> void:
	# Legacy: now handled by GameManager
	if GameManager:
		GameManager.load_next_level()
	else:
		get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")


func _on_level_2_pressed() -> void:
	if GameManager:
		GameManager.load_next_level()
	else:
		get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
