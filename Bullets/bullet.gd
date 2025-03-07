extends Area2D

var velocity = Vector2.ZERO
var max_distance = 800
var start_position = Vector2.ZERO
var shooter_id = ""

func _ready():
	start_position = position

func _physics_process(delta):
	position += velocity * delta
	
	# 检查是否超出最大距离
	if position.distance_to(start_position) > max_distance:
		queue_free()

func _on_body_entered(body):
	if body is CharacterBody2D:
		# 不对发射者造成伤害
		if body.name != shooter_id and body.has_method("take_damage"):
			body.take_damage(5)
			call_deferred("queue_free")

func _on_area_entered(area):
	call_deferred("queue_free")
