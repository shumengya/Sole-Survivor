extends CanvasLayer

@onready var ip_input = $IP
@onready var join_server_btn: Button = $JoinServerBtn
@onready var user_name: LineEdit = $User_Name
@onready var port_input :LineEdit = $Port

# 随机名称生成所需的数组
const ADJECTIVES = ['快乐的', '勇敢的', '聪明的', '可爱的', '神秘的', '友好的']
const NOUNS = ['小萌芽', '大萌芽', '红萌芽', '黑萌芽', '萌芽9号', '萌芽8号']

func _ready():
	# 连接按钮信号
	join_server_btn.pressed.connect(_on_join_server)

func generate_random_name() -> String:
	var adjective = ADJECTIVES[randi() % ADJECTIVES.size()]
	var noun = NOUNS[randi() % NOUNS.size()]
	var random_num = randi() % 1000
	return adjective + noun + str(random_num)

func _on_join_server():
	# 如果玩家名称为空，生成随机名称
	if user_name.text.strip_edges().is_empty():
		Global.player_name = generate_random_name()
	else:
		Global.player_name = user_name.text
	
	Global.server_IP = ip_input.text
	Global.server_port = port_input.text
	# 加载房间场景
	get_tree().change_scene_to_file("res://Rooms/room.tscn")
