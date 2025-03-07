extends BaseItem

func _ready():
	super._ready()
	item_type = "ammo"
	modulate = Color(1, 0.8, 0, 1)  # 金色

func apply_effect(player):
	player.ammo = min(player.ammo + 5, 200)  # 限制最大弹药数为100
