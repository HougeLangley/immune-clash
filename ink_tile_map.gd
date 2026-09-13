extends Node3D
## 墨汁瓦片地图（v2 核心）：地面 = 1m 瓦片网格
## MultiMeshInstance3D 渲染 + PackedByteArray 归属数据 + 圆形染色 + 覆盖率统计
## 服务器/客户端同构：所有端本地执行同一染色函数（确定性），终局由主机裁定

const TILE := 0.5        # 瓦片边长（米）
const TILE_H := 0.6      # 瓦片厚度（加厚：波浪时侧面不露缝）

## 地砖脉动着色器 v2：顶面几何波浪（真起伏）+ 明暗呼吸
## 顶面顶点按世界坐标行进波上下位移；砖体加厚避免缝隙
const TILE_SHADER := "
shader_type spatial;
render_mode unshaded;
uniform float wave_amount = 0.07;
uniform float wave_speed = 1.2;
varying vec4 v_color;
varying vec3 v_world;
void vertex() {
	v_color = COLOR;
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_world = wp.xyz;
	float w = sin(wave_speed * TIME + v_world.x * 0.45 + v_world.z * 0.28);
	if (NORMAL.y > 0.5) {
		VERTEX.y += w * wave_amount;
	}
}
void fragment() {
	float w2 = sin(TIME * 1.5 + v_world.x * 0.5 + v_world.z * 0.3);
	ALBEDO = v_color.rgb * (1.0 - 0.05 * (0.5 + 0.5 * w2));
}
"
const TILE_TOP := 0.12   # 顶面标高（与碰撞地板对齐）

var width := 96          # X 方向瓦片数
var depth := 96          # Z 方向瓦片数

var owner_bytes := PackedByteArray()   # 每瓦片归属：0=中立 1/2=队伍
var team_colors := [Color(1, 1, 1), Color(0.05, 0.75, 0.85), Color(1.0, 0.55, 0.15)]
var _neutral_a := Color(0.95, 0.70, 0.73)   # 中立地砖：玫瑰粉（体内组织色）
var _neutral_b := Color(0.88, 0.60, 0.64)

var mm: MultiMesh
var mmi: MultiMeshInstance3D
var painted_count := {}   # team -> 已涂瓦片数（增量维护）


func _ready() -> void:
	_build()


func tile_count() -> int:
	return width * depth


func world_to_tile(wx: float, wz: float) -> Vector2i:
	return Vector2i(int(floor((wx + width * TILE / 2.0) / TILE)),
		int(floor((wz + depth * TILE / 2.0) / TILE)))


func tile_center(tx: int, tz: int) -> Vector3:
	return Vector3((tx + 0.5) * TILE - width * TILE / 2.0,
		TILE_TOP - TILE_H / 2.0,
		(tz + 0.5) * TILE - depth * TILE / 2.0)


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < width and t.y >= 0 and t.y < depth


## 圆形染色：返回本次实际改变归属的瓦片数
func paint_circle(center: Vector3, radius: float, team: int) -> int:
	var t0 := world_to_tile(center.x - radius, center.z - radius)
	var t1 := world_to_tile(center.x + radius, center.z + radius)
	var col: Color = team_colors[team]
	var changed := 0
	for tz in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			if not in_bounds(Vector2i(tx, tz)):
				continue
			var c := tile_center(tx, tz)
			var dx := c.x - center.x
			var dz := c.z - center.z
			if dx * dx + dz * dz > radius * radius:
				continue
			var i := tz * width + tx
			if owner_bytes[i] == team:
				continue
			# 维护计数
			var old := owner_bytes[i]
			if old > 0:
				painted_count[old] = painted_count.get(old, 1) - 1
			owner_bytes[i] = team
			painted_count[team] = painted_count.get(team, 0) + 1
			# 微噪声让色块有像素手绘感
			var jitter := randf_range(0.88, 1.0)
			mm.set_instance_color(i, Color(col.r * jitter, col.g * jitter, col.b * jitter))
			changed += 1
	return changed


## 重置全部瓦片为中性（各端确定性一致，再战用）
func reset_tiles() -> void:
	owner_bytes.fill(0)
	painted_count.clear()
	for tz in depth:
		for tx in width:
			var i := tz * width + tx
			var checker := (tx + tz) % 2 == 0
			mm.set_instance_color(i, _neutral_a if checker else _neutral_b)
	print("[ink] 瓦片已重置")


func coverage(team: int) -> float:
	return float(painted_count.get(team, 0)) / float(tile_count())


## 查询某位置的瓦片归属（0=中立 1/2=队伍；界外=0）——墨中机动速度加成用
func tile_owner_at(wx: float, wz: float) -> int:
	var t := world_to_tile(wx, wz)
	if not in_bounds(t):
		return 0
	return owner_bytes[t.y * width + t.x]


func _build() -> void:
	owner_bytes.resize(tile_count())
	owner_bytes.fill(0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(TILE, TILE_H, TILE)
	var sh := Shader.new()
	sh.code = TILE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("wave_amount", 0.08)
	mesh.material = mat

	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = tile_count()

	var xf := Transform3D(Basis(), Vector3())
	for tz in depth:
		for tx in width:
			var i := tz * width + tx
			xf.origin = tile_center(tx, tz)
			mm.set_instance_transform(i, xf)
			# 棋盘格中性色（像素地砖感）
			var checker := (tx + tz) % 2 == 0
			mm.set_instance_color(i, _neutral_a if checker else _neutral_b)

	mmi = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	print("[ink] 瓦片地图就绪 %d×%d=%d 块" % [width, depth, tile_count()])
