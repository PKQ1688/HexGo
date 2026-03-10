class_name AIController
extends Node

signal action_ready(action)
signal thinking_changed(is_thinking)

const GameStateRef = preload("res://scripts/core/GameState.gd")
const EasyAIStrategyRef = preload("res://scripts/ai/EasyAIStrategy.gd")
const HardAIStrategyRef = preload("res://scripts/ai/HardAIStrategy.gd")
const MatchConfigRef = preload("res://scripts/ai/MatchConfig.gd")
const MediumAIStrategyRef = preload("res://scripts/ai/MediumAIStrategy.gd")

@export var think_delay_min: float = 0.2
@export var think_delay_max: float = 0.4

var game_state = null
var match_config: Dictionary = MatchConfigRef.default_config()
var rng := RandomNumberGenerator.new()
var _is_thinking: bool = false
var _strategy_cache: Dictionary = {}

@onready var think_timer := Timer.new()


func _ready() -> void:
	rng.randomize()
	think_timer.one_shot = true
	think_timer.timeout.connect(_on_think_timeout)
	add_child(think_timer)


func configure(state, config: Dictionary) -> void:
	cancel_pending_turn()
	if game_state != null and game_state.turn_completed.is_connected(_on_turn_completed):
		game_state.turn_completed.disconnect(_on_turn_completed)

	game_state = state
	match_config = MatchConfigRef.normalize(config)
	_strategy_cache.clear()

	if game_state != null and not game_state.turn_completed.is_connected(_on_turn_completed):
		game_state.turn_completed.connect(_on_turn_completed)


func is_thinking() -> bool:
	return _is_thinking


func cancel_pending_turn() -> void:
	if not think_timer.is_stopped():
		think_timer.stop()
	if _is_thinking:
		_is_thinking = false
		thinking_changed.emit(false)


func _on_turn_completed(_player: int, _scores: Dictionary) -> void:
	if game_state == null:
		return
	if game_state.phase != GameStateRef.Phase.WAITING:
		cancel_pending_turn()
		return
	if MatchConfigRef.get_player_control(match_config, game_state.current_player) != MatchConfigRef.PlayerControl.AI:
		cancel_pending_turn()
		return
	if _is_thinking or not think_timer.is_stopped():
		return

	_is_thinking = true
	thinking_changed.emit(true)
	var min_delay: float = minf(think_delay_min, think_delay_max)
	var max_delay: float = maxf(think_delay_min, think_delay_max)
	if max_delay <= 0.0:
		call_deferred("_on_think_timeout")
		return
	think_timer.wait_time = rng.randf_range(maxf(0.01, min_delay), maxf(0.01, max_delay))
	think_timer.start()


func _on_think_timeout() -> void:
	if game_state == null:
		cancel_pending_turn()
		return
	if game_state.phase != GameStateRef.Phase.WAITING:
		cancel_pending_turn()
		return
	if MatchConfigRef.get_player_control(match_config, game_state.current_player) != MatchConfigRef.PlayerControl.AI:
		cancel_pending_turn()
		return

	var action: Dictionary = _strategy_for(match_config["ai_difficulty"]).choose_action(game_state.build_turn_snapshot())
	_is_thinking = false
	thinking_changed.emit(false)
	action_ready.emit(action)


func _strategy_for(difficulty: int):
	if _strategy_cache.has(difficulty):
		return _strategy_cache[difficulty]

	var strategy
	match difficulty:
		MatchConfigRef.AIDifficulty.EASY:
			strategy = EasyAIStrategyRef.new()
		MatchConfigRef.AIDifficulty.HARD:
			strategy = HardAIStrategyRef.new()
		_:
			strategy = MediumAIStrategyRef.new()

	_strategy_cache[difficulty] = strategy
	return strategy
