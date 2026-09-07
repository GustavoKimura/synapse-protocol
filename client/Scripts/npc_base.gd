extends CharacterBody2D

enum Estado { PARADO, VAGAR, APROXIMAR }

@export var speed: float = 64.0
@export var npc_name: String = "Sujeito_01"
@export var body_color: Color = Color(0.2, 0.8, 0.4, 1.0)
@export var system_prompt: String = "Você é um humano simulado. Retorne um JSON PLANO com 'pensamento' e 'acao' (PARADO, VAGAR, ou APROXIMAR_Jogador). NÃO aninhe objetos."
@export var cognition_url: String = "http://127.0.0.1:8000/process_cognition"

@onready var cognitive_api: HTTPRequest = $CognitiveAPI
@onready var sprite: Sprite2D = $Sprite2D
@onready var vision_area: Area2D = $VisionArea

var estado_atual: Estado = Estado.PARADO
var direcao_alvo: Vector2 = Vector2.ZERO
var entidade_alvo: Node2D = null
var temporizador_estado: float = 5.0
var pensando: bool = false
var tempo_passado: float = 0.0

func _ready() -> void:
	add_to_group("Entidade")
	randomize()
	sprite.modulate = body_color
	cognitive_api.request_completed.connect(_on_cognitive_api_request_completed)
	estimular_cognicao("A simulacao comecou. O que voce fara?")

func _physics_process(delta: float) -> void:
	tempo_passado += delta
	match estado_atual:
		Estado.PARADO:
			velocity = Vector2.ZERO
			sprite.scale = Vector2(1, 1)
		Estado.VAGAR:
			velocity = direcao_alvo * speed
			animar_caminhada()
		Estado.APROXIMAR:
			if is_instance_valid(entidade_alvo):
				direcao_alvo = (entidade_alvo.global_position - global_position).normalized()
				velocity = direcao_alvo * speed
				animar_caminhada()
				if global_position.distance_to(entidade_alvo.global_position) < 30.0:
					velocity = Vector2.ZERO
					sprite.scale = Vector2(1, 1)
			else:
				estado_atual = Estado.PARADO
	
	move_and_slide()
	
	if get_slide_collision_count() > 0 and estado_atual == Estado.VAGAR:
		estado_atual = Estado.PARADO
		direcao_alvo = Vector2.ZERO
	
	if not pensando:
		temporizador_estado -= delta
		if temporizador_estado <= 0.0:
			estimular_cognicao("O tempo esta passando. Qual e a sua proxima acao?")

func animar_caminhada() -> void:
	var stretch = 1.0 + sin(tempo_passado * 20.0) * 0.15
	var squash = 1.0 - sin(tempo_passado * 20.0) * 0.15
	sprite.scale = Vector2(squash, stretch)

func obter_entidades_visiveis() -> Array:
	var entidades = []
	for body in vision_area.get_overlapping_bodies():
		if body != self and body.is_in_group("Entidade"):
			entidades.append(body.name)
	return entidades

func estimular_cognicao(estimulo: String) -> void:
	pensando = true
	var visiveis = obter_entidades_visiveis()
	var estado_mundo_atual := {
		"hora_do_dia": "Manha",
		"clima": "Limpo",
		"localizacao": "Praca da Cidade",
		"entidades_visiveis_proximas": visiveis,
		"acao_atual": Estado.keys()[estado_atual]
	}
	
	var payload := {
		"npc_name": npc_name,
		"system_prompt": system_prompt,
		"world_state": estado_mundo_atual,
		"stimulus": estimulo,
		"temperature": 0.3
	}
	var json_payload := JSON.stringify(payload)
	var headers := ["Content-Type: application/json"]
	cognitive_api.request(cognition_url, headers, HTTPClient.METHOD_POST, json_payload)

func _on_cognitive_api_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var dados_resposta = json.data
			if dados_resposta.has("action_thought"):
				var json_llm_puro: String = dados_resposta["action_thought"]
				var json_llm := JSON.new()
				if json_llm.parse(json_llm_puro) == OK:
					var decisao = json_llm.data
					if decisao.has("acao"):
						var str_acao = str(decisao["acao"]).to_upper()
						if "APROXIMAR" in str_acao:
							if "PLAYER" in str_acao: aplicar_acao("APROXIMAR_Player")
							elif "SUJEITO_01" in str_acao: aplicar_acao("APROXIMAR_Sujeito_01")
							elif "SUJEITO_02" in str_acao: aplicar_acao("APROXIMAR_Sujeito_02")
							else: aplicar_acao("VAGAR")
						elif "VAGAR" in str_acao:
							aplicar_acao("VAGAR")
						else:
							aplicar_acao("PARADO")
	
	pensando = false
	temporizador_estado = randf_range(3.0, 6.0)

func aplicar_acao(acao: String) -> void:
	if acao.begins_with("APROXIMAR_"):
		var nome_alvo = acao.replace("APROXIMAR_", "")
		var arvore = get_tree()
		if arvore:
			var alvo = arvore.get_root().find_child(nome_alvo, true, false)
			if alvo and alvo is Node2D:
				entidade_alvo = alvo
				estado_atual = Estado.APROXIMAR
			else:
				estado_atual = Estado.PARADO
	elif "VAGAR" in acao:
		estado_atual = Estado.VAGAR
		direcao_alvo = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	else:
		estado_atual = Estado.PARADO