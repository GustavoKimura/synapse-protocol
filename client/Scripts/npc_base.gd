extends CharacterBody2D

enum State { IDLE, WANDER }

@export var speed: float = 64.0
@export var npc_name: String = "Subject_01"
@export var system_prompt: String = "You are a simulated human. You MUST respond ONLY with a valid JSON object matching this schema: {\"thought\": \"your internal monologue in one sentence\", \"action\": \"IDLE\" or \"WANDER\"}."
@export var cognition_url: String = "http://127.0.0.1:8000/process_cognition"

@onready var cognitive_api: HTTPRequest = $CognitiveAPI

var current_state: State = State.IDLE
var current_thought: String = ""
var target_direction: Vector2 = Vector2.ZERO
var state_timer: float = 5.0
var is_thinking: bool = false

func _ready() -> void:
	cognitive_api.request_completed.connect(_on_cognitive_api_request_completed)
	stimulate_cognition("Simulation started. What will you do?")

func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.WANDER:
			velocity = target_direction.normalized() * speed
	
	move_and_slide()
	
	if not is_thinking:
		state_timer -= delta
		if state_timer <= 0.0:
			stimulate_cognition("Time is passing. What is your next action?")

func stimulate_cognition(stimulus: String) -> void:
	is_thinking = true
	var current_world_state := {
		"time_of_day": "Morning",
		"weather": "Clear",
		"location": "Spawn_Room",
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
						current_thought = decision["thought"]
						print("[", npc_name, "] ", current_thought)
					if decision.has("action"):
						apply_action(decision["action"])
	
	is_thinking = false
	state_timer = randf_range(3.0, 6.0)

func apply_action(action: String) -> void:
	print("[", npc_name, "] Changing state to: ", action)
	if action == "WANDER":
		current_state = State.WANDER
		var dirs = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
		target_direction = dirs[randi() % dirs.size()]
	else:
		current_state = State.IDLE