extends CharacterBody2D

# 玩家属性变量相关
@export var speed = 200 #玩家移动速度
@export var health = 100 #玩家当前生命值
@export var max_health = 100 #玩家最大生命值
@export var bullet_speed = 400 #玩家射出的子弹速度
@export var ammo = 100 #玩家弹药数量
@export var shoot_delay = 0.2 #玩家射击最快冷却时间

var is_local = false #是否为本地玩家
var player_name = "" #玩家名称
var can_shoot = true #是否可以射击

const BulletScene = preload("res://Bullets/bullet.tscn")

@onready var name_label = $Player_Name
@onready var health_bar = $HealthBar
@onready var shoot_timer = $ShootTimer

func _ready():
	# 设置碰撞层和掩码
	# 注意碰撞层和掩码的概念
	set_collision_layer(2)  # 玩家在第2层
	set_collision_mask(1)   # 玩家只与第1层（地图）碰撞
	
	# 初始化生命值条
	health_bar.max_value = max_health
	health_bar.value = health
	
	# 设置射击定时器
	shoot_timer.wait_time = shoot_delay
	shoot_timer.one_shot = true
	
	# 只有本地玩家可以处理输入
	if is_local:
		set_physics_process(true)
	else:
		set_physics_process(false)

func _physics_process(delta):
	if not is_local:
		return
	
	# 处理输入
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * speed
	move_and_slide()
	
	# 处理射击
	if Input.is_action_pressed("shoot") and can_shoot:
		shoot()
	
	# 发送位置更新到服务器
	var root = get_node("/root/Main")
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send_text(JSON.stringify({
			"type": "position_update",
			"position": {
				"x": position.x,
				"y": position.y
			}
		}))

func shoot():
	if not can_shoot or not is_local:
		return
		
	if ammo <= 0:  # 检查弹药数量
		print("弹药不足！")
		return
		
	can_shoot = false
	shoot_timer.start()
	ammo -= 1  # 减少弹药数量
	
	var bullet = BulletScene.instantiate()
	bullet.position = self.position
	bullet.shooter_id = self.name
	
	# 计算射击方向（朝向鼠标位置）
	var mouse_pos = get_global_mouse_position()
	var direction = (mouse_pos - position).normalized()
	bullet.velocity = direction * bullet_speed
	
	# 发送射击信息到服务器
	var root = get_node("/root/Main")
	if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send_text(JSON.stringify({
			"type": "shoot",
			"position": {
				"x": position.x,
				"y": position.y
			},
			"direction": {
				"x": direction.x,
				"y": direction.y
			}
		}))
	
	root.get_node("Bullets").add_child(bullet)

func take_damage(amount):
	if not is_local:  # 只处理本地玩家的伤害
		return
		
	health -= amount
	health_bar.value = health
	
	# 发送生命值更新到服务器
	var root = get_node("/root/Main")
	if root and root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		root.ws.send_text(JSON.stringify({
			"type": "health_update",
			"health": health
		}))
	
	if health <= 0:
		call_deferred("die")

# 新增方法：更新生命值（用于网络同步）
func update_health(new_health):
	health = new_health
	health_bar.value = health

func die():
	if is_local:
		# 使用定时器延迟返回主菜单
		var timer = get_tree().create_timer(0.1)
		timer.timeout.connect(func():
			var root = get_node("/root/Main")
			if root and root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				root.ws.close()
			get_tree().change_scene_to_file("res://GUI/ui.tscn")
		)
	
	# 不要立即从 players 字典中移除玩家
	# 让玩家保持在场景中，但是禁用其功能
	set_physics_process(false)
	modulate.a = 0.5  # 半透明表示死亡状态

# 在玩家节点之外处理场景切换
class DeathHandler extends Node:
	func handle_death(root):
		if root and root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			root.ws.close()
		get_tree().change_scene_to_file("res://GUI/ui.tscn")
		# 删除自己
		queue_free()

func _on_shoot_timer_timeout():
	can_shoot = true

# 设置玩家颜色
func set_player_color(color: Color):
	$Sprite2D.modulate = color

func set_player_name(new_name: String):
	player_name = new_name
	name_label.text = player_name
