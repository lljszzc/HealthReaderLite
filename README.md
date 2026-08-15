<div align="center">

# 🍃 HealthReaderLite

**极轻量 macOS menubar RSS 阅读器 · 订阅资讯 + 久坐提醒**

原生 Swift 编写 · 零第三方依赖 · 无遥测 · 安装包约 1.9 MB

[![macOS](https://img.shields.io/badge/macOS-15%2B-28a745?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/lljszzc/HealthReaderLite/ci.yml?branch=main&label=CI&logo=github)](https://github.com/lljszzc/HealthReaderLite/actions)
[![Release](https://img.shields.io/github/v/release/lljszzc/HealthReaderLite?label=Release&logo=github)](https://github.com/lljszzc/HealthReaderLite/releases)

</div>

HealthReaderLite 是常驻菜单栏的轻量 RSS 阅读器：一杯茶的时间读完最新消息。它很小、很快、不打扰——**打开资讯、读完关闭，应用自动从 Dock 消失**，同时内置可自定义的**久坐提醒**，到点弹窗提醒你先起身，顺便看看新闻。

## ✨ 特性

- 🍃 **常驻 menubar**：仅占状态栏一个小图标（自带**久坐进度环**，一眼看出距下次起身还有多久，可关闭），不驻留 Dock
- 📰 **订阅管理**：RSS/Atom 订阅、文件夹分组、自动定时更新（5–120 分钟）、失败保留、去重
- 📖 **Reeder 风格阅读窗口**：大标题、源信息、封面大图、正文统一排版；关闭窗口后应用自动从 Dock 消失
- 📄 **全文抓取**：只提供摘要的站点（如少数派 sspai）可一键开启"自动抓取全文"，并自动回填页面封面图
- 🧘 **久坐提醒**：自定义间隔（30–120 分钟）、提示音、menubar 弹窗 + "看看新闻/稍后 10 分钟"
- 🖼️ **图片缓存**：磁盘上限 500MB，超限自动按最久未使用清理（LRU）
- 💎 **macOS 26 Liquid Glass 设计语言**：玻璃拟态渐变图标、材料质感背景、自适应深色/浅色
- 🔒 **隐私友好**：纯本地解析呈现，零第三方依赖、零遥测、零账户

## 📷 截图

> 待补充：菜单栏图标与进度环 / 消息小窗口 / 阅读窗口 / 设置面板
> （替换为你的实际截图后即可让项目一目了然）

## 📦 安装

### 方式一：下载 Release（推荐）

前往 [Releases](https://github.com/lljszzc/HealthReaderLite/releases) 下载 `HealthReaderLite.app.zip`，
解压后拖入"应用程序"（或直接双击运行）。

首次启动会预置 3 个订阅（Hacker News / The Verge / 少数派）并自动抓取文章。

> macOS 可能提示"无法验证开发者"——本工具为 ad-hoc 签名、完全离线运行：
> 右键应用 → 打开，或系统设置 → 隐私与安全性 → 仍然打开。转正开发者证书后可消除该提示。

### 方式二：源码构建

需要 Xcode（Swift 6+）与 macOS 15+：

```bash
git clone https://github.com/lljszzc/HealthReaderLite.git
cd HealthReaderLite
./Scripts/build_app.sh          # 编译 + 生成图标 + 打包 .app + ad-hoc 签名
open build/HealthReaderLite.app # 运行
```

## 🕹️ 使用

| 操作 | 方法 |
|---|---|
| 展开/收起消息窗口 | 点击菜单栏 🍃 图标 |
| 阅读文章 | 点击消息列表条目 → 弹出阅读窗口（Dock 图标随之出现） |
| 关闭阅读窗口 | ✕ 或 `Esc` → 应用自动从 Dock 消失，回到纯 menubar 状态 |
| 添加订阅 | 窗口右上角 `+` → 粘贴 RSS/Atom 链接（可选名称/文件夹/全文抓取） |
| 文件夹管理 | 侧栏右键：重命名 / 删除 / 移动到分组 |
| 立即更新 | 顶部 ↻，或订阅项右键 → 立即更新 |
| 快捷键 | `⌘1` 消息窗口 · `⌘R` 刷新全部 · `⌘Q` 退出 |

阅读窗口内：⭐ 收藏、🌐 Safari 打开原文、正文链接直接可点、文字可选中复制。

### 设置项

| 设置 | 说明 |
|---|---|
| 刷新间隔 | 自动更新周期（5–120 分钟） |
| 久坐提醒 | 开/关、间隔 30–120 分钟、提示音 |
| 菜单栏显示久坐进度环 | 图标外圈环形进度，直观显示距下次起身的进度（默认开，可关） |
| 打开即标已读 | 打开文章自动标记已读（默认开） |

## 🧪 自检与调试

```bash
.build-release/release/HealthReaderLite --selftest                          # 全部自测（解析/排版/缓存 LRU 等）
.build-release/release/HealthReaderLite --fetch-test "<feed_url>"           # 抓取真实订阅源
.build-release/release/HealthReaderLite --extract-test "<article_url>"      # 全文提取实测（含封面图）
```

隐藏调试旗标（自动化验证用，读取即清除）：

```bash
defaults write com.healthreader.lite debugDemoNews -bool YES       # 自动打开并关闭阅读窗口（验证 Dock 出现/消失）
defaults write com.healthreader.lite debugReminderTest -bool YES   # 数秒后触发一次久坐提醒
```

## 🏗️ 技术架构

- 纯 AppKit + SwiftUI（macOS 15+），SPM 单可执行目标，**零第三方依赖**
- `LSUIElement` + 动态激活策略（`.regular` / `.accessory`）：阅读窗口打开时 Dock 出现，关闭后消失
- 自研 RSS 2.0 / Atom 解析器（`XMLParser`）；自研阅读模式全文提取器（`<p>` 段落聚类 + 容器兜底 + 图片归位）
- 正文**块级排版引擎**（段落/标题/引用/列表/配图统一风格）；纯文本摘要自动分段
- 4 路并发抓取、单源 80 条/全局 600 条上限、HTML 渲染后台线程化、原子 JSON 持久化（防抖 + 损坏自动备份）
- 图片缓存 500MB 上限 + LRU 清理（`URLCache`）

### 目录结构

```
Sources/HealthReaderLite/
  main.swift            入口（自检模式/调试旗标/GUI 启动）
  AppDelegate.swift     应用生命周期、定时器、阅读窗口管理
  StatusController.swift menubar 图标（含进度环）+ popover
  Reminder.swift        久坐提醒引擎
  Store.swift           AppStore：持久化/订阅 CRUD/刷新合并/全文补抓
  RSSParser.swift       RSS 2.0 / Atom 解析
  Network.swift         抓取与图标服务
  Readability.swift     阅读模式全文提取器（含封面图回填）
  Cache.swift           图片缓存管理（500MB / LRU）
  HTML.swift            清洗/日期/块级排版工具
  Views/                popover 主界面、阅读窗口、表单
Scripts/
  build_app.sh          一键构建打包脚本
  gen_icon.swift        Liquid Glass 图标生成（纯离线）
  Info.plist            应用配置（LSUIElement）
```

## 📁 数据与隐私

- 数据保存在 `~/Library/Application Support/HealthReaderLite/`：`store.json`（订阅/文章/设置）、`debug.log`（运行日志，可随时删除）
- 图片缓存位于 `~/Library/Caches/HealthReaderLite/`（500MB 上限自动清理）
- **不收集任何数据**：无遥测、无统计、无账户；仅在你订阅的 feed 上做本地解析与抓取
- 完全卸载：关闭应用后删除上述目录与 `HealthReaderLite.app` 即可

## 🤝 贡献

欢迎 Issue 与 PR！请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)（含构建、自测与代码约束）。
开发路线图见 [CHANGELOG.md](CHANGELOG.md)。

## 📄 License

[MIT](LICENSE) © HealthReaderLite contributors —— 自由使用、修改与分发。
请尊重你订阅的各个内容源的条款，本工具仅供个人学习与阅读使用。