extends Area2D
class_name BaseItem

var item_id = ""  # 服务器分配的道具ID
var spawn_time = 0  # 生成时间
var item_type = ""  # 道具类型

func _ready():
	# 将道具添加到组以便跟踪
	add_to_group("items")
	
	# 2分钟后自动消失
	var timer = get_tree().create_timer(120)
	timer.timeout.connect(func():
		# 更新道具计数
		var root = get_node("/root/Main")
		if root:
			root.item_count -= 1
			root.item_count_label.text = "场上道具: %d" % root.item_count
		queue_free()
	)

func _on_body_entered(body):
	if body is CharacterBody2D and body.is_local:
		# 通知服务器道具被拾取
		var root = get_node("/root/Main")
		if root.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			root.ws.send_text(JSON.stringify({
				"type": "item_collected",
				"item_id": item_id,
				"item_type": item_type
			}))
		
		# 应用道具效果
		apply_effect(body)
		
		# 更新道具计数
		root.item_count -= 1
		root.item_count_label.text = "场上道具: %d" % root.item_count
		
		queue_free()

# 虚函数，由子类实现具体效果
func apply_effect(player):
	pass 
