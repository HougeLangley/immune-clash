extends Node3D
## 世界 v2-M1：墨汁瓦片地图 + 涂色射击 + 覆盖率对抗 + 计时赛
## 弹道为代码模拟抛物线（无物理体），落地→染色→伤害判定

const MATCH_TIME := 180.0   # 3 分钟计时
const PAINT_RADIUS := 1.4   # 墨汁落地染色半径
const SPLASH_DAMAGE := 30   # 落点附近敌方伤害
const SPLASH_RANGE := 1.3

const WALL_COLOR_STONE := 0
const WALL_COLOR_COBBLE := 1

var tilemap: Node3D
var projectiles: Array = []
var match_time := MATCH_TIME
var match_over := false
var _tick_accum := 0.0
var _hud_accum := 0.0

var hud: CanvasLayer
var pause_btn: PauseButton
var pause_overlay: PauseOverlay
var is_paused := false
var crosshair: Control
var hp_bar: HpBarWidget
var ink_bar_bg: InkMeterWidget
var cover_bar_bg: CoverBarWidget
var end_label: Label
var feed_label: Label
var flash_rect: ColorRect
var touch: Control
var scores := {}
var sfx := {}
var _hair_segs: Array = []   # 毛发 MeshInstance3D（风摆动画用）
var _hair_bases: Array = []  # 原始位置
var _hair_meta: Array = []   # {phase, amp} 每根毛相位/幅度
var _wind_t := 0.0          # 风时钟
var _moving_platforms: Array = []  # 移动平台列表（[{body, rx, rz, speed}]）

## ==================== 多地图定义 ====================
const MAPS := {
	1: {
		"name": "口腔",
		"bg": Color(0.38, 0.10, 0.16),
		"fog": Color(0.92, 0.58, 0.62),
		"fog_density": 0.012,
		"ambient": Color(1.0, 0.82, 0.82),
		"sun": Color(1.0, 0.88, 0.88),
		"dome_tint": Color(1.05, 0.92, 0.90),
		"wall_c": Color(0.95, 0.92, 0.88),
		"layout": "teeth",
	},
	2: {
		"name": "鼻腔",
		"bg": Color(0.30, 0.15, 0.08),
		"fog": Color(0.85, 0.62, 0.38),
		"fog_density": 0.016,
		"ambient": Color(1.0, 0.90, 0.75),
		"sun": Color(1.0, 0.92, 0.80),
		"dome_tint": Color(1.10, 0.82, 0.62),
		"wall_c": Color(0.72, 0.48, 0.28),
		"layout": "maze",
	},
	3: {
		"name": "皮肤",
		"bg": Color(0.35, 0.25, 0.12),
		"fog": Color(0.95, 0.80, 0.55),
		"fog_density": 0.010,
		"ambient": Color(1.0, 0.95, 0.85),
		"sun": Color(1.0, 0.96, 0.90),
		"dome_tint": Color(1.15, 0.95, 0.75),
		"wall_c": Color(0.90, 0.72, 0.42),
		"layout": "layers",
	},
	4: {
		"name": "气管",
		"bg": Color(0.32, 0.08, 0.14),
		"fog": Color(0.90, 0.50, 0.55),
		"fog_density": 0.014,
		"ambient": Color(1.0, 0.80, 0.80),
		"sun": Color(1.0, 0.85, 0.85),
		"dome_tint": Color(1.08, 0.88, 0.85),
		"wall_c": Color(0.92, 0.88, 0.85),
		"layout": "trachea",
	},
	5: {
		"name": "眼睛",
		"bg": Color(0.06, 0.10, 0.22),
		"fog": Color(0.45, 0.65, 0.90),
		"fog_density": 0.009,
		"ambient": Color(0.85, 0.92, 1.0),
		"sun": Color(0.95, 0.97, 1.0),
		"dome_tint": Color(0.90, 0.95, 1.05),
		"wall_c": Color(0.88, 0.92, 0.95),
		"layout": "eye",
	},
	6: {
		"name": "耳朵",
		"bg": Color(0.28, 0.14, 0.20),
		"fog": Color(0.90, 0.70, 0.72),
		"fog_density": 0.013,
		"ambient": Color(1.0, 0.88, 0.88),
		"sun": Color(1.0, 0.90, 0.90),
		"dome_tint": Color(1.10, 0.90, 0.88),
		"wall_c": Color(0.85, 0.68, 0.70),
		"layout": "ear",
	},
	7: {
		"name": "肺",
		"bg": Color(0.08, 0.14, 0.20),
		"fog": Color(0.65, 0.80, 0.85),
		"fog_density": 0.008,
		"ambient": Color(0.92, 0.96, 1.0),
		"sun": Color(0.97, 0.99, 1.0),
		"dome_tint": Color(0.92, 1.0, 1.02),
		"wall_c": Color(0.85, 0.90, 0.92),
		"layout": "lung",
	},
	8: {
		"name": "胃",
		"bg": Color(0.22, 0.18, 0.05),
		"fog": Color(0.80, 0.70, 0.30),
		"fog_density": 0.015,
		"ambient": Color(1.0, 0.92, 0.70),
		"sun": Color(1.0, 0.95, 0.80),
		"dome_tint": Color(1.12, 0.95, 0.68),
		"wall_c": Color(0.82, 0.72, 0.35),
		"layout": "stomach",
	},
	9: {
		"name": "肠道",
		"bg": Color(0.35, 0.15, 0.18),
		"fog": Color(0.95, 0.65, 0.60),
		"fog_density": 0.013,
		"ambient": Color(1.0, 0.85, 0.82),
		"sun": Color(1.0, 0.90, 0.88),
		"dome_tint": Color(1.10, 0.85, 0.80),
		"wall_c": Color(0.88, 0.62, 0.58),
		"layout": "intestine",
	},
	10: {
		"name": "神经",
		"bg": Color(0.03, 0.05, 0.18),
		"fog": Color(0.35, 0.45, 0.90),
		"fog_density": 0.011,
		"ambient": Color(0.80, 0.85, 1.0),
		"sun": Color(0.88, 0.92, 1.0),
		"dome_tint": Color(0.85, 0.90, 1.15),
		"wall_c": Color(0.60, 0.68, 0.95),
		"layout": "nerve",
	},
	11: {
		"name": "肾",
		"bg": Color(0.25, 0.20, 0.08),
		"fog": Color(0.85, 0.75, 0.50),
		"fog_density": 0.010,
		"ambient": Color(1.0, 0.95, 0.80),
		"sun": Color(1.0, 0.97, 0.85),
		"dome_tint": Color(1.10, 1.00, 0.78),
		"wall_c": Color(0.85, 0.78, 0.55),
		"layout": "kidney",
	},
	12: {
		"name": "膀胱",
		"bg": Color(0.05, 0.15, 0.18),
		"fog": Color(0.50, 0.75, 0.80),
		"fog_density": 0.012,
		"ambient": Color(0.88, 0.95, 0.97),
		"sun": Color(0.92, 0.98, 1.0),
		"dome_tint": Color(0.90, 1.00, 1.02),
		"wall_c": Color(0.70, 0.85, 0.88),
		"layout": "bladder",
	},
	13: {
		"name": "骨骼",
		"bg": Color(0.15, 0.12, 0.10),
		"fog": Color(0.90, 0.85, 0.80),
		"fog_density": 0.009,
		"ambient": Color(1.0, 0.98, 0.92),
		"sun": Color(1.0, 0.99, 0.95),
		"dome_tint": Color(1.12, 1.08, 1.00),
		"wall_c": Color(0.92, 0.90, 0.85),
		"layout": "bone",
	},
}

func get_map_cfg() -> Dictionary:
	return MAPS.get(gamestate.selected_map, MAPS[1])


class CrosshairWidget extends Control:
	var color := Color(1, 1, 1, 0.9)

	func _draw() -> void:
		var k := clampf(size.y / 360.0, 0.7, 2.0)
		var c := size / 2.0
		var r := 3.0 * k
		draw_circle(c, r, Color(0, 0, 0, 0.35))
		draw_circle(c, r * 0.45, color)


## 卡通波浪比例条：青侧光滑+泡泡（免疫），橙侧尖刺（病原），两端小脸，内嵌摆动文字
class CoverBarWidget extends Control:
	var frac_c := 0.0   # 青绝对覆盖率（0-1，非两方比值）
	var frac_o := 0.0   # 橙绝对覆盖率
	var pct_l := "青 0%"
	var pct_r := "橙 0%"
	var time_str := "3:00"
	var t := 0.0
	const CYAN := Color(0.05, 0.75, 0.85)
	const ORANGE := Color(1.0, 0.55, 0.15)
	const LINE := Color(0.09, 0.1, 0.14)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _ytop(x: float) -> float:
		return 5.0 + sin(x * 0.14 + t * 2.2) * 3.0

	func _ybot(x: float) -> float:
		return size.y - 6.0 + sin(x * 0.12 + t * 2.2 + 1.7) * 3.0

	func _draw() -> void:
		var w := size.x
		var split := clampf(frac_c, 0.0, 0.98) * w   # 青绝对宽
		var split_o := w - clampf(frac_o, 0.0, 0.98) * w  # 橙右起（中间灰=未涂）
		# 青（0..split）光滑波
		var a := PackedVector2Array()
		var x := 0.0
		while x < split:
			a.append(Vector2(x, _ytop(x)))
			x += 6.0
		a.append(Vector2(split, _ytop(split)))
		x = split
		while x > 0.0:
			a.append(Vector2(x, _ybot(x)))
			x -= 6.0
		a.append(Vector2(0.0, _ybot(0.0)))
		if a.size() >= 3:
			draw_colored_polygon(a, CYAN)
		# 橙（split_o..w）尖刺波：高频三角齿（右侧绝对宽度，中间留灰=未涂）
		var b := PackedVector2Array()
		x = split_o
		while x < w:
			var spike := sin(x * 0.55 + t * 4.0)
			b.append(Vector2(x, _ytop(x) - maxf(0.0, spike) * 3.5))
			x += 4.0
		b.append(Vector2(w, _ytop(w)))
		x = w
		while x > split_o:
			b.append(Vector2(x, _ybot(x)))
			x -= 6.0
		b.append(Vector2(split_o, _ybot(split_o)))
		if b.size() >= 3:
			draw_colored_polygon(b, ORANGE)
		# 粗描边（卡通关键）：顶/底双线
		var top_l := PackedVector2Array()
		var bot_l := PackedVector2Array()
		x = 0.0
		while x <= w:
			top_l.append(Vector2(x, _ytop(x)))
			bot_l.append(Vector2(x, _ybot(x)))
			x += 6.0
		draw_polyline(top_l, LINE, 2.5)
		draw_polyline(bot_l, LINE, 2.5)
		# 青侧泡泡（免疫风）
		for i in 3:
			var bx := split * (0.15 + 0.3 * i) + sin(t * 1.5 + i * 2.0) * 4.0
			var by := size.y * 0.5 + cos(t * 2.0 + i * 1.3) * 4.0
			draw_circle(Vector2(bx, by), 2.0 + i * 0.5, Color(1, 1, 1, 0.5))
		# 两端小脸：左=细胞眼（白底黑瞳），右=细菌刺眼
		var fy := size.y * 0.5
		draw_circle(Vector2(10, fy), 5.0, Color(1, 1, 1))
		draw_circle(Vector2(11, fy), 2.2, Color(0.08, 0.08, 0.1))
		var gx := w - 10.0
		draw_circle(Vector2(gx, fy), 5.0, Color(1, 1, 1))
		draw_circle(Vector2(gx - 1, fy), 2.2, Color(0.08, 0.08, 0.1))
		for s in 6:
			var ang := TAU * s / 6.0 + t * 0.8
			draw_line(Vector2(gx, fy) + Vector2(cos(ang), sin(ang)) * 5.0,
				Vector2(gx, fy) + Vector2(cos(ang), sin(ang)) * 8.0, LINE, 2.0)
		# 内嵌摆动文字（逐字正弦 + 描边，与波形融为一体）
		var font := get_theme_default_font()
		var base := size.y * 0.5 + 4.5
		_wtext(font, Vector2(22, base), pct_l, 12, Color(1, 1, 1, 0.95), 0.0)
		_wtext(font, Vector2(w - 22 - _tw(font, pct_r, 12), base),
			pct_r, 12, Color(1, 1, 1, 0.95), 2.0)
		_wtext(font, Vector2(w / 2.0 - _tw(font, time_str, 13) / 2.0, base + 1.5),
			time_str, 13, Color(1, 1, 0.55), 4.0)

	func _tw(font: Font, text: String, size: int) -> float:
		var total := 0.0
		for i in text.length():
			total += font.get_string_size(text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		return total

	func _wtext(font: Font, pos: Vector2, text: String, size: int,
			col: Color, phase: float) -> void:
		var x := pos.x
		for i in text.length():
			var ch := text[i]
			var off := sin(t * 3.0 + i * 0.9 + phase) * 1.6
			var p := Vector2(x, pos.y + off)
			draw_string_outline(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1,
				size, 3, LINE)
			draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

	func set_data(c1: float, c2: float, ts: String) -> void:
		frac_c = c1
		frac_o = c2
		pct_l = "青 %d%%" % int(c1 * 100.0)
		pct_r = "橙 %d%%" % int(c2 * 100.0)
		time_str = ts


## 卡通墨汁试管：胶囊+波浪液面+泡泡，液体=阵营色
class InkMeterWidget extends Control:
	var value := 1.0
	var team := 1
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var col := Color(0.05, 0.75, 0.85) if team == 1 else Color(1.0, 0.55, 0.15)
		# 波浪胶囊轮廓（整体扭动）
		var outline := PackedVector2Array()
		for i in 32:
			var a := TAU * i / 32.0
			var rx := w / 2.0 - 3.0 + sin(a * 5 + t * 2.0) * 1.6
			var ry := h / 2.0 - 3.0 + cos(a * 4 - t * 1.7) * 1.6
			outline.append(Vector2(w / 2.0, h / 2.0) + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(outline, Color(0.1, 0.1, 0.15, 0.7))
		# 液体（左起，双层波浪面）
		var lw := clampf(value, 0.0, 1.0) * (w - 8.0)
		if lw > 3.0:
			var pts := PackedVector2Array()
			pts.append(Vector2(5, h - 5))
			var x := 5.0
			while x <= lw + 5.0:
				pts.append(Vector2(x, 5.0 + sin(x * 0.45 + t * 3.0) * 2.5))
				x += 3.0
			x = lw + 5.0
			while x >= 5.0:
				pts.append(Vector2(x, h - 5.0 + sin(x * 0.4 - t * 2.0) * 1.5))
				x -= 3.0
			if pts.size() >= 3:
				draw_colored_polygon(pts, col)
			# 上浮大泡泡
			for i in 3:
				var bx := 7.0 + (lw - 12.0) * (0.2 + 0.35 * i) + sin(t * 1.8 + i * 2.1) * 2.0
				draw_circle(Vector2(clampf(bx, 7, lw + 3), h * 0.45 + cos(t * 1.5 + i) * 2.5),
					2.2, Color(1, 1, 1, 0.55))
		# 粗描边（白色双线）
		draw_polyline(outline, Color(1, 1, 1, 0.85), 2.2, true)
		draw_polyline(outline, Color(0.1, 0.11, 0.16), 0.8, true)


## 卡通生命条：细胞脸图标 + 波浪胶囊（膜完整度拟物，颜色随血量绿→红）
class HpBarWidget extends Control:
	var value := 100
	var max_value := 100
	var faction := 2   # 1=免疫(青笑脸) 2=病原(橙尖刺怒脸)
	var t := 0.0
	const LINE := Color(0.09, 0.1, 0.14)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var bar_x := 24.0
		var bar_w := size.x - bar_x
		var fc := Color(0.05, 0.75, 0.85) if faction == 1 else Color(1.0, 0.55, 0.15)
		var c := Color(0.3, 0.9, 0.4).lerp(Color(0.95, 0.3, 0.25),
			1.0 - clampf(value / maxf(max_value, 1.0), 0.0, 1.0))
		# ---- 阵营脸图标（拟物化阵营标识，替代文字）----
		var cc := Vector2(10, h / 2.0)
		if faction == 1:
			# 免疫：光滑圆脸 + 大眼 + 微笑
			draw_circle(cc, 8.5, fc)
			draw_arc(cc, 8.5, 0, TAU, 24, LINE, 2.0)
			draw_circle(cc + Vector2(-2.8, -1.2), 1.8, Color(0.08, 0.08, 0.1))
			draw_circle(cc + Vector2(2.8, -1.2), 1.8, Color(0.08, 0.08, 0.1))
			draw_arc(cc + Vector2(0, 2.0), 3.2, 0.2, PI - 0.2, 8, Color(0.08, 0.08, 0.1), 1.6)
		else:
			# 病原：扭动尖刺 blob + 怒眉眼 + 嫖嘴
			var blob := PackedVector2Array()
			for i in 30:
				var a := TAU * i / 30.0
				var rr := 7.0 + sin(a * 7 + t * 2.5) * 1.8
				blob.append(cc + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(blob, fc)
			draw_polyline(blob, LINE, 2.0, true)
			draw_line(cc + Vector2(-4.5, -3.5), cc + Vector2(-1.2, -1.6), Color(0.08, 0.08, 0.1), 1.8)
			draw_line(cc + Vector2(4.5, -3.5), cc + Vector2(1.2, -1.6), Color(0.08, 0.08, 0.1), 1.8)
			draw_circle(cc + Vector2(-2.6, -0.4), 1.5, Color(0.08, 0.08, 0.1))
			draw_circle(cc + Vector2(2.6, -0.4), 1.5, Color(0.08, 0.08, 0.1))
			draw_arc(cc + Vector2(0, 3.8), 2.6, PI + 0.3, TAU - 0.3, 8, Color(0.08, 0.08, 0.1), 1.6)
		# ---- 波浪胶囊血条 ----
		var outline := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			var rx := bar_w / 2.0 + sin(a * 4 + t * 2.2) * 1.4
			var ry := h / 2.0 - 2.0 + cos(a * 3 - t * 1.8) * 1.2
			outline.append(Vector2(bar_x + bar_w / 2.0, h / 2.0)
				+ Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(outline, Color(0.1, 0.1, 0.15, 0.65))
		var lw := clampf(value / maxf(max_value, 1.0), 0.0, 1.0) * (bar_w - 6.0)
		if lw > 2.0:
			var pts := PackedVector2Array()
			var x := bar_x + 3.0
			while x <= bar_x + 3.0 + lw:
				pts.append(Vector2(x, 4.0 + sin(x * 0.5 + t * 3.0) * 1.8))
				x += 3.0
			x = bar_x + 3.0 + lw
			while x >= bar_x + 3.0:
				pts.append(Vector2(x, h - 4.0))
				x -= 3.0
			if pts.size() >= 3:
				draw_colored_polygon(pts, c)
		draw_polyline(outline, Color(1, 1, 1, 0.85), 2.0, true)
		# 休闲向：不显示数字，血量靠填充+颜色感知


## 卡通结算画面：阵营视角化文案 + 免疫吞噬病原体/病原体反杀动画 + 继续/退出
class EndWidget extends Control:
	var t := 0.0
	var win_text := ""
	var sub_text := ""
	var winner := 1          # 1=免疫胜 2=病原体胜
	var viewer_team := 1     # 观看者阵营（决定文案视角）
	var continue_cb: Callable = Callable()
	var quit_cb: Callable = Callable()
	var btn_continue: Button
	var btn_quit: Button
	const LINE := Color(0.09, 0.1, 0.14)
	const CYAN := Color(0.05, 0.75, 0.85)
	const ORANGE := Color(1.0, 0.55, 0.15)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _setup_buttons() -> void:
		var k := clampf(size.y / 360.0, 0.7, 2.0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18 * k)
		# 纯绝对定位（勿用 anchor preset——叠加偏移坑第 3 次）
		var btn_w := 108.0 * k
		var row_w := btn_w * 2.0 + 18.0 * k
		row.position = Vector2(size.x / 2.0 - row_w / 2.0, size.y - 56.0 * k)
		# 按钮按模式/胜负配置：[文案, 颜色, 回调]
		var btns: Array = []
		if gamestate.campaign_mode:
			if winner == viewer_team:  # 胜
				if gamestate.campaign_level < 13:
					btns = [["下一关", Color(0.16, 0.42, 0.2), continue_cb],
						["返回大厅", Color(0.55, 0.25, 0.25), quit_cb]]
				else:
					btns = [["重新挑战", Color(0.16, 0.42, 0.2), continue_cb],
						["返回大厅", Color(0.55, 0.25, 0.25), quit_cb]]
			else:  # 败
				btns = [["重试", Color(0.16, 0.3, 0.5), continue_cb],
					["返回大厅", Color(0.55, 0.25, 0.25), quit_cb]]
		else:
			btns = [["再战", Color(0.16, 0.42, 0.2), continue_cb],
				["返回大厅", Color(0.55, 0.25, 0.25), quit_cb]]
		for triple in btns:
			var b := Button.new()
			b.text = triple[0]
			b.custom_minimum_size = Vector2(btn_w, 42 * k)
			b.add_theme_font_size_override("font_size", int(15 * k))
			var sb := StyleBoxFlat.new()
			var c: Color = triple[1]
			sb.bg_color = Color(c.r, c.g, c.b, 0.82)
			sb.set_corner_radius_all(48)
			sb.set_border_width_all(3)
			sb.border_color = LINE
			b.add_theme_stylebox_override("normal", sb)
			var sbp := sb.duplicate()
			sbp.bg_color = Color(c.r, c.g, c.b, 1.0)
			b.add_theme_stylebox_override("pressed", sbp)
			b.pressed.connect(triple[2])
			row.add_child(b)
		add_child(row)

	func _wtext(font: Font, pos: Vector2, text: String, size_: int,
			col: Color, phase: float) -> void:
		var x := pos.x
		for i in text.length():
			var ch := text[i]
			var off := sin(t * 2.5 + i * 0.8 + phase) * 3.0
			var p := Vector2(x, pos.y + off)
			draw_string_outline(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1,
				size_, int(4), LINE)
			draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size_).x

	func _face(c: Vector2, r: float, col: Color, faction: int,
			mood: String) -> void:
		# faction 1=免疫光滑圆 2=病原尖刺blob；mood: grin/sad/dead
		if faction == 1:
			draw_circle(c, r, col)
			draw_arc(c, r, 0, TAU, 24, LINE, 2.5)
		else:
			var blob := PackedVector2Array()
			for i in 30:
				var a := TAU * i / 30.0
				var rr := r * 0.82 + sin(a * 7 + t * 3.0) * r * 0.2
				blob.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(blob, col)
			draw_polyline(blob, LINE, 2.5, true)
		var eye := Color(0.08, 0.08, 0.1)
		if mood == "dead":
			for dx in [-0.35, 0.35]:
				var ec := c + Vector2(r * dx, -r * 0.15)
				draw_line(ec - Vector2(r * 0.14, -r * 0.14),
					ec + Vector2(r * 0.14, -r * 0.14), eye, 2.0)
				draw_line(ec - Vector2(r * 0.14, r * 0.14),
					ec + Vector2(r * 0.14, r * 0.14), eye, 2.0)
		else:
			for dx in [-0.35, 0.35]:
				draw_circle(c + Vector2(r * dx, -r * 0.12), r * 0.13, eye)
			if mood == "grin":
				draw_arc(c + Vector2(0, r * 0.25), r * 0.45, 0.2, PI - 0.2,
					10, eye, 2.2)
			else:
				draw_arc(c + Vector2(0, r * 0.55), r * 0.4, PI + 0.3,
					TAU - 0.3, 10, eye, 2.2)

	func _draw() -> void:
		# 半透明暗幕
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.1, 0.72))
		var font := get_theme_default_font()
		var w := size.x
		var h := size.y
		var k := clampf(h / 360.0, 0.7, 2.0)
		# 主文案（按实际字宽真居中，不固定偏移）
		var main_col: Color = Color(0.95, 0.75, 0.6) if winner == viewer_team \
			else Color(0.75, 0.78, 0.85)
		var wfs := int(20 * k)
		var tw := 0.0
		for ch in win_text:
			tw += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs).x
		_wtext(font, Vector2(w / 2.0 - tw / 2.0, h * 0.22), win_text,
			wfs, main_col, 0.0)
		# 比分副文案
		var sw := font.get_string_size(sub_text, HORIZONTAL_ALIGNMENT_LEFT,
			-1, int(11 * k)).x
		draw_string(font, Vector2(w / 2.0 - sw / 2.0, h * 0.22 + 18 * k),
			sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * k),
			Color(0.85, 0.85, 0.9, 0.8))
		# 场景：胜方大脸在左 grin，败方三个小脸向右飘落 dead
		var win_faction := winner
		var lose_faction := 3 - winner
		var win_col := CYAN if win_faction == 1 else ORANGE
		var lose_col := ORANGE if win_faction == 1 else CYAN
		var bob := sin(t * 2.0) * 4 * k
		_face(Vector2(w * 0.32, h * 0.52 + bob), 26 * k, win_col,
			win_faction, "grin")
		for i in 3:
			var fx := w * (0.58 + 0.13 * i) + sin(t * 1.5 + i * 2.0) * 6 * k
			var fy := h * (0.5 + 0.1 * (i % 2)) + cos(t * 1.2 + i) * 8 * k \
				+ sin(t * 0.8 + i * 1.4) * 5 * k
			_face(Vector2(fx, fy), (12 - i * 2.0) * k, lose_col,
				lose_faction, "dead")
		# 胜方色墨滴庆祝
		for i in 8:
			var cx := (i * 97.3 + t * 40 * (0.5 + (i % 3) * 0.25))
			cx = fmod(cx, w)
			var cy := fmod(t * (50 + i * 13), h)
			draw_circle(Vector2(cx, cy), 3.5 * k,
				Color(win_col.r, win_col.g, win_col.b, 0.45))


## 暂停按钮（右上角圆形，图标=两竖条，点击弹出暂停面板）
class PauseButton extends Control:
	var t := 0.0
	var pressed_cb: Callable = Callable()
	var is_paused := false   # 暂停中不重复触发
	const LINE := Color(0.09, 0.1, 0.14)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _input(event: InputEvent) -> void:
		if is_paused:
			return
		var press: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT)
		if press:
			var center := position + size / 2.0
			if event.position.distance_to(center) < size.x * 0.7:
				pressed_cb.call()
				get_viewport().set_input_as_handled()

	func _draw() -> void:
		var c := size / 2.0
		var r := size.x * 0.5
		# 波浪圆底钮
		var pts := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			var rr := r + sin(a * 4 + t * 2.0) * 1.5
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, Color(0.1, 0.11, 0.16, 0.75))
		draw_polyline(pts, Color(1, 1, 1, 0.85), 2.5, true)
		# 两竖条（暂停符号 ⏸）
		var bar_h := r * 0.55
		var bar_w := r * 0.16
		for dx in [-r * 0.18, r * 0.18]:
			draw_rect(Rect2(c + Vector2(dx - bar_w / 2.0, -bar_h / 2.0),
				Vector2(bar_w, bar_h)), Color(1, 1, 1, 0.92))


## 暂停面板（半透明暗幕 + 继续圆钮大 + 退出钮小）
class PauseOverlay extends Control:
	var t := 0.0
	var grace_until_ms := 0   # 墙钟宽限（不受游戏暂停影响）
	var resume_cb: Callable = Callable()
	var quit_cb: Callable = Callable()
	const LINE := Color(0.09, 0.1, 0.14)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func show_pause() -> void:
		visible = true
		grace_until_ms = Time.get_ticks_msec() + 350

	func _input(event: InputEvent) -> void:
		if not visible or Time.get_ticks_msec() < grace_until_ms:
			return
		var press: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT)
		if press:
			var c := size / 2.0
			var k := clampf(size.y / 360.0, 0.7, 2.0)
			if event.position.distance_to(c) < 44 * k:
				resume_cb.call()
				get_viewport().set_input_as_handled()
			elif event.position.distance_to(c + Vector2(80 * k, 62 * k)) < 34 * k:
				quit_cb.call()
				get_viewport().set_input_as_handled()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.1, 0.68))
		var c := size / 2.0
		var k := clampf(size.y / 360.0, 0.7, 2.0)
		var r := 36 * k
		# 中央大播放钮（三角，一看就知=继续）
		var pts := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			var rr := r + sin(a * 4 + t * 2.0) * 2.0
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts, Color(0.05, 0.75, 0.85, 0.85))
		draw_polyline(pts, Color(1, 1, 1, 0.9), 3.0, true)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.25, -r * 0.35),
			c + Vector2(-r * 0.25, r * 0.35),
			c + Vector2(r * 0.35, 0),
		]), Color(1, 1, 1, 0.95))
		# 右下小退出钮（暗红圆+×）
		var qc := c + Vector2(80 * k, 60 * k)
		var qr := 24 * k
		var qpts := PackedVector2Array()
		for i in 24:
			var a2 := TAU * i / 24.0
			var rr2 := qr + sin(a2 * 4 + t * 1.8) * 1.5
			qpts.append(qc + Vector2(cos(a2), sin(a2)) * rr2)
		draw_colored_polygon(qpts, Color(0.7, 0.2, 0.2, 0.85))
		draw_polyline(qpts, Color(1, 1, 1, 0.9), 2.5, true)
		var xs := qr * 0.35
		draw_line(qc + Vector2(-xs, -xs), qc + Vector2(xs, xs), Color(1, 1, 1, 0.95), 3)
		draw_line(qc + Vector2(-xs, xs), qc + Vector2(xs, -xs), Color(1, 1, 1, 0.95), 3)
		# 退出钮下方明确文字「返回大厅」（可发现性）
		var font := get_theme_default_font()
		var lbl := "返回大厅"
		var lw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * k)).x
		draw_string_outline(font, qc + Vector2(-lw / 2.0, 42 * k), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * k), 3, Color(0.09, 0.1, 0.14))
		draw_string(font, qc + Vector2(-lw / 2.0, 42 * k), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 * k), Color(1.0, 0.85, 0.85))


var round_countdown := 5.0   # 开局倒计时（期间 AI 冻结、玩家锁枪）
var countdown_label: Label
var _last_cd_sec := -1


func _ready() -> void:
	add_to_group("world")
	# 战役模式：用关卡时间
	if gamestate.campaign_mode:
		match_time = gamestate.CAMPAIGN_LEVELS[gamestate.campaign_level]["time"]
	_build_pixel_materials()
	_build_environment()
	_build_arena()
	_build_spawn_points()
	_build_hud()
	_build_sfx()
	_start_bgm()
	print("[world] 墨汁竞技场就绪（战役=%s 关卡=%d 时长=%.0fs）" \
		% [gamestate.campaign_mode, gamestate.campaign_level, match_time])
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and not multiplayer.is_server():
		gamestate.client_world_ready.rpc_id(1)


func get_spawn_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for m in $SpawnPoints.get_children():
		pts.append((m as Node3D).global_position)
	return pts


## 阵营分区出生：周开局随机选一对对跖方向，同队同区+区内随机散布
var _team_spawn_centers := {}  # team -> Vector3

@rpc("any_peer", "call_local")
func setup_team_spawns(c1: Vector3 = Vector3.ZERO, c2: Vector3 = Vector3.ZERO) -> void:
	if c1 == Vector3.ZERO:
		# 服务器自己随机
		var angle := randf() * TAU
		var radius := 16.0
		c1 = Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
		c2 = Vector3(-c1.x, c1.y, -c1.z)
	_team_spawn_centers[1] = c1
	_team_spawn_centers[2] = c2
	print("[world] 阵营出生区：免疫=%s 病原体=%s 相距=%.0fm" % [
		c1, c2, c1.distance_to(c2)])


func team_spawn(team: int) -> Vector3:
	var center: Vector3 = _team_spawn_centers.get(team, Vector3(0, 1, 0))
	var ang := randf() * TAU
	var dist := randf_range(0.5, 5.0)
	var pos := center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
	var r := Vector2(pos.x, pos.z).length()
	if r > 22.0:
		pos.x = pos.x / r * 22.0
		pos.z = pos.z / r * 22.0
	return _find_clear_spawn(pos)


## 出生点障碍物薄空：用物理查询检测，被堵时螺旋搜索干净点
func _find_clear_spawn(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var params := PhysicsPointQueryParameters3D.new()
	params.position = pos + Vector3(0, 1.0, 0)  # 身体高度检测
	params.collision_mask = 1  # 环境层
	params.collide_with_bodies = true
	if space.intersect_point(params, 4).is_empty():
		return pos
	# 螺旋向外搜干净点（避开牙齿/障碍物）
	for radius in [1.8, 3.0, 4.5, 6.0]:
		for i in 8:
			var a := TAU * i / 8.0
			var test := pos + Vector3(cos(a) * radius, 0, sin(a) * radius)
			var rr := Vector2(test.x, test.z).length()
			if rr > 22.0:
				continue
			params.position = test + Vector3(0, 1.0, 0)
			if space.intersect_point(params, 4).is_empty():
				return test
	return pos  # 全堵→兑底原点


func random_spawn(team := 0) -> Vector3:
	if team > 0 and _team_spawn_centers.has(team):
		return team_spawn(team)
	# 兑底：无阵营信息时全区随机
	var ang := randf() * TAU
	var dist := randf_range(5.0, 20.0)
	return _find_clear_spawn(Vector3(cos(ang) * dist, 1.0, sin(ang) * dist))


# ---------------- 场景 ----------------

# 组织脉动着色器：按世界坐标行进波，GPU 呼吸感（地砖/墙面共用）
const PULSE_SHADER := "
shader_type spatial;
render_mode unshaded;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest;
uniform vec2 uv_scale = vec2(1.0);
uniform float wave_speed = 1.4;
uniform float wave_amount = 0.10;
varying vec4 v_color;
varying vec3 v_world;
void vertex() {
	v_color = COLOR;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float wave = sin(wave_speed * TIME + v_world.x * 0.55 + v_world.z * 0.35);
	float pulse = 1.0 - wave_amount * (0.5 + 0.5 * wave);
	vec3 tc = texture(tex, UV * uv_scale).rgb;
	ALBEDO = tint.rgb * v_color.rgb * tc * pulse;
}
"
var pulse_shader: Shader


## 血管蠕动 shader：凸起沿血管壁向上爬行 + 纹理明暗呼吸
const VESSEL_SHADER := "
shader_type spatial;
render_mode unshaded;
uniform sampler2D tex : source_color, filter_nearest;
uniform vec2 uv_scale = vec2(2.0, 3.0);
uniform float bulge_amp = 0.16;
uniform float bulge_speed = 2.5;
uniform float bulge_freq = 3.0;
varying vec3 v_world;
void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world = wp.xyz;
	float b = 1.0 + bulge_amp * sin(v_world.y * bulge_freq - TIME * bulge_speed);
	VERTEX.xz *= b;
}
void fragment() {
	vec3 tc = texture(tex, UV * uv_scale).rgb;
	float breath = 0.9 + 0.1 * sin(TIME * 1.3 + v_world.x * 0.8);
	ALBEDO = tc * breath;
}
"
var vessel_shader: Shader


## 血管柱：圆柱血管体 + 顶端球状血管结，碰撞用箱体近似
func _add_vessel(base: Vector3) -> void:
	var m := ShaderMaterial.new()
	m.shader = vessel_shader
	m.set_shader_parameter("tex", tex_vessel)
	m.set_shader_parameter("uv_scale", Vector2(2.0, 3.0))
	# 血管主体（圆柱，直径 1.7，高 2）
	var cyl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.85
	cm.bottom_radius = 0.95
	cm.height = 2.0
	cyl.mesh = cm
	cyl.material_override = m
	cyl.position = base + Vector3(0, 1.0, 0)
	add_child(cyl)
	# 顶端血管结（球）
	var cap := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	cap.mesh = sm
	cap.material_override = m
	cap.position = base + Vector3(0, 2.3, 0)
	add_child(cap)
	# 碰撞（箱体近似，覆盖柱+结）
	var sb := StaticBody3D.new()
	sb.position = base + Vector3(0, 1.3, 0)
	sb.set_meta("debris_color", Color(0.82, 0.2, 0.26))
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 2.9, 1.8)
	col.shape = shape
	sb.add_child(col)
	add_child(sb)


func _organ_mat(tex: ImageTexture, tint: Color, uv: Vector2, amount := 0.10) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = pulse_shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("uv_scale", uv)
	m.set_shader_parameter("wave_amount", amount)
	m.set_meta("avg", _avg_color(tex) * tint)
	return m


## 器官表面 shader：沿法线位移的真几何蠕动（穹顶/墙面共用）
const ORGAN_SURFACE_SHADER := "
shader_type spatial;
render_mode unshaded, cull_front;
uniform sampler2D tex : source_color, filter_nearest;
uniform vec2 uv_scale = vec2(8.0, 1.0);
uniform float disp_amp = 0.5;
uniform float disp_speed = 1.0;
uniform float disp_freq = 0.35;
uniform float breath = 0.06;
varying vec3 v_world;
void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world = wp.xyz;
	float d = sin(disp_speed * TIME + v_world.x * disp_freq
		+ v_world.y * disp_freq * 0.8 + v_world.z * 0.2);
	float ramp = clamp(v_world.y * 0.35, 0.0, 1.0);
	VERTEX += NORMAL * d * disp_amp * ramp;
}
void fragment() {
	vec3 tc = texture(tex, UV * uv_scale).rgb;
	float b = 1.0 - breath * (0.5 + 0.5 * sin(TIME * 1.4 + v_world.x * 0.3));
	ALBEDO = tc * b;
}
"
var organ_surface_shader: Shader


func _organ_surface_mat(tex: ImageTexture, uv: Vector2, disp_amp: float,
		disp_freq := 0.35, disp_speed := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = organ_surface_shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("uv_scale", uv)
	m.set_shader_parameter("disp_amp", disp_amp)
	m.set_shader_parameter("disp_freq", disp_freq)
	m.set_shader_parameter("disp_speed", disp_speed)
	return m


func _build_environment() -> void:
	var cfg := get_map_cfg()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = cfg["bg"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = cfg["ambient"]
	env.ambient_light_energy = 1.1  # 降低环境光防刺眼（原 1.4）
	env.fog_enabled = true
	env.fog_light_color = cfg["fog"]
	env.fog_density = cfg["fog_density"]
	# ==== 视觉增强（Bloom+色调映射+色彩微调，Vulkan Mobile 兼容）====
	# ACES 色调映射：更丰富的色彩渐变（暗部/亮部层次更好）
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.92    # 略降曝光防刺眼
	# Bloom 泛光：发光体柔和光晕（保守设置防过亮）
	env.glow_enabled = true
	env.glow_intensity = 0.35     # 降低泛光强度
	env.glow_strength = 0.8
	env.glow_bloom = 0.02         # 极轻微全屏泛光
	env.glow_hdr_threshold = 1.1  # 提高阈值=只让强发光体泛光
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# 色彩微调：降饱和微降对比（防刺眼）
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.0
	env.adjustment_brightness = 0.95  # 整体压暗 5%
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	add_child(wenv)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.95  # 降低阳光（原 1.2，防过曝）
	sun.light_color = cfg["sun"]
	sun.shadow_enabled = true
	add_child(sun)
	# 组织穹顶：赤道直接落地，扁球腔体，按地图染色
	var dome_mat := _organ_surface_mat(tex_flesh, Vector2(32, 16), 1.2, 0.2, 0.9)
	dome_mat.set_shader_parameter("tint", cfg["dome_tint"])
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 25.0
	sm.height = 50.0
	sm.radial_segments = 56
	sm.rings = 28
	dome.mesh = sm
	dome.material_override = dome_mat
	dome.scale = Vector3(1.0, 1.25, 1.0)
	add_child(dome)
	_add_wall_ring(24.5, 12, 14.0, cfg["wall_c"])
	_spawn_blood_cells()


## 漂浮红细胞（环形，缓慢漂过天空）
func _spawn_blood_cells() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.07
	mesh.outer_radius = 0.22
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.15, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var gp := GPUParticles3D.new()
	gp.amount = 26
	gp.lifetime = 14.0
	gp.preprocess = 14.0
	gp.draw_pass_1 = mesh
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0.1, 0.3)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24, 4, 24)
	gp.process_material = pm
	add_child(gp)
	print("[world] 红细胞粒子就绪")


# 器官纹理（程序化）：肌肉组织 / 血管 / 粘膜
var tex_flesh: ImageTexture
var tex_vessel: ImageTexture
var tex_mucosa: ImageTexture
var tex_tooth: ImageTexture
var tex_hair: ImageTexture
var tex_brick: ImageTexture
var tex_iris: ImageTexture
var tex_sclera: ImageTexture
var tex_cochlea: ImageTexture


func _build_pixel_materials() -> void:
	pulse_shader = Shader.new()
	pulse_shader.code = PULSE_SHADER
	organ_surface_shader = Shader.new()
	organ_surface_shader.code = ORGAN_SURFACE_SHADER
	vessel_shader = Shader.new()
	vessel_shader.code = VESSEL_SHADER
	tex_flesh = _tex(16, _p_flesh)
	tex_vessel = _tex(16, _p_vessel)
	tex_mucosa = _tex(16, _p_mucosa)
	tex_tooth = _tex(16, _p_tooth)
	tex_hair = _tex(16, _p_hair)
	tex_brick = _tex(16, _p_brick)
	tex_iris = _tex(16, _p_iris)
	tex_sclera = _tex(16, _p_sclera)
	tex_cochlea = _tex(16, _p_cochlea)


## 虹膜：蓝绿放射纹理
func _p_iris(x: int, y: int) -> Color:
	var c := Color(0.20, 0.45, 0.75)
	if (x + y * 2) % 5 == 0:
		c = Color(0.12, 0.30, 0.55)  # 暗纹（放射状）
	if (x * 3 + y) % 7 == 0:
		c = c.lightened(0.15)  # 亮丝
	return _jit(c, 0.03)


## 巩膜：瓷白微纹
func _p_sclera(x: int, y: int) -> Color:
	var c := Color(0.94, 0.95, 0.96)
	if (x * 5 + y * 3) % 13 == 0:
		c = Color(0.88, 0.90, 0.93)  # 微血管纹
	return _jit(c, 0.015)


## 耳蜗：粉棕螺旋纹
func _p_cochlea(x: int, y: int) -> Color:
	var c := Color(0.82, 0.62, 0.65)
	if (x + y) % 4 == 0:
		c = Color(0.72, 0.52, 0.58)  # 螺旋暗纹
	if (x * 2 + y * 3) % 9 == 0:
		c = c.lightened(0.12)
	return _jit(c, 0.03)


## 牙釉质：白色晶体光泽+淡黄根
func _p_tooth(x: int, y: int) -> Color:
	var c := Color(0.96, 0.95, 0.92)
	if y > 10:
		c = Color(0.88, 0.82, 0.65)  # 牙根微黄
	if (x * 7 + y * 3) % 11 == 0:
		c = c.lightened(0.05)  # 高光斑点
	return _jit(c, 0.02)


## 鼻毛：深棕毛发丝缕
func _p_hair(x: int, y: int) -> Color:
	var c := Color(0.55, 0.38, 0.20)
	if x % 3 == 0:
		c = Color(0.42, 0.28, 0.14)  # 暗丝
	if (x * 5 + y * 2) % 7 == 0:
		c = c.lightened(0.15)  # 高光丝
	return _jit(c, 0.04)


## 表皮砖墙：米黄砖块+浅缝
func _p_brick(x: int, y: int) -> Color:
	var c := Color(0.88, 0.72, 0.45)
	if y % 5 == 0 or (x + (y / 5) * 4) % 8 == 0:
		c = Color(0.78, 0.60, 0.35)  # 砖缝
	return _jit(c, 0.03)


## 肌肉组织：4x4 细胞团簇 + 深色缝隙（离分红色系）
func _p_flesh(x: int, y: int) -> Color:
	var cx := x / 4
	var cy := y / 4
	var h := float((cx * 73856093 ^ cy * 19349663) % 100) / 100.0
	if x % 4 == 0 or y % 4 == 0:
		return _jit(Color(0.70, 0.24, 0.32), 0.02)  # 组织缝隙
	var base := Color(0.88, 0.42, 0.48).lerp(Color(0.95, 0.58, 0.60), h)
	if randf() < 0.05:
		base = Color(0.98, 0.74, 0.76)  # 高光小泡
	return _jit(base, 0.03)


## 血管：竖向红蓝条纹（动脉/静脉）+ 环状瓣膜
func _p_vessel(x: int, y: int) -> Color:
	var col := x / 2
	var h := float((col * 2654435761) % 100) / 100.0
	var base := Color(0.82, 0.18, 0.24) if h < 0.7 else Color(0.30, 0.40, 0.88)
	if y % 8 == 0:
		base = base.darkened(0.3)  # 瓣膜环
	return _jit(base, 0.04)


## 粘膜：浅粉基底 + 腺体小孔
func _p_mucosa(x: int, y: int) -> Color:
	var base := Color(0.96, 0.74, 0.77)
	if (x % 5 == 2) and (y % 5 == 1) and randf() < 0.7:
		base = Color(0.86, 0.56, 0.62)  # 腺孔
	return _jit(base, 0.02)


func _p_stone(_x: int, _y: int) -> Color:
	var c := _jit(Color(0.55, 0.55, 0.57), 0.04)
	if randf() < 0.08:
		c = Color(0.42, 0.42, 0.44)
	return c


func _p_cobble(x: int, y: int) -> Color:
	var cx := x / 4
	var cy := y / 4
	var h := float((cx * 73856093 ^ cy * 19349663) % 100) / 100.0
	var v := 0.48 + h * 0.16
	if x % 4 == 0 or y % 4 == 0:
		v -= 0.15
	return _jit(Color(v, v, v + 0.01), 0.03)


func _p_planks(x: int, y: int) -> Color:
	var c := Color(0.62, 0.45, 0.26)
	if y % 4 == 3:
		c = Color(0.44, 0.31, 0.17)
	if (y / 4) % 2 == 0 and x == 7:
		c = Color(0.44, 0.31, 0.17)
	if (y / 4) % 2 == 1 and x == 15:
		c = Color(0.44, 0.31, 0.17)
	return _jit(c, 0.03)


func _p_crate(x: int, y: int) -> Color:
	if x <= 1 or x >= 14 or y <= 1 or y >= 14:
		return _jit(Color(0.38, 0.26, 0.14), 0.03)
	var c := Color(0.62, 0.45, 0.26)
	if y % 4 == 3:
		c = Color(0.44, 0.31, 0.17)
	return _jit(c, 0.03)


func _tex(size: int, paint: Callable) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, paint.call(x, y))
	return ImageTexture.create_from_image(img)


func _jit(c: Color, amt: float) -> Color:
	return Color(
		clampf(c.r + randf_range(-amt, amt), 0.0, 1.0),
		clampf(c.g + randf_range(-amt, amt), 0.0, 1.0),
		clampf(c.b + randf_range(-amt, amt), 0.0, 1.0))


func _pix_mat(tex: ImageTexture) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.set_meta("avg", _avg_color(tex))
	return m


func _avg_color(tex: ImageTexture) -> Color:
	var img := tex.get_image()
	var c := Color(0, 0, 0)
	var n := img.get_width() * img.get_height()
	for y in img.get_height():
		for x in img.get_width():
			c += img.get_pixel(x, y)
	return c / float(n)


func _tiled(mat: StandardMaterial3D, uv: Vector2) -> StandardMaterial3D:
	var m := mat.duplicate() as StandardMaterial3D
	m.uv1_scale = Vector3(uv.x, uv.y, 1.0)
	m.set_meta("avg", mat.get_meta("avg", Color(0.5, 0.5, 0.5)))
	return m


func _build_arena() -> void:
	# 墨汁瓦片地面（核心）
	tilemap = Node3D.new()
	tilemap.set_script(load("res://ink_tile_map.gd"))
	add_child(tilemap)
	# 地板碰撞体
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0, -0.38, 0)
	floor_body.set_meta("debris_color", Color(0.9, 0.5, 0.55))
	var fcol := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(50, 1, 50)
	fcol.shape = fshape
	floor_body.add_child(fcol)
	add_child(floor_body)
	# 按地图选障碍物布局
	var cfg := get_map_cfg()
	match cfg["layout"]:
		"teeth": _build_oral_teeth()
		"maze": _build_nasal_maze()
		"layers": _build_skin_layers()
		"trachea": _build_trachea()
		"eye": _build_eye()
		"ear": _build_ear()
		"lung": _build_lung()
		"stomach": _build_stomach()
		"intestine": _build_intestine()
		"nerve": _build_nerve()
		"kidney": _build_kidney()
		"bladder": _build_bladder()
		"bone": _build_bone()
		_: _build_default_layout()


## 组织面：细分 PlaneMesh + 位移 shader（墙面等）
## ==================== 地图布局构建器 ====================

## 口腔：白色齿柱两排弧线+中央高齿冠平台
func _build_oral_teeth() -> void:
	var tooth_mat := _pix_mat(tex_tooth)
	var gum_mat := _organ_mat(tex_mucosa, Color(1.05, 0.75, 0.78), Vector2(3, 2), 0.05)
	# 两条齿弓（上下弧线）——每颗牙=牙冠+牙龈座
	for arc: float in [0.0, PI]:
		for i in range(-2, 3):
			var ang := arc + i * 0.22
			var r := 13.0
			var base := Vector3(cos(ang) * r, 0, sin(ang) * r)
			_add_tooth(base, 1.0, tooth_mat, gum_mat)
	# 中央大磨牙（可跳上平台）
	_add_tooth(Vector3(0, 0, 0), 1.6, tooth_mat, gum_mat)
	# 内圈小齿尖
	for i in 8:
		var ang := TAU * i / 8.0 + 0.39
		var r := 7.0
		_add_tooth(Vector3(cos(ang) * r, 0, sin(ang) * r), 0.55, tooth_mat, gum_mat)

## 具象牙齿：牙冠桶状（中宽上下窄）+双牙尖+粉色牙龈座
func _add_tooth(base: Vector3, scale_f: float, tooth_mat: Material, gum_mat: Material) -> void:
	var s := scale_f
	# 牙龈座（粉色圆丘）
	_add_box(base + Vector3(0, 0.2 * s, 0), Vector3(2.8 * s, 0.4 * s, 2.8 * s), gum_mat, false)
	# 牙冠：底部窄→中部宽→顶部窄（桶状）
	_add_box(base + Vector3(0, 0.8 * s, 0), Vector3(2.0 * s, 0.8 * s, 2.0 * s), tooth_mat, false)
	_add_box(base + Vector3(0, 1.8 * s, 0), Vector3(2.4 * s, 1.2 * s, 2.4 * s), tooth_mat, false)
	_add_box(base + Vector3(0, 2.7 * s, 0), Vector3(2.0 * s, 0.6 * s, 2.0 * s), tooth_mat, false)
	# 双牙尖（磨牙咬合面的两个凸起）
	_add_box(base + Vector3(-0.5 * s, 3.2 * s, 0), Vector3(0.7 * s, 0.4 * s, 0.7 * s), tooth_mat, false)
	_add_box(base + Vector3(0.5 * s, 3.2 * s, 0), Vector3(0.7 * s, 0.4 * s, 0.7 * s), tooth_mat, false)
	# 单碰撞体（覆盖牙冠整体）
	_add_collision_box(base + Vector3(0, 1.6 * s, 0),
		Vector3(2.4 * s, 3.2 * s, 2.4 * s), Color(0.95, 0.92, 0.88))

## 鼻腔：鼻毛簇迷宫（每簇=多根弯曲细毛）
func _build_nasal_maze() -> void:
	var hair_mat := _pix_mat(tex_hair)
	var skin_mat := _organ_mat(tex_mucosa, Color(1.0, 0.72, 0.5), Vector2(2, 2), 0.04)
	# 5×5 网格，留出巷道；避开中央和出生区
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			if abs(gx) <= 0 and abs(gz) <= 0:
				continue
			if abs(gx) + abs(gz) == 4:
				continue
			if (gx + gz) % 2 == 0:
				continue
			var pos := Vector3(gx * 5.5, 0, gz * 5.5)
			_add_hair_cluster(pos, hair_mat, skin_mat)
	# 中央短毛簇
	for i in 4:
		var ang := TAU * i / 4.0 + 0.5
		var r := 4.0
		_add_hair_cluster(Vector3(cos(ang) * r, 0, sin(ang) * r), hair_mat, skin_mat, 0.6)

## 具象鼻毛簇：毛囊座+3-4根弯曲细毛（不同高度/角度，带风摆）
func _add_hair_cluster(base: Vector3, hair_mat: Material, skin_mat: Material, s := 1.0) -> void:
	var ph0 := base.x * 0.7 + base.z * 1.3  # 每簇相位错开
	# 毛囊座（肉色小丘）
	_add_box(base + Vector3(0, 0.15 * s, 0), Vector3(1.3 * s, 0.3 * s, 1.3 * s), skin_mat, false)
	# 毛 1（最高，3 段渐进弯曲，越上摆幅越大）
	_reg_hair(_add_box(base + Vector3(-0.1, 0.9 * s, 0), Vector3(0.18, 1.4 * s, 0.18), hair_mat, false), ph0, 0.02)
	_reg_hair(_add_box(base + Vector3(-0.05, 2.1 * s, 0.08), Vector3(0.16, 1.2 * s, 0.16), hair_mat, false), ph0 + 0.5, 0.04)
	_reg_hair(_add_box(base + Vector3(0.12, 3.1 * s, 0.2), Vector3(0.14, 1.0 * s, 0.14), hair_mat, false), ph0 + 1.0, 0.06)
	# 毛 2（中高，2 段反向弯）
	_reg_hair(_add_box(base + Vector3(0.25, 0.8 * s, -0.15), Vector3(0.16, 1.2 * s, 0.16), hair_mat, false), ph0 + 2.1, 0.03)
	_reg_hair(_add_box(base + Vector3(0.45, 1.7 * s, -0.3), Vector3(0.14, 1.0 * s, 0.14), hair_mat, false), ph0 + 2.6, 0.05)
	# 毛 3（短，直立）
	_reg_hair(_add_box(base + Vector3(-0.3, 0.7 * s, 0.2), Vector3(0.14, 1.0 * s, 0.14), hair_mat, false), ph0 + 4.2, 0.04)
	# 单碰撞体（覆盖整个毛簇）
	_add_collision_box(base + Vector3(0, 1.5 * s, 0),
		Vector3(1.1 * s, 3.0 * s, 1.1 * s), Color(0.5, 0.35, 0.18))

## 注册毛发段到风摆动画列表
func _reg_hair(mi: MeshInstance3D, phase: float, amp: float) -> void:
	_hair_segs.append(mi)
	_hair_bases.append(mi.position)
	_hair_meta.append({"phase": phase, "amp": amp})

## 皮肤：毛囊丘林+皮褶走廊
func _build_skin_layers() -> void:
	var flesh_mat := _organ_mat(tex_flesh, Color(1.1, 0.85, 0.72), Vector2(3, 2), 0.05)
	var hair_mat := _pix_mat(tex_hair)
	# 毛囊丘网格（可辨认的皮肤结构）
	for gx in range(-2, 3):
		for gz in range(-2, 3):
			if abs(gx) <= 0 and abs(gz) <= 0:
				continue
			if abs(gx) + abs(gz) == 4:
				continue
			if (gx * 3 + gz * 5) % 2 == 0:
				continue
			var pos := Vector3(gx * 5.5, 0, gz * 5.5)
			_add_follicle(pos, flesh_mat, hair_mat)
	# 皮褶低墙（表皮褶皱走廊）
	for sx: float in [-1, 1]:
		for sz: float in [-1, 1]:
			_add_box(Vector3(sx * 9, 0.5, sz * 9 - sz * 2), Vector3(7, 1.0, 1.2), flesh_mat, true)
	# 中央大毛囊丘（平台）
	_add_follicle(Vector3(0, 0, 0), flesh_mat, hair_mat, 2.0)
	# 入口毛丘
	for d: Vector3 in [Vector3(0, 0, -13), Vector3(0, 0, 13), Vector3(-13, 0, 0), Vector3(13, 0, 0)]:
		_add_follicle(d, flesh_mat, hair_mat, 0.8)

## 具象毛囊丘：肤色圆丘+中央长毛+毛孔
func _add_follicle(base: Vector3, flesh_mat: Material, hair_mat: Material, s := 1.0) -> void:
	# 丘体（两层肤色圆叠）
	_add_box(base + Vector3(0, 0.25 * s, 0), Vector3(2.4 * s, 0.5 * s, 2.4 * s), flesh_mat, false)
	_add_box(base + Vector3(0, 0.7 * s, 0), Vector3(1.8 * s, 0.4 * s, 1.8 * s), flesh_mat, false)
	# 毛孔（丘顶深色小凹）
	_add_box(base + Vector3(0, 0.91 * s, 0), Vector3(0.5 * s, 0.05 * s, 0.5 * s),
		_organ_mat(tex_mucosa, Color(0.5, 0.3, 0.25), Vector2(1, 1), 0.0), false)
	# 毛发（中央细毛，微微倾斜，带风摆）
	_reg_hair(_add_box(base + Vector3(0.1, 1.7 * s, 0), Vector3(0.12, 1.6 * s, 0.12), hair_mat, false),
		base.x * 0.9 + base.z * 0.4, 0.05 * s)
	# 碰撞体（覆盖丘体）
	_add_collision_box(base + Vector3(0, 0.45 * s, 0),
		Vector3(2.4 * s, 0.9 * s, 2.4 * s), Color(0.9, 0.7, 0.55))

## 兖底默认布局（血管柱+粘膜垫）
## 气管：环状软骨弓阵走廊（白色弓形连环，穿越掩体）
func _build_trachea() -> void:
	var cart_mat := _pix_mat(tex_tooth)  # 软骨白
	var mucosa_mat := _organ_mat(tex_mucosa, Color(1.05, 0.72, 0.72), Vector2(3, 2), 0.05)
	# 六道软骨弓沿 X 轴排列（穿越走廊感）
	for x in [-15, -9, -3, 3, 9, 15]:
		_add_cartilage_arch(Vector3(x, 0, 0), cart_mat)
	# 两行侧壁粘膜垫（走廊边缘掩体）
	for z: float in [-7.5, 7.5]:
		for x in [-12, -6, 0, 6, 12]:
			_add_box(Vector3(x, 0.5, z), Vector3(2.0, 1.0, 1.2), mucosa_mat, true)
	# 中央分叉隆起（气管分叉处标志）
	_add_box(Vector3(0, 0.8, 0), Vector3(3.5, 1.6, 2.0), cart_mat, true)
	_add_box(Vector3(0, 1.6, 0), Vector3(2.0, 0.8, 1.2), mucosa_mat, true)

## 单道软骨弓：左右柱+顶梁（弓形门，可穿行）
func _add_cartilage_arch(base: Vector3, mat: Material) -> void:
	# 左柱
	_add_box(base + Vector3(0, 1.6, -2.6), Vector3(1.3, 3.2, 1.3), mat, false)
	# 右柱
	_add_box(base + Vector3(0, 1.6, 2.6), Vector3(1.3, 3.2, 1.3), mat, false)
	# 顶梁（连接左右）
	_add_box(base + Vector3(0, 3.5, 0), Vector3(1.3, 0.9, 6.0), mat, false)
	# 碰撞：两柱+顶梁各一
	_add_collision_box(base + Vector3(0, 1.6, -2.6), Vector3(1.3, 3.2, 1.3), Color(0.92, 0.88, 0.85))
	_add_collision_box(base + Vector3(0, 1.6, 2.6), Vector3(1.3, 3.2, 1.3), Color(0.92, 0.88, 0.85))
	_add_collision_box(base + Vector3(0, 3.5, 0), Vector3(1.3, 0.9, 6.0), Color(0.92, 0.88, 0.85))


## 眼睛：虹膜环台+睫毛细柱+角膜弧墙（中央高台环形图）
func _build_eye() -> void:
	var iris_mat := _pix_mat(tex_iris)
	var sclera_mat := _pix_mat(tex_sclera)
	# 中央虹膜高台 = 会动的眼球平台（AnimatableBody3D，角色站上去跟随移动）
	_add_moving_iris(iris_mat)
	# 睫毛细柱（外围一圈，纤细高柱可躲）
	for i in 10:
		var a2 := TAU * i / 10.0 + 0.3
		var r := 16.5
		_add_box(Vector3(cos(a2) * r, 1.8, sin(a2) * r),
			Vector3(0.5, 3.6, 0.5), sclera_mat, true)
	# 角膜弧墙（两段大弧，半掩体）
	for arc: float in [0.4, PI + 0.4]:
		for i in 4:
			var a3 := arc + i * 0.25
			var r3 := 11.0
			_add_box(Vector3(cos(a3) * r3, 0.9, sin(a3) * r3),
				Vector3(2.2, 1.8, 1.2), sclera_mat, true)


## 会动的虹膜平台：AnimatableBody3D（官方移动平台方案，物理碰撞自动跟随）
func _add_moving_iris(iris_mat: Material) -> void:
	var ab := AnimatableBody3D.new()
	ab.name = "MovingIris"
	ab.position = Vector3(0, 0, 0)
	# 视觉：三层平台 + 辐条（全部挂在 AnimatableBody 下，随体移动）
	var m1 := _make_box_mesh(Vector3(9, 1.0, 9), iris_mat, Vector3(0, 0.5, 0))
	ab.add_child(m1)
	var m2 := _make_box_mesh(Vector3(4, 1.4, 4), iris_mat, Vector3(0, 1.2, 0))
	ab.add_child(m2)
	var pupil_mat := _organ_mat(tex_mucosa, Color(0.15, 0.12, 0.2), Vector2(1, 1), 0.0)
	var m3 := _make_box_mesh(Vector3(2, 0.6, 2), pupil_mat, Vector3(0, 2.2, 0))
	ab.add_child(m3)
	for i in 8:
		var a := TAU * i / 8.0
		var spoke := _make_box_mesh(Vector3(0.5, 0.2, 3.5), iris_mat,
			Vector3(cos(a) * 5.5, 1.1, sin(a) * 5.5))
		spoke.rotation.y = -a + PI / 2.0
		ab.add_child(spoke)
	# 碰撞：一大块箱体覆盖平台主体（站上去/被推都符合物理）
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(9, 2.6, 9)
	col.shape = shape
	col.position = Vector3(0, 1.3, 0)
	ab.add_child(col)
	add_child(ab)
	# 注册到移动平台列表（_physics_process 驱动，时间函数=全端确定性同步）
	_moving_platforms.append({
		"body": ab,
		"rx": 4.5,     # X 振幅
		"rz": 3.0,     # Z 振幅
		"speed": 0.25, # 角速度 rad/s（周期~25s，慢速公平）
	})
	print("[world] 虹膜移动平台就位（利萨茹轨迹 rx=4.5 rz=3.0）")


## 生成方块 Mesh（带材质/位置，无碰撞——挂到移动平台用的子件）
func _make_box_mesh(sz: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	return mi


## 耳朵：耳蜗螺旋爬升（同心环渐高+缺口通道+中央高峰）
func _build_ear() -> void:
	var cochlea_mat := _pix_mat(tex_cochlea)
	# 三层同心环（高度递增，每环留缺口→螺旋通道感）
	for ring in 3:
		var r := 5.0 + ring * 4.5
		var h := 1.0 + ring * 0.8
		var gap_at := TAU * ring / 3.0  # 每环缺口角度错开→螺旋感
		var segs := 10
		for i in segs:
			var a := TAU * i / segs
			# 缺口（跳过缺口附近的段）
			var da := absf(fmod(a - gap_at + PI, TAU) - PI)
			if da < 0.6:
				continue
			_add_box(Vector3(cos(a) * r, h / 2.0, sin(a) * r),
				Vector3(2.0, h, 1.4), cochlea_mat, true)
	# 中央耳蜗尖峰（最高点）
	_add_box(Vector3(0, 1.0, 0), Vector3(4.5, 2.0, 4.5), cochlea_mat, true)
	_add_box(Vector3(0, 2.4, 0), Vector3(2.0, 0.8, 2.0), cochlea_mat, true)
	# 外围听小骨三柱（耳标志，可躲）
	for i in 3:
		var a4 := TAU * i / 3.0 + 0.8
		_add_box(Vector3(cos(a4) * 17, 1.4, sin(a4) * 17),
			Vector3(1.6, 2.8, 1.6), cochlea_mat, true)


## 肺：支气管分杈树（中央主干+两主枝+小枝端）
func _build_lung() -> void:
	var bronchi_mat := _pix_mat(tex_iris)
	var alveoli_mat := _pix_mat(tex_sclera)
	# 中央气管主干（粗柱）
	_add_box(Vector3(0, 2.5, 0), Vector3(3, 5, 3), bronchi_mat, true)
	# 两主支气管（斜向分杈）
	for sx: float in [-1, 1]:
		_add_box(Vector3(sx * 5, 1.8, 2), Vector3(2.2, 3.6, 2.2), bronchi_mat, true)
		_add_box(Vector3(sx * 8, 1.2, 5), Vector3(1.8, 2.4, 1.8), bronchi_mat, true)
		# 小枝端肺泡簇（白色圆丘）
		_add_box(Vector3(sx * 10.5, 0.7, 7.5), Vector3(2.5, 1.4, 2.5), alveoli_mat, true)
		_add_box(Vector3(sx * 6, 0.5, 11), Vector3(3, 1.0, 3), alveoli_mat, true)
	# 顶部肺叶丘
	for sx: float in [-1, 1]:
		_add_box(Vector3(sx * 7, 3.5, -6), Vector3(4, 2, 4), alveoli_mat, true)


## 胃：酸液池（中央危险区）+胃壁褶皱环
func _build_stomach() -> void:
	var wall_mat := _organ_mat(tex_mucosa, Color(1.05, 0.88, 0.55), Vector2(4, 2), 0.06)
	var acid_mat := StandardMaterial3D.new()
	acid_mat.albedo_color = Color(0.4, 0.85, 0.2, 0.85)
	acid_mat.emission_enabled = true
	acid_mat.emission = Color(0.3, 0.7, 0.15)
	acid_mat.emission_energy_multiplier = 2.2
	# 中央酸液池（视觉+危险区标记，不可入）
	var acid := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6; cm.bottom_radius = 6; cm.height = 0.3
	cm.material = acid_mat
	acid.mesh = cm
	acid.position = Vector3(0, 0.15, 0)
	add_child(acid)
	_add_collision_box(Vector3(0, 1.5, 0), Vector3(11, 3, 11), Color(0.4, 0.85, 0.2))
	# 胃壁褶皱环（围酸池的弧墙）
	for i in 6:
		var a := TAU * i / 6.0
		var r := 10.5
		_add_box(Vector3(cos(a) * r, 1.2, sin(a) * r),
			Vector3(3.5, 2.4, 1.4), wall_mat, true)
	# 外圈消化丘（低掩体）
	for i in 5:
		var a2 := TAU * i / 5.0 + 0.6
		var r2 := 15.5
		_add_box(Vector3(cos(a2) * r2, 0.6, sin(a2) * r2),
			Vector3(2.5, 1.2, 2.5), wall_mat, true)


## 肠道：绒毛柱林（高密度细柱+蜿蜒通道）
func _build_intestine() -> void:
	var villi_mat := _pix_mat(tex_cochlea)
	# 高密度细柱阵（蛇形通道感）
	for gx in range(-3, 4):
		for gz in range(-3, 4):
			# 留出中央十字通道
			if abs(gx) <= 1 and abs(gz) <= 1:
				continue
			# 隔行布置→迷宫感
			if (gx + gz * 2) % 3 == 0:
				continue
			var pos := Vector3(gx * 4.5, 1.8, gz * 4.5)
			_add_box(pos, Vector3(1.2, 3.6, 1.2), villi_mat, true)
	# 中央蠕动拱门（标志结构）
	_add_box(Vector3(0, 2.8, 0), Vector3(5, 0.8, 2), villi_mat, true)
	_add_box(Vector3(-2.4, 1.4, 0), Vector3(0.8, 2.8, 2), villi_mat, true)
	_add_box(Vector3(2.4, 1.4, 0), Vector3(0.8, 2.8, 2), villi_mat, true)


## 神经：电光脉冲路径（发光柱阵+中央神经节）
func _build_nerve() -> void:
	var nerve_mat := StandardMaterial3D.new()
	nerve_mat.albedo_color = Color(0.55, 0.65, 1.0)
	nerve_mat.emission_enabled = true
	nerve_mat.emission = Color(0.35, 0.45, 0.95)
	nerve_mat.emission_energy_multiplier = 2.8
	# 中央神经节（发光核心）
	var core := MeshInstance3D.new()
	var core_m := BoxMesh.new()
	core_m.size = Vector3(4, 3, 4)
	core_m.material = nerve_mat
	core.mesh = core_m
	core.position = Vector3(0, 1.5, 0)
	add_child(core)
	_add_collision_box(Vector3(0, 1.5, 0), Vector3(4, 3, 4), Color(0.55, 0.65, 1.0))
	# 神经纤维放射（八向电光柱）
	for i in 8:
		var a := TAU * i / 8.0
		for d in [5.0, 9.0, 13.0]:
			var fiber := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.5, 2.2, 0.5)
			fm.material = nerve_mat
			fiber.mesh = fm
			fiber.position = Vector3(cos(a) * d, 1.1, sin(a) * d)
			add_child(fiber)
			_add_collision_box(Vector3(cos(a) * d, 1.1, sin(a) * d),
				Vector3(0.5, 2.2, 0.5), Color(0.55, 0.65, 1.0))
	# 间隙突触丘（低掩体）
	for i in 8:
		var a2 := TAU * i / 8.0 + 0.39
		var r := 7.0
		_add_box(Vector3(cos(a2) * r, 0.5, sin(a2) * r),
			Vector3(1.8, 1.0, 1.8), _pix_mat(tex_sclera), true)


## 肾：肾小球滤网（分层平台+中央血管球+滤网弧墙）
func _build_kidney() -> void:
	var cortex_mat := _pix_mat(tex_sclera)   # 皮质浅黄白
	var medulla_mat := _pix_mat(tex_cochlea) # 髓质粉棕
	# 中央肾小球（缠绕血管球，两层）
	_add_box(Vector3(0, 1.2, 0), Vector3(4, 2.4, 4), medulla_mat, true)
	_add_box(Vector3(0, 2.8, 0), Vector3(2.5, 0.8, 2.5), cortex_mat, true)
	# 三层滤网弧墙（由内向外递降）
	for ring in 3:
		var r := 6.0 + ring * 4.0
		var h := 2.5 - ring * 0.6
		var segs := 8 - ring
		for i in segs:
			var a := TAU * i / segs + ring * 0.4
			_add_box(Vector3(cos(a) * r, h / 2.0, sin(a) * r),
				Vector3(2.0, h, 1.0), cortex_mat, true)
	# 肾盏凹坑（低掩体丘）
	for i in 6:
		var a2 := TAU * i / 6.0 + 0.5
		_add_box(Vector3(cos(a2) * 10, 0.4, sin(a2) * 10),
			Vector3(2.2, 0.8, 2.2), medulla_mat, true)


## 膀胱：碗型腔体（环形阶梯+中央三角区）
func _build_bladder() -> void:
	var wall_mat := _pix_mat(tex_sclera)   # 青白腔壁
	var mucosa_mat := _organ_mat(tex_mucosa, Color(0.85, 0.95, 0.95), Vector2(4, 2), 0.05)
	# 中央三角区平台（膀胱三角标志）
	_add_box(Vector3(0, 0.5, 0), Vector3(5, 1.0, 5), mucosa_mat, true)
	# 环形阶梯（三层渐高，碗壁感）
	for ring in 3:
		var r := 7.5 + ring * 4.5
		var h := 1.0 + ring * 0.9
		var segs := 10
		for i in segs:
			var a := TAU * i / segs + ring * 0.3
			_add_box(Vector3(cos(a) * r, h / 2.0, sin(a) * r),
				Vector3(2.5, h, 1.2), wall_mat, true)
	# 输尿管口柱（两侧标志）
	for sx: float in [-1, 1]:
		_add_box(Vector3(sx * 4.5, 1.0, -4.5),
			Vector3(1.2, 2.0, 1.2), mucosa_mat, true)


## 骨骼：骨板高低差+骨髓红芯（最大高低差图）
func _build_bone() -> void:
	var bone_mat := _pix_mat(tex_tooth)    # 骨白
	var marrow_mat := _organ_mat(tex_mucosa, Color(0.85, 0.25, 0.30), Vector2(3, 2), 0.05)
	# 中央骨髓柱（红芯+骨密质外壳）
	_add_box(Vector3(0, 2.0, 0), Vector3(3.5, 4.0, 3.5), bone_mat, true)
	_add_box(Vector3(0, 4.4, 0), Vector3(2, 0.8, 2), marrow_mat, true)
	# 四块高骨板（可跳上平台，高低差最大；交替朝向成交叉形）
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		var r := 8.0
		var pos4 := Vector3(cos(a) * r, 1.8, sin(a) * r)
		var sz4 := Vector3(4, 3.6, 2) if i % 2 == 0 else Vector3(2, 3.6, 4)
		_add_box(pos4, sz4, bone_mat, true)
	# 骨小梁细柱阵（交错支撑）
	for i in 8:
		var a2 := TAU * i / 8.0 + 0.39
		_add_box(Vector3(cos(a2) * 13, 0.8, sin(a2) * 13),
			Vector3(0.8, 1.6, 0.8), bone_mat, true)
	# 骨髓红池（外围红芯丘）
	for i in 4:
		var a3 := TAU * i / 4.0
		_add_box(Vector3(cos(a3) * 5, 0.4, sin(a3) * 5),
			Vector3(2, 0.8, 2), marrow_mat, true)


func _build_default_layout() -> void:
	for c: Vector3 in [Vector3(-8, 0, -8), Vector3(8, 0, -8),
			Vector3(-8, 0, 8), Vector3(8, 0, 8), Vector3(0, 0, 0)]:
		_add_vessel(Vector3(c.x, 0, c.z))
	for low: Vector3 in [Vector3(-14, 0, 0), Vector3(14, 0, 0),
			Vector3(0, 0, -14), Vector3(0, 0, 14)]:
		_add_box(Vector3(low.x, 0.5, low.z), Vector3(2, 1, 2),
			_organ_mat(tex_mucosa, Color(1, 1, 1), Vector2(4, 2), 0.06), true)


func _add_organ_plane(pos: Vector3, size2d: Vector2,
		mat: ShaderMaterial, yaw := 0.0) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size2d
	pm.subdivide_width = 52
	pm.subdivide_depth = 6
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	add_child(mi)


## 纯碰撞箱环（N 边形近似圆，贴穹顶内缘）
func _add_wall_ring(radius: float, segments: int, height: float, wall_c := Color(0.88, 0.42, 0.48)) -> void:
	var seg_len := 2.0 * radius * tan(PI / float(segments))
	for i in segments:
		var ang := TAU * i / float(segments) + PI / float(segments)
		var sb := StaticBody3D.new()
		sb.position = Vector3(cos(ang) * radius, height / 2.0, sin(ang) * radius)
		sb.rotation.y = -ang - PI / 2.0
		sb.set_meta("debris_color", wall_c)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(seg_len + 0.5, height, 0.5)
		col.shape = shape
		sb.add_child(col)
		add_child(sb)


## 纯碰撞箱（无视觉，配合视觉件用）
func _add_collision_box(pos: Vector3, size: Vector3, debris_c: Color) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	sb.set_meta("debris_color", debris_c)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	sb.add_child(col)
	add_child(sb)


func _add_box(pos: Vector3, size: Vector3, mat: Material, static_body: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	if static_body:
		var sb := StaticBody3D.new()
		sb.position = pos
		sb.set_meta("debris_color", mat.get_meta("avg", Color(0.5, 0.5, 0.5)))
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		sb.add_child(col)
		add_child(sb)
	return mi


func _build_spawn_points() -> void:
	# world.tscn 已有 SpawnPoints 节点（勿新建同名，会被自动改名 SpawnPoints2）
	for p: Vector3 in [Vector3(-18, 1, -18), Vector3(18, 1, -18),
			Vector3(-18, 1, 18), Vector3(18, 1, 18),
			Vector3(0, 1, -18), Vector3(0, 1, 18)]:
		var m := Marker3D.new()
		m.position = p
		$SpawnPoints.add_child(m)


# ---------------- HUD ----------------

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	# 覆盖率对比条（卡通波浪自绘控件，文字内嵌）
	cover_bar_bg = CoverBarWidget.new()
	cover_bar_bg.size = Vector2(200, 30)
	hud.add_child(cover_bar_bg)

	crosshair = CrosshairWidget.new()
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(crosshair)

	hp_bar = HpBarWidget.new()
	hp_bar.size = Vector2(92, 18)
	hud.add_child(hp_bar)


	ink_bar_bg = InkMeterWidget.new()
	ink_bar_bg.size = Vector2(64, 18)
	hud.add_child(ink_bar_bg)

	feed_label = Label.new()
	feed_label.add_theme_font_size_override("font_size", 11)
	feed_label.size = Vector2(280, 40)
	feed_label.modulate = Color(1, 0.85, 0.6, 1)
	hud.add_child(feed_label)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.7, 0, 0, 0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash_rect)

	end_label = Label.new()
	end_label.add_theme_font_size_override("font_size", 22)
	end_label.size = Vector2(280, 80)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.visible = false
	hud.add_child(end_label)

	# 触屏控制
	var touch_ok := DisplayServer.is_touchscreen_available()
	if touch_ok:
		touch = load("res://touch_controls.gd").new()
		if not touch.has_method("consume_look"):
			push_error("[world] touch_controls 挂载失败！")
		else:
			hud.add_child(touch)

	# 暂停按钮（右上角圆钮，⏸ 图标）
	var k := clampf(get_viewport().get_visible_rect().size.y / 360.0, 0.7, 2.0)
	pause_btn = PauseButton.new()
	pause_btn.size = Vector2(28 * k, 28 * k)
	pause_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_btn.pressed_cb = _toggle_pause
	hud.add_child(pause_btn)
	_layout_pause()
	get_viewport().size_changed.connect(_layout_pause)

	pause_overlay = PauseOverlay.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停中动画/输入不休
	pause_overlay.resume_cb = _toggle_pause
	pause_overlay.quit_cb = _quit_to_lobby
	pause_overlay.visible = false
	hud.add_child(pause_overlay)

	# 倒计时大字（居中弹跳）
	countdown_label = Label.new()
	countdown_label.add_theme_font_size_override("font_size", 56)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	countdown_label.visible = false
	countdown_label.pivot_offset = Vector2(60, 30)
	hud.add_child(countdown_label)

	# 布局：视口尺寸绝对坐标，折叠/展开自适应
	_layout_hud.call_deferred()
	get_viewport().size_changed.connect(_layout_hud)


func _layout_pause() -> void:
	var w := get_viewport().get_visible_rect().size
	pause_btn.position = Vector2(w.x - 50, 44)


func _toggle_pause() -> void:
	is_paused = not is_paused
	pause_btn.is_paused = is_paused
	if is_paused:
		pause_overlay.show_pause()
	else:
		pause_overlay.visible = false
	get_tree().paused = is_paused and solo_mode()
	print("[world] 暂停=", is_paused)


func _quit_to_lobby() -> void:
	is_paused = false
	get_tree().paused = false
	# 关闭网络连接（自建服/客户端都清干净，便于重新开局）
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
		multiplayer.set_multiplayer_peer(null)
	gamestate.end_game()
	gamestate.game_started = false
	print("[world] 退出到主界面")


func solo_mode() -> bool:
	return not (multiplayer.multiplayer_peer is ENetMultiplayerPeer) \
		or gamestate.players.size() == 0


func _safe_top() -> float:
	# 状态栏/挖孔安全区（换算到逻辑视口坐标）
	var win := get_window().size
	var vp := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var scale_y := vp.y / maxf(win.y, 1.0)
	return safe.position.y * scale_y


func _layout_hud() -> void:
	var w := get_viewport().get_visible_rect().size
	var top := _safe_top() + 2.0
	# 圆角安全边距：折叠屏内屏圆角半径大，贴边元素两端会被切
	const CORNER_M := 70.0
	const CORNER_M_S := 46.0
	hp_bar.position = Vector2(w.x / 2.0 - hp_bar.size.x / 2.0, 38 + top)
	cover_bar_bg.position = Vector2(CORNER_M, top)
	cover_bar_bg.size = Vector2(w.x - CORNER_M * 2.0, 30)
	ink_bar_bg.position = Vector2(w.x - 112, w.y - 30)
	feed_label.position = Vector2(34, w.y - 52)
	end_label.position = Vector2(w.x / 2.0 - 140, w.y / 2.0 - 40)
	_update_cover_hud()
	print("[hud] 布局完成 w=", w, " 安全区顶部=", top)



func set_hp(hp: int) -> void:
	hp_bar.value = clampi(hp, 0, 999)


func set_ink(v: int) -> void:
	(ink_bar_bg as InkMeterWidget).value = clampf(v / 100.0, 0.0, 1.0)


var my_team := 1
var winner_just_now := 0   # 最近一局胜方（1/2；0=未结算）


func set_my_team(t: int) -> void:
	my_team = t
	(ink_bar_bg as InkMeterWidget).team = t
	hp_bar.faction = t
	if touch:
		touch.team = t
		if touch.has_method("set_team"):
			touch.set_team(t)
	print("[hud] 我的阵营=", t)


func death_flash() -> void:
	flash_rect.color = Color(0.7, 0.0, 0.0, 0.45)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.6)


# ---------------- 病原体 AI（服务器权威，全员同步创建） ----------------

const ENEMY_BACTERIA := 4
const ENEMY_VIRUS := 2
const ENEMY_Mycoplasma := 1
const ENEMY_PARASITE := 1
const ENEMY_FUNGUS := 1


@rpc("any_peer", "call_local")
func spawn_enemies() -> void:
	var holder := Node3D.new()
	holder.name = "Enemies"
	add_child(holder)
	# 3v3：AI 补齐每阵营空位（真人算 1 位，每阵营最多 3）
	var host_team: int = gamestate.my_faction
	var enemy_team: int = 2 if host_team == 1 else 1
	var ally_ai := maxi(0, 3 - gamestate.faction_human_count(host_team))
	var foe_ai := maxi(0, 3 - gamestate.faction_human_count(enemy_team))
	var i := 0
	# 友方 AI（多样化角色）
	var ally_types := [2, 4]
	for k in ally_ai:
		_make_enemy(ally_types[k % ally_types.size()], i,
			_enemy_spawn_pos(i, host_team), host_team)
		i += 1
	# 敌方 AI（多样化角色）
	var foe_types := [1, 2, 4]
	for k in foe_ai:
		_make_enemy(foe_types[k % foe_types.size()], i,
			_enemy_spawn_pos(i, enemy_team), enemy_team)
		i += 1
	print("[world] AI 就位：友方×%d（阵营%d）+ 敌方×%d（阵营%d），共 %d" \
		% [ally_ai, host_team, foe_ai, enemy_team, i])


func _enemy_spawn_pos(etype_id: int, ai_tm: int) -> Vector3:
	return team_spawn(ai_tm) + Vector3(0, 0.5, 0)


func _make_enemy(etype: int, idx: int, pos: Vector3, ai_team := 2) -> void:
	var e: CharacterBody3D = preload("res://enemy.tscn").instantiate()
	e.name = ("E%d" % etype) + ("_%d" % idx)
	e.position = pos
	e.setup(etype)
	e.ai_team = ai_team
	$Enemies.add_child(e)


## 战役模式：按关卡配置生成敌人（玩家+2友方AI vs 指定敌人）
@rpc("authority", "call_local", "reliable")
func spawn_campaign_enemies(enemy_types: Array) -> void:
	var holder := Node3D.new()
	holder.name = "Enemies"
	add_child(holder)
	var host_team: int = gamestate.my_faction  # 战役=1
	var enemy_team: int = 2 if host_team == 1 else 1
	# 友方 AI×2（同阵营，多样性角色）
	var ally_types := [2, 4]
	for k in 2:
		_make_enemy(ally_types[k], k,
			_enemy_spawn_pos(k, host_team), host_team)
	# 敌方 AI 按关卡配置
	for k in enemy_types.size():
		_make_enemy(int(enemy_types[k]), 10 + k,
			_enemy_spawn_pos(10 + k, enemy_team), enemy_team)
	print("[world] 战役AI就位：友方×2 + 敌方×%d（关卡%d）" \
		% [enemy_types.size(), gamestate.campaign_level])


## 找某阵营一个可替换的 AI（服务器端调用）
func find_replaceable_ai(faction: int) -> Node:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.ai_team == faction and is_instance_valid(e):
			return e
	return null


## 全端移除指定 AI（真人替换用，按名字同步全端）
@rpc("authority", "call_local", "reliable")
func remove_ai_replacement(ai_name: String) -> void:
	var holder := get_node_or_null("Enemies")
	if holder:
		var ai := holder.get_node_or_null(ai_name)
		if ai and is_instance_valid(ai):
			ai.queue_free()
			print("[world] AI %s 已被真人替换" % ai_name)


# ---------------- 技能基建（M2） ----------------

## 追踪弹（淋巴细胞）：朝目标持续转向
@rpc("any_peer", "call_local")
func fire_homing(from: Vector3, team: int, target_path: NodePath,
		shooter: int, delay: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22   # 加大可见度
	mesh.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 1.0)
	mat.emission_energy_multiplier = 3.0  # 更亮
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	mi.mesh = mesh
	mi.position = from
	add_child(mi)
	var tgt := get_node_or_null(target_path)
	var vel := Vector3.UP * 6.0
	if tgt:
		vel = (Vector3(tgt.global_position.x, 0.1, tgt.global_position.z)
			- from).normalized() * 18.0
	projectiles.append({"mi": mi, "pos": from, "vel": vel, "team": team,
		"shooter": shooter, "life": 4.0, "homing": target_path,
		"homing_delay": delay})
	_play("shot")


## NET 网区（粒细胞）：减速+持续伤害
var net_zones: Array = []


@rpc("any_peer", "call_local")
func add_net_zone(pos: Vector3, team: int) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.5
	cm.bottom_radius = 3.5
	cm.height = 0.3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.45, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.material = mat
	mi.mesh = cm
	mi.position = pos + Vector3(0, 0.15, 0)
	add_child(mi)
	net_zones.append({"mi": mi, "pos": pos, "expire": 5.0, "team": team,
		"tick": 0.0})
	_spawn_debris(pos + Vector3(0, 0.3, 0), Vector3.UP,
		Color(0.75, 0.45, 1.0), 8)


## 抗原标记（树突细胞）：减速 + 可视化标记（金色▼ + 减速光环）
var marks: Dictionary = {}
var _mark_visuals: Dictionary = {}  # path -> Label3D


@rpc("any_peer", "call_local")
func mark_enemy(path: NodePath, duration: float) -> void:
	marks[str(path)] = duration
	# 可视化：头顶金色▼标记
	var en := get_node_or_null(path)
	if en and is_instance_valid(en):
		var key := str(path)
		if not _mark_visuals.has(key):
			var marker := Label3D.new()
			marker.text = "▼▼"
			marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			marker.no_depth_test = true
			marker.font_size = 64
			marker.pixel_size = 0.004
			marker.modulate = Color(1.0, 0.65, 0.1)  # 亮金
			marker.outline_size = 12
			marker.position = Vector3(0, 1.6, 0)
			en.add_child(marker)
			_mark_visuals[key] = marker


func is_marked(path: NodePath) -> bool:
	return marks.get(str(path), 0.0) > 0.0


## 脱颗粒爆发（肥大细胞）：大面积涂色 + 击退（纯控制无伤害）
@rpc("any_peer", "call_local")
func burst(pos: Vector3, team: int, shooter: int) -> void:
	paint.rpc(pos, 5.5, team)
	_spawn_debris(pos + Vector3(0, 0.5, 0), Vector3.UP,
		tilemap.team_colors[team], 16)
	_play("shot")
	if multiplayer.is_server():
		if has_node("Enemies"):
			for en in $Enemies.get_children():
				if en.visible and en.global_position.distance_to(pos) < 5.5:
					var away: Vector3 = en.global_position - pos
					away.y = 0
					if away.length() > 0.1:
						en.velocity = away.normalized() * 9.0 + Vector3.UP * 3.0
		for pl in $Players.get_children():
			if pl is CharacterBody3D and pl.team() != team \
					and pl.global_position.distance_to(pos) < 5.5:
				var away2: Vector3 = pl.global_position - pos
				away2.y = 0
				if away2.length() > 0.1:
					pl.knockback.rpc(away2.normalized() * 8.0 + Vector3.UP * 2.5)


## NET 减速区查询：某位置的敌方是否在减速区内（玩家/AI 共用）
func in_net_zone(pos: Vector3, my_team: int) -> bool:
	for z in net_zones:
		if z["team"] != my_team \
				and pos.distance_to(z["pos"]) < 3.8:
			return true
	return false
## 复活保护
var protections: Dictionary = {}
var world_clock := 0.0


@rpc("any_peer", "call_local")
func set_protection(peer_id: int, duration: float) -> void:
	protections[peer_id] = duration


func is_protected(peer_id: int) -> bool:
	return protections.get(peer_id, 0.0) > 0.0


## 生命池：每队 6 命共享
var team_lives := {1: 6, 2: 6}
var lives_widget: Control


@rpc("any_peer", "call_local")
func consume_life(team: int) -> void:
	team_lives[team] = maxi(team_lives.get(team, 0) - 1, 0)
	if lives_widget:
		lives_widget.lives = team_lives.get(my_team, 0)
	if team_lives[team] <= 0:
		_push_feed("免疫阵营全部阵亡" if team == 1 else "病原体阵营全部阵亡")
		end_match.rpc(2 if team == 1 else 1,
			tilemap.coverage(1), tilemap.coverage(2))
	print("[world] 队伍%d 剩余生命 %d" % [team, team_lives[team]])


func set_skill_ready(ready: bool) -> void:
	if touch and touch.has_method("set_skill_ready"):
		touch.set_skill_ready(ready)


# ---------------- 墨汁弹道与涂色 ----------------

@rpc("any_peer", "call_local")
func fire_ink(from: Vector3, vel: Vector3, team: int,
		paint_rad: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var rad := 0.14
	if paint_rad > 2.0:
		rad = 0.26  # 狙击炮级大弹
	mesh.radius = rad
	mesh.height = rad * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tilemap.team_colors[team]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	mi.mesh = mesh
	mi.position = from
	add_child(mi)
	projectiles.append({"mi": mi, "pos": from, "vel": vel,
		"team": team, "shooter": multiplayer.get_remote_sender_id(), "life": 4.0})
	_play("shot_far" if not _is_local_shooter() else "shot")


func _is_local_shooter() -> bool:
	return false  # 简化：由 show 端距离判定（沿用 v1 思路）


@rpc("any_peer", "call_local")
func paint(pos: Vector3, radius: float, team: int) -> void:
	tilemap.paint_circle(pos, radius, team)
	_spawn_debris(pos + Vector3(0, 0.1, 0), Vector3.UP,
		tilemap.team_colors[team], 5)


## 移动平台驱动（_physics_process 保证物理同步，AnimatableBody 自动携带站立角色）
## 位置=纯时间函数 → 全端确定性一致（无需 RPC 同步）
func _physics_process(_delta: float) -> void:
	if _moving_platforms.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	for p in _moving_platforms:
		var body: AnimatableBody3D = p["body"]
		if is_instance_valid(body):
			# 利萨茹轨迹（X/Z 异频 → 像眼球扫视的 8 字游走）
			body.position.x = sin(t * p["speed"]) * p["rx"]
			body.position.z = sin(t * p["speed"] * 0.7 + PI / 3.0) * p["rz"]


func _process(delta: float) -> void:
	_wind_t += delta
	# 毛发风摆（每根相位/幅度不同，越高摆越大）
	if _hair_segs.size() > 0:
		var wt := _wind_t
		for i in _hair_segs.size():
			var seg: MeshInstance3D = _hair_segs[i]
			if is_instance_valid(seg):
				var b: Vector3 = _hair_bases[i]
				var m: Dictionary = _hair_meta[i]
				var ph: float = m["phase"]
				var amp: float = m["amp"]
				seg.position.x = b.x + sin(wt * 1.3 + ph) * amp
				seg.position.z = b.z + sin(wt * 1.0 + ph * 1.4) * amp * 0.6
				seg.rotation.z = sin(wt * 1.3 + ph) * amp * 0.35
	# 教育视频字幕同步（按播放时间切句）
	if _edu_layer and is_instance_valid(_edu_layer):
		var vsp2 := _edu_layer.get_node_or_null("EduVideo") as VideoStreamPlayer
		if vsp2 and vsp2.is_playing():
			var subs2: Array = _edu_layer.get_meta("subs", [])
			var cur_i: int = _edu_layer.get_meta("sub_i", -1)
			var t2 := vsp2.stream_position
			var want_i := -1
			for i2 in subs2.size():
				if t2 >= float(subs2[i2]["t"]):
					want_i = i2
				else:
					break
			if want_i != cur_i and want_i >= 0:
				_edu_layer.set_meta("sub_i", want_i)
				var sp := _edu_layer.get_node("SubPinyin") as Label
				var sc := _edu_layer.get_node("SubCN") as Label
				sp.text = str(subs2[want_i]["py"])
				sc.text = str(subs2[want_i]["cn"])
	# 碎片
	_update_debris(delta)
	# 墨汁弹
	var i := projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = projectiles[i]
		var mi: MeshInstance3D = p["mi"]
		var vel: Vector3 = p["vel"]
		# 追踪弹转向（淋巴细胞技能）：瞄准目标脚下地面，确保落地涂色
		if p.has("homing") and p["homing_delay"] <= 0.0:
			var tgt := get_node_or_null(p["homing"])
			if tgt and is_instance_valid(tgt) and tgt.visible:
				var want: Vector3 = Vector3(tgt.global_position.x, 0.1,
					tgt.global_position.z) - mi.position
				if want.length() > 0.5:
					want = want.normalized() * vel.length()
					vel = vel.lerp(want, 4.0 * delta)
		elif p.has("homing_delay"):
			p["homing_delay"] = p["homing_delay"] - delta
		vel.y -= 13.0 * delta
		var pos: Vector3 = p["pos"] + vel * delta
		p["pos"] = pos
		p["vel"] = vel
		p["life"] = p["life"] - delta
		mi.position = pos
		# 落地判定（瓦片面高度 0.12）
		var landed := pos.y <= 0.12 + 0.1
		# 追踪弹近距自爆：接近目标时直接落地涂色
		if not landed and p.has("homing") and p["homing_delay"] <= 0.0:
			var ht := get_node_or_null(p["homing"])
			if ht and is_instance_valid(ht) and ht.visible:
				if mi.position.distance_to(ht.global_position) < 2.0:
					landed = true
		var hit_world := false
		if not landed and pos.y < 3.0:
			# 简易掩体碰撞（打在箱体上方算落点）
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(
				mi.position, pos, 0xFFFFFFFF, [])
			var h := space.intersect_ray(q)
			if h:
				pos = h.position
				hit_world = true
		if landed or hit_world or p["life"] <= 0.0:
			var team: int = p["team"]
			# 自定义半径（角色差异化）：追踪弹 2.0 / 狙击炮用传入值 / 普通弹标准
			var pr: float = 2.0 if p.has("homing") else (p.get("paint_rad", PAINT_RADIUS))
			paint.rpc(pos, pr, team)
			# 纯涂地规则：墨汁弹不造成任何伤害，只占地
			mi.queue_free()
			projectiles.remove_at(i)
		i -= 1
	# 技能计时器：标记/保护衰减 + 网区结算 + 标记可视化清理
	world_clock += delta
	for k in marks.keys():
		marks[k] = marks[k] - delta
		if marks[k] <= 0.0:
			marks.erase(k)
			if _mark_visuals.has(k):
				var mv: Label3D = _mark_visuals[k]
				if is_instance_valid(mv):
					mv.queue_free()
				_mark_visuals.erase(k)
	for pid in protections.keys():
		protections[pid] = protections[pid] - delta
		if protections[pid] <= 0.0:
			protections.erase(pid)
	var zi := net_zones.size() - 1
	while zi >= 0:
		var z: Dictionary = net_zones[zi]
		z["expire"] = z["expire"] - delta
		z["tick"] = z["tick"] - delta
		var zmi: MeshInstance3D = z["mi"]
		zmi.rotation.y += delta * 0.8
		if z["expire"] < 1.0:
			zmi.scale = Vector3.ONE * maxf(z["expire"], 0.05)
		if z["expire"] <= 0.0:
			zmi.queue_free()
			net_zones.remove_at(zi)
		zi -= 1
	# 减速由实体自身逐帧查询 in_net_zone()（纯控制无伤害）
	# 覆盖率 HUD（4Hz）
	_hud_accum += delta
	if _hud_accum > 0.25:
		_hud_accum = 0.0
		_update_cover_hud()
	# 开局倒计时：AI 冻结、玩家锁枪、比赛计时不走
	if round_countdown > 0.0:
		round_countdown -= delta
		var sec := int(ceil(round_countdown))
		if sec != _last_cd_sec:
			_last_cd_sec = sec
			if sec > 0:
				countdown_label.text = str(sec)
				countdown_label.modulate = Color(1, 0.85, 0.3, 1)
			else:
				countdown_label.text = "GO!"
				countdown_label.modulate = Color(0.2, 1.0, 0.4, 1)
			countdown_label.visible = true
			countdown_label.scale = Vector2(2.0, 2.0)
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(countdown_label, "scale", Vector2.ONE, 0.7)
			tw.tween_property(countdown_label, "modulate:a", 0.4, 0.7)
		if round_countdown <= 0.0:
			countdown_label.visible = false
			print("[world] 倒计时结束，战斗开始！")
		# 倒计时期间不走比赛计时
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server() \
			and not match_over:
		match_time -= delta
		if match_time <= 0.0:
			_finish_match()
		# 平衡采集：每 30 秒记录覆盖率+存活数
		if int((match_time + delta) / 30.0) != int(match_time / 30.0) and not match_over:
			var b1: float = tilemap.coverage(1)
			var b2: float = tilemap.coverage(2)
			var alive1 := 0; var alive2 := 0
			for e in get_tree().get_nodes_in_group("enemies"):
				if e.visible:
					if e.ai_team == 1: alive1 += 1
					else: alive2 += 1
			print("[bal] T-%.0fs 青=%.1f%% 橙=%.1f%% AI存活=青%d橙%d" \
				% [match_time, b1 * 100, b2 * 100, alive1, alive2])
	_tick_accum += delta
	if _tick_accum > 1.0:
		_tick_accum = 0.0
		if multiplayer.is_server():
			set_timer.rpc(match_time)


@rpc("any_peer", "call_local")
func set_timer(t: float) -> void:
	if multiplayer.is_server():
		return  # 主机自己直接算
	match_time = t


func _finish_match() -> void:
	var c1: float = tilemap.coverage(1)
	var c2: float = tilemap.coverage(2)
	var winner: int
	if gamestate.campaign_mode:
		# 战役：己方覆盖率高于敌方即胜（与多人同规则，简洁明了）
		var pf: int = gamestate.my_faction
		var pc: float = c1 if pf == 1 else c2
		var oc: float = c2 if pf == 1 else c1
		winner = pf if pc > oc else (2 if pf == 1 else 1)
	else:
		winner = 1 if c1 >= c2 else 2
	end_match.rpc(winner, c1, c2)


var end_widget: EndWidget


@rpc("any_peer", "call_local")
func end_match(winner: int, c1: float, c2: float) -> void:
	match_over = true
	# 战斗结束→停 BGM（教育视频/结算画面不与 BGM 重叠）
	if _bgm_player and _bgm_player.playing:
		_bgm_player.stop()
	winner_just_now = winner
	_pending_end_data = {"winner": winner, "c1": c1, "c2": c2}
	# 战役胜利→解锁下一关+存档
	if gamestate.campaign_mode and winner == gamestate.my_faction:
		gamestate.campaign_win()
	# 战役模式：先播教育视频→播完再显示结算；多人直接结算
	if gamestate.campaign_mode:
		if _play_edu_video(winner):
			return  # 视频播完回调里再弹 EndWidget
	_show_end_widget()


var _pending_end_data: Dictionary = {}
var _edu_layer: Control = null


## 结算画面显示（从 end_match 或教育视频播完后调）
## 带自定义消息的结算显示（主机退出等特殊场景）
func _show_end_widget_with_msg(msg: String) -> void:
	match_over = true
	var vt := my_team
	var data := _pending_end_data
	var winner: int = data.get("winner", 0)
	var c1: float = data.get("c1", 0.0)
	var c2: float = data.get("c2", 0.0)
	if end_widget == null:
		end_widget = EndWidget.new()
		end_widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		end_widget.mouse_filter = Control.MOUSE_FILTER_STOP
		end_widget.winner = winner
		end_widget.viewer_team = vt
		end_widget.win_text = msg
		end_widget.sub_text = "青 %d%% vs 橙 %d%%" % [int(c1 * 100), int(c2 * 100)]
		end_widget.continue_cb = _on_end_continue
		end_widget.quit_cb = _on_end_quit
		hud.add_child(end_widget)
		end_widget.call_deferred("_setup_buttons")
	end_widget.visible = true
	print("[world] %s" % msg)

func _show_end_widget() -> void:
	var data := _pending_end_data
	var winner: int = data.get("winner", 1)
	var c1: float = data.get("c1", 0.0)
	var c2: float = data.get("c2", 0.0)
	var vt := my_team
	var win_text := ""
	if winner == 1:
		win_text = "我们消灭了病原体!" if vt == 1 else "被免疫系统清除了..."
	else:
		win_text = "病原体占领了人体!" if vt == 2 else "免疫力有待提高..."
	if end_widget == null:
		end_widget = EndWidget.new()
		end_widget.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		end_widget.mouse_filter = Control.MOUSE_FILTER_STOP
		end_widget.winner = winner
		end_widget.viewer_team = vt
		end_widget.win_text = win_text
		end_widget.sub_text = "青 %d%% vs 橙 %d%%" % [int(c1 * 100), int(c2 * 100)]
		end_widget.continue_cb = _on_end_continue
		end_widget.quit_cb = _on_end_quit
		hud.add_child(end_widget)
		end_widget.call_deferred("_setup_buttons")
	end_widget.visible = true
	print("[world] 比赛结束 胜方=%d 视角=%d 文案=%s" % [winner, vt, win_text])


## 教育视频：战役结束先播（全屏拉伸+字幕+跳过），播完再弹结算
## 返回 true=视频开始播放（结算延后）；false=视频不存在直接结算
func _play_edu_video(winner: int) -> bool:
	var side := "win" if winner == 1 else "lose"
	var path := "res://edu_L%d_%s.ogv" % [gamestate.campaign_level, side]
	var vp_stream := load(path)
	if vp_stream == null:
		print("[edu] 教育视频不存在(%s)，直接结算" % path)
		return false
	var subkey := "%d_%s" % [gamestate.campaign_level, side]
	var subs: Array = gamestate.EDU_SUBTITLES.get(subkey, [])
	_edu_layer = Control.new()
	_edu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edu_layer.add_child(bg)
	var vp_size := get_viewport().get_visible_rect().size
	var vsp := VideoStreamPlayer.new()
	vsp.stream = vp_stream
	vsp.autoplay = true
	vsp.expand = true
	vsp.name = "EduVideo"
	vsp.finished.connect(_on_edu_finished)
	_edu_layer.add_child(vsp)
	# cover-fill 全屏拉伸（与开场视频同款；入树后再设尺寸防覆盖）
	var v_ratio := 1280.0 / 720.0
	var s_ratio := vp_size.x / vp_size.y
	var w: float
	var h: float
	if s_ratio > v_ratio:
		w = vp_size.x
		h = w / v_ratio
	else:
		h = vp_size.y
		w = h * v_ratio
	vsp.size = Vector2(w, h)
	vsp.position = Vector2((vp_size.x - w) / 2.0, (vp_size.y - h) / 2.0)
	# 字幕（拼音+中文，底部居中）
	var sub_py := Label.new()
	sub_py.name = "SubPinyin"
	sub_py.add_theme_font_size_override("font_size", 13)
	sub_py.add_theme_color_override("font_color", Color(1.0, 0.75, 0.85))
	sub_py.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.1))
	sub_py.add_theme_constant_override("outline_size", 4)
	sub_py.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_py.size = Vector2(vp_size.x - 40, 18)
	sub_py.position = Vector2(20, vp_size.y - 66)
	_edu_layer.add_child(sub_py)
	var sub_cn := Label.new()
	sub_cn.name = "SubCN"
	sub_cn.add_theme_font_size_override("font_size", 21)
	sub_cn.add_theme_color_override("font_color", Color.WHITE)
	sub_cn.add_theme_color_override("font_outline_color", Color(0.08, 0.08, 0.1))
	sub_cn.add_theme_constant_override("outline_size", 5)
	sub_cn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_cn.size = Vector2(vp_size.x - 40, 28)
	sub_cn.position = Vector2(20, vp_size.y - 44)
	_edu_layer.add_child(sub_cn)
	_edu_layer.set_meta("subs", subs)
	_edu_layer.set_meta("sub_i", -1)
	# 跳过按钮（右下角同开场）
	var skip := Button.new()
	skip.text = "跳过 »"
	skip.add_theme_font_size_override("font_size", 13)
	skip.custom_minimum_size = Vector2(88, 36)
	skip.position = Vector2(vp_size.x - 116, vp_size.y - 52)
	skip.pressed.connect(_on_edu_finished)
	_edu_layer.add_child(skip)
	hud.add_child(_edu_layer)
	vsp.play()
	print("[edu] 教育视频播放 %s 字幕%d句" % [path, subs.size()])
	return true


## 教育视频结束/跳过 → 显示结算
func _on_edu_finished() -> void:
	if _edu_layer and is_instance_valid(_edu_layer):
		_edu_layer.queue_free()
		_edu_layer = null
	_show_end_widget()


func _on_end_continue() -> void:
	# 战役模式：胜→下一关（回大厅自动开）；败→重试同关
	if gamestate.campaign_mode:
		if winner_just_now == gamestate.my_faction \
				and gamestate.campaign_level < 13:
			gamestate.auto_next_campaign = gamestate.campaign_level + 1
			_quit_to_lobby()
		else:
			restart_match()
		return
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer \
			and multiplayer.is_server():
		# 检查是否有存活玩家（接管后可能全被释放）
		var world2 := get_tree().get_root().get_node_or_null(^"World")
		var has_players := false
		if world2 and world2.has_node("Players"):
			has_players = world2.get_node("Players").get_child_count() > 0
		if not has_players:
			# 接管重开：完整重建（加载世界+生成玩家+AI）
			gamestate.begin_game()
		else:
			restart_match.rpc()
	elif multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		restart_request.rpc_id(1)
	else:
		# 主机已退出：本机接管成为新主机 + AI 补位续战
		gamestate.takeover_host()
		gamestate.begin_game()


func _on_end_quit() -> void:
	_quit_to_lobby()


@rpc("any_peer")
func restart_request() -> void:
	if multiplayer.is_server():
		restart_match.rpc()


@rpc("any_peer", "call_local")
func restart_match() -> void:
	# 清空战斗态（各端确定性一致）
	match_time = gamestate.CAMPAIGN_LEVELS[gamestate.campaign_level]["time"] \
		if gamestate.campaign_mode else MATCH_TIME
	# 再战→恢复 BGM（新回合继续有战斗音乐）
	if _bgm_player and not _bgm_player.playing:
		_bgm_player.play()
	team_lives = {1: 6, 2: 6}
	scores.clear()
	feed_label.text = ""
	marks.clear()
	protections.clear()
	for z in net_zones:
		(z["mi"] as MeshInstance3D).queue_free()
	net_zones.clear()
	for p in projectiles:
		(p["mi"] as MeshInstance3D).queue_free()
	projectiles.clear()
	tilemap.reset_tiles()
	match_over = false
	round_countdown = 5.0
	_last_cd_sec = -1
	if multiplayer.is_server():
		var ang2 := randf() * TAU
		var c1b := Vector3(cos(ang2) * 16.0, 1.0, sin(ang2) * 16.0)
		setup_team_spawns.rpc(c1b, Vector3(-c1b.x, c1b.y, -c1b.z))  # 每局重新随机（服务器算+广播）
	if end_widget:
		end_widget.visible = false
	# 玩家重置（各自权威重置自身）
	for pl in $Players.get_children():
		if pl is CharacterBody3D:
			pl.reset_for_match.rpc()
	# AI 重置（确定性：按名字索引取出生点）
	if has_node("Enemies"):
		var pts := get_spawn_points()
		for en in $Enemies.get_children():
			var idx: int = str(en.name).right(1).to_int() if str(en.name).length() > 1 else 0
			if multiplayer.is_server():
				en.global_position = pts[idx % pts.size()] + Vector3(0, 0.5, 0)
			en.velocity = Vector3.ZERO
			en.reset_for_match()
	print("[world] 再战开始！")


func _update_cover_hud() -> void:
	var c1: float = tilemap.coverage(1)
	var c2: float = tilemap.coverage(2)
	var mm := int(match_time) / 60
	var ss := int(match_time) % 60
	(cover_bar_bg as CoverBarWidget).set_data(c1, c2, "%d:%02d" % [mm, ss])
	


# ---------------- 碎片（沿用 v1） ----------------

var _debris: Array = []
const DEBRIS_MAX := 200


func _spawn_debris(pos: Vector3, normal: Vector3, color: Color, count := 8) -> void:
	for i in count:
		if _debris.size() >= DEBRIS_MAX:
			var old: Dictionary = _debris.pop_front()
			(old["mi"] as MeshInstance3D).queue_free()
		var s := randf_range(0.05, 0.12)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(s, s, s)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(
			clampf(color.r * randf_range(0.85, 1.1), 0, 1),
			clampf(color.g * randf_range(0.85, 1.1), 0, 1),
			clampf(color.b * randf_range(0.85, 1.1), 0, 1))
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		mi.mesh = mesh
		mi.position = pos + normal * 0.06
		add_child(mi)
		var vel := normal * randf_range(1.0, 2.8) + Vector3(
			randf_range(-1.5, 1.5), randf_range(1.0, 3.0), randf_range(-1.5, 1.5))
		_debris.append({
			"mi": mi, "vel": vel, "life": randf_range(0.35, 0.7),
			"spin": Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)),
		})


func _update_debris(delta: float) -> void:
	var i := _debris.size() - 1
	while i >= 0:
		var d: Dictionary = _debris[i]
		var mi: MeshInstance3D = d["mi"]
		var vel: Vector3 = d["vel"]
		vel.y -= 13.0 * delta
		mi.position += vel * delta
		mi.rotation += (d["spin"] as Vector3) * delta
		if mi.position.y < 0.05:
			mi.position.y = 0.05
			vel.y = absf(vel.y) * 0.35
			vel.x *= 0.7
			vel.z *= 0.7
			d["spin"] = (d["spin"] as Vector3) * 0.5
		d["vel"] = vel
		d["life"] = d["life"] - delta
		if d["life"] < 0.15:
			mi.scale = Vector3.ONE * maxf(d["life"] / 0.15, 0.05)
		if d["life"] <= 0.0:
			mi.queue_free()
			_debris.remove_at(i)
		i -= 1


# ---------------- 音效（沿用 v1 合成） ----------------

var _bgm_player: AudioStreamPlayer


## 地图 BGM：按当前地图播放对应曲目（循环/低音量不压游戏音效）
func _start_bgm() -> void:
	var map_id: int = gamestate.selected_map
	var stream: AudioStream = load("res://bgm_%d.ogg" % map_id)
	if stream == null:
		print("[bgm] bgm_%d.ogg 不存在，跳过" % map_id)
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.volume_db = -9.0  # 音量约 35%（不压游戏音效）
		add_child(_bgm_player)
	_bgm_player.stream = stream
	_bgm_player.play()
	print("[bgm] 地图%d BGM 播放中" % map_id)


func _build_sfx() -> void:
	_gen_sfx("shot", _gen_shot(), -6.0)
	_gen_sfx("shot_far", _gen_shot(), -15.0)
	_gen_sfx("ding", _gen_ding(), -10.0)


func _gen_sfx(key: String, stream: AudioStreamWAV, vol_db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	sfx[key] = p


func _play(key: String) -> void:
	if sfx.has(key):
		(sfx[key] as AudioStreamPlayer).play()


func play_ding() -> void:
	_play("ding")


func _make_wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	wav.data = data
	return wav


func _gen_shot() -> AudioStreamWAV:
	var n := int(0.1 * 22050)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / 22050.0
		s[i] = (randf() * 2.0 - 1.0) * exp(-t * 55.0) * 0.5 \
			+ sin(t * TAU * 300.0) * exp(-t * 40.0) * 0.4  # 墨汁"啾"声
	return _make_wav(s)


func _gen_ding() -> AudioStreamWAV:
	var n := int(0.1 * 22050)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / 22050.0
		s[i] = sin(t * TAU * 1250.0) * exp(-t * 45.0) * 0.5
	return _make_wav(s)


# ---------------- 计分播报（沿用 v1） ----------------

@rpc("any_peer", "call_local")
func report_kill(killer_id: int, victim_id: int, victim_name := "") -> void:
	var killer := gamestate.get_player_name(killer_id)
	var victim := victim_name if victim_name != "" else gamestate.get_player_name(victim_id)
	if killer_id == 0:
		_push_feed(victim + " 被敌方墨汁溶解了")
	elif killer_id != victim_id:
		scores[killer_id] = scores.get(killer_id, 0) + 1
		_push_feed(killer + " 击破 " + victim)
	else:
		_push_feed(victim + " 自爆了")
	var entries: Array = []
	for id in scores:
		entries.append([gamestate.get_player_name(id), scores[id]])
	entries.sort_custom(func(a, b): return a[1] > b[1])
	var text := ""
	for e in entries:
		text += "%s: %d\n" % [e[0], e[1]]
	feed_label.text = text


func _push_feed(text: String) -> void:
	var lines := feed_label.text.split("\n")
	lines.append(text)
	while lines.size() > 4:
		lines.remove_at(0)
	feed_label.text = "\n".join(lines)


## 抗原呈递冲击波（金色扩散圈，标记技能范围）
@rpc("any_peer", "call_local")
func antigen_wave(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.5
	mi.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.2, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.75, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos + Vector3(0, 0.15, 0)
	mi.rotation.x = PI / 2.0
	add_child(mi)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(40, 40, 40), 0.6)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(mi.queue_free)
