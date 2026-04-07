class_name HeuristicAgent
extends "res://scripts/agents/BaseAgent.gd"

const EasyAIStrategyRef = preload("res://scripts/ai/EasyAIStrategy.gd")
const HardAIStrategyRef = preload("res://scripts/ai/HardAIStrategy.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")
const MediumAIStrategyRef = preload("res://scripts/ai/MediumAIStrategy.gd")

var _strategy = null


func setup(spec: Dictionary, context: Dictionary = {}) -> void:
	super.setup(spec, context)
	_strategy = _build_strategy(int(agent_spec.get("difficulty", MatchConfigRef.AIDifficulty.MEDIUM)))


func request_action(observation: Dictionary) -> void:
	if _strategy == null:
		_strategy = _build_strategy(int(agent_spec.get("difficulty", MatchConfigRef.AIDifficulty.MEDIUM)))
	action_ready.emit(_strategy.choose_action(observation))


func _build_strategy(difficulty: int):
	match difficulty:
		MatchConfigRef.AIDifficulty.EASY:
			return EasyAIStrategyRef.new()
		MatchConfigRef.AIDifficulty.HARD:
			return HardAIStrategyRef.new()
		_:
			return MediumAIStrategyRef.new()
