extends Node2D

var server_IP :String= Global.server_IP
var server_port :String= Global.server_port

# 预加载玩家场景
const PlayerScene = preload("res://Players/player.tscn")
# 预加载子弹场景
const BulletScene = preload("res://Bullets/bullet.tscn")
# 预加载道具场景
const HealthItemScene = preload("res://Items/health_item.tscn")
const AmmoItemScene = preload("res://Items/ammo_item.tscn")

# 预定义一些颜色供玩家使用
const PLAYER_COLORS = [
	Color(1, 0.5, 0.5),  # 红色
	Color(0.5, 1, 0.5),  # 绿色
	Color(0.5, 0.5, 1),  # 蓝色
	Color(1, 1, 0.5),    # 黄色
	Color(1, 0.5, 1),    # 粉色
	Color(0.5, 1, 1),    # 青色
]

# 记录已分配的颜色
var used_colors = {}

var ws = WebSocketPeer.new()
var my_id = ""
var players = {}

# 添加游戏状态变量
var game_running = false

# UI 引用
@onready var position_label = $UI/PlayerInfo/VBox/PositionLabel
@onready var health_label = $UI/PlayerInfo/VBox/HealthLabel
@onready var ammo_label = $UI/PlayerInfo/VBox/AmmoLabel
@onready var item_count_label = $UI/PlayerInfo/VBox/ItemLabel  
@onready var online_player_label = $UI/PlayerInfo/VBox/OnlinePlayer

var local_player = null  # 存储本地玩家的引用
var item_count = 0  # 跟踪道具数量

@onready var players_node = $Players
@onready var bullets_node = $Bullets
@onready var items_node = $Items



func _ready():
	# 连接到服务器
	ws.connect_to_url("ws://"+server_IP+":"+server_port)
	
	# 通知服务器我们已经从房间进入游戏
	await get_tree().create_timer(0.5).timeout  # 等待连接建立
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({
			"type": "enter_game",
			"name": Global.player_name
		}))
	
	# 初始化在线玩家数量显示
	update_online_player_count()

func _process(delta):
	ws.poll()
	
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count():
				var packet = ws.get_packet()
				var data = JSON.parse_string(packet.get_string_from_utf8())
				handle_message(data)
		WebSocketPeer.STATE_CLOSING:
			# 我们正在关闭连接
			pass
		WebSocketPeer.STATE_CLOSED:
			var code = ws.get_close_code()
			var reason = ws.get_close_reason()
			print("WebSocket 服务器关闭 代码: %d, 原因: %s" % [code, reason])
			
			# 当连接关闭时，返回到UI场景
			await get_tree().create_timer(0.1).timeout  # 短暂延迟以确保消息显示
			get_tree().change_scene_to_file("res://GUI/ui.tscn")
			return  # 不再尝试重新连接

	# 更新UI信息
	if local_player and is_instance_valid(local_player):
		# 更新位置信息
		position_label.text = "位置: X: %d, Y: %d" % [local_player.position.x, local_player.position.y]
		# 更新生命值信息
		health_label.text = "生命值: %d" % local_player.health
		# 更新弹药信息
		ammo_label.text = "弹药: %d" % local_player.ammo

func check_game_end():
	# 检查存活玩家数量（只计算生命值大于0的玩家）
	var alive_players = []
	for player in players.values():
		if is_instance_valid(player) and player.health > 0:
			alive_players.append(player)
	
	if alive_players.size() <= 1 and game_running:
		game_running = false
		# 找到获胜者
		var winner_name = "没有人"
		if alive_players.size() == 1:
			winner_name = alive_players[0].player_name
		
		# 通知所有客户端游戏结束
		ws.send_text(JSON.stringify({
			"type": "game_over",
			"winner": winner_name
		}))
		
		# 使用定时器延迟返回主菜单
		var timer = get_tree().create_timer(3.0)
		timer.timeout.connect(func():
			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				ws.close()
			get_tree().change_scene_to_file("res://GUI/ui.tscn")
		)

func handle_message(data):
	print("收到数据包: ", data.type)
	match data.type:
		"game_init":
			# 游戏初始化消息，与之前的init消息不同
			print("正在初始化游戏玩家 ID: ", data.id)
			my_id = data.id
			game_running = true
			
			# 创建本地玩家
			var player = spawn_player(data.id, data.color, true)
			player.set_player_name(Global.player_name)
			if "position" in data:
				player.position = Vector2(data.position.x, data.position.y)
			
			update_online_player_count()
			
		"player_joined":
			if data.id != my_id:
				var player = spawn_player(data.id, data.color, false)
				player.set_player_name(data.name)
				# 设置玩家位置
				if "position" in data:
					player.position = Vector2(data.position.x, data.position.y)
			else:
				var player = spawn_player(data.id, data.color, true)
				player.set_player_name(data.name)
				# 设置玩家位置
				if "position" in data:
					player.position = Vector2(data.position.x, data.position.y)
				
			update_online_player_count()
			
		"player_left":
			if data.id in players:
				players[data.id].queue_free()
				players.erase(data.id)
				# 更新在线玩家数量
				update_online_player_count()
				# 检查游戏结束
				check_game_end()
				
		"position_update":
			if data.id in players and data.id != my_id:
				if is_instance_valid(players[data.id]):  # 检查玩家是否还有效
					players[data.id].position = Vector2(data.position.x, data.position.y)
				
		"shoot":
			if data.id in players and data.id != my_id:
				if is_instance_valid(players[data.id]):
					var bullet = BulletScene.instantiate()
					bullet.position = Vector2(data.position.x, data.position.y)
					bullet.velocity = Vector2(data.direction.x, data.direction.y) * 400
					bullet.shooter_id = str(data.id)
					bullets_node.add_child(bullet)
				
		"health_update":
			if data.id in players and data.id != my_id:
				if is_instance_valid(players[data.id]):
					var player = players[data.id]
					player.update_health(data.health)
					if data.health <= 0:
						player.die()
				
		"game_over":
			# 显示获胜者信息
			print("游戏结束！获胜者：", data.winner)
			# 可以在这里添加UI显示获胜者信息
			await get_tree().create_timer(3.0).timeout
			ws.close()
			get_tree().change_scene_to_file("res://GUI/ui.tscn")
		
		"server_shutdown":
			# 显示服务器关闭消息
			print("服务器已关闭")
			# 断开连接并返回主菜单
			ws.close()  # 这会触发 STATE_CLOSED 状态，从而返回UI场景
		
		"spawn_item":
			print("生成%s道具，位置: X: %d, Y: %d" % [
				"生命值" if data.item_type == "health" else "弹药",
				data.position.x,
				data.position.y
			])
			var item
			if data.item_type == "health":
				item = HealthItemScene.instantiate()
			else:  # ammo
				item = AmmoItemScene.instantiate()
			
			item.position = Vector2(data.position.x, data.position.y)
			item.item_id = data.item_id
			item.spawn_time = Time.get_unix_time_from_system()
			items_node.add_child(item)
			item_count += 1
			item_count_label.text = "场上道具: %d" % item_count
			
		"item_collected":
			# 其他玩家拾取道具时，移除道具
			for item in get_tree().get_nodes_in_group("items"):
				if item.item_id == data.item_id:
					item.queue_free()
					item_count -= 1
					item_count_label.text = "场上道具: %d" % item_count
					break

func spawn_player(id, color, is_local):
	var player = PlayerScene.instantiate()
	player.name = str(id)
	player.set_player_color(Color(color.r, color.g, color.b))
	player.is_local = is_local
	
	# 设置摄像机
	var camera = player.get_node("Camera2D")
	if is_local:
		camera.enabled = true
		print("启用摄像机成功！")
		local_player = player
	else:
		camera.enabled = false
		
	players_node.add_child(player)
	players[id] = player
	return player

# 添加更新在线玩家数量的函数
func update_online_player_count():
	var count = players.size()
	online_player_label.text = "在线玩家: %d" % count
