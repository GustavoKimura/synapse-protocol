extends CharacterBody2D

enum State { IDLE, WANDER, APPROACH }

@export var speed: float = 64.0
@export var npc_name: String = "Subject_01"
@export var body_color: Color = Color(0.2, 0.8, 0.4, 1.0)
@export var system_prompt: String = "You are a simulated human. Return a JSON with 'thought' and 'action' (IDLE, WANDER, or APPROACH_name). Example: {\"thought\": \"I see Player.\", \"action\": \"APPROACH_Player\"}"
@export var cognition_url: String = "http://127.0.0.1:8000/process_cognition"

@onready var cognitive_api: HTTPRequest = $CognitiveAPI
@onready var thought_label: Label = $ThoughtBubble
@onready var sprite: Sprite2D = $Sprite2D
@onready var vision_area: Area2D = $VisionArea

var current_state: State = State.IDLE
var target_direction: Vector2 = Vector2.ZERO
var target_entity: Node2D = null
var state_timer: float = 5.0
var is_thinking: bool = false
var time_passed: float = 0.0

func _ready() -> void:
	add_to_group("Entity")
	randomize()
	sprite.modulate = body_color
	thought_label.visible = false
	cognitive_api.request_completed.connect(_on_cognitive_api_request_completed)
	stimulate_cognition("Simulation started. What will you do?")

func _physics_process(delta: float) -> void:
	time_passed += delta
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
			sprite.scale = Vector2(1, 1)
		State.WANDER:
			velocity = target_direction.normalized() * speed
			animate_walk()
		State.APPROACH:
			if is_instance_valid(target_entity):
				target_direction = (target_entity.global_position - global_position).normalized()
				velocity = target_direction * speed
				animate_walk()
				if global_position.distance_to(target_entity.global_position) < 25.0:
					velocity = Vector2.ZERO
					sprite.scale = Vector2(1, 1)
			else:
				current_state = State.IDLE
	
	move_and_slide()
	
	if get_slide_collision_count() > 0 and current_state == State.WANDER:
		current_state = State.IDLE
		target_direction = Vector2.ZERO
	
	if not is_thinking:
		state_timer -= delta
		if state_timer <= 0.0:
			stimulate_cognition("Time is passing. What is your next action?")

func animate_walk() -> void:
	var stretch = 1.0 + sin(time_passed * 20.0) * 0.15
	var squash = 1.0 - sin(time_passed * 20.0) * 0.15
	sprite.scale = Vector2(squash, stretch)

func get_visible_entities() -> Array:
	var entities = []
	for body in vision_area.get_overlapping_bodies():
		if body != self and body.is_in_group("Entity"):
			entities.append(body.name)
	return entities

func stimulate_cognition(stimulus: String) -> void:
	is_thinking = true
	var visible = get_visible_entities()
	var current_world_state := {
		"time_of_day": "Morning",
		"weather": "Clear",
		"location": "Town Square",
		"visible_entities_nearby": visible,
		"current_action": State.keys()[current_state]
	}
	
	var payload := {
		"npc_name": npc_name,
		"system_prompt": system_prompt,
		"world_state": current_world_state,
		"stimulus": stimulus,
		"temperature": 0.7
	}
	var json_payload := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	cognitive_api.request(cognition_url, headers, HTTPClient.METHOD_POST, json_payload)

func _on_cognitive_api_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var response_data = json.data
			if response_data.has("action_thought"):
				var raw_llm_json: String = response_data["action_thought"]
				var llm_json := JSON.new()
				if llm_json.parse(raw_llm_json) == OK:
					var decision = llm_json.data
					if decision.has("thought"):
						thought_label.text = str(decision["thought"])
					if decision.has("action"):
						apply_action(str(decision["action"]).to_upper())
	
	is_thinking = false
	state_timer = randf_range(3.0, 6.0)

func apply_action(action: String) -> void:
	if action.begins_with("APPROACH_"):
		var target_name = action.replace("APPROACH_", "")
		var tree = get_tree()
		if tree:
			var target = tree.get_root().find_child(target_name, true, false)
			if target and target is Node2D:
				target_entity = target
				current_state = State.APPROACH
			else:
				current_state = State.IDLE
	elif "WANDER" in action:
		current_state = State.WANDER
		var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2(1,1), Vector2(-1,1), Vector2(1,-1), Vector2(-1,-1)]
		target_direction = dirs[randi() % dirs.size()]
	else:
		current_state = State.IDLE