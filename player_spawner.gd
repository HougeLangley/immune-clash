extends MultiplayerSpawner
## 玩家生成器：服务器调用 spawn([位置, peer_id])，自动复制到所有客户端


func _ready() -> void:
	set_spawn_function(spawn_player)


func spawn_player(data: Array) -> CharacterBody3D:
	if data.size() < 2 or typeof(data[0]) != TYPE_VECTOR3 or typeof(data[1]) != TYPE_INT:
		push_error("spawn 参数错误：需要 [Vector3 位置, int peer_id, int 角色]")
		return null
	var player: CharacterBody3D = preload("res://player.tscn").instantiate()
	player.name = str(data[1])
	player.char_id = data[2] if data.size() > 2 else 1
	player.my_team = data[3] if data.size() > 3 else 0
	player.position = data[0]  # 未入树，用局部坐标（父节点在原点，等效全局）
	return player
