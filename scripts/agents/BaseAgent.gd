class_name BaseAgent
extends Node

signal action_ready(action)
signal status_changed(status)
signal explanation_ready(text)

var agent_spec: Dictionary = {}
var setup_context: Dictionary = {}


func setup(spec: Dictionary, context: Dictionary = {}) -> void:
	agent_spec = spec.duplicate(true)
	setup_context = context


func request_action(_observation: Dictionary) -> void:
	pass


func cancel() -> void:
	pass


func get_action_codec():
	return setup_context.get("action_codec")


func get_agent_type() -> int:
	return int(agent_spec.get("type", -1))
