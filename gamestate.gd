extends Node
## 全局游戏状态：联机会话管理（参考官方 multiplayer_bomber 架构，3D 适配）

# 53317 已在主机防火墙 allowedUDPPorts（LocalSend 端口，临时复用；正式版应改回独立端口并放行）
const DEFAULT_PORT := 53317
const MAX_PEERS := 12
const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(-14, 1.0, -14), Vector3(14, 1.0, -14),
	Vector3(-14, 1.0, 14), Vector3(14, 1.0, 14),
	Vector3(0, 1.0, -14), Vector3(0, 1.0, 14),
]

var peer: ENetMultiplayerPeer
var player_name: String = "Player"
var players := {}
var game_started := false
var pending_players: Array[int] = []
var late_peers: Array[int] = []
var player_chars := {}   # peer_id -> 角色id（1-5）
var my_char := 1
var player_teams := {}   # peer_id -> 阵营（1=免疫 2=病原体）
var my_faction := 1
var selected_map := 1   # 1=口腔 2=鼻腔 3=皮肤
signal faction_full_rejected

## ==================== 战役模式 ====================
var campaign_mode := false   # true=战役 false=多人
var campaign_level := 1      # 当前打的关卡
var auto_next_campaign := 0  # >0=大厅自动开此关卡（下一关流转）

## ==================== LAN 主机广播（autoload 级=跨场景存活） ====================
const DISCOVERY_PORT := 53318
var _bcast_udp: PacketPeerUDP
var _bcast_timer: Timer

func start_broadcast(nickname: String) -> void:
	stop_broadcast()
	_bcast_udp = PacketPeerUDP.new()
	_bcast_udp.set_broadcast_enabled(true)
	# 双路广播：全屏广播 + 子网定向（路由器可能屏蔽 255.255.255.255）
	var bdata := JSON.stringify({"n": nickname, "p": 53317}).to_utf8_buffer()
	var addrs: Array[String] = ["255.255.255.255"]
	# 从本机 IP 推导子网广播地址（如 192.168.31.126/24 → 192.168.31.255）
	for local_ip in IP.get_local_addresses():
		var parts := local_ip.split(".")
		if parts.size() == 4 and parts[0] != "127":
			# 不再过滤 10.x（Android 热点也用 10.x 段，误过滤导致热点模式发现失败）
			var subnet_bcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not addrs.has(subnet_bcast):
				addrs.append(subnet_bcast)
	_bcast_timer = Timer.new()
	_bcast_timer.wait_time = 2.0
	_bcast_timer.autostart = true
	_bcast_timer.timeout.connect(func():
		if _bcast_udp:
			for addr in addrs:
				_bcast_udp.set_dest_address(addr, DISCOVERY_PORT)
				_bcast_udp.put_packet(bdata))
	add_child(_bcast_timer)
	print("[lan] 主机广播中: %s → %s" % [nickname, str(addrs)])

func stop_broadcast() -> void:
	if _bcast_timer and is_instance_valid(_bcast_timer):
		_bcast_timer.queue_free()
	_bcast_timer = null
	if _bcast_udp:
		_bcast_udp.close()
		_bcast_udp = null

## ==================== 教育视频字幕（拼音+中文，游戏内叠加） ====================
## 键："关卡_胜方"（win=免疫胜播保护版 / lose=病原胜播后果版）
const EDU_SUBTITLES := {
	"1_win": [
		{"t": 0.5, "py": "měi tiān zǎo wǎn yào shuā yá", "cn": "每天早晚要刷牙"},
		{"t": 3.5, "py": "xì jūn dōu gǎn pǎo la", "cn": "细菌都赶跑啦"},
		{"t": 6.5, "py": "yá chǐ bái bái xiào hā hā", "cn": "牙齿白白笑哈哈"},
	],
	"1_lose": [
		{"t": 0.5, "py": "bù shuā yá xì jūn lái", "cn": "不刷牙细菌来"},
		{"t": 3.5, "py": "yá chǐ hēi hēi yǒu xiǎo dòng", "cn": "牙齿黑黑有小洞"},
		{"t": 6.5, "py": "yá téng yào kàn yī shēng", "cn": "牙疼要看医生"},
	],
	"2_win": [
		{"t": 0.5, "py": "qín xǐ shǒu jiǎng wèi shēng", "cn": "勤洗手讲卫生"},
		{"t": 3.5, "py": "bù wā bí kǒng hǎo xí guàn", "cn": "不挖鼻孔好习惯"},
		{"t": 6.5, "py": "hū xī shùn chàng shēn tǐ bàng", "cn": "呼吸顺畅身体棒"},
	],
	"2_lose": [
		{"t": 0.5, "py": "bìng dú zuān jìn bí zi lǐ", "cn": "病毒钻进鼻子里"},
		{"t": 3.5, "py": "pēn tì liú tì zhēn nán shòu", "cn": "喷嚏流涕真难受"},
		{"t": 6.5, "py": "shēng bìng jiù yào kàn yī shēng", "cn": "生病就要看医生"},
	],
	"3_win": [
		{"t": 0.5, "py": "qín xǐ shǒu qín xǐ zǎo", "cn": "勤洗手勤洗澡"},
		{"t": 3.5, "py": "xiǎo shāng kǒu kuài chǔ lǐ", "cn": "小伤口快处理"},
		{"t": 6.5, "py": "pí fū jiàn kāng rén rén kuā", "cn": "皮肤健康人人夸"},
	],
	"3_lose": [
		{"t": 0.5, "py": "zāng shǒu mō liǎn zhēn jūn lái", "cn": "脏手摸脸真菌来"},
		{"t": 3.5, "py": "pí fū hóng hóng yǎng yǎng de", "cn": "皮肤红红痒痒的"},
		{"t": 6.5, "py": "zhuā pò le huì gèng yán zhòng", "cn": "抓破了会更严重"},
	],
	"4_win": [
		{"t": 0.5, "py": "duō hē shuǐ qín tōng fēng", "cn": "多喝水勤通风"},
		{"t": 3.5, "py": "chū mén jì de dài kǒu zhào", "cn": "出门记得戴口罩"},
		{"t": 6.5, "py": "qì guǎn qīng shuǎng hū xī chàng", "cn": "气管清爽呼吸畅"},
	],
	"4_lose": [
		{"t": 0.5, "py": "bìng jūn pǎo dào qì guǎn lǐ", "cn": "病菌跑到气管里"},
		{"t": 3.5, "py": "ké sou fā shāo zhēn nán shòu", "cn": "咳嗽发烧真难受"},
		{"t": 6.5, "py": "hǎo hǎo xiū xi kuài chī yào", "cn": "好好休息快吃药"},
	],
	"5_win": [
		{"t": 0.5, "py": "bù yòng zāng shǒu róu yǎn jīng", "cn": "不用脏手揉眼睛"},
		{"t": 3.5, "py": "kàn wán yuǎn chù kàn jìn chù", "cn": "看完远处看近处"},
		{"t": 6.5, "py": "míng liàng yǎn jīng kàn de qīng", "cn": "明亮眼睛看得清"},
	],
	"5_lose": [
		{"t": 0.5, "py": "zāng shǒu róu yǎn xì jūn lái", "cn": "脏手揉眼细菌来"},
		{"t": 3.5, "py": "yǎn jīng hóng hóng zhǒng zhǒng de", "cn": "眼睛红红肿肿的"},
		{"t": 6.5, "py": "kàn bù qīng yào zhǎo yī shēng", "cn": "看不清要找医生"},
	],
	"6_win": [
		{"t": 0.5, "py": "bù wǎng ěr duo sāi dōng xi", "cn": "不往耳朵塞东西"},
		{"t": 3.5, "py": "yóu yǒng jì de dài ěr sāi", "cn": "游泳记得戴耳塞"},
		{"t": 6.5, "py": "ěr duo líng líng tīng de qīng", "cn": "耳朵灵灵听得清"},
	],
	"6_lose": [
		{"t": 0.5, "py": "luàn sāi dōng xi ěr duo shāng", "cn": "乱塞东西耳朵伤"},
		{"t": 3.5, "py": "téng de lì hai tīng bù qīng", "cn": "疼得厉害听不清"},
		{"t": 6.5, "py": "kuài ràng yī shēng kàn yī kàn", "cn": "快让医生看一看"},
	],
	"7_win": [
		{"t": 0.5, "py": "qín yùn dòng shēn tǐ hǎo", "cn": "勤运动身体好"},
		{"t": 3.5, "py": "shēn hū xī duō hū xīn xiān kōng qì", "cn": "深呼吸多吸新鲜空气"},
		{"t": 6.5, "py": "fèi bù jiàn kāng jīng shén zú", "cn": "肺部健康精神足"},
	],
	"7_lose": [
		{"t": 0.5, "py": "xi yān wū rǎn shāng fèi bù", "cn": "吸烟污染伤肺部"},
		{"t": 3.5, "py": "ké sou qì chuǎn zhēn nán shòu", "cn": "咳嗽气喘真难受"},
		{"t": 6.5, "py": "bǎo hù fèi bù cóng jīn tiān", "cn": "保护肺部从今天"},
	],
	"8_win": [
		{"t": 0.5, "py": "àn shí chī fàn bù tān shí", "cn": "按时吃饭不贪食"},
		{"t": 3.5, "py": "shǎo chī líng shí duō xiāo huà", "cn": "少吃零食多消化"},
		{"t": 6.5, "py": "wèi er shū fu xiāng pēn pēn", "cn": "胃儿舒服香喷喷"},
	],
	"8_lose": [
		{"t": 0.5, "py": "bào yǐn bào shí wèi nán shòu", "cn": "暴饮暴食胃难受"},
		{"t": 3.5, "py": "dù zi zhàng zhàng zhí dǎ gé", "cn": "肚子胀胀直打嗝"},
		{"t": 6.5, "py": "guī lǜ yǐn shí jì xīn jiān", "cn": "规律饮食记心间"},
	],
	"9_win": [
		{"t": 0.5, "py": "duō chī shū cài hé shuǐ guǒ", "cn": "多吃蔬菜和水果"},
		{"t": 3.5, "py": "cháng dào tōng chàng xiāo huà hǎo", "cn": "肠道通畅消化好"},
		{"t": 6.5, "py": "měi tiān biàn biàn hěn qīng sōng", "cn": "每天便便很轻松"},
	],
	"9_lose": [
		{"t": 0.5, "py": "tiāo shí bù chī qīng cài", "cn": "挑食不吃青菜"},
		{"t": 3.5, "py": "dù zi zhàng qì nán shòu jí le", "cn": "肚子胀气难受极了"},
		{"t": 6.5, "py": "jūn héng yǐn shí cái jiàn kāng", "cn": "均衡饮食才健康"},
	],
	"10_win": [
		{"t": 0.5, "py": "zǎo shuì zǎo qǐ jīng shén hǎo", "cn": "早睡早起精神好"},
		{"t": 3.5, "py": "dà nǎo chōng zú de xiū xī", "cn": "大脑充足的休息"},
		{"t": 6.5, "py": "fǎn yìng líng huó xué xí kuài", "cn": "反应灵活学习快"},
	],
	"10_lose": [
		{"t": 0.5, "py": "áo yè kàn shǒu jī shāng shén jīng", "cn": "熬夜看手机伤神经"},
		{"t": 3.5, "py": "tóu yūn yǎn huā méi jīng shén", "cn": "头晕眼花没精神"},
		{"t": 6.5, "py": "chōng zú shuì mián zuì zhòng yào", "cn": "充足睡眠最重要"},
	],
	"11_win": [
		{"t": 0.5, "py": "duō hē shuǐ qín pái niào", "cn": "多喝水勤排尿"},
		{"t": 3.5, "py": "shèn zàng guò lǜ zhēn qín láo", "cn": "肾脏过滤真勤劳"},
		{"t": 6.5, "py": "shēn tǐ gān jìng jīng shén hǎo", "cn": "身体干净精神好"},
	],
	"11_lose": [
		{"t": 0.5, "py": "biē niào shāng shèn zàng", "cn": "憋尿伤肾脏"},
		{"t": 3.5, "py": "dú sù pái bù chū qù", "cn": "毒素排不出去"},
		{"t": 6.5, "py": "duō hē shuǐ bǎo jiàn kāng", "cn": "多喝水保健康"},
	],
	"12_win": [
		{"t": 0.5, "py": "jí shí shàng cè suǒ bù biē niào", "cn": "及时上厕所不憋尿"},
		{"t": 3.5, "py": "páng guāng jiàn kāng tán xìng hǎo", "cn": "膀胱健康弹性好"},
		{"t": 6.5, "py": "qīng sōng yú kuài měi yī tiān", "cn": "轻松愉快每一天"},
	],
	"12_lose": [
		{"t": 0.5, "py": "zǒng shì biē niào páng guāng lèi", "cn": "总是憋尿膀胱累"},
		{"t": 3.5, "py": "pín fán zháo jí shàng cè suǒ", "cn": "频繁着急上厕所"},
		{"t": 6.5, "py": "yǎng chéng hǎo xí guàn hěn zhòng yào", "cn": "养成好习惯很重要"},
	],
	"13_win": [
		{"t": 0.5, "py": "duō hē niú nǎi duō yùn dòng", "cn": "多喝牛奶多运动"},
		{"t": 3.5, "py": "gǔ gé qiáng zhuàng gè zi gāo", "cn": "骨骼强壮个子高"},
		{"t": 6.5, "py": "bèng bèng tiào tiào shēn tǐ bàng", "cn": "蹦蹦跳跳身体棒"},
	],
	"13_lose": [
		{"t": 0.5, "py": "bù yùn dòng quē gài zhì", "cn": "不运动缺钙质"},
		{"t": 3.5, "py": "gǔ tou biàn cuì róng yì shāng", "cn": "骨头变脆容易伤"},
		{"t": 6.5, "py": "bǔ gài yùn dòng yào jì láo", "cn": "补钙运动要记牢"},
	],
}
const CAMPAIGN_LEVELS := {
	1: {
		"name_i": "口腔保卫战", "name_g": "口腔远征", "map_id": 1,
		"desc_i": "细菌大军入侵口腔!守住第一道防线",
		"desc_g": "突破口腔免疫防线!占领入口",
		"time": 180.0,
		"enemies": [5, 1, 5],  # L1: 真菌+细菌+真菌（慢速=教学友好）
	},
	2: {
		"name_i": "鼻腔迷雾", "name_g": "鼻腔潜伏", "map_id": 2,
		"desc_i": "病毒藏在鼻毛迷宫里!抢占更多地盘",
		"desc_g": "潜入鼻毛要塞!悄悄扩张地盘",
		"time": 180.0,
		"enemies": [2, 2, 3],
	},
	3: {
		"name_i": "皮肤防线", "name_g": "皮肤殖民", "map_id": 3,
		"desc_i": "真菌想在皮肤安家!把它赶出去",
		"desc_g": "在皮肤建立菌落!顶住免疫反扑",
		"time": 180.0,
		"enemies": [5, 1, 5],
	},
	4: {
		"name_i": "气管危机", "name_g": "气管要塞", "map_id": 4,
		"desc_i": "支原体渗透气管!守住最终防线",
		"desc_g": "攻占气管咽喉!拿下最终据点",
		"time": 180.0,
		"enemies": [3, 3, 4],
	},
	5: {
		"name_i": "眼球风暴", "name_g": "眼球突袭", "map_id": 5,
		"desc_i": "病毒直捣眼球!抢占虹膜高台",
		"desc_g": "攻入视觉中枢!占领高地",
		"time": 180.0,
		"enemies": [2, 2, 5],
	},
	6: {
		"name_i": "耳蜗回响", "name_g": "耳蜗渗透", "map_id": 6,
		"desc_i": "真菌钻进耳朵!螺旋阵地反击",
		"desc_g": "潜入听觉要塞!螺旋推进",
		"time": 180.0,
		"enemies": [5, 4, 5],
	},
	7: {
		"name_i": "肺叶风暴", "name_g": "肺叶侵略", "map_id": 7,
		"desc_i": "病菌攻入肺叶!守住呼吸要道",
		"desc_g": "深入呼吸中枢!占领枝杈",
		"time": 180.0,
		"enemies": [2, 5, 2],  # L7: 病毒+真菌+病毒（降速）
	},
	8: {
		"name_i": "胃酸危机", "name_g": "胃酸炼狱", "map_id": 8,
		"desc_i": "细菌搅动胃酸!稳住消化防线",
		"desc_g": "搅乱消化中枢!酸池为障",
		"time": 180.0,
		"enemies": [1, 1, 3],
	},
	9: {
		"name_i": "肠道迷阵", "name_g": "肠道潜伏", "map_id": 9,
		"desc_i": "寄生虫占领肠道!绒毛阵反击",
		"desc_g": "藏身绒毛迷宫!暗度陈仓",
		"time": 180.0,
		"enemies": [4, 4, 1],
	},
	10: {
		"name_i": "神经闪电", "name_g": "神经风暴", "map_id": 10,
		"desc_i": "病毒入侵神经!守护信号通路",
		"desc_g": "切断信号中枢!电光占领",
		"time": 180.0,
		"enemies": [2, 3, 2],
	},
	11: {
		"name_i": "肾脏滤网", "name_g": "肾脏渗透", "map_id": 11,
		"desc_i": "毒素入侵肾脏!守住过滤防线",
		"desc_g": "攻破过滤中枢!毒害全身",
		"time": 180.0,
		"enemies": [5, 3, 5],  # L11: 真菌+支原体+真菌（降细菌）
	},
	12: {
		"name_i": "膀胱守卫", "name_g": "膀胱扩张", "map_id": 12,
		"desc_i": "细菌攻入膀胱!守住储水要塞",
		"desc_g": "占据储水腔!全面扩张",
		"time": 180.0,
		"enemies": [1, 1, 5],
	},
	13: {
		"name_i": "骨髓终战", "name_g": "骨骼沦陷", "map_id": 13,
		"desc_i": "最终决战!守住生命之源骨髓",
		"desc_g": "攻陷骨髓要塞!终结免疫",
		"time": 180.0,
		"enemies": [4, 5, 4],
	},
}


## 按当前阵营取关卡名/描述
func campaign_name(level: int) -> String:
	var lv: Dictionary = CAMPAIGN_LEVELS[level]
	return lv["name_g"] if my_faction == 2 else lv["name_i"]

func campaign_desc(level: int) -> String:
	var lv: Dictionary = CAMPAIGN_LEVELS[level]
	return lv["desc_g"] if my_faction == 2 else lv["desc_i"]

## 战役存档（user://campaign.json）
func campaign_save_path() -> String:
	return "user://campaign.json"

func campaign_load() -> Dictionary:
	var default := {"unlocked": 1, "completed": []}
	if not FileAccess.file_exists(campaign_save_path()):
		return default
	var f := FileAccess.open(campaign_save_path(), FileAccess.READ)
	if f == null:
		return default
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return default
	var data = json.get_data()
	return data if data is Dictionary else default

func campaign_save(unlocked: int, completed: Array) -> void:
	var f := FileAccess.open(campaign_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"unlocked": unlocked, "completed": completed}))

func campaign_unlocked_level() -> int:
	return int(campaign_load().get("unlocked", 1))

func campaign_completed() -> Array:
	var c = campaign_load().get("completed", [])
	if c is Array:
		var ints: Array = []
		for v in c:
			ints.append(int(v))
		return ints
	return []

## 战役胜利：解锁下一关+存档
func campaign_win() -> void:
	var unlocked := campaign_unlocked_level()
	var completed := campaign_completed()
	if not completed.has(campaign_level):
		completed.append(campaign_level)
	if campaign_level >= unlocked and campaign_level < 13:
		unlocked = campaign_level + 1
	campaign_save(unlocked, completed)
	print("[gamestate] 战役第%d关胜利! 解锁至第%d关" % [campaign_level, unlocked])


## 统计某阵营真人玩家数（含主机）
func faction_human_count(f: int) -> int:
	var count := 1 if my_faction == f else 0
	for pid in player_teams:
		if player_teams[pid] == f:
			count += 1
	return count

const CHARS_HINT := {
	1: "吞噬 - 锥形拉拽+大面积涂色",
	2: "抗体导弹 - 自动追踪涂色三连发",
	3: "NET网 - 脚下减速陷阱区",
	4: "抗原呈递 - 减速敌群+自身加速",
	5: "脱颗粒 - 爆发涂色+击退",
}

const GERM_HINT := {
	1: "分裂增殖 - 周身三团快速涂色",
	2: "突变爆发 - 六向散射涂色弹",
	3: "变形渗透 - 冲刺+沿途涂色轨迹",
	4: "蠕动席卷 - 直线冲锋宽幅涂色",
	5: "孢子雨 - 8m内五点随机轰炸",
}

## 角色医学介绍（儿童向通俗版）
const IMMUNE_DESC := {
	1: "免疫系统的清道夫大哥！它伸出「手臂」把坏细菌一口吞掉，在肚子里消化。真实名字叫巨噬细胞，是身体里的垃圾处理厂。",
	2: "免疫系统的神射手！它能记住每个坏蛋的脸，然后发射「抗体导弹」精准打击。得过的病不会再得，就是它的功劳！",
	3: "免疫系统的机关枪手！浑身装满「小炸弹」，遇到敌人就疯狂扫射。伤口化脓的白色的东西，就是它牺牲后的残骸。",
	4: "免疫系统的情报员！长满「天线」专门收集敌人信息，然后拍张「通缉令照片」告诉战友们：坏蛋长这样，打它！",
	5: "免疫系统的地雷专家！肚子里装满「组胺炸弹」，一引爆就整片区域变红变肿——过敏就是它太积极了！",
}

const GERM_DESC := {
	1: "地球上最古老的居民！它像小香肠，浑身长毛还拖着长尾巴（鞭毛）游泳。你手上的细菌比地球人口还多！",
	2: "分子级刺客！长得像登月飞船，用六条腿站在细胞上，然后像打针一样把自己的基因注进去——它其实是「半生命」！",
	3: "没有外壳的变形怪！因为没有细胞壁，它可以变成任何形状，从最窄的缝隙里钻过去，超难抓！",
	4: "贪婪的入侵者！像蚯蚓一样一节一节蠕动，走到哪吃到哪。蛔虫就是它的亲戚，能长到 30 厘米！",
	5: "安静的占领者！像珊瑚一样站在原地不动，但不停地撒孢子，慢慢地把周围都变成自己的地盘——脚气就是它干的！",
}  # 中途加入、不走 spawner 的客户端

signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what)


func _ready() -> void:
	multiplayer.peer_connected.connect(_player_connected)
	multiplayer.peer_disconnected.connect(_player_disconnected)
	multiplayer.connected_to_server.connect(_connected_ok)
	multiplayer.connection_failed.connect(_connected_fail)
	multiplayer.server_disconnected.connect(_server_disconnected)


func _player_connected(id: int) -> void:
	print("[gamestate] 对端接入 id=%d" % id)
	# 新玩家连上来，把自己的名字发给它 + 当前地图
	register_player.rpc_id(id, player_name, my_char, my_faction)
	sync_map.rpc_id(id, selected_map)
	# 中途加入：补发玩家表 + 世界；等客户端确认世界就绪后再生成角色（避免时序丢包）
	if multiplayer.is_server() and game_started:
		for pid in players:
			register_player.rpc_id(id, players[pid], player_chars.get(pid, 1),
				player_teams.get(pid, 2))
		load_world.rpc_id(id)
		pending_players.append(id)


@rpc("any_peer")
func client_world_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id in pending_players:
		pending_players.erase(id)
		var join_faction: int = player_teams.get(id, 2)
		# 阵营满员检查（真人+AI 已满 3）
		if faction_human_count(join_faction) >= 3:
			print("[gamestate] 玩家 %d 选的阵营 %d 已满，拒绝" % [id, join_faction])
			faction_full_notify.rpc_id(id)
			return
		var world: Node3D = get_tree().get_root().get_node(^"World")
		for p in world.get_node(^"Players").get_children():
			spawn_remote_player.rpc_id(id, p.global_position, str(p.name).to_int())
		late_peers.append(id)
		# 同阵营有 AI → 替换（真人接管 AI 位置，满血，角色模型用真人选的）
		var ai: Node = world.find_replaceable_ai(join_faction)
		if ai:
			var ai_pos: Vector3 = ai.global_position
			var ai_name := str(ai.name)
			world.remove_ai_replacement.rpc(ai_name)
			spawn_player(id, ai_pos)
			print("[gamestate] 玩家 %d 替换了 AI %s（阵营%d）" % [id, ai_name, join_faction])
		else:
			spawn_player(id)
		print("[gamestate] 迟到玩家 %d 已同步并生成" % id)


## 阵营满员通知（客户端显示提示并弹回大厅）
@rpc("authority", "call_local", "reliable")
func faction_full_notify() -> void:
	faction_full_rejected.emit()
	print("[gamestate] 阵营已满员！请选择另一阵营")


@rpc("any_peer")
func spawn_remote_player(pos: Vector3, p_id: int, char_id: int, team_id: int) -> void:
	# 服务器自己由 spawner 管理；此通道只给中途加入的客户端补节点
	if multiplayer.is_server():
		return
	var world := get_tree().get_root().get_node_or_null(^"World")
	if world == null:
		return
	var players_node := world.get_node(^"Players")
	if players_node.has_node(str(p_id)):
		return
	var player: CharacterBody3D = preload("res://player.tscn").instantiate()
	player.name = str(p_id)
	player.position = pos
	player.char_id = char_id
	player.my_team = team_id
	players_node.add_child(player)


func _player_disconnected(id: int) -> void:
	print("[gamestate] 对端断开 id=%d" % id)
	# 清理迟到通道登记（否则向死 peer 发 RPC 报 _send_rpc 错）
	late_peers.erase(id)
	pending_players.erase(id)
	if has_node(^"/root/World"):
		# 局中掉线：移除其角色，游戏继续（不再全员踢出）
		var node := get_tree().get_root().get_node_or_null("World/Players/" + str(id))
		if node:
			node.queue_free()
		players.erase(id)
	else:
		unregister_player(id)


func _connected_ok() -> void:
	print("[gamestate] 已连上服务器")
	connection_succeeded.emit()


func _server_disconnected() -> void:
	print("[gamestate] 主机已断开")
	if has_node(^"/root/World"):
		# 对局内：显示结算画面让玩家选「再战」（自动接管）或退出
		# 注：不直接继续——set_multiplayer_peer(null) 会释放 spawner 管理的角色节点
		# 导致灰屏；必须走再战→重建完整对局
		var world: Node3D = get_tree().get_root().get_node(^"World")
		# 接管成为新主机（为「再战」做准备）
		takeover_host()
		# 显示结算画面（再战按钮会触发 restart_match）
		world._pending_end_data = {"winner": 0, "c1": 0.0, "c2": 0.0}
		world._show_end_widget_with_msg("主机退出! 你已成为新主机")
	else:
		game_error.emit("主机已断开")
		end_game()


func _connected_fail() -> void:
	print("[gamestate] 连接失败！")
	multiplayer.set_multiplayer_peer(null)
	connection_failed.emit()


@rpc("any_peer")
func register_player(new_player_name: String, char_id: int, faction: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	# 阵营满员检查（每阵营最多 3 真人）
	if multiplayer.is_server() and faction_human_count(faction) >= 3:
		print("[gamestate] 拒绝 %s：阵营 %d 已满" % [new_player_name, faction])
		faction_full_notify.rpc_id(id)
		return
	players[id] = new_player_name
	player_chars[id] = char_id
	player_teams[id] = faction
	player_list_changed.emit()


func unregister_player(id: int) -> void:
	players.erase(id)
	player_list_changed.emit()


func host_game(new_name: String) -> bool:
	player_name = new_name
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(DEFAULT_PORT, MAX_PEERS)
	if err != OK:
		return false
	multiplayer.set_multiplayer_peer(peer)
	return true


func join_game(ip: String, new_name: String) -> bool:
	player_name = new_name
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, DEFAULT_PORT)
	if err != OK:
		return false
	multiplayer.set_multiplayer_peer(peer)
	return true


func get_player_name(id: int) -> String:
	if id == multiplayer.get_unique_id():
		return player_name
	return players.get(id, "P" + str(id))


func get_player_list() -> Array:
	return players.values()


@rpc("call_local")
func load_world() -> void:
	# 移除旧 World（改名+释放，不阻塞——避免 await 导致调用方拿到 null）
	var old_w := get_tree().get_root().get_node_or_null(^"World")
	if old_w:
		old_w.name = "World_Old"  # 改名让新 World 能同名注册
		old_w.queue_free()          # 帧末释放（非阻塞）
	var world: Node3D = load("res://world.tscn").instantiate()
	get_tree().get_root().add_child(world)
	var lobby := get_tree().get_root().get_node_or_null(^"Main")
	if lobby:
		lobby.hide()
	get_tree().paused = false


@rpc("authority", "call_local", "reliable")
func sync_map(m: int) -> void:
	selected_map = m
	print("[gamestate] 地图已同步: %d" % m)


## 战役开局：单人+2友方AI vs 关卡指定敌人
func begin_campaign(level: int) -> void:
	campaign_mode = true
	campaign_level = level
	var lv: Dictionary = CAMPAIGN_LEVELS[level]
	selected_map = lv["map_id"]
	# 阵营由玩家在大厅选择（免疫=防守视角 / 病原体=进攻视角）
	game_started = true
	load_world.rpc()
	var world: Node3D = get_tree().get_root().get_node(^"World")
	var angle := randf() * TAU
	var c1 := Vector3(cos(angle) * 16.0, 1.0, sin(angle) * 16.0)
	var c2 := Vector3(-c1.x, c1.y, -c1.z)
	world.setup_team_spawns.rpc(c1, c2)
	spawn_player(1)
	world.spawn_campaign_enemies.rpc(lv["enemies"])
	print("[gamestate] 战役第%d关[%s]开始 阵营=%d" \
		% [level, campaign_name(level), my_faction])


func begin_game() -> void:
	assert(multiplayer.is_server())
	game_started = true
	sync_map.rpc(selected_map)  # 先同步地图再加载世界（顺序 RPC 保序）
	load_world.rpc()
	var world: Node3D = get_tree().get_root().get_node(^"World")
	# 阵营分区必须在所有出生之前设定（否则全取兑底=中央）
	var angle := randf() * TAU
	var radius := 16.0
	var c1 := Vector3(cos(angle) * radius, 1.0, sin(angle) * radius)
	var c2 := Vector3(-c1.x, c1.y, -c1.z)
	world.setup_team_spawns.rpc(c1, c2)
	# 现在才生玩家（分区已就绪）
	var ids: Array[int] = [1]
	ids.append_array(players.keys())
	for id in ids:
		spawn_player(id)
	# AI 也用同一分区
	world.spawn_enemies.rpc()
	print("[gamestate] begin_game 完成，共 %d 名玩家" % ids.size())


func spawn_player(p_id: int, at_pos: Vector3 = Vector3.ZERO) -> void:
	var world: Node3D = get_tree().get_root().get_node(^"World")
	var spawner: MultiplayerSpawner = world.get_node(^"PlayerSpawner")
	var tm: int = my_faction if p_id == 1 else player_teams.get(p_id, 2)
	var pos: Vector3 = at_pos if at_pos != Vector3.ZERO else world.team_spawn(tm)
	var cid: int = player_chars.get(p_id, 1) if p_id != 1 else my_char
	var player: CharacterBody3D = spawner.spawn([pos, p_id, cid, tm])
	if player:
		player.face_arena_center()
	# 其他迟到客户端不归 spawner 管，手动补发（含刚加入的它自己）
	for lp in late_peers:
		spawn_remote_player.rpc_id(lp, player.global_position, p_id, cid, tm)


func end_game() -> void:
	game_started = false
	pending_players.clear()
	late_peers.clear()
	if has_node(^"/root/World"):
		get_node(^"/root/World").queue_free()
	game_ended.emit()
	players.clear()


func get_player_color(p_name: String) -> Color:
	return Color.from_hsv(wrapf(p_name.hash() * 0.001, 0.0, 1.0), 0.6, 1.0)


## 主机退出后的接管：本机成为新主机，AI 权威转移，续战
func takeover_host() -> void:
	print("[gamestate] 接管成为新主机")
	multiplayer.set_multiplayer_peer(null)
	if not host_game(player_name):
		push_error("接管开服失败")
		return
	# AI 与世界节点的权威归新主机（原主机 id=1）
	var world := get_tree().get_root().get_node_or_null(^"World")
	if world:
		var my_id := multiplayer.get_unique_id()
		if world.has_node("Enemies"):
			for en in world.get_node("Enemies").get_children():
				en.set_multiplayer_authority(my_id)
				for sn in en.find_children("*", "MultiplayerSynchronizer"):
					sn.set_multiplayer_authority(my_id)
	print("[gamestate] 接管完成 id=", multiplayer.get_unique_id())
