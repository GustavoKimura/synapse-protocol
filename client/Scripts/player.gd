extends CharacterBody2D

@export var speed: float = 120.0
@onready var sprite: Sprite2D = $Sprite2D
var time_passed: float = 0.0

func _ready() -> void:
	add_to_group("Entity")

func _physics_process(delta: float) -> void:
	time_passed += delta
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_dir * speed
	move_and_slide()
	
	if velocity.length() > 0:
		var stretch = 1.0 + sin(time_passed * 20.0) * 0.15
		var squash = 1.0 - sin(time_passed * 20.0) * 0.15
		sprite.scale = Vector2(squash, stretch)
	else:
		sprite.scale = Vector2(1, 1)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_select"):
		print("[SISTEMA DE VOZ] Microfone ABERTO. Gravando...")
		$UI/VoicePrompt.modulate = Color(1, 0.2, 0.2)
		$UI/VoicePrompt.text = "Gravando Voz... (Fale agora)"
	elif event.is_action_released("ui_select"):
		print("[SISTEMA DE VOZ] Microfone FECHADO. Preparando envio para Whisper...")
		$UI/VoicePrompt.modulate = Color(1, 1, 1)
		$UI/VoicePrompt.text = "Pressione [ESPACO] para Falar"