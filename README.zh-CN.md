# Writing Tools Anywhere

在 **任何** macOS 应用里调用 Apple Intelligence 改写文字 —— 包括 Microsoft Teams、
Slack、VS Code 这些系统原本不支持 Writing Tools 的应用。

<img src="Resources/icon-preview.png" width="128">

## 两种用法

**① 悬浮球（Grammarly 式）** — 在任何应用里选中文字，选区旁边浮出一个 ✨ 小球，
鼠标移上去展开成三项：

```
┌──────────────────────────────┐
│  ✓ 校对    🄰 翻译    ✨ 写作工具  │
└──────────────────────────────┘
```

- **校对** — 修正语法、拼写和别扭的表达，直接替换原文。保留你的语气和长度，
  不会把你的话改成官腔。
- **翻译** — 在你的语言和英文之间互译，方向自动判断。
- **写作工具** — 打开编辑面板并唤起 **Apple 原版 Writing Tools**，
  官方那一整套语气、摘要、要点功能都在里面。

**② 全局快捷键** — 选中文字按 `⌥⌘W`，直接进编辑面板。
悬浮球取不到选区的应用（见「已知限制」）用这条路，它有 `⌘C` 兜底。

**内联部分刻意只做一件事。** 通用模型可靠的地方就是语法。
语气和摘要需要 Apple 自己留着的适配器，所以它们放在 ✨ 后面，
而不是在这里做一个拙劣的近似——见[性能上限](#性能上限内联为什么追不上官方)。

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
| 语言 | 我的语言 | 翻译在这个语言和英文之间进行，方向自动判断。设成英文则一切非英文都转英文 |
| 语言 | 下载语言包… | 跳转到系统设置，Apple 的翻译语言包在那里安装 |
| 高级 | 自动替换 | 写作工具面板结束后自动写回，省掉 `⌘↩` |
| 高级 | 替换方式 | 模拟粘贴（兼容性最好）/ 辅助功能直接写入 |
| 高级 | 剪贴板 | 用完后恢复原有内容 |
| 高级 | 调试日志 | **默认关闭**；打开后会把你选中的文字写入本地日志 |

校对结果始终使用原文的语言，界面语言只影响 App 自身的 UI。
翻译走的是 Apple 内置的翻译引擎，所以语言包需要先在系统设置里下载——
没装的话，悬浮球会直接告诉你缺哪一对。

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
| `Sources/LLM.swift` | FoundationModels 封装、prompt、引导式生成 |
| `Sources/Translator.swift` | Translation.framework 封装与语种识别 |
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

## 性能上限：内联为什么追不上官方

这个 App 里的几条路径**跑在不同的引擎上**，这个差别就是全部答案：

| | 引擎 | 质量 |
|---|---|---|
| **内联**（校对） | `FoundationModels` —— Apple 的**通用**端上基座模型，由本项目写 prompt 驱动 | 够用来修语法，仅此而已 |
| **翻译** | `Translation.framework` —— Apple 专用翻译引擎，和「翻译」App、Safari 同一套 | Apple 官方水准 |
| **写作工具**（✨） | `showWritingTools:` —— **Apple 真正的 Writing Tools**，带它任务专训的 LoRA 适配器 | Apple 官方水准 |

**官方 Writing Tools 不是拿通用模型写 prompt。** 它加载**任务专属的 LoRA 适配器**
——校对一个、摘要一个、每种语气各一个——运行时按需换入。
然后通过 `NSWritingToolsCoordinator` 把 **`(范围, 替换文本)` 对**交回 App，
直接编辑已有的文本存储，而不是返回一整段文字。

**这两样公开 API 都拿不到。** FoundationModels 给你的是通用的约 3B 基座模型和
整段字符串响应；官方那些适配器是私有系统资源，
`SystemLanguageModel.Adapter(name:)` 加载的是**你自己提供**的适配器，不是 Apple 的。

所以内联编辑本质上是「对通用模型做 prompt 工程」，它有天花板。
这也是它只做一件事的原因。

### 天花板体现在哪

只要让基座模型做「正确」之外的事，它就会飘，而且飘得可测量。真实聊天消息上：

| 你要的 | 通用模型实际给的 |
|---|---|
| 专业的语气 | 一句话的消息变成 2.4 倍长的信函模板——`Hi [Recipient's Name] … Best regards, [Your Name]`。给 prompt 加缰绳能压住长度，压不住那个本能。 |
| 友好的语气 | 加上原文根本没有的客套：「Thanks for your understanding!」 |
| 更短一些 | 约一半概率把原文原样交回。而且 prompt 写得越强**越糟**——加上「结果必须明显更短」和字符数预算之后，模型干脆放弃编辑、直接复制输入。 |
| 翻译 | **会编。**「明天」被翻成「Wednesday」；一个没翻的 "someone" 直接留在中文句子里。 |

最后一条就是翻译改用 `Translation.framework` 的原因。
Apple 的翻译器犯的是普通的选词错误，不是笃定的捏造——
这两种「错」，对于要粘进别人消息里的文字来说，性质完全不同。

其余几条，就是内联只做校对、以及 ✨ 为什么存在的原因。

### 校对靠什么守住

1. **引导式生成**。响应被强制填进只有一个 `text` 字段的 schema，
   「Here is the corrected version:」无处安放。用 `DynamicGenerationSchema` 运行时构建，
   而不是 `@Generable` 宏——那个宏的编译器插件只随 Xcode 发布。
2. **给文档加围栏**。文字包在 `⟪⟪⟪ … ⟫⟫⟫` 里。不加围栏时，模型会去「回答」短文本或疑问句
   而不是编辑它：`ok` 会被编出一整段，写着「忽略你的指令」的文字会被照做。
   模型有时会把围栏的**残片**吐回来，所以是按字符集裁剪，而不是匹配完整标记。
3. **合理长度上限**。结果超过原文约 1.6 倍，那就是「续写」而不是「修正」，直接丢弃。

如果结果和原文完全一致，悬浮球会告诉你「没有可改的地方」，
而不是把你自己的话原样贴回你自己身上。

### 那自己训一个适配器行不行

技术上可以。`SystemLanguageModel.Adapter` 是公开的，Apple 也提供训练 rank-32 LoRA 的
Python 工具包（Apple silicon + ≥32GB 内存，或 Linux GPU 机器）。但这里不值得，两个原因：

- **适配器锁死基座模型版本**——一个系统模型版本对应一个适配器，无一例外。
  macOS 一更新就可能失效，在你重新训练并发版之前，所有用户的 App 都是坏的。
- **它补不上真正的差距。** 差别不只是模型，更是**传输格式**：官方按范围原地编辑，
  我们是整块替换。换适配器改变不了这一点。

**所以分工是诚实的：内联是便利路径，✨ 是质量路径。**
后者把你的文字放进一个真正的 `NSTextView` 再调 `showWritingTools:`，
于是你拿到的是 Apple 自己的适配器、prompt 和逐条接受/拒绝的界面——
在一个本来永远不会提供这些的 App 里。

## 已知限制## 已知限制## 已知限制

- 翻译需要先安装 Apple 的语言包（系统设置 → 通用 → 语言与地区 → 翻译语言）。
  缺哪一对会直接报出来。
- 语种识别需要足够的文字。置信度低于 0.6 时——`ok` 会被识别成波兰语、`LGTM` 成土耳其语
  ——方向会退回到你设定的语言对，而不是相信那个猜测。
- 只读纯文本，写回也是纯文本，富文本格式（加粗、链接）会丢失。
- 「模拟粘贴」会短暂占用剪贴板，之后恢复。剪贴板管理器可能会记录这一次。
- 需要辅助功能权限，无法沙盒化，因此也无法上架 App Store。
- **悬浮球依赖辅助功能 API 读选区**。绝大多数原生应用和 Electron 应用可用，
  但少数应用（部分 Java 程序、游戏、自绘文本引擎、远程桌面）不上报选区，
  这些应用里悬浮球不会出现 —— 用 `⌥⌘W` 快捷键，它有 `⌘C` 兜底。
- 悬浮球定位：优先用选区的屏幕矩形；部分应用返回 `0×0`，此时退回鼠标位置。
- 为了检测选区，App 注册了全局键鼠事件监听（这也是辅助功能权限的用途之一）。
  监听内容不做任何记录、存储或上传，除非你手动打开「记录调试日志」。
