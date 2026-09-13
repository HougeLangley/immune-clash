extends CharacterBody3D
## 病原体 AI（M2）：服务器权威，客户端只收同步
## type: 1=细菌（地面近战追击） 2=病毒（浮空远程吐息）

const GRAVITY := 9.8
const PATHOGEN_COLOR := Color(1.0, 0.55, 0.15)
const IMMUNE_COLOR := Color(0.05, 0.75, 0.85)

func _team_color() -> Color:
	return IMMUNE_COLOR if ai_team == 1 else PATHOGEN_COLOR

var etype := 1
var ai_team := 2   # AI 所属阵营（1=免疫 2=病原体；与主机对立）
var hp := 60.0
var max_hp := 60.0
var target: Node3D = null
var retarget_timer := 0.0
var paint_trail_timer := 0.0   # 行进涂路计时器
var paint_spot := Vector3.ZERO # 涂地目标点
var paint_spot_t := 0.0        # 换点计时器
var last_paint_pos := Vector3(999, 999, 999)  # 上次涂色位置（防原地重复涂）
var _stuck_t := 0.0            # 卡死计时
var _stuck_pos := Vector3.ZERO  # 上次卡死检测位置
var _retreat_cd := 0.0          # 撤退目标冷却（防每帧刷新抖动）
var _skill_cd := 6.0            # 技能冷却（周期性占地技能）
var respawn_timer := -1.0
var _worm_t := 0.0
var _worm_segs: Array = []
var _worm_bases: Array = []
var _flagellum_segs: Array = []
var _flagellum_bases: Array = []
var _pulse_nodes: Array = []
var _pulse_bases: Array = []

# 类型参数
var move_speed := 3.0


func _enter_tree() -> void:
	set_multiplayer_authority(1)  # 服务器权威


func setup(t: int) -> void:
	etype = t
	match t:
		1:  # 细菌
			max_hp = 60; move_speed = 3.2
		2:  # 病毒
			max_hp = 40; move_speed = 2.4
		3:  # 支原体：快速不定形，高闪避
			max_hp = 30; move_speed = 4.5
		4:  # 寄生虫：Boss 型，高血量
			max_hp = 150; move_speed = 1.8
		5:  # 真菌：领地型，慢速
			max_hp = 80; move_speed = 0.6
	hp = max_hp


func _ready() -> void:
	add_to_group("enemies")
	set_process(true)
	set_meta("debris_color", _team_color())
	if ai_team == 2:
		add_child(_build_germ_ai(etype))
	else:
		add_child(_build_immune_ai(etype))
	$Collision.shape = _capsule(0.4, 1.2)
	position.y = 0.9
	print("[enemy] %s 就绪 id=%s 阵营=%d" % [
		["", "坦克", "狙击", "速射", "辅助", "爆发"][etype] if ai_team == 1 else ["", "细菌", "病毒", "支原体", "寄生虫", "真菌"][etype],
		name, ai_team])


func _capsule(r: float, h: float) -> CapsuleShape3D:
	var s := CapsuleShape3D.new()
	s.radius = r
	s.height = h
	return s


## 细菌：杆菌造型（复用玩家阵营的细菌模型语言）
func _build_germ_model() -> Node3D:
	var root := Node3D.new()
	var rod := _box(Vector3(0.62, 0.62, 1.3), PATHOGEN_COLOR)
	root.add_child(rod)
	for z in [-0.72, 0.72]:
		var cap := _box(Vector3(0.5, 0.5, 0.18), PATHOGEN_COLOR.lightened(0.15))
		cap.position = Vector3(0, 0, z)
		root.add_child(cap)
	for i in 3:
		var seg := _box(Vector3(0.09, 0.09, 0.34), PATHOGEN_COLOR.darkened(0.35))
		seg.position = Vector3((i - 1) * 0.16, 0.12 * (i % 2), 0.95)
		seg.rotation.y = (i - 1) * 0.4
		root.add_child(seg)
	for x in [-0.16, 0.16]:
		var eye := _box(Vector3(0.1, 0.1, 0.03), Color(0.9, 0.2, 0.1))
		eye.position = Vector3(x, 0.05, -0.68)
		root.add_child(eye)
	return root


## 病毒：低多边形几何体 + 刺突（电镜下的二十面体风）
func _build_virus_model() -> Node3D:
	var root := Node3D.new()
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.84
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.3, 0.55)  # 病毒紫红
	mat.roughness = 0.5
	sm.material = mat
	core.mesh = sm
	root.add_child(core)
	for i in 8:
		var ang := TAU * i / 8.0
		var spike := _box(Vector3(0.06, 0.06, 0.22), Color(0.9, 0.4, 0.6))
		spike.position = Vector3(cos(ang) * 0.5, 0, sin(ang) * 0.5)
		spike.rotation.y = -ang + PI / 2.0
		root.add_child(spike)
	var top := _box(Vector3(0.06, 0.22, 0.06), Color(0.9, 0.4, 0.6))
	top.position = Vector3(0, 0.5, 0)
	root.add_child(top)
	for x in [-0.12, 0.12]:
		var eye := _box(Vector3(0.09, 0.09, 0.03), Color(1, 0.9, 0.2))
		eye.position = Vector3(x, 0.08, -0.42)
		root.add_child(eye)
	return root


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	mi.mesh = mesh
	return mi


func _physics_process(delta: float) -> void:
	if respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return
	if not multiplayer.is_server():
		return  # 客户端：位置由 Synchronizer 推送
	_retreat_cd -= delta
	_skill_cd -= delta
	# 场界保险：出环拉回 / 坠落重生（与玩家同规格）
	var rr := Vector2(global_position.x, global_position.z).length()
	if rr > 24.0:
		global_position = Vector3(global_position.x / rr * 23.0,
			maxf(global_position.y, 0.9), global_position.z / rr * 23.0)
		velocity = Vector3.ZERO
	if global_position.y < -15.0:
		_respawn()
	var world := get_tree().get_first_node_in_group("world")
	if world == null or world.match_over:
		return
	# 开局倒计时：AI 冻结
	if world.round_countdown > 0.0:
		velocity.x = 0
		velocity.z = 0
		if etype != 2 and not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	# 技能减速 + 墨汁腐蚀（受免疫方墨汁持续伤害，与玩家同规则）
	var slow := 1.0
	if world.in_net_zone(global_position, 2):
		slow *= 0.5
	if world.is_marked(get_path()):
		slow *= 0.5  # 抗原标记：减速 50%（与 NET 网同效，叠加可达 25%）
	if world.tilemap and world.tilemap.tile_owner_at(global_position.x, global_position.z) != ai_team and world.tilemap.tile_owner_at(global_position.x, global_position.z) != 0:
		hp -= 8.0 * delta
		if hp <= 0.0 and multiplayer.is_server():
			_die(0)
	var spd := move_speed * slow

	# 重选目标
	retarget_timer -= delta
	if retarget_timer <= 0.0 or target == null or not is_instance_valid(target) \
			or target.global_position.y < -10.0:
		retarget_timer = 1.5
		target = _nearest_player()

	# ==== AI 目标系统（占地优先，不打架）====
	# 互相撕咬无意义：伤害来源=敌方踩己方墨汁腐蚀减速
	# 优先级：踩敌墨撤退 > 低血回城 > 敌近围涂 > 默认占地
	var on_enemy_ink: bool = false
	if world and world.tilemap:
		var under: int = world.tilemap.tile_owner_at(global_position.x, global_position.z)
		on_enemy_ink = under != 0 and under != ai_team
	var target_dist: float = 1e9
	if target != null and is_instance_valid(target) and target.global_position.y > -10.0:
		target_dist = global_position.distance_to(target.global_position)
	paint_spot_t -= delta  # 涂地点过期计时（无此行则永不换点）

	if on_enemy_ink:
		# 优先1：踩敌墨（掉血）→ 撤向己方出生区（没3秒才重设目标，不每帧刷新防抖）
		if _retreat_cd <= 0.0:
			_retreat_cd = 3.0
			paint_spot = _team_spawn_pos(world)
	elif hp < max_hp * 0.3:
		# 优先2：低血→回城回血（同样设一次不抖）
		if _retreat_cd <= 0.0:
			_retreat_cd = 3.0
			paint_spot = _team_spawn_pos(world)
	elif target_dist < 10.0 and target != null and is_instance_valid(target):
		# 优先3：敌近→在敌周围涂色（创造腐蚀区，敌踩己方墨掉血减速）
		if paint_spot_t <= 0.0 or global_position.distance_to(paint_spot) < 2.5:
			paint_spot_t = 3.0
			var ea := randf() * TAU
			var ed := randf_range(1.0, 4.0)
			paint_spot = target.global_position + Vector3(cos(ea) * ed, 0, sin(ea) * ed)
	elif paint_spot_t <= 0.0 or paint_spot == Vector3.ZERO \
			or global_position.distance_to(paint_spot) < 2.5:
		# 优先4：默认占地（找未涂/敌色瓦片）
		paint_spot_t = 6.0
		paint_spot = _find_paint_spot(world)

	# 卡死检测：2 秒没挪 1m→强制换点
	_stuck_t += delta
	if _stuck_t > 2.0:
		if global_position.distance_to(_stuck_pos) < 1.0:
			paint_spot = Vector3.ZERO
			paint_spot_t = 0.0
		_stuck_t = 0.0
		_stuck_pos = global_position

	_do_paint_mode(world, delta, spd)
	return

## 涂地模式：找非己方瓦片→移动→沿途大半径涂色
func _do_paint_mode(world, delta: float, spd: float) -> void:
	# 注：涂地点选择由上层优先级系统决定（撤退/围涂/占地），此处只执行移动+涂色
	# 移动向涂地点（撞墙时沿墙滑行，不硬推抖动）
	var dir := paint_spot - global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.5 else Vector3.ZERO
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if is_on_wall():
		var wn := get_wall_normal()
		wn.y = 0
		if wn.length() > 0.1:
			wn = wn.normalized()
			# 速度投影到墙面切向（沿墙绕行）
			var dot := velocity.x * wn.x + velocity.z * wn.z
			velocity.x -= wn.x * dot
			velocity.z -= wn.z * dot
	if etype == 2:
		velocity.y = sin(Time.get_ticks_msec() / 420.0) * 0.6  # 病毒漂浮
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
	# 高频大半径涂色（占领欲核心；移动足够距离才涂，防原地重复）
	paint_trail_timer -= delta
	if paint_trail_timer <= 0.0:
		paint_trail_timer = 0.7
		if global_position.distance_to(last_paint_pos) > 1.8:
			last_paint_pos = global_position
			world.paint.rpc(global_position, 2.2, ai_team)
	# 周期性技能（全部为占地型：多点位/散射/宽幅涂色）
	if _skill_cd <= 0.0:
		_skill_cd = randf_range(7.0, 11.0)
		_use_skill_paint(world, dir)
	look_at_target(dir)
	move_and_slide()


## 采样找涂地点：环绕 AI 自身+最远优先+己色跳过（避免原地反复涂）
## 撤退用：己方出生区位置
func _team_spawn_pos(world) -> Vector3:
	if world and world.has_method("team_spawn"):
		return world.team_spawn(ai_team)
	return Vector3.ZERO


func _find_paint_spot(world) -> Vector3:
	if world == null or world.tilemap == null:
		return Vector3.ZERO
	var best: Vector3 = Vector3.ZERO
	var best_d := -1.0
	for i in 10:
		var ang := randf() * TAU
		var d := randf_range(5.0, 15.0)
		# 环绕 AI 自身采样（非世界中心）→ 逼 AI 离开原地
		var p := global_position + Vector3(cos(ang) * d, 0, sin(ang) * d)
		p.y = 1.0
		# 钳制在场内（半径 22m）
		var rr := Vector2(p.x, p.z).length()
		if rr > 21.0:
			var s := 20.0 / rr
			p = Vector3(p.x * s, 1.0, p.z * s)
		# 跳过己方色瓦片
		if world.tilemap.tile_owner_at(p.x, p.z) == ai_team:
			continue
		# 越远分越高（鼓励扩张，不停留近处）
		if d > best_d:
			best_d = d
			best = p
	if best != Vector3.ZERO:
		return best
	# 附近全己色→朝场心对侧走（去敌方区域）
	var away: Vector3 = -global_position.normalized() if global_position.length() > 1.0 else Vector3.RIGHT
	return global_position + away * 12.0


## 占地技能（每角色一种涂地模式，周期释放）
func _use_skill_paint(world, move_dir: Vector3) -> void:
	match etype:
		1:
			# 细菌-分裂增殖：周身三团涂色
			for i in 3:
				var a1 := TAU * i / 3.0 + randf() * 0.5
				world.paint.rpc(global_position \
					+ Vector3(cos(a1) * 2.0, 0, sin(a1) * 2.0), 2.0, ai_team)
		2:
			# 病毒-突变爆发：六向散射墨弹
			for i in 6:
				var a2 := TAU * i / 6.0
				var vel := Vector3(cos(a2) * 16.0, 3.0, sin(a2) * 16.0)
				world.fire_ink.rpc(global_position + Vector3(0, 1.2, 0),
					vel, ai_team, 1.2)
		3:
			# 支原体-变形渗透：前方直线冲刺涂色
			var d3 := move_dir.normalized() if move_dir.length() > 0.1 else Vector3.FORWARD
			for i in 4:
				world.paint.rpc(global_position + d3 * (1.5 + i * 1.5), 1.5, ai_team)
		4:
			# 寄生虫-蠕动席卷：前方宽幅涂色
			var d4 := move_dir.normalized() if move_dir.length() > 0.1 else Vector3.FORWARD
			var perp := Vector3(-d4.z, 0, d4.x)
			for i in 5:
				var off := (i - 2) * 1.5
				world.paint.rpc(global_position + d4 * 3.5 \
					+ perp * off, 1.8, ai_team)
		5:
			# 真菌-孢子雨：周边五点随机轰炸
			for i in 5:
				var a5 := randf() * TAU
				var d5 := randf_range(2.5, 8.0)
				world.paint.rpc(global_position \
					+ Vector3(cos(a5) * d5, 0, sin(a5) * d5), 2.2, ai_team)


func look_at_target(dir: Vector3) -> void:
	if dir.length() > 0.01:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 0.15)



func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	var target_team := 2 if ai_team == 1 else 1
	for p in get_tree().get_nodes_in_group("players"):
		if p is CharacterBody3D and p.team() == target_team and p.global_position.y > -5.0:
			var d := global_position.distance_squared_to(p.global_position)
			if d < best_d:
				best_d = d
				best = p
	# AI 敌人（对方阵营，排除自己；友方 AI 也能打敌方 AI）
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and e is CharacterBody3D \
				and e.ai_team == target_team and e.global_position.y > -5.0:
			var d2 := global_position.distance_squared_to(e.global_position)
			if d2 < best_d:
				best_d = d2
				best = e
	return best


## 被击退（细菌撞击；RPC 兼容 AI 目标）
@rpc("any_peer", "call_local")
func knockback(vel: Vector3) -> void:
	velocity += vel


## 受击（所有端一致计算，死亡由服务器广播）
func apply_damage(dmg: int, shooter_id: int) -> void:
	hp -= dmg
	if hp <= 0 and multiplayer.is_server():
		_die(shooter_id)


func _die(shooter_id: int) -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		world.paint.rpc(global_position, 1.6, ai_team)
		# AI 名字按阵营+角色生成可读播报
		var gnames := {1: "细菌", 2: "病毒", 3: "支原体", 4: "寄生虫", 5: "真菌"}
		var inames := {1: "巨噬", 2: "淋巴", 3: "粒细胞", 4: "树突", 5: "肥大"}
		var tag: String = (gnames[etype] if ai_team == 2 else inames[etype]) + "AI"
		world.report_kill.rpc(shooter_id, 100 + etype, tag)
		world.play_ding()
	visible = false
	$Collision.set_deferred("disabled", true)
	hp = max_hp
	respawn_timer = 8.0
	print("[enemy] %s 被击破，8 秒后重生" % ["细菌" if etype == 1 else "病毒"])


func _respawn() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world:
		global_position = world.random_spawn(ai_team) + Vector3(0, 0.5, 0)
	velocity = Vector3.ZERO
	visible = true
	$Collision.set_deferred("disabled", false)


## 再战重置（与玩家同规格）
func reset_for_match() -> void:
	hp = max_hp
	respawn_timer = -1.0
	target = null
	visible = true
	$Collision.set_deferred("disabled", false)


## 支原体模型：不定形 blob（无细胞壁多形性）
func _build_mycoplasma_model() -> Node3D:
	var root := Node3D.new()
	var c := Color(0.6, 0.85, 0.3)  # 黄绿
	var core := _box(Vector3(0.6, 0.45, 0.7), c)
	root.add_child(core)
	for i in 5:
		var ang := TAU * i / 5.0
		var bump := _box(Vector3(0.2, 0.18, 0.2), c.lightened(0.2))
		bump.position = Vector3(cos(ang) * 0.38, randf_range(-0.1, 0.1),
			sin(ang) * 0.38)
		root.add_child(bump)
	var eye := _box(Vector3(0.09, 0.09, 0.03), Color(0.9, 0.2, 0.1))
	eye.position = Vector3(0, 0.03, -0.36)
	root.add_child(eye)
	return root


## 寄生虫模型：分节长虫
func _build_parasite_model() -> Node3D:
	var root := Node3D.new()
	var c := Color(0.75, 0.5, 0.3)  # 褐粉
	for i in 6:
		var s := 0.55 - i * 0.07
		var seg := _box(Vector3(s, s * 0.8, s), c.darkened(0.08 * i))
		seg.position = Vector3(0, -0.1, i * 0.3 - 0.7)
		root.add_child(seg)
	for x in [-0.14, 0.14]:
		var eye := _box(Vector3(0.1, 0.1, 0.03), Color(0.95, 0.85, 0.2))
		eye.position = Vector3(x, 0.08, -0.95)
		root.add_child(eye)
	var tail := _box(Vector3(0.1, 0.1, 0.35), c.darkened(0.35))
	tail.position = Vector3(0, -0.1, 1.4)
	root.add_child(tail)
	return root


## 真菌模型：珊瑚状分支+孢子球
func _build_fungus_model() -> Node3D:
	var root := Node3D.new()
	var c := Color(0.7, 0.5, 0.8)  # 紫
	var stem := _box(Vector3(0.45, 0.8, 0.45), c)
	stem.position = Vector3(0, -0.05, 0)
	root.add_child(stem)
	for i in 6:
		var ang := TAU * i / 6.0
		var br := _box(Vector3(0.1, 0.5, 0.1), c.lightened(0.25))
		br.position = Vector3(cos(ang) * 0.38, 0.2, sin(ang) * 0.38)
		br.rotation.z = cos(ang) * 0.5
		br.rotation.x = -sin(ang) * 0.5
		root.add_child(br)
	var cap := _box(Vector3(0.3, 0.3, 0.3), Color(0.85, 0.65, 0.95))
	cap.position = Vector3(0, 0.55, 0)
	root.add_child(cap)
	for x in [-0.14, 0.14]:
		var eye := _box(Vector3(0.08, 0.08, 0.03), Color(0.9, 0.9, 0.2))
		eye.position = Vector3(x, 0.05, -0.28)
		root.add_child(eye)
	return root


# ============ 病原体 AI 新造型 ============

## 病原体 AI 五造型（=玩家版精确复制，含动画注册）
func _build_germ_ai(etype_id: int) -> Node3D:
	var col := _team_color()
	var root := Node3D.new()
	var eye_c := Color(0.04, 0.04, 0.06)
	match etype_id:
		1:  # 细菌：椭圆+菌毛+鞭毛
			var core := _box(Vector3(0.5, 0.48, 0.7), col)
			core.position = Vector3(0, -0.15, 0)
			root.add_child(core)
			_pulse_nodes = [core]
			_pulse_bases = [core.position]
			for z in [-0.45, 0.45]:
				var cap := _box(Vector3(0.38, 0.38, 0.22), col.lightened(0.1))
				cap.position = Vector3(0, -0.15, z)
				root.add_child(cap)
				_pulse_nodes.append(cap)
				_pulse_bases.append(cap.position)
			for ring in 3:
				for j in 6:
					var ang := TAU * j / 6.0 + ring * 0.4
					var pilus := _box(Vector3(0.03, 0.03, 0.1), col.darkened(0.25))
					pilus.position = Vector3(cos(ang) * 0.2, -0.25 + ring * 0.1,
						sin(ang) * 0.28)
					pilus.rotation.y = -ang + PI / 2.0
					root.add_child(pilus)
			_flagellum_segs = []
			_flagellum_bases = []
			for i in 6:
				var seg_r := 0.035 - i * 0.004
				var seg := _box(Vector3(seg_r, seg_r, 0.14), col.darkened(0.3))
				var pos := Vector3(0, -0.15, 0.72 + i * 0.13)
				seg.position = pos
				root.add_child(seg)
				_flagellum_segs.append(seg)
				_flagellum_bases.append(pos)
			for x in [-0.14, 0.14]:
				var eye := _box(Vector3(0.09, 0.09, 0.03), eye_c)
				eye.position = Vector3(x, -0.05, -0.65)
				root.add_child(eye)
		2:  # 病毒：噬菌体
			var head := _box(Vector3(0.5, 0.45, 0.5), col)
			head.position = Vector3(0, 0.3, 0)
			root.add_child(head)
			for i in 4:
				var ang := TAU * i / 4.0 + PI / 4.0
				var facet := _box(Vector3(0.1, 0.1, 0.1), col.lightened(0.2))
				facet.position = Vector3(cos(ang) * 0.25, 0.3 + (i % 2) * 0.12,
					sin(ang) * 0.25)
				root.add_child(facet)
			var neck := _box(Vector3(0.12, 0.1, 0.12), col.darkened(0.25))
			neck.position = Vector3(0, 0, 0)
			root.add_child(neck)
			var tail := _box(Vector3(0.2, 0.35, 0.2), col)
			tail.position = Vector3(0, -0.2, 0)
			root.add_child(tail)
			var needle := _box(Vector3(0.06, 0.12, 0.06), Color(0.85, 0.85, 0.9))
			needle.position = Vector3(0, -0.45, 0)
			root.add_child(needle)
			var base := _box(Vector3(0.35, 0.06, 0.35), col.darkened(0.3))
			base.position = Vector3(0, -0.4, 0)
			root.add_child(base)
			for i in 6:
				var ang := TAU * i / 6.0
				var up := _box(Vector3(0.05, 0.25, 0.05), col.darkened(0.15))
				up.position = Vector3(cos(ang) * 0.22, -0.35, sin(ang) * 0.22)
				up.rotation.z = cos(ang) * 0.5
				up.rotation.x = -sin(ang) * 0.5
				root.add_child(up)
				var foot := _box(Vector3(0.07, 0.04, 0.07), col.darkened(0.4))
				foot.position = Vector3(cos(ang) * 0.45, -0.55, sin(ang) * 0.45)
				root.add_child(foot)
			for x in [-0.14, 0.14]:
				var eye := _box(Vector3(0.09, 0.09, 0.03), Color(1.0, 0.85, 0.1))
				eye.position = Vector3(x, 0.32, -0.26)
				root.add_child(eye)
		3:  # 支原体
			var core := _box(Vector3(0.7, 0.55, 0.8), col)
			root.add_child(core)
			for i in 4:
				var ang := TAU * i / 4.0 + 0.5
				var bump := _box(Vector3(0.25, 0.2, 0.25), col.lightened(0.15))
				bump.position = Vector3(cos(ang) * 0.45, -0.1 + (i % 2) * 0.12,
					sin(ang) * 0.45)
				root.add_child(bump)
			var eye := _box(Vector3(0.09, 0.09, 0.03), Color(0.9, 0.2, 0.1))
			eye.position = Vector3(0, 0.03, -0.42)
			root.add_child(eye)
		4:  # 寄生虫：蠕虫（8节+环带+肉刺+蠕动）
			var head := _box(Vector3(0.42, 0.36, 0.35), col.lightened(0.15))
			head.position = Vector3(0, -0.08, -1.0)
			root.add_child(head)
			var mouth := _box(Vector3(0.26, 0.18, 0.06), col.darkened(0.5))
			mouth.position = Vector3(0, -0.08, -1.18)
			root.add_child(mouth)
			for x in [-0.12, 0.12]:
				var eye := _box(Vector3(0.08, 0.08, 0.03), Color(0.95, 0.85, 0.2))
				eye.position = Vector3(x, 0.12, -0.95)
				root.add_child(eye)
			_worm_segs = []
			_worm_bases = []
			for i in 8:
				var t := i / 7.0
				var seg_w := 0.44 - t * 0.14
				var seg_h := 0.34 - t * 0.08
				var seg_c: Color
				if i == 3 or i == 4:
					seg_c = col.lightened(0.35)
				else:
					seg_c = col.darkened(0.06 * (i % 2))
				var seg := _box(Vector3(seg_w, seg_h, 0.22), seg_c)
				var seg_pos := Vector3(0, -0.1, -0.62 + i * 0.24)
				seg.position = seg_pos
				root.add_child(seg)
				_worm_segs.append(seg)
				_worm_bases.append(seg_pos)
				var bump := _box(Vector3(seg_w * 0.35, 0.05, 0.14),
					col.darkened(0.3))
				bump.position = Vector3(0, -0.27, -0.62 + i * 0.24)
				root.add_child(bump)
			var tail1 := _box(Vector3(0.16, 0.12, 0.2), col.darkened(0.2))
			var tail1_pos := Vector3(0, -0.1, 1.42)
			tail1.position = tail1_pos
			root.add_child(tail1)
			_worm_segs.append(tail1)
			_worm_bases.append(tail1_pos)
			var tail2 := _box(Vector3(0.07, 0.06, 0.16), col.darkened(0.4))
			var tail2_pos := Vector3(0, -0.1, 1.6)
			tail2.position = tail2_pos
			root.add_child(tail2)
			_worm_segs.append(tail2)
			_worm_bases.append(tail2_pos)
		5:  # 真菌：珊瑚
			var stem := _box(Vector3(0.4, 0.7, 0.4), col)
			stem.position = Vector3(0, -0.1, 0)
			root.add_child(stem)
			for i in 5:
				var ang := TAU * i / 5.0
				var br := _box(Vector3(0.1, 0.5, 0.1), col.lightened(0.25))
				br.position = Vector3(cos(ang) * 0.35, 0.15, sin(ang) * 0.35)
				br.rotation.z = cos(ang) * 0.5
				br.rotation.x = -sin(ang) * 0.5
				root.add_child(br)
			var spore := _box(Vector3(0.25, 0.25, 0.25), Color(0.85, 0.65, 0.95))
			spore.position = Vector3(0, 0.5, 0)
			root.add_child(spore)
			for x in [-0.12, 0.12]:
				var eye := _box(Vector3(0.08, 0.08, 0.03), Color(0.9, 0.9, 0.2))
				eye.position = Vector3(x, 0.05, -0.22)
				root.add_child(eye)
	return root


## 免疫 AI 五造型（=玩家版精确复制，含脉动注册）
func _build_immune_ai(etype_id: int) -> Node3D:
	var col := _team_color()
	var root := Node3D.new()
	var eye_c := Color(0.04, 0.04, 0.06)
	match etype_id:
		1:  # 巨噬细胞：马蹄形+伪足脉动
			var gray_blue := Color(0.45, 0.55, 0.65)
			var back := _box(Vector3(0.7, 0.65, 0.25), gray_blue)
			back.position = Vector3(0, -0.1, 0.35)
			root.add_child(back)
			for x in [-0.3, 0.3]:
				var arm := _box(Vector3(0.2, 0.55, 0.65), gray_blue)
				arm.position = Vector3(x, -0.1, 0)
				root.add_child(arm)
			var bridge := _box(Vector3(0.4, 0.3, 0.15), gray_blue.darkened(0.15))
			bridge.position = Vector3(0, -0.2, -0.3)
			root.add_child(bridge)
			_pulse_nodes = []
			_pulse_bases = []
			for i in 4:
				var ang := PI * (0.25 + i * 0.17)
				var p := _box(Vector3(0.1, 0.1, 0.45), gray_blue.lightened(0.1))
				var p_pos := Vector3(cos(ang) * 0.25, -0.15 + (i % 2) * 0.1,
					-0.4 - sin(ang) * 0.15)
				p.position = p_pos
				p.rotation.y = -ang + PI / 2.0
				root.add_child(p)
				_pulse_nodes.append(p)
				_pulse_bases.append(p_pos)
			for x in [-0.15, 0.15]:
				var eye := _box(Vector3(0.08, 0.08, 0.03), eye_c)
				eye.position = Vector3(x, 0.05, -0.35)
				root.add_child(eye)
		2:  # 淋巴细胞：致密三层+深核
			var dense_c := col.darkened(0.15)
			var core := _box(Vector3(0.45, 0.42, 0.45), dense_c)
			root.add_child(core)
			var layer2 := _box(Vector3(0.32, 0.3, 0.32), dense_c.lightened(0.12))
			layer2.position = Vector3(0, 0.08, 0)
			root.add_child(layer2)
			var layer3 := _box(Vector3(0.18, 0.16, 0.18), dense_c.lightened(0.25))
			layer3.position = Vector3(0, 0.15, 0)
			root.add_child(layer3)
			var nucleus := _box(Vector3(0.3, 0.28, 0.3), Color(0.15, 0.08, 0.3))
			nucleus.position = Vector3(0, -0.05, 0)
			root.add_child(nucleus)
			for x in [-0.12, 0.12]:
				var eye := _box(Vector3(0.07, 0.07, 0.03), eye_c)
				eye.position = Vector3(x, 0.02, -0.24)
				root.add_child(eye)
		3:  # 粒细胞：分叶核+窄环+车轮
			for i in 3:
				var ang := TAU * i / 3.0 + 0.4
				var lobe := _box(Vector3(0.22, 0.22, 0.22), col.darkened(0.2))
				lobe.position = Vector3(cos(ang) * 0.2, sin(ang) * 0.1, sin(ang) * 0.15)
				root.add_child(lobe)
			var body := _box(Vector3(0.5, 0.45, 0.5), col)
			body.position = Vector3(0, -0.05, 0)
			root.add_child(body)
			for i in 3:
				var ring := _box(Vector3(0.52 + i * 0.04, 0.08, 0.52 + i * 0.04),
					col.lightened(0.15 + i * 0.08))
				ring.position = Vector3(0, -0.15 + i * 0.12, 0)
				root.add_child(ring)
			for i in 6:
				var ang := TAU * i / 6.0
				var spoke := _box(Vector3(0.04, 0.04, 0.2), col.lightened(0.3))
				spoke.position = Vector3(cos(ang) * 0.28, 0.05, sin(ang) * 0.28)
				spoke.rotation.y = -ang + PI / 2.0
				root.add_child(spoke)
			for x in [-0.12, 0.12]:
				var eye := _box(Vector3(0.07, 0.07, 0.03), eye_c)
				eye.position = Vector3(x, 0.05, -0.26)
				root.add_child(eye)
		4:  # 树突细胞：8长枝+末端球
			var body := _box(Vector3(0.45, 0.42, 0.45), col)
			root.add_child(body)
			for i in 8:
				var ang := TAU * i / 8.0
				var tilt := (i % 2) * 0.35 - 0.15
				var dend := _box(Vector3(0.05, 0.05, 0.55), col.lightened(0.2))
				dend.position = Vector3(cos(ang) * 0.45, tilt, sin(ang) * 0.45)
				dend.rotation.y = -ang + PI / 2.0
				dend.rotation.x = tilt * 0.5
				root.add_child(dend)
				var tip := _box(Vector3(0.08, 0.08, 0.08), col.lightened(0.35))
				tip.position = Vector3(cos(ang) * 0.68, tilt + 0.05, sin(ang) * 0.68)
				root.add_child(tip)
			for x in [-0.1, 0.1]:
				var eye := _box(Vector3(0.07, 0.07, 0.03), eye_c)
				eye.position = Vector3(x, 0.05, -0.24)
				root.add_child(eye)
		5:  # 肥大细胞：14紫颗粒+3大突出
			var body := _box(Vector3(0.5, 0.45, 0.5), col)
			root.add_child(body)
			var purple := Color(0.65, 0.25, 0.75)
			for i in 14:
				var ang := TAU * i / 14.0
				var row := i % 4
				var r := 0.28 + (row % 2) * 0.06
				var g := _box(Vector3(0.1, 0.1, 0.1), purple)
				g.position = Vector3(cos(ang) * r, -0.1 + row * 0.1, sin(ang) * r)
				root.add_child(g)
			for i in 3:
				var ang := TAU * i / 3.0 + 0.5
				var big := _box(Vector3(0.14, 0.14, 0.14), purple.lightened(0.15))
				big.position = Vector3(cos(ang) * 0.32, 0.08, sin(ang) * 0.32)
				root.add_child(big)
			for x in [-0.12, 0.12]:
				var eye := _box(Vector3(0.07, 0.07, 0.03), eye_c)
				eye.position = Vector3(x, 0.08, -0.26)
				root.add_child(eye)
	return root


## 视觉动画（所有端运行，与玩家版同规格同公式）
func _process(delta: float) -> void:
	_worm_t += delta
	# 寄生虫蠕动（行波：弹跳+摆动+挤压）
	if _worm_segs.size() > 0:
		var s := _worm_t * 4.0
		for i in _worm_segs.size():
			var seg: Node3D = _worm_segs[i]
			if is_instance_valid(seg):
				var base: Vector3 = _worm_bases[i]
				var phase := i * 0.8
				var amp_y := 0.05 * (1.0 - float(i) / _worm_segs.size() * 0.5)
				var amp_x := 0.03 * (1.0 - float(i) / _worm_segs.size() * 0.3)
				seg.position.y = base.y + sin(s + phase) * amp_y
				seg.position.x = base.x + sin(s * 0.6 + phase) * amp_x
				var sq := 1.0 + sin(s + phase) * 0.06
				seg.scale = Vector3(sq, sq, 2.0 - sq)
	# 细菌鞭毛（鞭状甩动）
	if _flagellum_segs.size() > 0:
		var fs := _worm_t * 8.0
		for i in _flagellum_segs.size():
			var fseg: Node3D = _flagellum_segs[i]
			if is_instance_valid(fseg):
				var fbase: Vector3 = _flagellum_bases[i]
				var fphase := i * 0.7
				var amp_x := 0.015 + i * 0.025
				fseg.position.x = fbase.x + sin(fs + fphase) * amp_x
				fseg.position.y = fbase.y + cos(fs * 0.8 + fphase) * 0.008
	# 通用脉动（细菌体伸缩/巨噬伪足伸缩）
	if _pulse_nodes.size() > 0:
		var pt := _worm_t * 2.5
		for i in _pulse_nodes.size():
			var pn: Node3D = _pulse_nodes[i]
			if is_instance_valid(pn):
				var pb: Vector3 = _pulse_bases[i]
				var phase := i * 0.7
				pn.position.y = pb.y + sin(pt + phase) * 0.015
				var sq := 1.0 + sin(pt + phase) * 0.04
				pn.scale = Vector3(sq, sq, 2.0 - sq)
