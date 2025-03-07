extends BaseItem

func _ready():
	super._ready()
	item_type = "health"
	modulate = Color(1, 0.478431, 1, 1)  # 粉色

func apply_effect(player):
	if player.health < 100:  # 限制最大生命值
		player.health = min(player.health + 10, 100)
		player.health_bar.value = player.health
