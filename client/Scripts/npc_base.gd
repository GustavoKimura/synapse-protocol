extends CharacterBody2D

@export var speed: float = 64.0
@export var target_direction: Vector2 = Vector2.ZERO
@export var npc_name: String = "Subject_01"
@export var system_prompt: String = "You are a simulated human. Respond in one sentence."
@export var cognition_url: String = "http://127.0.0.1:8000/process_cognition"

@onready var cognitive_api: HTTPRequest = $CognitiveAPI

var current_thought: String = ""

func _ready() -> void:
	cognitive_api.request_completed.connect(_on_cognitive_api_request_completed)
	stimulate_cognition("Wake up.")

func _physics_process(_delta: float) -> void:
	velocity = target_direction.normalized() * speed
	move_and_slide()

func stimulate_cognition(stimulus: String) -> void:
	var current_world_state := {
		"time_of_day": "Morning",
		"weather": "Clear",
		"location": "Spawn_Room"
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
		var error := json.parse(body.get_string_from_utf8())
		if error == OK:
			var response_data = json.data
			if response_data.has("action_thought"):
				current_thought = response_data["action_thought"]
				print("[", npc_name, "] Thought received: ", current_thought)