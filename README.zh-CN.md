# Writing Tools Anywhere

在 **任何** macOS 应用里调用 Apple Intelligence 改写文字 —— 包括 Microsoft Teams、
Slack、VS Code 这些系统原本不支持 Writing Tools 的应用。

<img src="Resources/icon-preview.png" width="128">

## 两种用法

**① 悬浮球（Grammarly 式）** — 在任何应用里选中文字，选区旁边浮出一个 ✨ 小球，
鼠标移上去展开成一排：

```
┌─────────────────────────────────────────┐
│ ✓校对  ↻改写  ☺友好  ▣专业  ≡简洁  ✨写作工具 │
└─────────────────────────────────────────┘
```

前五个**一键直改**：点一下，改写好的文字直接覆盖原文（约 1～2 秒）。
第六个打开编辑面板并唤起 Apple 原版的 Writing Tools。

**② 全局快捷键** — 选中文字按 `⌥⌘W`，直接进编辑面板。
悬浮球取不到选区的应用（见「已知限制」）用这条路，它有 `⌘C` 兜底。

## 它是怎么做到的

Apple 没有开放「把 Writing Tools 注入到别的 App」的接口。Teams 之类的 Electron 应用不用
`NSTextView`，所以系统不会给它挂上 Writing Tools，这一点无法绕过。

这个 App 换了个思路：读取你在任意应用里选中的文字 → 交给 Apple Intelligence 处理 →
把结果写回去。

### 一键按钮 vs. Apple 原版

Apple 只开放了「**打开** Writing Tools 面板」这一个入口（`showWritingTools:`），
没有开放「直接执行校对」或「直接执行改写」。

所以那五个一键按钮走的是 **FoundationModels**（macOS 26 公开的端上大模型框架，
和 Writing Tools 是同一个本地模型），配本项目自己写的 prompt。全程离线，不联网，
不需要 API key。

想要 Apple 原版的 prompt 和界面，点第六个「写作工具」——那会把文字放进一个真正的
`NSTextView` 里，系统就会给它完整的 Writing Tools 体验。

### 选区是怎么检测到的

监听全局鼠标松开和选择性按键，然后用辅助功能 API 读取选区 —— **绝不**在这里模拟 `⌘C`，
否则每点一次鼠标都会污染剪贴板。

Electron 应用（Teams、Slack、VS Code、Obsidian）默认不构建辅助功能树，
所以会先给它们设置 `AXManualAccessibility`，这样才读得到选区。

## 要求

- macOS 26 或更新（一键改写依赖 FoundationModels）
- **Apple Intelligence 已开启** —— 启动时会自动检测，没开会弹窗并提供跳转按钮
- Apple silicon
- 只需 Command Line Tools，不需要装 Xcode

## 构建与运行

先建一次固定的签名身份（只需一次）：

```bash
./setup-signing.sh
```

然后构建并运行：

```bash
./build.sh --run
```

首次启动会请求**辅助功能**权限：
系统设置 → 隐私与安全性 → 辅助功能 → 打开 `WritingToolsAnywhere`，然后重启 App。

生成应用图标（改了 `tools/MakeIcon/main.swift` 之后才需要重跑）：

```bash
./make-icon.sh
```

### 为什么需要 setup-signing.sh

macOS 把辅助功能权限绑在 App 的**代码签名**上，不是绑在路径或 bundle ID 上。

ad-hoc 签名的值是由二进制内容算出来的，所以**改一行代码重新编译，签名就变一次**，
系统会把它当成另一个 App —— 而系统设置里那个开关还留着旧记录、显示为「已开启」，
于是出现最难受的情况：**看起来已授权，实际不生效，也不再弹提示**。

`setup-signing.sh` 在登录钥匙串里建一张自签名的代码签名证书，签名身份从此不随代码变化，
授权一次就一直有效，连移动文件夹都不受影响。

如果确实遇到权限错乱，清掉记录重来：

```bash
tccutil reset Accessibility com.linshan.WritingToolsAnywhere
```

（若报 `No such bundle identifier`，先用 `lsregister -f <app 路径>` 注册一下。）

## 设置

菜单栏 ✨ 图标 → **设置…**（或 `⌘,`）

| 分区 | 项目 | 说明 |
|---|---|---|
| 状态 | Apple Intelligence | 实时检测；未开启时给出跳转按钮 |
| 状态 | 辅助功能权限 | 实时检测；未授予时给出跳转按钮 |
| 通用 | 登录时自动启动 | 走 `SMAppService`，不需要额外的 helper |
| 通用 | 悬浮球 | 关掉之后只保留快捷键 |
| 通用 | 快捷键 | 修饰键勾选 + 主键下拉，改完立即生效 |
| 语言 | 界面语言 | 跟随系统 / 简体中文 / English |
| 语言 | 改写输出语言 | 跟随原文 / 中文 / English / 日本語 / 한국어 / Français / Deutsch / Español |
| 高级 | 自动替换 | 写作工具面板结束后自动写回，省掉 `⌘↩` |
| 高级 | 替换方式 | 模拟粘贴（兼容性最好）/ 辅助功能直接写入 |
| 高级 | 剪贴板 | 用完后恢复原有内容 |
| 高级 | 调试日志 | **默认关闭**；打开后会把你选中的文字写入本地日志 |

「改写输出语言」和界面语言是两回事：前者决定改写结果用什么语言，
所以你可以中文界面 + 输出英文，写完中文草稿一键转成英文。

配置存在 `~/Library/Application Support/WritingToolsAnywhere/config.json`，
也可以直接手改。

## 快捷键

| 位置 | 按键 | 作用 |
|---|---|---|
| 全局 | 选中文字 | 悬浮球自动出现，鼠标移上去展开 |
| 全局 | `⌥⌘W` | 抓取选中文字并打开编辑面板 |
| 面板内 | `⌘J` | 重新打开 Writing Tools |
| 面板内 | `⌘↩` | 用结果替换原文 |
| 面板内 | `⇧⌘C` | 复制结果 |
| 面板内 | `esc` | 取消 |

## 源码结构

| 文件 | 作用 |
|---|---|
| `Sources/main.swift` | 入口 |
| `Sources/AppDelegate.swift` | 菜单栏、权限与 Apple Intelligence 引导、总调度 |
| `Sources/SettingsWindow.swift` | 设置窗口 |
| `Sources/SelectionWatcher.swift` | 全局选区检测 + 悬浮球定位 |
| `Sources/BubbleController.swift` | 悬浮球容器（不抢焦点的 non-activating panel） |
| `Sources/ActionMenuView.swift` | 展开后的一排按钮（自绘） |
| `Sources/PanelController.swift` | 编辑面板与 `showWritingTools:` 调用 |
| `Sources/TextBridge.swift` | 跨应用读取选区 / 写回结果 / 剪贴板保护 |
| `Sources/LLM.swift` | FoundationModels 封装与各动作的 prompt |
| `Sources/HotKey.swift` | Carbon 全局快捷键（不需要额外权限） |
| `Sources/LoginItem.swift` | 开机自启（`SMAppService`） |
| `Sources/L10n.swift` | 中英文界面 |
| `Sources/MenuBarIcon.swift` | 菜单栏单色图标（代码绘制） |
| `Sources/Prefs.swift` | JSON 配置 |
| `Sources/Log.swift` | 调试日志（默认关闭） |
| `tools/MakeIcon/main.swift` | 应用图标（Core Graphics 矢量绘制，十个尺寸各自渲染） |

## 排查

设置 → 高级 → **复制诊断信息**，会把权限、模型、快捷键等状态复制到剪贴板。

需要更细的信息就打开「记录调试日志」，日志在
`~/Library/Logs/WritingToolsAnywhere.log`，每次启动清空：

```
launch: trusted=true llm=true          ← trusted=false 就是权限没生效，小球不会出现
watcher: start                          ← 选区监听已启动
check: front=Obsidian sel=... rect=...  ← 每次检测选区的结果
bubble: orderFront frame=... visible=true
```

## 已知限制

- 只读纯文本，写回也是纯文本，富文本格式（加粗、链接）会丢失。
- 「模拟粘贴」会短暂占用剪贴板，之后恢复。剪贴板管理器可能会记录这一次。
- 需要辅助功能权限，无法沙盒化，因此也无法上架 App Store。
- **悬浮球依赖辅助功能 API 读选区**。绝大多数原生应用和 Electron 应用可用，
  但少数应用（部分 Java 程序、游戏、自绘文本引擎、远程桌面）不上报选区，
  这些应用里悬浮球不会出现 —— 用 `⌥⌘W` 快捷键，它有 `⌘C` 兜底。
- 悬浮球定位：优先用选区的屏幕矩形；部分应用返回 `0×0`，此时退回鼠标位置。
- 为了检测选区，App 注册了全局键鼠事件监听（这也是辅助功能权限的用途之一）。
  监听内容不做任何记录、存储或上传，除非你手动打开「记录调试日志」。
