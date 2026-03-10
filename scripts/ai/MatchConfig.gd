class_name MatchConfig
extends RefCounted

enum PlayerControl {
	HUMAN,
	AI,
}

enum AIDifficulty {
	EASY,
	MEDIUM,
	HARD,
}


static func default_config() -> Dictionary:
	return {
		"black_control": PlayerControl.HUMAN,
		"white_control": PlayerControl.AI,
		"ai_difficulty": AIDifficulty.MEDIUM,
	}


static func normalize(config: Dictionary = {}) -> Dictionary:
	var merged := default_config()
	for key: String in config.keys():
		merged[key] = config[key]
	return merged


static func get_player_control(config: Dictionary, player: int) -> int:
	var normalized := normalize(config)
	return normalized["black_control"] if player == 0 else normalized["white_control"]


static func control_label(control: int) -> String:
	return "AI" if control == PlayerControl.AI else "玩家"


static func difficulty_label(difficulty: int) -> String:
	match difficulty:
		AIDifficulty.EASY:
			return "简单"
		AIDifficulty.HARD:
			return "困难"
		_:
			return "中等"


static func player_mode_label(config: Dictionary, player: int) -> String:
	var control := get_player_control(config, player)
	if control == PlayerControl.HUMAN:
		return "玩家"
	return "AI（%s）" % difficulty_label(normalize(config)["ai_difficulty"])
