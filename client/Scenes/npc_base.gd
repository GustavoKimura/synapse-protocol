extends CharacterBody2D

@export var speed: float = 64.0
@export var target_direction: Vector2 = Vector2.ZERO

func _physics_process(_delta: float) -> void:
	velocity = target_direction.normalized() * speed
	move_and_slide()