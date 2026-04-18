extends Node

var souls_collected: int = 0
const SOULS_NEEDED: int = 100

signal soul_collected(total: int)

func collect_soul() -> void:
	souls_collected += 1
	soul_collected.emit(souls_collected)

func reset() -> void:
	souls_collected = 0
