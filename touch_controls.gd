extends Control
## 触屏控制 v5·全卡通：
## - 摇杆：脉动斑点 blob + 波浪外环 + 阵营色箭头
## - 跳跃键：全自绘波浪圆钮（按压缩放+文字摆动），弃用系统 Button
## - 触摸=纯视角绑定；单击判定（位移<阈值 且 <450ms）发射
## - 全部尺寸按视口高度自适应（基准 360p）

const BASE_H := 360.0

var joy_id := -1
var joy_center := Vector2.ZERO
var joy_radius := 60.0
var knob_radius := 24.0
var joy_vec := Vector2.ZERO
var look_id := -1
var look_accum := Vector2.ZERO
var look_press_pos := Vector2.ZERO
var look_moved := 0.0
var look_press_ms := 0

var fire_edge := false
var jump_latch := false
var skill_latch := false
var skill_ready := true

var team := 1  # 1=青(免疫)/2=橙(病原)
var tt := 0.0  # 动画时钟

# 跳跃键（自绘）
var jump_center := Vector2.ZERO
var jump_r := 30.0
var jump_rect := Rect2()
var jump_touch := -1
var jump_press := false

# 技能键（自绘，跳跃键上方）
var skill_center := Vector2.ZERO
var skill_r := 24.0
var skill_rect := Rect2()
var skill_touch := -1
var skill_press := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	print("[touch] _ready 触屏可用=", DisplayServer.is_touchscreen_available(),
		" 初始size=", size)
	await get_tree().process_frame
	_layout()


func _process(delta: float) -> void:
	tt += delta
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_layout")


func _k() -> float:
	return clampf(size.y / BASE_H, 0.7, 2.0)


func _accent() -> Color:
	return Color(0.05, 0.75, 0.85) if team == 1 else Color(1.0, 0.55, 0.15)


func set_team(t: int) -> void:
	team = t


func _layout() -> void:
	var w := size
	if w.x < 10.0 or w.y < 10.0:
		return
	var k := _k()
	joy_radius = 62.0 * k
	knob_radius = 25.0 * k
	joy_center = Vector2(95.0 * k, w.y - 95.0 * k)
	jump_r = 28.0 * k
	jump_center = Vector2(w.x - 52.0 * k, w.y - 92.0 * k)
	jump_rect = Rect2(jump_center - Vector2.ONE * (jump_r * 1.3),
		Vector2.ONE * (jump_r * 2.6))
	skill_r = 24.0 * k
	skill_center = Vector2(w.x - 110.0 * k, w.y - 132.0 * k)
	skill_rect = Rect2(skill_center - Vector2.ONE * (skill_r * 1.3),
		Vector2.ONE * (skill_r * 2.6))
	print("[touch] layout完成 size=", w, " joy=", joy_center, " jump=", jump_center)
	queue_redraw()


func _in_button_area(pos: Vector2) -> bool:
	return jump_rect.has_point(pos) or skill_rect.has_point(pos)


func _wobble_circle(c: Vector2, r: float, spikes: int, amp: float,
		speed: float, phase := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 36:
		var a := TAU * i / 36.0
		var rr := r + sin(a * spikes + tt * speed + phase) * amp
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


var _dbg_events := 0


func _input(event: InputEvent) -> void:
	if _dbg_events < 6 and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		_dbg_events += 1
		print("[touch] 事件#", _dbg_events, " ", event.get_class(),
			" pos=", event.position)
	if event is InputEventScreenTouch:
		if event.pressed:
			if jump_touch == -1 and jump_rect.has_point(event.position):
				jump_touch = event.index
				jump_press = true
				jump_latch = true
				return
			if skill_touch == -1 and skill_rect.has_point(event.position):
				skill_touch = event.index
				skill_press = true
				skill_latch = true
				return
			var d: Vector2 = event.position - joy_center
			if d.length() < joy_radius * 1.7 and joy_id == -1:
				joy_id = event.index
				_update_joy(event.position)
			elif look_id == -1 and not _in_button_area(event.position):
				look_id = event.index
				look_press_pos = event.position
				look_moved = 0.0
				look_press_ms = Time.get_ticks_msec()
		else:
			if event.index == jump_touch:
				jump_touch = -1
				jump_press = false
			elif event.index == skill_touch:
				skill_touch = -1
				skill_press = false
			elif event.index == joy_id:
				joy_id = -1
				joy_vec = Vector2.ZERO
			elif event.index == look_id:
				look_id = -1
				var tap_ok := look_moved < 16.0 * _k() \
					and Time.get_ticks_msec() - look_press_ms < 450
				if tap_ok:
					fire_edge = true
	elif event is InputEventScreenDrag:
		if event.index == joy_id:
			_update_joy(event.position)
		elif event.index == look_id:
			look_accum += event.relative
			look_moved += event.relative.length()


func _update_joy(pos: Vector2) -> void:
	var d: Vector2 = pos - joy_center
	joy_vec = d.limit_length(joy_radius) / joy_radius


func consume_look() -> Vector2:
	var v := look_accum
	look_accum = Vector2.ZERO
	return v


func consume_fire_edge() -> bool:
	var v := fire_edge
	fire_edge = false
	return v


func just_jump() -> bool:
	var v := jump_latch
	jump_latch = false
	return v


func just_skill() -> bool:
	var v := skill_latch
	skill_latch = false
	return v


func set_skill_ready(ready: bool) -> void:
	skill_ready = ready


func _draw() -> void:
	if joy_center == Vector2.ZERO:
		return
	var ac := _accent()
	var dark := Color(0.1, 0.11, 0.16)
	var k := _k()

	# ---- 摇杆：脉动斑点 blob 底托 ----
	draw_circle(joy_center, joy_radius + 9.0 * k, Color(0.06, 0.07, 0.12, 0.62))
	for i in 6:
		var ang := TAU * i / 6.0
		var pulse := 1.0 + sin(tt * 2.2 + i * 1.1) * 0.1
		draw_circle(joy_center + Vector2(cos(ang), sin(ang)) * (joy_radius * 0.7),
			joy_radius * 0.44 * pulse, Color(0.08, 0.1, 0.16, 0.5))
	draw_circle(joy_center, joy_radius * 0.8, Color(0.1, 0.12, 0.2, 0.55))
	# 波浪外环（呼吸扭动）+ 阵营色内环
	var ring := _wobble_circle(joy_center, joy_radius, 6, 2.6 * k, 2.6)
	draw_colored_polygon(ring, Color(0.1, 0.12, 0.2, 0.28))
	draw_polyline(ring, dark, 4.0, true)
	var ring2 := _wobble_circle(joy_center, joy_radius - 4.0 * k, 5, 1.8 * k, -2.0)
	draw_polyline(ring2, ac, 2.0, true)
	# 四向三角箭头（随扭动微摆）
	for ang in [0.0, PI / 2, PI, PI * 1.5]:
		var dir := Vector2(cos(ang), sin(ang))
		var wob := sin(tt * 2.5 + ang) * 1.2 * k
		var tip := joy_center + dir * (joy_radius - 10.0 * k + wob)
		var side := Vector2(-dir.y, dir.x) * 5.5 * k
		draw_colored_polygon(PackedVector2Array([
			tip, joy_center + dir * (joy_radius - 22.0 * k) + side,
			joy_center + dir * (joy_radius - 22.0 * k) - side,
		]), Color(ac.r, ac.g, ac.b, 0.95))
	# 摇杆头：脉动 + 高光 + 粗边
	var knob := joy_center + joy_vec * joy_radius
	var kr := knob_radius * (1.0 + sin(tt * 3.0) * 0.06)
	draw_circle(knob, kr + 3.0 * k, dark)
	draw_circle(knob, kr, Color(0.92, 0.95, 1.0, 0.92))
	draw_arc(knob, kr, 0, TAU, 32, dark, 3.0)
	draw_circle(knob + Vector2(-kr * 0.32, -kr * 0.36), kr * 0.28, Color(1, 1, 1))

	# ---- 跳跃键：自绘波浪圆钮 ----
	_draw_skill_button()
	var jr := jump_r * (0.85 if jump_press else 1.0)
	var jampl := (1.6 if jump_press else 2.4) * k
	var jpts := _wobble_circle(jump_center, jr, 5, jampl, 4.0)
	draw_colored_polygon(jpts, Color(ac.r, ac.g, ac.b,
		0.9 if jump_press else 0.55))
	draw_polyline(jpts, dark, 3.5 * k, true)
	# 内圈亮环
	var jpts2 := _wobble_circle(jump_center, jr - 5.0 * k, 5, 1.2 * k, 4.0, 1.3)
	draw_polyline(jpts2, Color(1, 1, 1, 0.35), 1.5, true)
	# 文字「跳」摆动 + 描边
	var font := get_theme_default_font()
	var fs := int(15 * k)
	var txt := "跳"
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(jump_center.x - tw / 2.0,
		jump_center.y + fs * 0.36 + sin(tt * 4.0) * 1.4)
	draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, int(3 * k), dark)
	draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, Color(1, 1, 1, 0.95))

## 技能键绘制（跳跃键左上方的波浪圆钮，就绪亮/冷却暗）
func _draw_skill_button() -> void:
	var k := _k()
	var ac := _accent()
	var dark := Color(0.1, 0.11, 0.16)
	var sr := skill_r * (0.85 if skill_press else 1.0)
	var alpha := 0.9 if skill_ready else 0.3
	var col := Color(1.0, 0.85, 0.3, alpha) if skill_ready else Color(0.5, 0.5, 0.55, 0.5)
	var pts := _wobble_circle(skill_center, sr, 5, 1.8 * k, 3.5)
	draw_colored_polygon(pts, col)
	draw_polyline(pts, dark, 3.0 * k, true)
	var font := get_theme_default_font()
	var fs := int(11 * k)
	var txt := "技"
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tp := Vector2(skill_center.x - tw / 2.0,
		skill_center.y + fs * 0.36 + sin(tt * 4.0) * 1.0)
	draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, int(3 * k), dark)
	draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, Color(1, 1, 1, 0.95 if skill_ready else 0.5))
