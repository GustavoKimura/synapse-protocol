extends CharacterBody2D

@export var speed: float = 120.0
@onready var sprite: Sprite2D = $Sprite2D
@onready var voice_prompt: Label = $UI/VoicePrompt

var time_passed: float = 0.0
var mic_bus_idx: int
var record_effect: AudioEffectRecord
var mic_player: AudioStreamPlayer
var is_recording: bool = false
var http_request: HTTPRequest

func _ready() -> void:
	add_to_group("Entidade")
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_transcription_completed)
	
	mic_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(mic_bus_idx)
	AudioServer.set_bus_name(mic_bus_idx, "Microfone")
	record_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(mic_bus_idx, record_effect)
	AudioServer.set_bus_mute(mic_bus_idx, true)
	
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Microfone"
	add_child(mic_player)
	mic_player.play()

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
	if event.is_action_pressed("ui_select") and not is_recording:
		is_recording = true
		record_effect.set_recording_active(true)
		voice_prompt.modulate = Color(1, 0.2, 0.2)
		voice_prompt.text = "Gravando Voz... (Fale e solte o ESPACO)"
		print("[SISTEMA DE VOZ] Microfone ABERTO. Gravando...")
		
	elif event.is_action_released("ui_select") and is_recording:
		is_recording = false
		record_effect.set_recording_active(false)
		voice_prompt.modulate = Color(1, 1, 0)
		voice_prompt.text = "Enviando audio para transcricao..."
		print("[SISTEMA DE VOZ] Microfone FECHADO. Enviando...")
		
		var recording = record_effect.get_recording()
		if recording:
			var save_path = "user://voz_temp.wav"
			recording.save_to_wav(save_path)
			send_voice_to_backend(save_path)

func send_voice_to_backend(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	var buffer = file.get_buffer(file.get_length())
	file.close()
	
	var boundary = "WebKitFormBoundary7MA4YWxkTrZu0gW"
	var body = PackedByteArray()
	body.append_array(("--" + boundary + "\r\n").to_utf8_buffer())
	body.append_array(("Content-Disposition: form-data; name=\"file\"; filename=\"voz.wav\"\r\n").to_utf8_buffer())
	body.append_array(("Content-Type: audio/wav\r\n\r\n").to_utf8_buffer())
	body.append_array(buffer)
	body.append_array(("\r\n--" + boundary + "--\r\n").to_utf8_buffer())
	
	var headers = ["Content-Type: multipart/form-data; boundary=" + boundary]
	http_request.request("http://127.0.0.1:8000/transcribe_voice", headers, HTTPClient.METHOD_POST, body)

func _on_transcription_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	voice_prompt.modulate = Color(1, 1, 1)
	voice_prompt.text = "Pressione [ESPACO] para Falar"
	
	if response_code == 200:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var transcription = json.data.get("text", "")
			if transcription != "":
				print("[JOGADOR FALOU]: ", transcription)
				broadcast_to_npcs(transcription)

func broadcast_to_npcs(spoken_text: String) -> void:
	var tree = get_tree()
	if tree:
		for node in tree.get_nodes_in_group("Entidade"):
			if node.has_method("estimular_cognicao") and node != self:
				if global_position.distance_to(node.global_position) < 250.0:
					node.estimular_cognicao("O JOGADOR DISSE PARA VOCE: " + spoken_text)