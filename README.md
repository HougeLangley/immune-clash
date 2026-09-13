# 免疫大作战 Immune Clash

> 🎮 一款以人体免疫系统为主题的 Splatoon 式涂色射击游戏，专为儿童设计的寓教于乐手机游戏。

[![Bilibili](https://img.shields.io/badge/Bilibili-观看演示-FF69B4?logo=bilibili&style=for-the-badge)](https://www.bilibili.com/video/BV1GEYi6kEYR)
[![YouTube](https://img.shields.io/badge/YouTube-Watch_Demo-FF0000?logo=youtube&style=for-the-badge)](https://youtu.be/Cc4Tujw2tZE)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Godot 4.7](https://img.shields.io/badge/Engine-Godot_4.7-478CBF?logo=godotengine&style=for-the-badge)](https://godotengine.org)

---

## 📖 游戏介绍

**免疫大作战（Immune Clash）** 是一款运行在 Android 手机上的像素风第三人称涂色射击游戏。玩家扮演免疫细胞或病原体，在人体内的 13 个器官战场（口腔、鼻腔、皮肤、气管、眼睛、耳朵、肺、胃、肠道、神经、肾、膀胱、骨骼）中用生物墨汁争夺领地。

### ✨ 特色

- 🧬 **10 种角色**：5 种免疫细胞（巨噬细胞、淋巴细胞、粒细胞、树突细胞、肥大细胞）vs 5 种病原体（细菌、病毒、支原体、寄生虫、真菌），每种都有独特造型和技能
- 🗺 **13 张专属地图**：从口腔到骨骼，每张地图还原真实器官的形态结构
- 🎵 **13 首专属 BGM**：每张地图配独特背景音乐
- 🎬 **26 条教育视频**：每场战斗结束播放健康知识儿歌（带拼音字幕），教会小朋友保护身体
- 🤖 **智能 AI**：占地优先策略型 AI，支持真人替换
- 📡 **局域网联机**：UDP 自动发现主机，最多 3v3 多人对战
- 🔄 **主机迁移**：主机退出后自动接管继续游戏
- 🎨 **程序化生成**：全部美术资源（纹理、模型、音乐、音效）纯代码生成，零外部素材

---

## 🎮 玩法介绍

### 核心规则

| 规则 | 说明 |
|---|---|
| **目标** | 在限定时间内，己方涂鸦覆盖率超过敌方 |
| **涂色** | 射击墨汁给地面染色，扩大己方领地 |
| **伤害** | 墨汁不造成直接伤害；站在敌方墨汁中会持续掉血+减速 |
| **恢复** | 站在己方墨汁中恢复 HP（+10/秒）和弹药（+45/秒） |
| **胜利** | 计时结束覆盖率更高的一方获胜 |

### 游戏模式

```
🏰 战役模式：单人闯关 13 个器官关卡（免疫/病原体双视角）
⚔️ 多人对战：局域网 3v3 实时对战（支持中途加入）
```

### 操作

- 虚拟摇杆移动
- 点击屏幕射击
- 跳跃/技能按钮在屏幕右侧

---

## 📥 下载

| 平台 | 链接 |
|---|---|
| Android APK | [Release v1.0.0](../../releases/tag/v1.0.0) |

---

## 🔧 本地构建

### 环境要求

- [Godot 4.7](https://godotengine.org/download)（标准版即可）
- Android SDK（命令行工具即可）
- JDK 17+

### 构建步骤

```bash
# 1. 克隆仓库
git clone https://github.com/HougeLangley/immune-clash.git
cd immune-clash

# 2. 用 Godot 编辑器打开项目
#    打开 Godot → Import → 选择项目目录中的 project.godot

# 3. 配置 Android 导出
#    编辑器 → 项目 → 导出 → 添加 Android
#    设置 keystore（或使用 debug keystore）
#    确保 Android SDK 路径正确

# 4. 导出 APK
#    方法 A：编辑器 → 项目 → 导出 → Android → 导出项目
#    方法 B：命令行
godot --headless --export-debug "Android" build/immune-clash.apk

# 5. 安装到手机
adb install build/immune-clash.apk
```

### 项目结构

```
├── project.godont       # Godot 项目配置
├── main.gd / main.tscn  # 大厅（选角/选图/联机）
├── world.gd / world.tscn# 战斗世界（地图/规则/HUD）
├── player.gd            # 玩家控制
├── enemy.gd             # AI 行为
├── gamestate.gd         # 全局状态/网络
├── ink_tile_map.gd      # 墨汁瓦片系统
├── touch_controls.gd    # 触屏操作
├── edu_L*.ogv           # 26 条教育视频
├── bgm_*.ogg            # 13 首 BGM
└── intro.ogv            # 开场动画
```

---

## 📜 开源协议

本项目采用 [MIT License](LICENSE) 开源。

```
MIT License

Copyright (c) 2026 Houge Langley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🙏 鸣谢

- **[Godot Engine](https://godotengine.org)** — 强大的开源游戏引擎
- **MiniMax & Seedance** — AI 生成开场动画和教育视频
- **DeepSeek** — AI 视觉验证辅助开发
- **所有测试玩家** — 感谢你们的反馈和耐心

---

## ☕ 支持开发者

如果这个游戏给你或你的孩子带来了快乐，欢迎请我喝一杯咖啡！

<img src="docs_donate.png" width="200" alt="收款码" />

你的支持是我继续开发的动力！🙏

---

## 🎬 演示视频

### Bilibili
[![Bilibili 演示](https://img.shields.io/badge/▶_观看_Bilibili_演示视频-FF69B4?style=for-the-badge&logo=bilibili)](https://www.bilibili.com/video/BV1GEYi6kEYR)

### YouTube
[![YouTube Demo](https://img.youtube.com/vi/Cc4Tujw2tZE/maxresdefault.jpg)](https://youtu.be/Cc4Tujw2tZE "点击播放")

---

## 🗺️ 路线图

- [x] v1.0.0 — 13 关战役 + 多人联机 + 教育视频
- [ ] v1.1.0 — 更多角色技能
- [ ] v1.2.0 — 在线排行榜
- [ ] v2.0.0 — iOS 支持

---

Made with ❤️ and 🧬 by [Houge Langley](https://github.com/HougeLangley)
