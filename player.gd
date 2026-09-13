extends CharacterBody3D
## 玩家 v2-M2：五免疫细胞角色（专属造型/武器手感/特殊技能）
## 第三人称 + 墨汁涂色射击；技能触屏按钮或 F 键

const GRAVITY := 9.8
const MOUSE_SENS := 0.0022
const TOUCH_SENS := 0.0045

const INK_MAX := 100.0
const INK_COST := 8.0
const INK_REGEN := 14.0
const INK_REGEN_OWN := 45.0   # 己方墨上弹药快速恢复（3.2 倍）

## 角色定义：速度/射速/弹速/弧度/染色半径/技能冷却
const CHARS := {
	1: {"name": "巨噬细胞", "spd": 1.0, "cd": 0.30, "vel": 16.0, "arc": 2.6,
		"rad": 1.7, "skill_cd": 8.0, "skill": "吞噬 - 锥形拉拽+大面积涂色"},
	2: {"name": "淋巴细胞", "spd": 1.05, "cd": 0.65, "vel": 28.0, "arc": 0.6,
		"rad": 2.5, "skill_cd": 10.0, "skill": "抗体导弹 - 自动追踪涂色三连发"},
	3: {"name": "粒细胞", "spd": 1.1, "cd": 0.10, "vel": 14.0, "arc": 2.8,
		"rad": 0.9, "skill_cd": 12.0, "skill": "NET网 - 减速陷阱区域"},
	4: {"name": "树突细胞", "spd": 1.15, "cd": 0.24, "vel": 20.0, "arc": 2.2,
		"rad": 1.4, "skill_cd": 14.0, "skill": "抗原呈递 - 减速敌群+自身加速+大涂色"},
	5: {"name": "肥大细胞", "spd": 0.95, "cd": 0.34, "vel": 15.0, "arc": 3.0,
		"rad": 1.9, "skill_cd": 12.0, "skill": "脱颗粒 - 爆发涂色+击退"},
}

## 病原体五角色：专属造型/武器手感/技能（与免疫方对与对称）
const GERM_CHARS := {
	1: {"name": "细菌", "spd": 1.0, "cd": 0.26, "vel": 17.0, "arc": 2.2,
		"rad": 1.5, "skill_cd": 8.0, "skill": "分裂增殖 - 周身三团快速涂色"},
	2: {"name": "病毒", "spd": 1.1, "cd": 0.45, "vel": 24.0, "arc": 1.0,
		"rad": 1.0, "skill_cd": 10.0, "skill": "突变爆发 - 六向散射涂色弹"},
	3: {"name": "支原体", "spd": 1.2, "cd": 0.20, "vel": 19.0, "arc": 1.8,
		"rad": 1.3, "skill_cd": 9.0, "skill": "变形渗透 - 冲刺+沿途涂色轨迹"},
	4: {"name": "寄生虫", "spd": 0.9, "cd": 0.36, "vel": 14.0, "arc": 2.8,
		"rad": 1.8, "skill_cd": 11.0, "skill": "蠕动席卷 - 直线冲锋宽幅涂色"},
	5: {"name": "真菌", "spd": 0.85, "cd": 0.40, "vel": 13.0, "arc": 3.2,
		"rad": 2.0, "skill_cd": 13.0, "skill": "孢子雨 - 8m 内五点随机轰炸"},
}

const SPEED := 6.0
const SPEED_OWN := 1.4
const SPEED_ENEMY := 0.6
const OWN_INK_HPS := 10.0
const ENEMY_INK_DPS := 8.0
const JUMP_VELOCITY := 4.6

const TEAM_COLORS: Array[Color] = [
	Color(1, 1, 1), Color(0.05, 0.75, 0.85), Color(1.0, 0.55, 0.15),
]
const ROLE_NAMES := ["", "巨噬细胞", "细菌"]

var char_id := 1
var my_team := 0   # 阵营（1=免疫 2=病原体），0=未定（回退按主机判定）
var hp := 100.0
var ink := INK_MAX
var fire_timer := 0.0
var skill_timer := 0.0
var boost_timer := 0.0     # 树突加速
var no_shoot_time := 0.0
var shots := 0
var tile_owner := 0

@onready var head: Node3D = $Head
@onready var cam_arm: SpringArm3D = $Head/SpringArm3D
@onready var camera: Camera3D = $Head/SpringArm3D/Camera3D


func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())


func team() -> int:
	if my_team != 0:
		return my_team
	return 1 if get_multiplayer_authority() == 1 else 2


func cinfo() -> Dictionary:
	return CHARS[char_id] if team() == 1 else GERM_CHARS[char_id]


var _worm_segs: Array = []   # 寄生虫体节引用（蠕动动画用）
var _worm_bases: Array = []  # 每节的基础位置
var _worm_t := 0.0           # 蠕动时钟
var _flagellum_segs: Array = []  # 细菌鞭毛引用
var _flagellum_bases: Array = []
var _pulse_nodes: Array = []   # 通用脉动节点（细菌体/巨噬伪足）
var _pulse_bases: Array = []


func _ready() -> void:
	var is_me := is_multiplayer_authority()
	camera.current = is_me
	cam_arm.position = Vector3(0.7, 0.45, 0)
	cam_arm.spring_length = 4.4
	cam_arm.margin = 0.5
	cam_arm.add_excluded_object(get_rid())
	head.rotation.x = -0.22
	$Body.visible = false

	var t := team()
	var team_col: Color = TEAM_COLORS[t]
	var col: Color = gamestate.get_player_color(
		gamestate.get_player_name(get_multiplayer_authority()))
	var body := _build_cell_model(team_col) if t == 1 else _build_germ_v2_model(team_col)
	add_child(body)
	set_meta("debris_color", team_col)
	set_meta("model", body)

	if not is_me:
		var tag := Label3D.new()
		tag.text = gamestate.get_player_name(get_multiplayer_authority())
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.font_size = 40
		tag.pixel_size = 0.004
		tag.outline_size = 10
		tag.modulate = col
		tag.position = Vector3(0, 1.1, 0)
		head.add_child(tag)
	else:
		var me := Label3D.new()
		me.text = cinfo()["name"]
		me.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		me.font_size = 56
		me.pixel_size = 0.004
		me.outline_size = 14
		me.modulate = Color(1, 1, 1)
		me.position = Vector3(0, 1.65, 0)
		head.add_child(me)
		var world0 = _world()
		if world0:
			world0.set_my_team(t)
	print("[player] id=%d 就绪 (本机=%s) 队伍=%d 角色=%s" % [
		get_multiplayer_authority(), is_me, t,
		cinfo()["name"] if t == 1 else "细菌"])


## 程序化免疫细胞模型（按角色差异化的五造型）

## 免疫细胞·按用户描述重做（马蹄/致密/分叶/夸张树突/满颗粒）
func _build_cell_model(col: Color) -> Node3D:
	var root := Node3D.new()
	var eye_c := Color(0.04, 0.04, 0.06)
	match char_id:
		1:  # 巨噬细胞：大身体、马蹄形、灰蓝色、有伪足
			var gray_blue := Color(0.45, 0.55, 0.65)
			# 马蹄形主体（U 形：后壁+两侧臂）
			var back := _box(Vector3(0.7, 0.65, 0.25), gray_blue)
			back.position = Vector3(0, -0.1, 0.35)
			root.add_child(back)
			for x in [-0.3, 0.3]:
				var arm := _box(Vector3(0.2, 0.55, 0.65), gray_blue)
				arm.position = Vector3(x, -0.1, 0)
				root.add_child(arm)
			# 前端连接桥
			var bridge := _box(Vector3(0.4, 0.3, 0.15), gray_blue.darkened(0.15))
			bridge.position = Vector3(0, -0.2, -0.3)
			root.add_child(bridge)
			# 伪足（从 U 形开口伸出，4 根长条，注册到脉动系统）
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
			# 眼睛在前端
			for x in [-0.15, 0.15]:
				var eye := _box(Vector3(0.08, 0.08, 0.03), eye_c)
				eye.position = Vector3(x, 0.05, -0.35)
				root.add_child(eye)
		2:  # 淋巴细胞：小身体、圆形、致密块状
			var dense_c := col.darkened(0.15)
			# 致密小圆体（多层堆叠=块状感）
			var core := _box(Vector3(0.45, 0.42, 0.45), dense_c)
			root.add_child(core)
			var layer2 := _box(Vector3(0.32, 0.3, 0.32), dense_c.lightened(0.12))
			layer2.position = Vector3(0, 0.08, 0)
			root.add_child(layer2)
			var layer3 := _box(Vector3(0.18, 0.16, 0.18), dense_c.lightened(0.25))
			layer3.position = Vector3(0, 0.15, 0)
			root.add_child(layer3)
			# 致密核（深色大块，占体积 60%）
			var nucleus := _box(Vector3(0.3, 0.28, 0.3), Color(0.15, 0.08, 0.3))
			nucleus.position = Vector3(0, -0.05, 0)
			root.add_child(nucleus)
			for x in [-0.12, 0.12]:
				var eye := _box(Vector3(0.07, 0.07, 0.03), eye_c)
				eye.position = Vector3(x, 0.02, -0.24)
				root.add_child(eye)
		3:  # 粒细胞：分叶状、中等体型、窄环和车轮装饰
			# 分叶核（3 个叶块，不规则分布）
			for i in 3:
				var ang := TAU * i / 3.0 + 0.4
				var lobe := _box(Vector3(0.22, 0.22, 0.22), col.darkened(0.2))
				lobe.position = Vector3(cos(ang) * 0.2, sin(ang) * 0.1,
					sin(ang) * 0.15)
				root.add_child(lobe)
			# 主体
			var body := _box(Vector3(0.5, 0.45, 0.5), col)
			body.position = Vector3(0, -0.05, 0)
			root.add_child(body)
			# 窄环装饰（3 条环形带）
			for i in 3:
				var ring := _box(Vector3(0.52 + i * 0.04, 0.08, 0.52 + i * 0.04),
					col.lightened(0.15 + i * 0.08))
				ring.position = Vector3(0, -0.15 + i * 0.12, 0)
				root.add_child(ring)
			# 车轮状装饰（6 根辐条从中心辐射）
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
		4:  # 树突细胞：中等体型、圆形、夸张的长树突突起
			var body := _box(Vector3(0.45, 0.42, 0.45), col)
			root.add_child(body)
			# 夸张长树突（8 根，比体径更长，像海胆刺）
			for i in 8:
				var ang := TAU * i / 8.0
				var tilt := (i % 2) * 0.35 - 0.15
				var dend := _box(Vector3(0.05, 0.05, 0.55), col.lightened(0.2))
				dend.position = Vector3(cos(ang) * 0.45, tilt,
					sin(ang) * 0.45)
				dend.rotation.y = -ang + PI / 2.0
				dend.rotation.x = tilt * 0.5
				root.add_child(dend)
				# 树突末端小球
				var tip := _box(Vector3(0.08, 0.08, 0.08), col.lightened(0.35))
				tip.position = Vector3(cos(ang) * 0.68, tilt + 0.05,
					sin(ang) * 0.68)
				root.add_child(tip)
			for x in [-0.1, 0.1]:
				var eye := _box(Vector3(0.07, 0.07, 0.03), eye_c)
				eye.position = Vector3(x, 0.05, -0.24)
				root.add_child(eye)
		5:  # 肥大细胞：紫色颗粒多且扩张
			var body := _box(Vector3(0.5, 0.45, 0.5), col)
			root.add_child(body)
			# 满身紫色颗粒（14 颗，大且分布广）
			var purple := Color(0.65, 0.25, 0.75)
			for i in 14:
				var ang := TAU * i / 14.0
				var row := i % 4
				var r := 0.28 + (row % 2) * 0.06  # 交替两层，扩张分布
				var g := _box(Vector3(0.1, 0.1, 0.1), purple)
				g.position = Vector3(cos(ang) * r,
					-0.1 + row * 0.1, sin(ang) * r)
				root.add_child(g)
			# 部分颗粒更大（3 颗突出的）
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


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mesh.material = mat
	mi.mesh = mesh
	return mi


func _world():
	return get_tree().get_first_node_in_group("world")


func _process(delta: float) -> void:
	_worm_t += delta  # 动画总时钟：无条件递增（细菌/巨噬的脉动也依赖此时钟）
	# 寄生虫蠕动动画（行波：每节按相位差弹跳+摆动，从头到尾传播）
	if _worm_segs.size() > 0:
		var s := _worm_t * 4.0  # 波速
		for i in _worm_segs.size():
			var seg: Node3D = _worm_segs[i]
			if is_instance_valid(seg):
				var base: Vector3 = _worm_bases[i]
				var phase := i * 0.8  # 每节相位差（行波）
				# 垂直弹跳（peristalsis，头部幅度大尾部小）
				var amp_y := 0.05 * (1.0 - float(i) / _worm_segs.size() * 0.5)
				# 左右摆动（蛇形）
				var amp_x := 0.03 * (1.0 - float(i) / _worm_segs.size() * 0.3)
				seg.position.y = base.y + sin(s + phase) * amp_y
				seg.position.x = base.x + sin(s * 0.6 + phase) * amp_x
				# 挤压感（收缩/舒张）
				var sq := 1.0 + sin(s + phase) * 0.06
				seg.scale = Vector3(sq, sq, 2.0 - sq)
	# 细菌鞭毛动画（鞭状左右甩+微上下）
	if _flagellum_segs.size() > 0:
		var fs := _worm_t * 8.0  # 鞭毛比虫更快
		for i in _flagellum_segs.size():
			var fseg: Node3D = _flagellum_segs[i]
			if is_instance_valid(fseg):
				var fbase: Vector3 = _flagellum_bases[i]
				var fphase := i * 0.7
				# 振幅从头到尾递增（鞭梢甩得最厉害）
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


## 面向场地中央（出生/复活后调用）
func face_arena_center() -> void:
	rotation.y = atan2(global_position.x, global_position.z)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_cam(event.relative * MOUSE_SENS)
	elif event is InputEventMouseButton and event.pressed \
			and not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED)


func _rotate_cam(d: Vector2) -> void:
	rotate_y(-d.x)
	head.rotation.x = clampf(head.rotation.x - d.y, -1.1, 0.45)


# ---------------- 主循环 ----------------

var _dbg_timer := 0.0


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var world = _world()
	if world and world.match_over:
		return
	# 开局倒计时：冻结移动+锁枪（公平开局）
	if world and world.round_countdown > 0.0:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	# 掉出世界保险 + 半径硬钳制
	if global_position.y < -20.0:
		if world:
			global_position = world.random_spawn(team())
			face_arena_center()
		velocity = Vector3.ZERO
	var rr := Vector2(global_position.x, global_position.z).length()
	if rr > 23.8:
		var dir2 := Vector2(global_position.x, global_position.z) / rr
		global_position = Vector3(dir2.x * 23.8, global_position.y, dir2.y * 23.8)

	# 触屏视角
	if world and world.touch:
		var look: Vector2 = world.touch.consume_look()
		if look != Vector2.ZERO:
			_rotate_cam(look * TOUCH_SENS)

	# 移动（角色速度系数 + 树突加速 + 墨中机动）
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var jump := Input.is_action_just_pressed("jump")
	if world and world.touch:
		input_dir += world.touch.joy_vec
		if input_dir.length() > 1.0:
			input_dir = input_dir.normalized()
		if world.touch.just_jump():
			jump = true
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var dir := (fwd * -input_dir.y + right * input_dir.x)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	var speed_mult := 1.0
	var my_team := team()
	if world and world.tilemap:
		tile_owner = world.tilemap.tile_owner_at(global_position.x, global_position.z)
		if tile_owner == my_team:
			speed_mult = SPEED_OWN
			hp = minf(hp + OWN_INK_HPS * delta, 100.0)
		elif tile_owner != 0:
			speed_mult = SPEED_ENEMY
			if not world.is_protected(get_multiplayer_authority()):
				hp -= ENEMY_INK_DPS * delta
				if hp <= 0.0:
					on_death.rpc(0)
	# 技能减速：NET 网区内 ×0.5，抗原标记 ×0.7
	if world:
		if world.in_net_zone(global_position, my_team):
			speed_mult *= 0.5
		if world.is_marked(get_path()):
			speed_mult *= 0.5
	var char_spd: float = cinfo()["spd"] * (1.5 if boost_timer > 0.0 else 1.0)
	velocity.x = dir.x * SPEED * speed_mult * char_spd
	velocity.z = dir.z * SPEED * speed_mult * char_spd
	if jump and is_on_floor():
		velocity.y = JUMP_VELOCITY
	move_and_slide()

	# 计时器
	fire_timer -= delta
	skill_timer -= delta
	boost_timer -= delta
	if no_shoot_time < 0.5:
		no_shoot_time += delta
	else:
		# 己方墨上弹药快回（3.2 倍），普通地面正常速率
		var ink_regen: float = INK_REGEN_OWN \
			if tile_owner == team() else INK_REGEN
		ink = minf(ink + ink_regen * delta, INK_MAX)

	var touchscreen := DisplayServer.is_touchscreen_available()
	var want_hold := Input.is_action_pressed("fire") and not touchscreen
	var want_edge := Input.is_action_just_pressed("fire") and not touchscreen
	var want_skill := Input.is_action_just_pressed("skill")
	if world and world.touch:
		want_edge = want_edge or world.touch.consume_fire_edge()
		if world.touch.just_skill():
			want_skill = true
	# 开局倒计时：锁枪锁技能
	if world and world.round_countdown > 0.0:
		want_hold = false
		want_edge = false
		want_skill = false
	if (want_edge or want_hold) and fire_timer <= 0.0 and ink >= INK_COST:
		fire_timer = cinfo()["cd"]
		_shoot(world)
	if want_skill and skill_timer <= 0.0:
		skill_timer = cinfo()["skill_cd"]
		_use_skill(world)

	# 复活保护闪烁（结束时确保恢复可见，否则 50% 概率卡在隐身相位）
	var model: Node3D = get_meta("model", null)
	if world and world.is_protected(get_multiplayer_authority()):
		if model:
			model.visible = fmod(Time.get_ticks_msec() / 100.0, 2.0) < 1.0
	elif model and not model.visible:
		model.visible = true

	# HUD + 诊断
	if world:
		world.set_ink(int(ink))
		world.set_hp(int(hp))
		world.set_skill_ready(skill_timer <= 0.0)
		_dbg_timer += delta
		if _dbg_timer > 3.0:
			_dbg_timer = 0.0
			var w0 = _world()
			var to := -1
			if w0 and w0.tilemap:
				to = w0.tilemap.tile_owner_at(global_position.x, global_position.z)
			print("[player] 诊断 fps=", Engine.get_frames_per_second(),
				" 血=", int(hp), " 墨=", int(ink), " 击发=", shots,
				" 角色=", cinfo()["name"],
				" 站瓦片=", tile_owner, " 实查=", to, " my_team=", my_team,
				" team()=", team(), " pos=", global_position.round())


func _shoot(world) -> void:
	ink -= INK_COST
	no_shoot_time = 0.0
	shots += 1
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(
		from, from + dir * 60.0, 0xFFFFFFFF, [self])
	var aim := from + dir * 60.0
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		aim = hit.position
	var muzzle := global_position + Vector3(0, 1.0, 0) - global_transform.basis.z * 0.6
	var info: Dictionary = cinfo()
	var vel_dir: Vector3 = (aim - muzzle).normalized() * float(info["vel"]) + Vector3(0, float(info["arc"]), 0)
	world.fire_ink.rpc(muzzle, vel_dir, team(), float(info["rad"]))


# ---------------- 五大技能 ----------------

func _use_skill(world) -> void:
	var my_team := team()
	if my_team == 2:
		_use_germ_skill(world)
		return
	match char_id:
		1:  # 吞噬：前方锥形拉拽 + 大面积涂色（把敌人拖进我的墨海）
			var fwd := -global_transform.basis.z
			if get_tree().get_nodes_in_group("enemies").size() > 0:
				for en in get_tree().get_nodes_in_group("enemies"):
					if not en.visible:
						continue
					var to: Vector3 = en.global_position - global_position
					to.y = 0
					if to.length() < 4.0 and to.normalized().dot(Vector3(fwd.x, 0, fwd.z).normalized()) > 0.5:
						en.velocity = -to.normalized() * 8.0 + Vector3.UP * 2.0
			for pl in world.get_node("Players").get_children():
				if pl != self and pl.team() != my_team:
					var to: Vector3 = pl.global_position - global_position
					to.y = 0
					if to.length() < 4.0:
						pl.knockback.rpc(-to.normalized() * 6.0)
			for d in [1.0, 2.2, 3.4]:
				world.paint.rpc(global_position + Vector3(fwd.x, 0, fwd.z) * d, 1.3, my_team)
			world._spawn_debris(global_position - fwd * 1.5 + Vector3.UP,
				fwd, TEAM_COLORS[my_team], 8)
			world.play_ding()
		2:  # 抗体导弹：追踪/直射双模式（始终有反馈）
			var tgt := _nearest_foe(world, 30.0)
			for i in 3:
				var from := global_position + Vector3(0, 1.3, 0) \
					+ Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
				if tgt:
					world.fire_homing.rpc(from, team(), tgt.get_path(),
						get_multiplayer_authority(), 0.15 * i)
				else:
					# 无目标：朝相机前方直射
					var dir := -camera.global_transform.basis.z
					var vel: Vector3 = dir * 18.0 + Vector3(0, 2.5, 0)
					world.fire_ink.rpc(from, vel, team(), 1.1)
			world.play_ding()
		3:  # NET 网：脚下减速陷阱区（区内敌方 ×0.5，5 秒）+ 占地
			world.add_net_zone.rpc(global_position, my_team)
			world.paint.rpc(global_position, 3.0, my_team)
			world.play_ding()
		4:  # 抗原呈递：减速 20m 敌群（×0.5，6 秒）+ 自身加速 ×1.5 + 大范围涂色
			boost_timer = 6.0
			for en in get_tree().get_nodes_in_group("enemies"):
				if en.visible and en.global_position.distance_to(global_position) < 20.0:
					world.mark_enemy.rpc(en.get_path(), 6.0)
			for pl in world.get_node("Players").get_children():
				if pl != self and pl.team() != my_team \
						and pl.global_position.distance_to(global_position) < 20.0:
					world.mark_enemy.rpc(pl.get_path(), 6.0)
			# 核心反馈：大范围涂色宣示领地
			world.paint.rpc(global_position, 8.0, my_team)
			world._spawn_debris(global_position + Vector3(0, 0.8, 0),
				Vector3.UP, TEAM_COLORS[my_team], 14)
			world.antigen_wave.rpc(global_position)
			world.play_ding()
		5:  # 脱颗粒：范围爆发涂色 + 击退（推入我方墨海）
			world.burst.rpc(global_position, my_team,
				get_multiplayer_authority())
			world.play_ding()
	print("[player] 技能释放：", cinfo()["skill"])


## 被击退（服务器广播，纯位移控制）
@rpc("any_peer", "call_local")
func knockback(vel: Vector3) -> void:
	velocity += vel


## 再战重置（各端执行；位置仅拥有者设置，经同步推送）
@rpc("any_peer", "call_local")
func reset_for_match() -> void:
	hp = 100.0
	ink = INK_MAX
	boost_timer = 0.0
	skill_timer = 0.0
	shots = 0
	if is_multiplayer_authority():
		var world = _world()
		if world:
			global_position = world.random_spawn(team())
			face_arena_center()
		velocity = Vector3.ZERO
	print("[player] 再战重置 id=", get_multiplayer_authority())
func _nearest_foe(world, max_d: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_d
	# 用 group 查找（路径查找已证实不可靠）
	for en in get_tree().get_nodes_in_group("enemies"):
		if en.visible:
			var d: float = global_position.distance_to(en.global_position)
			if d < best_d:
				best_d = d
				best = en
	for pl in world.get_node("Players").get_children():
		if pl != self and pl.team() != team():
			var d: float = global_position.distance_to(pl.global_position)
			if d < best_d:
				best_d = d
				best = pl
	return best


# ---------------- 伤害与死亡 ----------------

@rpc("any_peer", "call_local")
func take_damage(dmg: int, shooter_id: int) -> void:
	# 纯涂地规则：直接伤害已移除，仅保留接口（墨汁腐蚀为唯一伤害，本地结算）
	pass


@rpc("any_peer", "call_local")
func on_death(shooter_id: int) -> void:
	hp = 100.0
	ink = INK_MAX
	boost_timer = 0.0
	if is_multiplayer_authority():
		var world = _world()
		world.paint.rpc(global_position, 2.6, team())
		world.report_kill.rpc(shooter_id, get_multiplayer_authority())
		world.consume_life.rpc(team())
		global_position = world.random_spawn(team())
		face_arena_center()
		velocity = Vector3.ZERO
		world.death_flash()
		world.set_protection.rpc(get_multiplayer_authority(), 2.0)

## ---------------- 病原体五技能 ----------------

func _use_germ_skill(world) -> void:
	var my_team := team()
	match char_id:
		1:  # 细菌·分裂增殖：周身三团快速涂色
			for ang in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
				var d := Vector3(cos(ang), 0, sin(ang)) * 3.0
				world.paint.rpc(global_position + d, 2.0, my_team)
			world._spawn_debris(global_position + Vector3.UP,
				Vector3.UP, TEAM_COLORS[my_team], 10)
			world.play_ding()
		2:  # 病毒·突变爆发：六向散射涂色弹
			for i in 6:
				var ang := TAU * i / 6.0
				var vel := Vector3(cos(ang) * 16.0, 3.0, sin(ang) * 16.0)
				world.fire_ink.rpc(global_position + Vector3(0, 1.2, 0),
					vel, my_team, 1.2)
			world.play_ding()
		3:  # 支原体·变形渗透：冲刺+沿途涂色轨迹
			var fwd := -global_transform.basis.z
			boost_timer = 2.0
			for d in [1.0, 2.5, 4.0, 5.5, 7.0]:
				world.paint.rpc(
					global_position + Vector3(fwd.x, 0, fwd.z) * d, 1.5, my_team)
			world.play_ding()
		4:  # 寄生虫·蠕动席卷：直线冲锋宽幅涂色
			var fwd2 := -global_transform.basis.z
			velocity = fwd2 * 14.0 + Vector3.UP * 2.0
			for d in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]:
				world.paint.rpc(
					global_position + Vector3(fwd2.x, 0, fwd2.z) * d, 2.2, my_team)
			world._spawn_debris(global_position + Vector3.UP,
				Vector3.UP, TEAM_COLORS[my_team], 12)
			world.play_ding()
		5:  # 真菌·孢子雨：8m 内五点随机轰炸
			for i in 5:
				var ang := TAU * i / 5.0 + randf() * 0.8
				var dist := randf_range(3.0, 8.0)
				var p := global_position + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
				world.paint.rpc(p, 2.5, my_team)
				world._spawn_debris(p + Vector3(0, 0.5, 0), Vector3.UP,
					TEAM_COLORS[my_team], 6)
			world.play_ding()
	print("[player] 病原体技能：", cinfo()["skill"])


## 病原体五造型（全部内联，不依赖外部函数——修复不可见 bug）
func _build_germ_v2_model(col: Color) -> Node3D:
	var root := Node3D.new()
	var eye_c := Color(0.04, 0.04, 0.06)
	match char_id:
		1:  # 细菌：椭圆+菌毛+鞭毛（体+鞭毛都动画）
			var core := _box(Vector3(0.5, 0.48, 0.7), col)
			core.position = Vector3(0, -0.15, 0)
			root.add_child(core)
			_pulse_nodes = []
			_pulse_bases = []
			_pulse_nodes.append(core)
			_pulse_bases.append(core.position)
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
					pilus.position = Vector3(cos(ang) * 0.2,
						-0.25 + ring * 0.1, sin(ang) * 0.28)
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
		2:  # 病毒：噬菌体（头颈尾针板腿）
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
		3:  # 支原体：不定形 blob+独眼
			var core := _box(Vector3(0.7, 0.55, 0.8), col)
			root.add_child(core)
			for i in 4:
				var ang := TAU * i / 4.0 + 0.5
				var bump := _box(Vector3(0.25, 0.2, 0.25), col.lightened(0.15))
				bump.position = Vector3(cos(ang) * 0.45, randf_range(-0.15, 0.15),
					sin(ang) * 0.45)
				root.add_child(bump)
			var eye := _box(Vector3(0.09, 0.09, 0.03), Color(0.9, 0.2, 0.1))
			eye.position = Vector3(0, 0.03, -0.42)
			root.add_child(eye)
		4:  # 寄生虫：蠕虫（8 节+环带+肉刺+尾，蠕动动画）
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
		5:  # 真菌：珊瑚（茎+枝+孢子球）
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

