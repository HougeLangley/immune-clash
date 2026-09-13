extends Control
## 大厅：创建主机 / 加入游戏（触屏友好大按钮 UI）

var name_edit: LineEdit
var ip_edit: LineEdit
var columns_node: HBoxContainer
var map_grid: GridContainer
var _title_widget: TitleWidget
var campaign_btn: Button
var campaign_panel: Control = null

## ==================== LAN 主机发现（客户端监听；广播在 gamestate autoload） ====================
const DISCOVERY_PORT := 53318      # 广播发现端口（与游戏端口 53317 区分）
var _listen_udp: PacketPeerUDP
var _discovered: Dictionary = {}   # ip -> {n: 昵称, p: 端口, t: 最后收到}
var _selected_host_ip := ""
var host_list: ItemList            # 主机列表 UI（只显示昵称）
var host_hint: Label
var disc_row: HBoxContainer        # 发现系统 UI 行（进房间时隐藏）

## 客户端：开始监听广播
func _start_discovery() -> void:
	_stop_discovery()
	_listen_udp = PacketPeerUDP.new()
	_listen_udp.bind(DISCOVERY_PORT)
	_discovered.clear()
	print("[lan] 发现监听中(端口 %d)..." % DISCOVERY_PORT)

func _stop_discovery() -> void:
	if _listen_udp:
		_listen_udp.close()
		_listen_udp = null
	_discovered.clear()
	_selected_host_ip = ""

## 轮询广播包+清理过期主机+刷新列表（由 _process 驱动）
func _poll_discovery() -> void:
	if _listen_udp == null:
		return
	while _listen_udp.get_available_packet_count() > 0:
		var data := _listen_udp.get_packet().get_string_from_utf8()
		var ip := _listen_udp.get_packet_ip()
		var parsed = JSON.parse_string(data)
		if parsed is Dictionary and parsed.has("n"):
			_discovered[ip] = {
				"n": str(parsed["n"]),
				"p": int(parsed.get("p", 53317)),
				"t": Time.get_ticks_msec(),
			}
	# 清理 6 秒未广播的主机（已下线/已开局）
	var now := Time.get_ticks_msec()
	for ip in _discovered.keys():
		if now - int(_discovered[ip]["t"]) > 6000:
			_discovered.erase(ip)
	_refresh_host_list()

## 刷新主机列表 UI（只显示昵称）
func _refresh_host_list() -> void:
	if host_list == null:
		return
	var sel_ip := _selected_host_ip
	host_list.clear()
	var idx := 0
	for ip in _discovered.keys():
		var nick: String = _discovered[ip]["n"]
		host_list.add_item(nick)
		if ip == sel_ip:
			host_list.select(idx)
		idx += 1
	if _discovered.is_empty():
		host_hint.text = "正在搜索主机..."
	elif _selected_host_ip == "" or not _discovered.has(_selected_host_ip):
		host_hint.text = "点击昵称选择主机"
	else:
		host_hint.text = "已选: %s" % _discovered[_selected_host_ip]["n"]
var error_label: Label
var host_btn: Button
var join_btn: Button
var players_panel: VBoxContainer
var players_list: ItemList
var start_btn: Button
var _intro_layer: Control = null
var _intro_done := false


func _ready() -> void:
	set_process(true)  # 驱动 LAN 发现轮询
	var args0 := OS.get_cmdline_user_args()
	print("[main] 启动，用户参数: %s" % args0)
	_build_ui()
	_start_discovery()
	gamestate.connection_failed.connect(_on_connection_failed)
	gamestate.connection_succeeded.connect(_on_connection_success)
	gamestate.player_list_changed.connect(refresh_lobby)
	gamestate.game_error.connect(_on_game_error)
	gamestate.faction_full_rejected.connect(func():
		error_label.text = "该阵营已满员(3人)! 请选另一阵营"
		# 弹回选阵营界面：断开连接回大厅
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
			gamestate.players.clear()
			gamestate.player_teams.clear()
			players_panel.visible = false
			host_btn.visible = true
			join_btn.visible = true)
	gamestate.game_ended.connect(_on_game_ended)
	# 战役下一关自动启动（结算点「下一关」流转回大厅）
	if gamestate.auto_next_campaign > 0:
		var nlv: int = gamestate.auto_next_campaign
		gamestate.auto_next_campaign = 0
		name_edit.text = "指挥官"
		gamestate.player_name = "指挥官"
		await get_tree().create_timer(0.8).timeout
		gamestate.begin_campaign(nlv)
		return
	# 测试钩子：user://campaign.txt 存在则直接开战役（读后即删，单次生效防残留）
	if FileAccess.file_exists("user://campaign.txt"):
		var cf := FileAccess.open("user://campaign.txt", FileAccess.READ)
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://campaign.txt"))
		var clv := 1
		if cf:
			var parts := cf.get_as_text().strip_edges().split(":")
			clv = int(parts[0])
			if parts.size() > 1:
				gamestate.my_faction = int(parts[1])
		name_edit.text = "指挥官"
		gamestate.player_name = "指挥官"
		await get_tree().create_timer(0.5).timeout
		gamestate.begin_campaign(clv)
		return
	# 测试钩子：user://autohost.txt 存在则本机自建服务器（读后即删，单次生效防残留）
	if FileAccess.file_exists("user://autohost.txt"):
		name_edit.text = "主机"
		var af := FileAccess.open("user://autohost.txt", FileAccess.READ)
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://autohost.txt"))
		if af:
			var m := int(af.get_as_text().strip_edges())
			if m >= 1 and m <= 3:
				gamestate.selected_map = m
		await get_tree().process_frame
		_do_host()
		await get_tree().create_timer(0.5).timeout
		gamestate.begin_game()
		return
	# 测试钩子：user://autojoin.txt 存在则自动填名并加入其中 IP（读后即删，单次生效）
	if FileAccess.file_exists("user://autojoin.txt"):
		var f := FileAccess.open("user://autojoin.txt", FileAccess.READ)
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://autojoin.txt"))
		var ip := f.get_as_text().strip_edges().replace("\r", "").replace("\n", "")
		if ip.is_valid_ip_address():
			print("[main] autojoin 钩子触发 → ", ip)
			name_edit.text = "Phone"
			ip_edit.text = ip
			await get_tree().process_frame
			gamestate.join_game(ip, "Phone")
			return
	# 命令行自动化（PC 端 E2E 测试用）：godot --path . -- --auto-host
	var args := OS.get_cmdline_user_args()
	if "--auto-host" in args:
		name_edit.text = "PC"
		# 场景树初始化完再开服（否则 add_child 会撞上 root 忙碌）
		await get_tree().process_frame
		_do_host()
		# 等待 3 秒给客户端加入窗口，再开局
		await get_tree().create_timer(3.0).timeout
		gamestate.begin_game()
		# 无头验证钩子：开局 1.5 秒后自动试射墨汁并打印覆盖率
		await get_tree().create_timer(1.5).timeout
		var world = get_tree().get_root().get_node_or_null(^"World")
		if world:
			world.fire_ink.rpc(Vector3(0, 2, 0), Vector3(5, 3, 2), 1)
			await get_tree().create_timer(1.0).timeout
			world.paint.rpc(Vector3(3, 0, 3), 2.0, 2)
			print("[test] 覆盖率 青=%.2f%% 橙=%.2f%% 瓦片查询(3,3)=%d(应=2) (-10,-10)=%d(应=0)" % [
				world.tilemap.coverage(1) * 100.0,
				world.tilemap.coverage(2) * 100.0,
				world.tilemap.tile_owner_at(3, 3),
				world.tilemap.tile_owner_at(-10, -10)])
			# 碰撞环探针：8 方向射线测墙距离（应≈24.5）
			for i in 8:
				var a := TAU * i / 8.0
				var from := Vector3(0, 5.0, 0)
				var q := PhysicsRayQueryParameters3D.create(from,
					from + Vector3(cos(a), 0, sin(a)) * 60.0)
				var hitw: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(q)
				var d := from.distance_to(hitw.position) if hitw else -1.0
				print("[test] 探针角度 %d° → 距离 %.1f" % [i * 45, d])
	elif args.size() > 0 and args[0].begins_with("--auto-join="):
		name_edit.text = "Client"
		ip_edit.text = args[0].split("=")[1]
		print("[main] 准备加入 %s ..." % ip_edit.text)
		await get_tree().process_frame
		gamestate.join_game(ip_edit.text, "Client")
		print("[main] join_game 已调用")


var char_preview: CharPreviewPanel


## 卡通标题控件：五字队伍渐变（青→橙）+ 粗描边 + 呼吸摆动 + 英文副标线


func _process(_delta: float) -> void:
	# LAN 主机发现轮询（仅在大厅非房间视图时）
	if players_panel == null or not players_panel.visible:
		_poll_discovery()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 标题（动效 TitleWidget）
	var title_w := TitleWidget.new()
	title_w.custom_minimum_size = Vector2(170, 42)
	title_w.size = Vector2(170, 42)
	title_w.name = "TitleWidget"
	add_child(title_w)
	_title_widget = title_w

	# 双栏容器
	columns_node = HBoxContainer.new()
	columns_node.add_theme_constant_override("separation", 14)
	add_child(columns_node)
	_layout_lobby()
	get_viewport().size_changed.connect(_layout_lobby)

	# ===== 左栏 =====
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(260, 0)
	columns_node.add_child(left)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "昵称"
	name_edit.custom_minimum_size = Vector2(240, 26)
	name_edit.add_theme_font_size_override("font_size", 12)
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if OS.has_environment("USERNAME"):
		name_edit.text = OS.get_environment("USERNAME")
	left.add_child(name_edit)

	# LAN 主机发现列表（只显示昵称）+ 刷新按钮
	disc_row = HBoxContainer.new()
	disc_row.add_theme_constant_override("separation", 8)
	left.add_child(disc_row)
	var disc_label := Label.new()
	disc_label.text = "局域网主机"
	disc_label.add_theme_font_size_override("font_size", 10)
	disc_label.modulate = Color(0.75, 0.82, 0.9)
	disc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc_row.add_child(disc_label)
	var refresh_btn := Button.new()
	refresh_btn.text = "刷新"
	refresh_btn.add_theme_font_size_override("font_size", 10)
	refresh_btn.custom_minimum_size = Vector2(52, 24)
	refresh_btn.pressed.connect(func():
		_discovered.clear()
		_selected_host_ip = ""
		_start_discovery()
		host_hint.text = "正在搜索主机...")
	disc_row.add_child(refresh_btn)
	host_list = ItemList.new()
	host_list.custom_minimum_size = Vector2(240, 58)
	host_list.add_theme_font_size_override("font_size", 12)
	host_list.select_mode = ItemList.SELECT_SINGLE
	host_list.item_selected.connect(func(idx):
		var ips := _discovered.keys()
		if idx < ips.size():
			_selected_host_ip = str(ips[idx])
			host_hint.text = "已选: %s" % _discovered[_selected_host_ip]["n"])
	left.add_child(host_list)
	host_hint = Label.new()
	host_hint.text = "正在搜索主机..."
	host_hint.add_theme_font_size_override("font_size", 9)
	host_hint.modulate = Color(0.55, 0.62, 0.72)
	host_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(host_hint)
	# 手动 IP（折叠备用，仅高级用户）
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "或手动填 IP"
	ip_edit.custom_minimum_size = Vector2(240, 22)
	ip_edit.add_theme_font_size_override("font_size", 12)
	ip_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(ip_edit)

	for le: LineEdit in [name_edit, ip_edit]:
		le.focus_entered.connect(func():
			DisplayServer.virtual_keyboard_show(le.text))
		le.focus_exited.connect(func():
			DisplayServer.virtual_keyboard_hide())
		le.gui_input.connect(func(ev):
			var press: bool = (ev is InputEventScreenTouch and ev.pressed) \
				or (ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT)
			if press:
				le.grab_focus()
				DisplayServer.virtual_keyboard_show(le.text))

	name_edit.text_changed.connect(func(_t):
		var nm := name_edit.text.strip_edges()
		if nm != "":
			gamestate.player_name = nm
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer \
					and not multiplayer.is_server():
				gamestate.register_player.rpc_id(1, nm,
					gamestate.my_char, gamestate.my_faction)
			refresh_lobby())

	var conn_row := HBoxContainer.new()
	conn_row.add_theme_constant_override("separation", 10)
	conn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(conn_row)
	host_btn = _big_button("创建主机", Color(0.16, 0.42, 0.2))
	host_btn.pressed.connect(_on_host_pressed)
	conn_row.add_child(host_btn)
	join_btn = _big_button("加入游戏", Color(0.16, 0.3, 0.5))
	join_btn.pressed.connect(_on_join_pressed)
	conn_row.add_child(join_btn)

	# 战役模式入口（单机闯关）
	campaign_btn = _big_button("战役模式", Color(0.45, 0.2, 0.5))
	campaign_btn.custom_minimum_size = Vector2(240, 36)
	campaign_btn.pressed.connect(_open_campaign_select)
	left.add_child(campaign_btn)

	players_panel = VBoxContainer.new()
	players_panel.add_theme_constant_override("separation", 6)
	players_panel.visible = false
	left.add_child(players_panel)
	players_list = ItemList.new()
	players_list.custom_minimum_size = Vector2(240, 48)
	players_list.add_theme_font_size_override("font_size", 11)
	players_panel.add_child(players_list)
	start_btn = _big_button("开始游戏", Color(0.5, 0.35, 0.12))
	start_btn.pressed.connect(_on_start_pressed)
	players_panel.add_child(start_btn)

	error_label = Label.new()
	error_label.add_theme_font_size_override("font_size", 10)
	error_label.modulate = Color(1.0, 0.45, 0.4, 1)
	left.add_child(error_label)

	# ===== 右栏 =====
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	right.custom_minimum_size = Vector2(440, 0)
	columns_node.add_child(right)

	var faction_row := HBoxContainer.new()
	faction_row.add_theme_constant_override("separation", 12)
	faction_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(faction_row)

	var fb1 := Button.new()
	fb1.text = "免疫阵营"
	fb1.toggle_mode = true
	var fb2 := Button.new()
	fb2.text = "病原体阵营"
	fb2.toggle_mode = true
	for fb in [fb1, fb2]:
		fb.custom_minimum_size = Vector2(96, 28)
		fb.add_theme_font_size_override("font_size", 11)
		faction_row.add_child(fb)
	fb1.set_pressed(true)

	var char_row := HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 5)
	char_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(char_row)

	for cid in range(1, 6):
		var cb := Button.new()
		var inames := {1: "巨噬", 2: "淋巴", 3: "粒", 4: "树突", 5: "肥大"}
		cb.text = inames[cid]
		cb.custom_minimum_size = Vector2(50, 30)
		cb.add_theme_font_size_override("font_size", 11)
		cb.toggle_mode = true
		cb.set_pressed(cid == 1)
		cb.pressed.connect(func():
			gamestate.my_char = cid
			for other in char_row.get_children():
				other.set_pressed(false)
			cb.set_pressed(true)
			_update_preview(cid))
		char_row.add_child(cb)

	# 地图选择（标签+七列两行）
	var map_label := Label.new()
	map_label.text = "地图"
	map_label.add_theme_font_size_override("font_size", 9)
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_label.modulate = Color(0.8, 0.85, 0.9, 0.9)
	right.add_child(map_label)
	map_grid = GridContainer.new()
	map_grid.columns = 7
	map_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # 网格居中
	map_grid.add_theme_constant_override("h_separation", 4)
	map_grid.add_theme_constant_override("v_separation", 3)
	right.add_child(map_grid)
	var map_btns: Array[Button] = []
	for mid in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]:
		var mb := Button.new()
		mb.text = ["口腔", "鼻腔", "皮肤", "气管", "眼睛", "耳朵",
			"肺", "胃", "肠道", "神经", "肾", "膀胱", "骨骼"][mid - 1]
		mb.custom_minimum_size = Vector2(58, 24)
		mb.add_theme_font_size_override("font_size", 10)
		mb.toggle_mode = true
		mb.set_pressed(mid == gamestate.selected_map)
		mb.pressed.connect(func():
			if not (multiplayer.multiplayer_peer is ENetMultiplayerPeer) \
					or multiplayer.is_server():
				gamestate.selected_map = mid
				for o in map_btns:
					o.set_pressed(false)
				mb.set_pressed(true)
				if multiplayer.multiplayer_peer is ENetMultiplayerPeer \
						and multiplayer.is_server():
					gamestate.sync_map.rpc(mid)
				# 地图预览
				var mnames := {1: "口腔", 2: "鼻腔", 3: "皮肤", 4: "气管", 5: "眼睛", 6: "耳朵",
					7: "肺", 8: "胃", 9: "肠道", 10: "神经",
					11: "肾", 12: "膀胱", 13: "骨骼"}
				var mdescs := {
					1: "牙齿阵地!白色磨牙排成弓阵，中央大磨牙可跳上",
					2: "鼻毛迷宫!弯曲毛簇挡视线，适合伏击突袭",
					3: "表皮战场!毛囊丘林+皮褶走廊，低掩体多",
					4: "软骨弓走廊!环状软骨拱门连环，穿越推挤",
					5: "虹膜高台!中央瞳孔高地，环形视野开阔",
					6: "耳蜗螺旋!同心环渐高，缺口通道攻防",
					7: "支气管分杈!枝杈通道+肺泡丘，立体攻防",
					8: "酸液危险区!中央酸池不可入，环形争夺",
					9: "绒毛柱林!高密度细柱迷宫，蜿蜒游击",
					10: "电光神经!发光柱阵+中央神经节，科幻战场",
					11: "肾小球滤网!分层平台渐降，滤网弧墙攻防",
					12: "碗型阶梯!中央三角区+环形渐高，弧面战场",
					13: "骨髓终战!骨板高低差最大，中央红芯据点",
				}
				char_preview.show_map(mid, mnames[mid], mdescs[mid]))
		map_btns.append(mb)
		map_grid.add_child(mb)

	char_preview = CharPreviewPanel.new()
	right.add_child(char_preview)

	fb1.pressed.connect(func():
		gamestate.my_faction = 1
		fb2.set_pressed(false)
		fb1.set_pressed(true)
		var in2 := {1: "巨噬", 2: "淋巴", 3: "粒", 4: "树突", 5: "肥大"}
		var btns := char_row.get_children()
		for i in btns.size():
			btns[i].text = in2[i + 1]
		_update_preview(gamestate.my_char))
	fb2.pressed.connect(func():
		gamestate.my_faction = 2
		fb1.set_pressed(false)
		fb2.set_pressed(true)
		var gn := {1: "细菌", 2: "病毒", 3: "支原体", 4: "寄生虫", 5: "真菌"}
		var btns := char_row.get_children()
		for i in btns.size():
			btns[i].text = gn[i + 1]
		_update_preview(gamestate.my_char))

	_update_preview(1)
	# 开场动画（无测试钩子时播放）
	_play_intro()


## 开场视频：全屏播放 intro.ogv → 播完/跳过后移除
func _play_intro() -> void:
	if _intro_done:
		return
	var vp_stream := load("res://intro.ogv")
	if vp_stream == null:
		print("[intro] intro.ogv 不存在，跳过开场")
		return
	_intro_done = true
	_intro_layer = Control.new()
	_intro_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(bg)
	var vp_size := get_viewport().get_visible_rect().size
	var vsp := VideoStreamPlayer.new()
	vsp.stream = vp_stream
	# cover-fill：铺满全屏无黑边（视频按屏比例缩放，超出部分居中裁切）
	var v_ratio := 1280.0 / 720.0  # 视频实际比例（Seedance 2.0 产出）
	var s_ratio := vp_size.x / vp_size.y
	var w: float
	var h: float
	if s_ratio > v_ratio:
		# 屏更宽→按宽铺满，上下溢出居中裁切
		w = vp_size.x
		h = w / v_ratio
	else:
		# 屏更高→按高铺满，左右溢出居中裁切
		h = vp_size.y
		w = h * v_ratio
	vsp.autoplay = true
	vsp.expand = true
	vsp.finished.connect(_on_intro_finished)
	_intro_layer.add_child(vsp)
	# 入树后再设尺寸/位置（树前设置会被原生分辨率覆盖）
	vsp.size = Vector2(w, h)
	vsp.position = Vector2((vp_size.x - w) / 2.0, (vp_size.y - h) / 2.0)
	# 跳过按钮（右下角，离边适当距离防手机圆角裁切）
	var skip := Button.new()
	skip.text = "跳过 »"
	skip.add_theme_font_size_override("font_size", 13)
	skip.custom_minimum_size = Vector2(88, 36)
	skip.position = Vector2(vp_size.x - 116, vp_size.y - 52)
	skip.pressed.connect(_on_intro_finished)
	_intro_layer.add_child(skip)
	add_child(_intro_layer)
	vsp.play()
	print("[intro] 开场视频播放中...")


func _on_intro_finished() -> void:
	if _intro_layer and is_instance_valid(_intro_layer):
		_intro_layer.queue_free()
		_intro_layer = null
		print("[intro] 开场结束，进入大厅")


func _layout_lobby() -> void:
	var vp := get_viewport().get_visible_rect().size
	if _title_widget:
		_title_widget.position = Vector2(
			(vp.x - _title_widget.size.x) / 2.0, 4)
	var total_w := 260.0 + 14.0 + 440.0
	var x := maxf((vp.x - total_w) / 2.0, 4.0)
	columns_node.position = Vector2(x, 56)  # 标题下方留呼吸空间
	columns_node.size = Vector2(minf(total_w, vp.x - 8), vp.y - 62)

class TitleWidget extends Control:
	var t := 0.0
	const FLESH_A := Color(0.98, 0.78, 0.74)
	const FLESH_B := Color(0.88, 0.45, 0.52)
	const LINE := Color(0.09, 0.1, 0.14)
	const CHARS := ["免", "疫", "大", "作", "战"]

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var fs := 18
		var x := 4.0
		for i in 5:
			var mix := i / 4.0
			var col := FLESH_A.lerp(FLESH_B, mix)
			var bob := sin(t * 2.2 + i * 0.9) * 2.0
			var rot := sin(t * 1.6 + i * 1.3) * 0.06
			draw_set_transform(Vector2(x, 20 + bob), rot, Vector2.ONE)
			draw_string_outline(font, Vector2.ZERO, CHARS[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, LINE)
			draw_string(font, Vector2.ZERO, CHARS[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += font.get_string_size(CHARS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 2.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 英文逐字动效（与中文同节奏）
		var cap := "IMMUNE CLASH"
		var cfs := 12
		var cx := 4.0
		for i in cap.length():
			var ch := cap[i]
			var cbob := sin(t * 2.2 + 5.0 + i * 0.4) * 1.2
			draw_string_outline(font, Vector2(cx, 38 + cbob), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, 3, LINE)
			draw_string(font, Vector2(cx, 38 + cbob), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(0.92, 0.68, 0.70, 0.9))
			cx += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x + 2.0
## 角色预览面板（左：3D 模型 / 右：医学介绍）

## 角色预览面板（完整版模型+动效 = 游戏内一致）
class CharPreviewPanel extends Control:
	var t := 0.0
	var vp: SubViewport
	var cam: Camera3D
	var model_holder: Node3D
	var desc_label: RichTextLabel
	var _light: DirectionalLight3D
	var _worm_segs: Array = []
	var _worm_bases: Array = []
	var _flag_segs: Array = []
	var _flag_bases: Array = []
	var _pulse_nodes: Array = []
	var _pulse_bases: Array = []
	var _is_map_mode := false

	func _init() -> void:
		custom_minimum_size = Vector2(400, 140)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var vp_cont := SubViewportContainer.new()
		# 左：3D 模型（竖版，占满高度）
		vp_cont.custom_minimum_size = Vector2(112, 130)
		vp_cont.stretch = true
		vp_cont.position = Vector2(4, 5)  # 面板内对称：左边距4
		add_child(vp_cont)
		vp = SubViewport.new()
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.size = Vector2(112, 130)
		vp_cont.add_child(vp)
		cam = Camera3D.new()
		cam.position = Vector3(1.2, 0.8, 1.4)
		cam.fov = 42
		vp.add_child(cam)
		cam.look_at(Vector3(0, -0.1, 0), Vector3.UP)
		_light = DirectionalLight3D.new()
		_light.rotation_degrees = Vector3(-50, -35, 0)
		_light.light_energy = 1.3
		vp.add_child(_light)
		model_holder = Node3D.new()
		vp.add_child(model_holder)
		desc_label = RichTextLabel.new()
		desc_label.bbcode_enabled = true
		desc_label.position = Vector2(122, 42)   # 视觉居中（3行文字光学中心）
		desc_label.size = Vector2(272, 80)
		desc_label.add_theme_font_size_override("normal_font_size", 12)
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override("default_color", Color(0.85, 0.9, 0.95))
		desc_label.fit_content = false
		desc_label.scroll_active = false
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(desc_label)

	## 文字垂直居中：固定布局已按典型文字长度调优，无需动态计算
	func _center_desc() -> void:
		pass

	func _process(delta: float) -> void:
		t += delta
		# 模型旋转展示
		if model_holder and not _is_map_mode:
			model_holder.rotation.y = t * 0.5
		# 蠕虫蠕动（行波）
		if _worm_segs.size() > 0:
			var s := t * 4.0
			for i in _worm_segs.size():
				var seg: Node3D = _worm_segs[i]
				if is_instance_valid(seg):
					var b: Vector3 = _worm_bases[i]
					var ph := i * 0.8
					var ay := 0.05 * (1.0 - float(i) / _worm_segs.size() * 0.5)
					var ax := 0.03 * (1.0 - float(i) / _worm_segs.size() * 0.3)
					seg.position.y = b.y + sin(s + ph) * ay
					seg.position.x = b.x + sin(s * 0.6 + ph) * ax
					var sq := 1.0 + sin(s + ph) * 0.06
					seg.scale = Vector3(sq, sq, 2.0 - sq)
		# 鞭毛甩动
		if _flag_segs.size() > 0:
			var fs := t * 8.0
			for i in _flag_segs.size():
				var f: Node3D = _flag_segs[i]
				if is_instance_valid(f):
					var fb: Vector3 = _flag_bases[i]
					var fp := i * 0.7
					var amp := 0.015 + i * 0.025
					f.position.x = fb.x + sin(fs + fp) * amp
					f.position.y = fb.y + cos(fs * 0.8 + fp) * 0.008
		# 脉动（细菌体/巨噬伪足）
		if _pulse_nodes.size() > 0:
			var pt := t * 2.5
			for i in _pulse_nodes.size():
				var pn: Node3D = _pulse_nodes[i]
				if is_instance_valid(pn):
					var pb: Vector3 = _pulse_bases[i]
					var ph2 := i * 0.7
					pn.position.y = pb.y + sin(pt + ph2) * 0.015
					var sq2 := 1.0 + sin(pt + ph2) * 0.04
					pn.scale = Vector3(sq2, sq2, 2.0 - sq2)

	func _bx(sz: Vector3, col: Color) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = sz
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		m.material = mat
		mi.mesh = m
		return mi

	func _clear_anim() -> void:
		_worm_segs = []; _worm_bases = []
		_flag_segs = []; _flag_bases = []
		_pulse_nodes = []; _pulse_bases = []

	## 地图预览模式：俯视小地图
	func show_map(map_id: int, mname: String, mdesc: String) -> void:
		for c in model_holder.get_children():
			c.queue_free()
		_clear_anim()
		_is_map_mode = true
		# 切换相机：俯视 45°
		cam.position = Vector3(0, 7, 5)
		cam.fov = 50
		cam.look_at(Vector3(0, 0, 0), Vector3.UP)
		model_holder.rotation.y = 0  # 地图不旋转
		# 底盘（地图主题色圆盘）
		var floor_c := Color(0.95, 0.85, 0.85)
		match map_id:
			2: floor_c = Color(0.85, 0.65, 0.45)
			3: floor_c = Color(0.92, 0.75, 0.55)
			4: floor_c = Color(0.90, 0.78, 0.78)
			5: floor_c = Color(0.92, 0.94, 0.96)
			6: floor_c = Color(0.85, 0.66, 0.68)
			7: floor_c = Color(0.85, 0.90, 0.92)
			8: floor_c = Color(0.88, 0.82, 0.55)
			9: floor_c = Color(0.88, 0.65, 0.62)
			10: floor_c = Color(0.55, 0.62, 0.92)
			11: floor_c = Color(0.88, 0.82, 0.60)
			12: floor_c = Color(0.72, 0.86, 0.88)
			13: floor_c = Color(0.91, 0.89, 0.84)
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 6.0; cm.bottom_radius = 6.0; cm.height = 0.2
		var dm := StandardMaterial3D.new(); dm.albedo_color = floor_c
		cm.material = dm
		disc.mesh = cm
		disc.position.y = -0.1
		model_holder.add_child(disc)
		match map_id:
			1: _mini_oral()
			2: _mini_nasal()
			3: _mini_skin()
			4: _mini_trachea()
			5: _mini_eye()
			6: _mini_ear()
			7: _mini_lung()
			8: _mini_stomach()
			9: _mini_intestine()
			10: _mini_nerve()
			11: _mini_kidney()
			12: _mini_bladder()
			13: _mini_bone()
		desc_label.text = "[color=#ffd4a8]🗺 %s[/color]  [color=#a8d4e8]%s[/color]" % [mname, mdesc.substr(0, 30)]
		_center_desc()

	func _mini_bx(pos: Vector3, sz: Vector3, col: Color) -> void:
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new(); m.size = sz
		var mat := StandardMaterial3D.new(); mat.albedo_color = col
		m.material = mat; mi.mesh = m; mi.position = pos
		model_holder.add_child(mi)

	func _mini_oral() -> void:
		var white := Color(0.96, 0.94, 0.90)
		for arc: float in [0.0, PI]:
			for i in range(-2, 3):
				var a1 := arc + i * 0.22
				_mini_bx(Vector3(cos(a1) * 3.2, 0.5, sin(a1) * 3.2), Vector3(0.55, 0.8, 0.55), white)
		_mini_bx(Vector3(0, 0.5, 0), Vector3(0.9, 0.9, 0.9), white)
		for i in 8:
			var a2 := TAU * i / 8.0 + 0.39
			_mini_bx(Vector3(cos(a2) * 1.7, 0.3, sin(a2) * 1.7), Vector3(0.3, 0.5, 0.3), white)

	func _mini_nasal() -> void:
		var brown := Color(0.5, 0.35, 0.18)
		for gx in range(-2, 3):
			for gz in range(-2, 3):
				if abs(gx) <= 0 and abs(gz) <= 0: continue
				if abs(gx) + abs(gz) == 4: continue
				if (gx + gz) % 2 == 0: continue
				_mini_bx(Vector3(gx * 1.4, 0.6, gz * 1.4), Vector3(0.25, 1.0, 0.25), brown)
		for i in 4:
			var a3 := TAU * i / 4.0 + 0.5
			_mini_bx(Vector3(cos(a3) * 1.0, 0.4, sin(a3) * 1.0), Vector3(0.25, 0.6, 0.25), brown)

	func _mini_skin() -> void:
		var flesh := Color(0.92, 0.72, 0.55)
		var dark := Color(0.45, 0.3, 0.15)
		for gx in range(-2, 3):
			for gz in range(-2, 3):
				if abs(gx) <= 0 and abs(gz) <= 0: continue
				if abs(gx) + abs(gz) == 4: continue
				if (gx * 3 + gz * 5) % 2 == 0: continue
				_mini_bx(Vector3(gx * 1.4, 0.2, gz * 1.4), Vector3(0.6, 0.25, 0.6), flesh)
				_mini_bx(Vector3(gx * 1.4, 0.6, gz * 1.4), Vector3(0.06, 0.5, 0.06), dark)
		for sx: float in [-1, 1]:
			for sz: float in [-1, 1]:
				_mini_bx(Vector3(sx * 2.2, 0.2, sz * 2.2 - sz * 0.5), Vector3(1.8, 0.25, 0.3), flesh)
		_mini_bx(Vector3(0, 0.3, 0), Vector3(1.2, 0.5, 1.2), flesh)
		_mini_bx(Vector3(0, 0.8, 0), Vector3(0.1, 0.6, 0.1), dark)

	func _mini_trachea() -> void:
		var white := Color(0.93, 0.90, 0.88)
		var pink := Color(0.90, 0.62, 0.65)
		# 六道软骨弓（迷你化：柱+顶梁）
		for x in [-3.0, -1.8, -0.6, 0.6, 1.8, 3.0]:
			_mini_bx(Vector3(x, 0.5, -0.7), Vector3(0.28, 1.0, 0.28), white)
			_mini_bx(Vector3(x, 0.5, 0.7), Vector3(0.28, 1.0, 0.28), white)
			_mini_bx(Vector3(x, 1.1, 0), Vector3(0.28, 0.25, 1.6), white)
		# 侧壁粘膜垫
		for z: float in [-2.0, 2.0]:
			for x in [-2.5, -1.2, 0, 1.2, 2.5]:
				_mini_bx(Vector3(x, 0.15, z), Vector3(0.5, 0.2, 0.3), pink)
		# 中央分叉
		_mini_bx(Vector3(0, 0.35, 0), Vector3(0.9, 0.5, 0.6), white)
		_mini_bx(Vector3(0, 0.7, 0), Vector3(0.5, 0.3, 0.35), pink)

	func _mini_eye() -> void:
		var blue := Color(0.20, 0.45, 0.75)
		var white := Color(0.93, 0.94, 0.95)
		var dark := Color(0.12, 0.10, 0.18)
		# 中央虹膜两层+瞳孔
		_mini_bx(Vector3(0, 0.3, 0), Vector3(2.4, 0.5, 2.4), blue)
		_mini_bx(Vector3(0, 0.6, 0), Vector3(1.2, 0.5, 1.2), blue.lightened(0.2))
		_mini_bx(Vector3(0, 0.9, 0), Vector3(0.6, 0.3, 0.6), dark)
		# 辐条
		for i in 8:
			var a := TAU * i / 8.0
			_mini_bx(Vector3(cos(a) * 1.6, 0.55, sin(a) * 1.6), Vector3(0.15, 0.15, 0.8), blue)
		# 睫毛细柱
		for i in 10:
			var a2 := TAU * i / 10.0 + 0.3
			_mini_bx(Vector3(cos(a2) * 4.2, 0.4, sin(a2) * 4.2), Vector3(0.12, 0.8, 0.12), white)
		# 角膜弧
		for arc: float in [0.4, PI + 0.4]:
			for i in 4:
				var a3 := arc + i * 0.25
				_mini_bx(Vector3(cos(a3) * 2.8, 0.2, sin(a3) * 2.8), Vector3(0.5, 0.35, 0.28), white)

	func _mini_ear() -> void:
		var pink := Color(0.82, 0.62, 0.65)
		# 三层同心环（缺口错开）
		for ring in 3:
			var r := 1.2 + ring * 1.1
			var h := 0.3 + ring * 0.2
			var gap := TAU * ring / 3.0
			for i in 10:
				var a := TAU * i / 10.0
				var da := absf(fmod(a - gap + PI, TAU) - PI)
				if da < 0.6:
					continue
				_mini_bx(Vector3(cos(a) * r, h / 2.0, sin(a) * r), Vector3(0.45, h, 0.3), pink)
		# 中央尖峰
		_mini_bx(Vector3(0, 0.5, 0), Vector3(1.0, 0.9, 1.0), pink)
		_mini_bx(Vector3(0, 1.1, 0), Vector3(0.5, 0.4, 0.5), pink.lightened(0.2))
		# 听小骨柱
		for i in 3:
			var a4 := TAU * i / 3.0 + 0.8
			_mini_bx(Vector3(cos(a4) * 4.5, 0.3, sin(a4) * 4.5), Vector3(0.4, 0.6, 0.4), pink)

	func _mini_lung() -> void:
		var blue := Color(0.55, 0.70, 0.85)
		var white := Color(0.92, 0.94, 0.96)
		# 中央主干+两分杈
		_mini_bx(Vector3(0, 0.8, 0), Vector3(0.7, 1.6, 0.7), blue)
		for sx: float in [-1, 1]:
			_mini_bx(Vector3(sx * 1.4, 0.6, 0.6), Vector3(0.5, 1.2, 0.5), blue)
			_mini_bx(Vector3(sx * 2.4, 0.4, 1.3), Vector3(0.4, 0.8, 0.4), blue)
			# 肺泡丘
			_mini_bx(Vector3(sx * 3.1, 0.25, 2.2), Vector3(0.8, 0.5, 0.8), white)
			_mini_bx(Vector3(sx * 1.7, 0.2, 3.2), Vector3(0.9, 0.4, 0.9), white)
			_mini_bx(Vector3(sx * 2.0, 0.9, -1.8), Vector3(1.2, 0.7, 1.2), white)

	func _mini_stomach() -> void:
		var yellow := Color(0.88, 0.80, 0.50)
		var green := Color(0.35, 0.80, 0.25)
		# 中央酸液池（绿色发光圆）
		_mini_bx(Vector3(0, 0.15, 0), Vector3(2.4, 0.3, 2.4), green)
		_mini_bx(Vector3(0, 0.35, 0), Vector3(1.6, 0.1, 1.6), green.lightened(0.3))
		# 胃壁褶皱弧墙
		for i in 6:
			var a := TAU * i / 6.0
			_mini_bx(Vector3(cos(a) * 3.0, 0.4, sin(a) * 3.0), Vector3(1.0, 0.8, 0.4), yellow)
		# 外圈消化丘
		for i in 5:
			var a2 := TAU * i / 5.0 + 0.6
			_mini_bx(Vector3(cos(a2) * 4.4, 0.2, sin(a2) * 4.4), Vector3(0.7, 0.4, 0.7), yellow)

	func _mini_intestine() -> void:
		var pink := Color(0.88, 0.62, 0.60)
		# 高密度细柱
		for gx in range(-3, 4):
			for gz in range(-3, 4):
				if abs(gx) <= 1 and abs(gz) <= 1: continue
				if (gx + gz * 2) % 3 == 0: continue
				_mini_bx(Vector3(gx * 1.3, 0.5, gz * 1.3), Vector3(0.3, 1.0, 0.3), pink)
		# 中央拱门
		_mini_bx(Vector3(0, 0.9, 0), Vector3(1.5, 0.25, 0.6), pink)
		_mini_bx(Vector3(-0.7, 0.45, 0), Vector3(0.25, 0.9, 0.6), pink)
		_mini_bx(Vector3(0.7, 0.45, 0), Vector3(0.25, 0.9, 0.6), pink)

	func _mini_nerve() -> void:
		var elec := Color(0.45, 0.55, 1.0)
		var white := Color(0.90, 0.92, 0.98)
		# 中央神经节
		_mini_bx(Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 1.2), elec)
		# 八向纤维
		for i in 8:
			var a := TAU * i / 8.0
			for d: float in [1.5, 2.6, 3.8]:
				_mini_bx(Vector3(cos(a) * d, 0.35, sin(a) * d), Vector3(0.14, 0.7, 0.14), elec)
		# 突触丘
		for i in 8:
			var a2 := TAU * i / 8.0 + 0.39
			_mini_bx(Vector3(cos(a2) * 2.0, 0.18, sin(a2) * 2.0), Vector3(0.5, 0.35, 0.5), white)

	func _mini_kidney() -> void:
		var tan_c := Color(0.88, 0.82, 0.60)
		var pink := Color(0.85, 0.68, 0.65)
		# 中央肾小球两层
		_mini_bx(Vector3(0, 0.5, 0), Vector3(1.2, 1.0, 1.2), pink)
		_mini_bx(Vector3(0, 1.1, 0), Vector3(0.7, 0.3, 0.7), tan_c)
		# 三层滤网弧
		for ring in 3:
			var r := 1.6 + ring * 1.1
			var h := 0.7 - ring * 0.15
			var segs := 8 - ring
			for i in segs:
				var a := TAU * i / segs + ring * 0.4
				_mini_bx(Vector3(cos(a) * r, h / 2.0, sin(a) * r), Vector3(0.5, h, 0.25), tan_c)
		# 凹坑丘
		for i in 6:
			var a2 := TAU * i / 6.0 + 0.5
			_mini_bx(Vector3(cos(a2) * 4.2, 0.15, sin(a2) * 4.2), Vector3(0.6, 0.3, 0.6), pink)

	func _mini_bladder() -> void:
		var teal := Color(0.72, 0.86, 0.88)
		var soft := Color(0.85, 0.95, 0.95)
		# 中央三角区
		_mini_bx(Vector3(0, 0.25, 0), Vector3(1.4, 0.5, 1.4), soft)
		# 三层环阶梯
		for ring in 3:
			var r := 2.0 + ring * 1.2
			var h := 0.35 + ring * 0.25
			var segs := 10
			for i in segs:
				var a := TAU * i / segs + ring * 0.3
				_mini_bx(Vector3(cos(a) * r, h / 2.0, sin(a) * r), Vector3(0.55, h, 0.3), teal)
		# 输尿管柱
		for sx: float in [-1, 1]:
			_mini_bx(Vector3(sx * 1.3, 0.35, -1.3), Vector3(0.3, 0.7, 0.3), soft)

	func _mini_bone() -> void:
		var white := Color(0.92, 0.90, 0.85)
		var red := Color(0.85, 0.25, 0.30)
		# 中央骨髓柱
		_mini_bx(Vector3(0, 0.9, 0), Vector3(1.0, 1.8, 1.0), white)
		_mini_bx(Vector3(0, 1.9, 0), Vector3(0.55, 0.3, 0.55), red)
		# 四块高骨板
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			_mini_bx(Vector3(cos(a) * 2.3, 0.7, sin(a) * 2.3), Vector3(1.1, 1.4, 0.55), white)
		# 骨小梁柱
		for i in 8:
			var a2 := TAU * i / 8.0 + 0.39
			_mini_bx(Vector3(cos(a2) * 3.8, 0.3, sin(a2) * 3.8), Vector3(0.2, 0.6, 0.2), white)
		# 红池丘
		for i in 4:
			var a3 := TAU * i / 4.0
			_mini_bx(Vector3(cos(a3) * 1.4, 0.18, sin(a3) * 1.4), Vector3(0.55, 0.35, 0.55), red)

	## 切回角色模式时恢复相机
	func show_char(cid: int, is_immune: bool, desc: String) -> void:
		_is_map_mode = false
		cam.position = Vector3(1.2, 0.8, 1.4)
		cam.fov = 42
		cam.look_at(Vector3(0, -0.1, 0), Vector3.UP)
		for c in model_holder.get_children():
			c.queue_free()
		_clear_anim()
		var col := Color(0.05, 0.75, 0.85) if is_immune else Color(1.0, 0.55, 0.15)
		var ec := Color(0.04, 0.04, 0.06)
		if is_immune:
			match cid:
				1: _immune_1(col, ec)
				2: _immune_2(col, ec)
				3: _immune_3(col, ec)
				4: _immune_4(col, ec)
				5: _immune_5(col, ec)
		else:
			match cid:
				1: _germ_1(col, ec)
				2: _germ_2(col, ec)
				3: _germ_3(col, ec)
				4: _germ_4(col, ec)
				5: _germ_5(col, ec)
		desc_label.text = "[color=#a8d4e8]" + desc + "[/color]"
		_center_desc()

	# === 免疫完整版 ===
	func _immune_1(col: Color, ec: Color) -> void:
		var gb := Color(0.45, 0.55, 0.65)
		var b := _bx(Vector3(0.7, 0.65, 0.25), gb); b.position = Vector3(0, -0.1, 0.35); model_holder.add_child(b)
		for x in [-0.3, 0.3]:
			var a := _bx(Vector3(0.2, 0.55, 0.65), gb); a.position = Vector3(x, -0.1, 0); model_holder.add_child(a)
		var br := _bx(Vector3(0.4, 0.3, 0.15), gb.darkened(0.15)); br.position = Vector3(0, -0.2, -0.3); model_holder.add_child(br)
		for i in 4:
			var ang := PI * (0.25 + i * 0.17)
			var p := _bx(Vector3(0.1, 0.1, 0.45), gb.lightened(0.1))
			var pp := Vector3(cos(ang) * 0.25, -0.15 + (i % 2) * 0.1, -0.4 - sin(ang) * 0.15)
			p.position = pp; p.rotation.y = -ang + PI / 2.0; model_holder.add_child(p)
			_pulse_nodes.append(p); _pulse_bases.append(pp)
		for x in [-0.15, 0.15]:
			var e := _bx(Vector3(0.08, 0.08, 0.03), ec); e.position = Vector3(x, 0.05, -0.35); model_holder.add_child(e)

	func _immune_2(col: Color, ec: Color) -> void:
		var dc := col.darkened(0.15)
		var c1 := _bx(Vector3(0.45, 0.42, 0.45), dc); model_holder.add_child(c1)
		var c2 := _bx(Vector3(0.32, 0.3, 0.32), dc.lightened(0.12)); c2.position.y = 0.08; model_holder.add_child(c2)
		var c3 := _bx(Vector3(0.18, 0.16, 0.18), dc.lightened(0.25)); c3.position.y = 0.15; model_holder.add_child(c3)
		var n := _bx(Vector3(0.3, 0.28, 0.3), Color(0.15, 0.08, 0.3)); n.position.y = -0.05; model_holder.add_child(n)
		for x in [-0.12, 0.12]:
			var e := _bx(Vector3(0.07, 0.07, 0.03), ec); e.position = Vector3(x, 0.02, -0.24); model_holder.add_child(e)

	func _immune_3(col: Color, ec: Color) -> void:
		for i in 3:
			var ang := TAU * i / 3.0 + 0.4
			var l := _bx(Vector3(0.22, 0.22, 0.22), col.darkened(0.2))
			l.position = Vector3(cos(ang) * 0.2, sin(ang) * 0.1, sin(ang) * 0.15); model_holder.add_child(l)
		var b := _bx(Vector3(0.5, 0.45, 0.5), col); b.position.y = -0.05; model_holder.add_child(b)
		for i in 3:
			var r := _bx(Vector3(0.52 + i * 0.04, 0.08, 0.52 + i * 0.04), col.lightened(0.15 + i * 0.08))
			r.position.y = -0.15 + i * 0.12; model_holder.add_child(r)
		for i in 6:
			var ang := TAU * i / 6.0
			var s := _bx(Vector3(0.04, 0.04, 0.2), col.lightened(0.3))
			s.position = Vector3(cos(ang) * 0.28, 0.05, sin(ang) * 0.28); s.rotation.y = -ang + PI / 2.0; model_holder.add_child(s)
		for x in [-0.12, 0.12]:
			var e := _bx(Vector3(0.07, 0.07, 0.03), ec); e.position = Vector3(x, 0.05, -0.26); model_holder.add_child(e)

	func _immune_4(col: Color, ec: Color) -> void:
		var b := _bx(Vector3(0.45, 0.42, 0.45), col); model_holder.add_child(b)
		for i in 8:
			var ang := TAU * i / 8.0
			var tilt := (i % 2) * 0.35 - 0.15
			var d := _bx(Vector3(0.05, 0.05, 0.55), col.lightened(0.2))
			d.position = Vector3(cos(ang) * 0.45, tilt, sin(ang) * 0.45)
			d.rotation.y = -ang + PI / 2.0; d.rotation.x = tilt * 0.5; model_holder.add_child(d)
			var tip := _bx(Vector3(0.08, 0.08, 0.08), col.lightened(0.35))
			tip.position = Vector3(cos(ang) * 0.68, tilt + 0.05, sin(ang) * 0.68); model_holder.add_child(tip)
		for x in [-0.1, 0.1]:
			var e := _bx(Vector3(0.07, 0.07, 0.03), ec); e.position = Vector3(x, 0.05, -0.24); model_holder.add_child(e)

	func _immune_5(col: Color, ec: Color) -> void:
		var b := _bx(Vector3(0.5, 0.45, 0.5), col); model_holder.add_child(b)
		var pu := Color(0.65, 0.25, 0.75)
		for i in 14:
			var ang := TAU * i / 14.0; var row := i % 4; var r := 0.28 + (row % 2) * 0.06
			var g := _bx(Vector3(0.1, 0.1, 0.1), pu)
			g.position = Vector3(cos(ang) * r, -0.1 + row * 0.1, sin(ang) * r); model_holder.add_child(g)
		for i in 3:
			var ang := TAU * i / 3.0 + 0.5
			var bg := _bx(Vector3(0.14, 0.14, 0.14), pu.lightened(0.15))
			bg.position = Vector3(cos(ang) * 0.32, 0.08, sin(ang) * 0.32); model_holder.add_child(bg)
		for x in [-0.12, 0.12]:
			var e := _bx(Vector3(0.07, 0.07, 0.03), ec); e.position = Vector3(x, 0.08, -0.26); model_holder.add_child(e)

	# === 病原体完整版 ===
	func _germ_1(col: Color, ec: Color) -> void:
		var c := _bx(Vector3(0.5, 0.48, 0.7), col); c.position.y = -0.15; model_holder.add_child(c)
		_pulse_nodes.append(c); _pulse_bases.append(c.position)
		for z in [-0.45, 0.45]:
			var cp := _bx(Vector3(0.38, 0.38, 0.22), col.lightened(0.1)); cp.position = Vector3(0, -0.15, z)
			model_holder.add_child(cp); _pulse_nodes.append(cp); _pulse_bases.append(cp.position)
		for ring in 3:
			for j in 6:
				var ang := TAU * j / 6.0 + ring * 0.4
				var p := _bx(Vector3(0.03, 0.03, 0.1), col.darkened(0.25))
				p.position = Vector3(cos(ang) * 0.2, -0.25 + ring * 0.1, sin(ang) * 0.28)
				p.rotation.y = -ang + PI / 2.0; model_holder.add_child(p)
		for i in 6:
			var sr := 0.035 - i * 0.004
			var s := _bx(Vector3(sr, sr, 0.14), col.darkened(0.3))
			var sp := Vector3(0, -0.15, 0.72 + i * 0.13)
			s.position = sp; model_holder.add_child(s)
			_flag_segs.append(s); _flag_bases.append(sp)
		for x in [-0.14, 0.14]:
			var e := _bx(Vector3(0.09, 0.09, 0.03), ec); e.position = Vector3(x, -0.05, -0.65); model_holder.add_child(e)

	func _germ_2(col: Color, ec: Color) -> void:
		var h := _bx(Vector3(0.5, 0.45, 0.5), col); h.position.y = 0.3; model_holder.add_child(h)
		for i in 4:
			var ang := TAU * i / 4.0 + PI / 4.0
			var f := _bx(Vector3(0.1, 0.1, 0.1), col.lightened(0.2))
			f.position = Vector3(cos(ang) * 0.25, 0.3 + (i % 2) * 0.12, sin(ang) * 0.25); model_holder.add_child(f)
		var n := _bx(Vector3(0.12, 0.1, 0.12), col.darkened(0.25)); model_holder.add_child(n)
		var tl := _bx(Vector3(0.2, 0.35, 0.2), col); tl.position.y = -0.2; model_holder.add_child(tl)
		var nd := _bx(Vector3(0.06, 0.12, 0.06), Color(0.85, 0.85, 0.9)); nd.position.y = -0.45; model_holder.add_child(nd)
		var bs := _bx(Vector3(0.35, 0.06, 0.35), col.darkened(0.3)); bs.position.y = -0.4; model_holder.add_child(bs)
		for i in 6:
			var ang := TAU * i / 6.0
			var up := _bx(Vector3(0.05, 0.25, 0.05), col.darkened(0.15))
			up.position = Vector3(cos(ang) * 0.22, -0.35, sin(ang) * 0.22)
			up.rotation.z = cos(ang) * 0.5; up.rotation.x = -sin(ang) * 0.5; model_holder.add_child(up)
			var ft := _bx(Vector3(0.07, 0.04, 0.07), col.darkened(0.4))
			ft.position = Vector3(cos(ang) * 0.45, -0.55, sin(ang) * 0.45); model_holder.add_child(ft)
		for x in [-0.14, 0.14]:
			var e := _bx(Vector3(0.09, 0.09, 0.03), Color(1.0, 0.85, 0.1)); e.position = Vector3(x, 0.32, -0.26); model_holder.add_child(e)

	func _germ_3(col: Color, ec: Color) -> void:
		var c := _bx(Vector3(0.7, 0.55, 0.8), col); model_holder.add_child(c)
		for i in 4:
			var ang := TAU * i / 4.0 + 0.5
			var b := _bx(Vector3(0.25, 0.2, 0.25), col.lightened(0.15))
			b.position = Vector3(cos(ang) * 0.45, -0.1 + (i % 2) * 0.12, sin(ang) * 0.45); model_holder.add_child(b)
		var e := _bx(Vector3(0.09, 0.09, 0.03), Color(0.9, 0.2, 0.1)); e.position = Vector3(0, 0.03, -0.42); model_holder.add_child(e)

	func _germ_4(col: Color, ec: Color) -> void:
		var h := _bx(Vector3(0.42, 0.36, 0.35), col.lightened(0.15)); h.position = Vector3(0, -0.08, -1.0); model_holder.add_child(h)
		var m := _bx(Vector3(0.26, 0.18, 0.06), col.darkened(0.5)); m.position = Vector3(0, -0.08, -1.18); model_holder.add_child(m)
		for x in [-0.12, 0.12]:
			var e := _bx(Vector3(0.08, 0.08, 0.03), Color(0.95, 0.85, 0.2)); e.position = Vector3(x, 0.12, -0.95); model_holder.add_child(e)
		for i in 8:
			var tt := i / 7.0; var sw := 0.44 - tt * 0.14; var sh := 0.34 - tt * 0.08
			var sc: Color = col.lightened(0.35) if i == 3 or i == 4 else col.darkened(0.06 * (i % 2))
			var s := _bx(Vector3(sw, sh, 0.22), sc)
			var sp := Vector3(0, -0.1, -0.62 + i * 0.24)
			s.position = sp; model_holder.add_child(s)
			_worm_segs.append(s); _worm_bases.append(sp)
			var bp := _bx(Vector3(sw * 0.35, 0.05, 0.14), col.darkened(0.3))
			bp.position = Vector3(0, -0.27, -0.62 + i * 0.24); model_holder.add_child(bp)
		for i in 2:
			var ts := _bx(Vector3(0.16 - i * 0.09, 0.12 - i * 0.06, 0.2), col.darkened(0.2 + i * 0.2))
			var tp := Vector3(0, -0.1, 1.42 + i * 0.18)
			ts.position = tp; model_holder.add_child(ts)
			_worm_segs.append(ts); _worm_bases.append(tp)

	func _germ_5(col: Color, ec: Color) -> void:
		var st := _bx(Vector3(0.4, 0.7, 0.4), col); st.position.y = -0.1; model_holder.add_child(st)
		for i in 5:
			var ang := TAU * i / 5.0
			var br := _bx(Vector3(0.1, 0.5, 0.1), col.lightened(0.25))
			br.position = Vector3(cos(ang) * 0.35, 0.15, sin(ang) * 0.35)
			br.rotation.z = cos(ang) * 0.5; br.rotation.x = -sin(ang) * 0.5; model_holder.add_child(br)
		var sp := _bx(Vector3(0.25, 0.25, 0.25), Color(0.85, 0.65, 0.95)); sp.position.y = 0.5; model_holder.add_child(sp)
		for x in [-0.12, 0.12]:
			var e := _bx(Vector3(0.08, 0.08, 0.03), Color(0.9, 0.9, 0.2)); e.position = Vector3(x, 0.05, -0.22); model_holder.add_child(e)


func _big_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(104, 36)
	b.add_theme_font_size_override("font_size", 14)
	return b


func _update_preview(cid: int) -> void:
	if char_preview == null:
		return
	var is_immune := gamestate.my_faction == 1
	var desc: String = gamestate.IMMUNE_DESC.get(cid, "") if is_immune \
		else gamestate.GERM_DESC.get(cid, "")
	char_preview.show_char(cid, is_immune, desc)


func _on_host_pressed() -> void:
	print("[lobby] 创建主机点击，昵称='", name_edit.text, "'")
	if name_edit.text.strip_edges() == "":
		error_label.text = "请先填写名字"
		return
	_do_host()
	refresh_lobby()


func _probe_room() -> void:
	await get_tree().process_frame
	print("[layout] 房间视图 开始钮=", start_btn.get_global_rect(),
		" 玩家列表=", players_list.get_global_rect(),
		" 昵称框=", name_edit.get_global_rect())


func _probe_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("[layout] 昵称框=", name_edit.get_global_rect(),
		" IP框=", ip_edit.get_global_rect(),
		" 创建主机=", host_btn.get_global_rect(),
		" 视口=", get_viewport().get_visible_rect().size)


func _do_host() -> void:
	var ok := gamestate.host_game(name_edit.text.strip_edges())
	print("[lobby] host_game 结果=", ok)
	if not ok:
		error_label.text = "开服失败 - 端口被占用?"
		return
	# 停发现监听→gamestate 级广播（跨场景存活，迟到玩家也能发现）
	_stop_discovery()
	gamestate.start_broadcast(name_edit.text.strip_edges())
	_enter_room_view()


func _on_join_pressed() -> void:
	if name_edit.text.strip_edges() == "":
		error_label.text = "请先填写名字"
		return
	# 优先用选中的主机；否则回退手动 IP
	var ip := ""
	if _selected_host_ip != "" and _discovered.has(_selected_host_ip):
		ip = _selected_host_ip
	else:
		ip = ip_edit.text.strip_edges()
	if not ip.is_valid_ip_address():
		error_label.text = "请先从列表选择主机 或 手动填 IP"
		return
	error_label.text = "连接中..."
	host_btn.disabled = true
	join_btn.disabled = true
	gamestate.join_game(ip, name_edit.text.strip_edges())


func _on_connection_success() -> void:
	_enter_room_view()


func _on_game_ended() -> void:
	print("[lobby] 收到 game_ended，恢复大厅")
	gamestate.stop_broadcast()  # 回大厅停广播（不再是主机状态）
	show()
	players_panel.visible = false
	host_btn.visible = true
	join_btn.visible = true
	host_btn.disabled = false
	join_btn.disabled = false
	name_edit.editable = true
	# 恢复发现系统 UI
	if disc_row: disc_row.visible = true
	if host_list: host_list.visible = true
	if host_hint: host_hint.visible = true
	if ip_edit: ip_edit.visible = true
	if campaign_btn: campaign_btn.visible = true
	_start_discovery()  # 重新开始发现
	ip_edit.editable = true
	error_label.text = ""
	error_label.text = ""


func _on_connection_failed() -> void:
	error_label.text = "连接失败 - 检查 IP 或主机是否在线"
	host_btn.disabled = false
	join_btn.disabled = false
	players_panel.visible = false
	host_btn.visible = true
	join_btn.visible = true
	ip_edit.editable = true


func _on_game_error(errtxt: String) -> void:
	error_label.text = errtxt
	host_btn.disabled = false
	join_btn.disabled = false


func _enter_room_view() -> void:
	print("[lobby] 进入房间视图，开始按钮可见=", multiplayer.is_server())
	_probe_room.call_deferred()
	error_label.text = ""
	players_panel.visible = true
	host_btn.visible = false
	join_btn.visible = false
	# 隐藏发现系统 UI（已入房不再需要，防止内容溢出）
	if disc_row: disc_row.visible = false
	if host_list: host_list.visible = false
	if host_hint: host_hint.visible = false
	if ip_edit: ip_edit.visible = false
	if campaign_btn: campaign_btn.visible = false
	# 右栏（阵营/角色/预览）保持可见——玩家可随时修改
	refresh_lobby()


func refresh_lobby() -> void:
	players_list.clear()
	var all_players := gamestate.get_player_list()
	all_players.append(gamestate.player_name)
	all_players.sort()
	for p in all_players:
		var suffix := " (你)" if p == gamestate.player_name else ""
		players_list.add_item(p + suffix)
	start_btn.disabled = not multiplayer.is_server()
	start_btn.visible = multiplayer.is_server()


func _open_campaign_select() -> void:
	if campaign_panel and is_instance_valid(campaign_panel):
		campaign_panel.queue_free()
	campaign_panel = Control.new()
	campaign_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	campaign_panel.add_child(bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.position = Vector2(141, 32)  # 纯绝对定位（782×360 视口）
	box.size = Vector2(500, 310)
	box.size = Vector2(500, 270)
	campaign_panel.add_child(box)
	var title := Label.new()
	var faction_label := "免疫视角(防守)" if gamestate.my_faction == 1 else "病原体视角(进攻)"
	title.text = "-- 战役模式 %s --" % faction_label
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.95, 0.75, 0.85)
	box.add_child(title)
	var unlocked: int = gamestate.campaign_unlocked_level()
	var completed: Array = gamestate.campaign_completed()
	# 两列网格（5 行×2 列=10 关，屏内不溢出；点击=选中高亮）
	var sel_ref: Array = [0]  # 选中关卡号（Array 包装穿透 lambda 按值捕获）
	var start_ref: Array = [null]  # 用 Array 包装（lambda 按值捕获，引用类型才能穿透）
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	for lv_id in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]:
		var lv: Dictionary = gamestate.CAMPAIGN_LEVELS[lv_id]
		var locked: bool = lv_id > unlocked
		var done := completed.has(lv_id)
		var lb := Button.new()
		var state := "√" if done else ("×" if locked else "!")
		lb.text = "%d.%s[%s]" \
			% [lv_id, gamestate.campaign_name(lv_id), state]
		lb.add_theme_font_size_override("font_size", 10)
		lb.custom_minimum_size = Vector2(242, 28)
		lb.disabled = locked
		if locked:
			lb.modulate = Color(0.5, 0.5, 0.55)
		elif done:
			lb.modulate = Color(0.6, 0.9, 0.6)
		var lid: int = lv_id
		var lbtn: Button = lb
		lb.pressed.connect(func():
			# 选中高亮（不直接开始）
			sel_ref[0] = lid  # 记录选中
			for other in grid.get_children():
				if other is Button and other != lbtn and not other.disabled:
					other.modulate = Color(0.6, 0.9, 0.6) \
						if completed.has(int(str(other.text).split(".")[0])) \
						else Color.WHITE
			lbtn.modulate = Color(1.0, 0.85, 0.3)  # 选中=金色高亮
			if start_ref[0]:
				(start_ref[0] as Button).disabled = false
				(start_ref[0] as Button).text = "开始 第%d关" % lid)
		grid.add_child(lb)
	var hint := Label.new()
	hint.text = "胜利条件: 己方涂鸦覆盖率超过敌方"
	hint.add_theme_font_size_override("font_size", 9)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.6, 0.65, 0.75)
	box.add_child(hint)
	var close := Button.new()
	# 底部按钮行：返回 + 开始（选中后可用）
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(btn_row)
	close.text = "返回"
	close.add_theme_font_size_override("font_size", 12)
	close.custom_minimum_size = Vector2(100, 30)
	close.pressed.connect(func():
		campaign_panel.queue_free()
		campaign_panel = null)
	btn_row.add_child(close)
	var sb := Button.new()
	start_ref[0] = sb
	sb.text = "先选关卡"
	sb.add_theme_font_size_override("font_size", 12)
	sb.custom_minimum_size = Vector2(120, 30)
	sb.disabled = true
	sb.pressed.connect(func():
		if sel_ref[0] > 0:
			var sl: int = int(sel_ref[0])
			campaign_panel.queue_free()
			campaign_panel = null
			gamestate.begin_campaign(sl))
	btn_row.add_child(sb)
	add_child(campaign_panel)
	# 调试：确认关卡面板位置在屏内
	await get_tree().process_frame
	var vp_size := get_viewport().get_visible_rect().size
	for child in box.get_children():
		if child is Button:
			var r: Rect2 = child.get_global_rect()
			var in_bounds: bool = r.position.x >= 0 and r.end.x <= vp_size.x \
				and r.position.y >= 0 and r.end.y <= vp_size.y
			print("[camp] %s 位置=(%.0f,%.0f)-(%.0f,%.0f) %s" \
				% [child.text.left(12), r.position.x, r.position.y, r.end.x, r.end.y,
				"OK" if in_bounds else "超出!!"])
			break  # 只查第一个


func _on_start_pressed() -> void:
	# 开战前重读昵称（允许房间内修改）
	var nm := name_edit.text.strip_edges()
	if nm != "":
		gamestate.player_name = nm
	gamestate.begin_game()
