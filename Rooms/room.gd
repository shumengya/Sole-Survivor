extends Node2D

var server_IP: String = Global.server_IP
var server_port: String = Global.server_port
var ws = WebSocketPeer.new()
var my_id = ""
var players = {}
var my_ready_status = false

@onready var player_list = $UI/PlayerList
@onready var ready_button = $UI/ReadyButton
@onready var status_label = $UI/StatusLabel

func _ready():
	# 连接到服务器
	ws.connect_to_url("ws://" + server_IP + ":" + server_port)
	status_label.text = "正在连接到服务器..."
	ready_button.pressed.connect(_on_ready_button_pressed)

func _process(delta):
	ws.poll()
	
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count():
				var packet = ws.get_packet()
				var data = JSON.parse_string(packet.get_string_from_utf8())
				handle_message(data)
		WebSocketPeer.STATE_CLOSING:
			# 正在关闭连接
			pass
		WebSocketPeer.STATE_CLOSED:
			var code = ws.get_close_code()
			var reason = ws.get_close_reason()
			print("WebSocket 服务器关闭 代码: %d, 原因: %s" % [code, reason])
			
			# 当连接关闭时，返回到UI场景
			await get_tree().create_timer(0.1).timeout
			get_tree().change_scene_to_file("res://GUI/ui.tscn")
			return

func handle_message(data):
	print("房间收到数据包: ", data.type)
	match data.type:
		"init":
			print("正在初始化玩家 ID: ", data.id)
			my_id = data.id
			status_label.text = "已连接到服务器"
			# 发送玩家名称到服务器
			ws.send_text(JSON.stringify({
				"type": "player_name",
				"name": Global.player_name
			}))
			
		"room_player_joined":
			print("玩家加入房间: ", data.name)
			update_player_in_list(data.id, data.name, data.ready)
			
		"room_player_left":
			print("玩家离开房间: ", data.id)
			remove_player_from_list(data.id)
			
		"player_ready_status":
			print("玩家准备状态更新: ", data.id, " 准备状态: ", data.ready)
			update_player_ready_status(data.id, data.ready)
			
		"start_game":
			print("所有玩家已准备，游戏即将开始...")
			status_label.text = "所有玩家已准备，游戏即将开始..."
			await get_tree().create_timer(1.0).timeout
			get_tree().change_scene_to_file("res://main.tscn")
			
		"server_shutdown":
			print("服务器已关闭")
			ws.close()

func update_player_in_list(id, player_name, ready_status):
	# 如果玩家不在列表中，添加到列表
	if not id in players:
		players[id] = {
			"name": player_name,
			"ready": ready_status
		}
	else:
		# 更新玩家信息
		players[id].name = player_name
		players[id].ready = ready_status
	
	refresh_player_list()

func remove_player_from_list(id):
	if id in players:
		players.erase(id)
		refresh_player_list()

func update_player_ready_status(id, ready_status):
	if id in players:
		players[id].ready = ready_status
		refresh_player_list()

func refresh_player_list():
	# 清空当前列表
	for child in player_list.get_children():
		child.queue_free()
	
	# 重新填充列表
	for id in players:
		var player_info = players[id]
		var label = Label.new()
		var ready_text = "[准备完毕]" if player_info.ready else "[未准备]"
		var is_you = " (你)" if id == my_id else ""
		label.text = player_info.name + is_you + " " + ready_text
		player_list.add_child(label)

func _on_ready_button_pressed():
	my_ready_status = !my_ready_status
	ready_button.text = "取消准备" if my_ready_status else "准备"
	
	# 发送准备状态到服务器
	ws.send_text(JSON.stringify({
		"type": "player_ready",
		"ready": my_ready_status
	})) 