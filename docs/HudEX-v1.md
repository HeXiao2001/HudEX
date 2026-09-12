# HudEX v1 — 设计与迁移记录

> 本文件记录 HudEX v1 的架构、从 DeskHUD / DockCue 迁移的过程、被删除的旧逻辑、
> macOS 平台限制，以及实测结果。

## 1. 工程结构

```
Package.swift                    SwiftPM，macOS 26，两个 target
Sources/
  HudEXCore/                     纯逻辑，无 AppKit UI，可单元测试
    Models/ProjectModel.swift    HudEXProject / ProjectSection / 状态与内置小节
    Models/ShortTitle.swift      短名生成、稳定 ID
    Parsing/MarkdownProjectParser.swift   HudEX.md 解析（宽松、带 diagnostics）
    Parsing/MarkdownBlocks.swift          段落 / 列表 / 引用 / 代码块切分
    Parsing/InlineMarkdown.swift          AttributedString(markdown:) 封装 + 图片剥离
    Layout/EdgeLayoutEngine.swift         DockEdge / EdgeSlot / Axis / 溢出 / 数量上限
    Layout/DockGeometryEstimator.swift    Dock 偏好 → 厚度与占用范围（纯函数）
    Style/TagColorPolicy.swift            颜色阈值与相对时间
    Source/DocumentSource.swift           文件签名、解码、默认候选路径
    Source/HudEXTemplate.swift            示例文件
  HudEXApp/                      AppKit 外壳 + SwiftUI 内容
    App/HudEXMain.swift          @main、AppDelegate、NSStatusItem 菜单
    App/HudEXController.swift    唯一协调者：文档 / 几何 / 布局 / 窗口
    Data/Preferences.swift       UserDefaults 偏好
    Data/DocumentStore.swift     载入、发布、失败不清屏
    Data/DirectoryWatcher.swift  FSEvents 目录监听 + 防抖
    Geometry/DockGeometryProvider.swift  几何检测与缓存
    Geometry/ScreenGeometry.swift        NSScreen → 纯值
    Windows/HudEXPanels.swift    NSPanel 工厂、悬停追踪视图
    Windows/EdgePanelController.swift    每个 slot 一个容器面板
    Windows/PreviewPanelController.swift 复用一个简介面板 + 完整窗口控制器
    Views/                       标签、简介、完整窗口、Markdown 渲染
    Settings/                    通用 / 数据源 / 布局 / 外观 / 高级
    Services/SystemServices.swift 开机启动、外部打开、设置窗口
    Diagnostics/                 os.Logger 与性能自测
Tests/HudEXCoreTests/           71 项测试
Examples/HudEX.md               示例数据
script/build_and_run.sh         构建 + 组 bundle + 签名 + 启动
script/generate_assets.swift    图标生成
```

## 2. 从旧项目删除了什么

旧工程（DeskHUD → DockCue）约 7400 行，全部移除，工作区改动已先存到分支
`archive/pre-hudex-wip`（提交 `chore: archive DockCue/DeskHUD work-in-progress`），
需要时 `git checkout archive/pre-hudex-wip` 可取回。

删除的子系统：

| 旧逻辑 | 为什么删 |
|---|---|
| `hud.json` / `hud_*Dock.json` / `config.json` / `bookmarks.json` schema | v1 的数据源是单个 Markdown |
| `deskhudctl` CLI（612 行）与 `DockCueWorkspaceTool` | 只服务于 JSON 工作流 |
| 双 Dock 面板 + 每 slot 一窗 + 桌面大面板 | v1 只有边缘小标签 |
| 自动滚动 / 轮播 / rotation / TimelineRail 分页 | v1 明确不做自动滚动 |
| Liquid Glass（`NSGlassEffectView`）、`.glassEffect`、渐变、阴影、脉冲/弹跳动画 | 标签必须纯色，不做毛玻璃 |
| 60 Hz Dock 跟随、0.15 s 鼠标轮询、2 s 空闲刷新、0.08 s AX 缓存 | 全部换成事件驱动 |
| Accessibility（AXUIElement）Dock 测量与权限申请 | v1 不需要任何 TCC 权限 |
| EventKit / 日历合并 | 与产品定义无关 |
| 竖排文字与 CJK 竖排排版引擎（900+ 行） | 标签是横排短名 |
| 只看 Dock 一侧的固定布局 | v1 之后增加了布局模式（跟随 / 两侧分布 / 固定屏幕边） |
| `hud_context.json` 回写、CLI 分布式通知 | HudEX 不写用户的文件 |
| Metal / Genie shader 与 `.metallib` 打包 | 复杂动画被排除 |
| 旧的 DMG / 安装脚本 / 自签证书流程 | 换成最小可用脚本 |

## 3. 新架构的取舍

### 3.1 没有 SwiftUI App/Scene，只有 SwiftUI 视图

最初按「SwiftUI `MenuBarExtra` + `Settings` scene」实现（这也是最初的首选方案）。
实测发现：**在这种 agent app 里，只要面板里的 SwiftUI 内容更新，SwiftUI 就会重建
应用主菜单并在 run loop observer 里反复刷新**（`scenesDidChange` → `makeMainMenu`），
主线程被占满 —— 表现为鼠标悬停时转圈（beachball），并且窗口 server 收不到几何更新，
所以 Dock 移动后标签也不跟着走（`setFrame` 之后 AppKit 的 `frame` 已经更新，但窗口
server 里仍然停在旧位置）。

因此改成：`@main` + `NSApplication` + AppDelegate（AppKit），菜单栏用
`NSStatusItem` + 原生 `NSMenu`（`menuNeedsUpdate` 只在菜单打开时刷新状态），
设置窗口用普通 `NSWindow` 托管 SwiftUI 表单。**SwiftUI 只负责视图内容**，
不再参与 scene graph。改完后：主线程空闲（`mach_msg` 等待事件），
Dock 三个方向都能跟随，内存从 125 MB 降到 20 MB 以下。

代价：不能使用 `MenuBarExtra(isInserted:)`（改用 `NSStatusItem.isVisible`，
能力相同）与 SwiftUI `Settings` scene（用普通窗口 + 同样的原生控件）。
这是一个由实测决定的偏离，已在代码注释中写明原因。

### 3.2 窗口

* 标签：`NSPanel`，`styleMask = [.nonactivatingPanel, .borderless]`，
  `level = .floating`，`collectionBehavior = [.canJoinAllSpaces,
  .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]`，
  `hidesOnDeactivate = false`，`canBecomeKey = false`（标签本身不需要键盘焦点）。
* 简介窗口：同样配方，但 `canBecomeKey = false`，纯展示、不接受点击。
* 完整窗口：普通 `NSWindow`（titled/closable/resizable），带系统标题栏与按钮。
* 窗口数量：每个 edge slot 一个容器面板（最多 2 个）+ 1 个简介面板 + 1 个完整窗口。
  10 个项目也还是这 4 个窗口对象。

### 3.3 线程模型

文件 I/O 与解析在专用串行队列；Markdown 渲染结果随文档一起在后台生成；
MainActor 只做 UI 与模型发布。文档是值类型，成功解析后整体替换。

## 4. Dock 几何：公开 API 的真相

* 位置（左/右/下）与厚度：`com.apple.dock` 的 `orientation` / `tilesize` /
  `autohide`，以及 `NSScreen.visibleFrame` 保留区（精确，实测 34 pt tile → 54 pt 带）。
* **自动隐藏**：Dock 隐藏时 `visibleFrame` 不再保留空间，因此必须用
  `tilesize + 20` 反推，绝不把隐藏的 Dock 区域当成空闲区域。
* **占用长度（Dock 有多长）**：macOS 26 起，Dock 自己的窗口覆盖整个屏幕
  （CGWindowList 里 layer 20 的窗口 bounds == 全屏），因此无法从窗口列表量出
  Dock 长条的范围。`CGWindowListCopyWindowInfo` 依然保留在代码里（事件驱动、
  30 s 限流），能测到就用，测不到就按「固定图标数 × 图标间距 + 余量」估算，
  并且偏保守（宁可少放标签，也不覆盖 Dock）。
* 因此设置里提供手动校准：Dock 厚度、Dock 占用长度、标签宽高、每屏标签数上限。
  用户固定一次即可，之后不需要任何监测。

## 4b. 后续加入的能力（第二轮迭代）

* **布局模式**：`跟随 Dock` / `Dock 那条边两侧分布` / `固定屏幕边（自选边 + 起点·居中·终点 + 偏移）`。
  固定屏幕边时忽略 Dock 所在边；若与 Dock 同边，仍然避开 Dock 的占用范围。
* **叠放与悬停**：标签像书签一样互相重叠、整体略带倾斜（累计角度），后面的压在前面上面；
  鼠标移到某一张时它轻轻抬起并回正。静止时不跑动画（SwiftUI 只在 `isHovered` 变化时做一次 spring），
  所以空闲成本不变。
* **调色板**：换成一套低饱和、明暗两版的手调颜色，并保留 WCAG 对比度计算自动决定黑/白文字；
  对比度有单元测试兜底（>3.5）。项目里可以用 `颜色：绿色` / `颜色：#4C6FA0` 单独覆盖。
* **设置双向同步**：`HudEX.md` 底部的 `# HudEX 设置` 段由 HudEX 维护，也可人工/AI 修改；
  每个选项是「一行说明 + 一行 `名称：值`」。写入是原子的（临时文件 + 替换），
  1.2 秒防抖，只在真正变化时写；读取时把文件中出现的键应用回应用。
  HudEX 写出来的标签本身也能被读回来（有专门的回归测试），中英文标签都能互读。
* **多语言**：英语 + 简体中文，跟随系统语言（都不是则用英语），设置里可以手动固定；
  `HudEXCore` 持有 `.strings` 资源，`HudEXApp` 通过 `L10n.t` 取用，测试校验两种语言键集一致、
  且代码里用到的键都存在。
* **手动优先**：标签宽高、字号、数量上限的范围扩大到实际可用（宽/高最大 240 pt、字号 8–24 pt、
  数量 0–99），Dock 厚度/占用长度可手动校准。

## 4c. 外观风格（第三轮）

四种风格共用同一套几何，只换绘制：

| 风格 | 标签 | 悬停卡片 | 额外元素 |
|---|---|---|---|
| 拟物（默认） | 卡片 + 1pt 立体高光/暗边、朝向卡片一侧的洞洞 | **标签同色系粉彩纸** + 与文字对齐的横线、圆角 6 | 两端打洞的曲线连接（颜色 = 优先级） |
| 磨砂玻璃 | 纯色 + 一圈亮边 | `.regularMaterial` 半透明、圆角 14 | — |
| 极简 | 无填充 + 1pt 线框 | 无填充 + 线框 | — |

> 早先的「液态玻璃」与「磨砂」看起来几乎一样，已合并成「磨砂玻璃」；
> 文件里旧的 `glass` 值会被自动读成 `frosted`。设置里三个风格各自带一张预览图，
> 不再另设一块总预览。

* **洞洞与连接线**：`Priority` 来自项目里的 `优先级：高/中/低`；洞洞画在标签上（距卡片侧边缘
  6.5 pt，保证两个圆角都露出来），连接线画在卡片所在的窗口里，用三次贝塞尔曲线从标签边缘
  连到卡片近侧边中点。曲线的控制点也参与包围盒计算，所以线永远不会被裁掉。
* **只对拟物生效**：`AppearanceStyle.usesHoleAndConnector` 控制，其他风格完全不画洞洞。
* **横线跟着文字走**：横线不再是整张卡片的背景花纹，而是画在每个小节的正文背后，
  间距与正文行距（22 pt = 12.5 pt 字体 × 1.2 + 7 行距）一致，所以一条线正好托住一行字。
* **纸张跟着标签走**：`PaperPalette` 取标签颜色的**色相**，用极低饱和度、高亮度生成粉彩纸
  （浅色 #F7EAC6 这类，深色模式也保持在 0.86 亮度），所以棕色标签弹出暖黄纸、绿色标签弹出薄荷纸，
  文字永远用黑色；小节标题用 `softInk`（墨与纸的中间色）保证次要但可读。深色纸 + 浅色字试过，
  文字发灰、标题会消失，已放弃。

### 卡片尺寸与内容（第三轮修正）

* 卡片大小**完全由 Markdown 决定**：`PreviewModel` 按文件顺序渲染**所有**小节
  （不再只取 当前/下一步/最新对话），宽度按内容测量并夹在 240–420 pt，高度按内容测量；
  只有当整张卡片高于屏幕时，才从尾部减少小节并显示“其余内容在完整窗口”一行。
* 连接线**两端都打洞**：起点用 `paintedEdgePoint()` 精确取「标签朝向卡片那条边、在中心线上的点」——
  它包含旋转与悬停位移，所以线端和标签边缘完全重合（用包围盒会差 1–1.5 pt，就是之前那点缝隙）；
  标签内部再画一小段短线把洞口连到边缘。终点是卡片纸张**内部**的另一个洞（`cardHoleInset = 11`），
  不再骑在卡片边缘上凸出一个点。
* 线永远是**平滑但各不相同**的曲线：控制点位置（0.22–0.40 / 0.62–0.80）与侧向偏移
  （幅度 5–14、方向 ±、单弧或 S 形）由**项目 id 的稳定种子**决定（`PreviewAnchor.StringShape`），
  所以每个项目的线粗细、弯法都不一样，但同一个标签每次悬停都一样，不会抖动。
* **洞洞打在标签边缘上**：洞心精确落在标签朝向卡片那条边的中点，再用标签自身的圆角形状裁剪，
  于是它是一个"半圆缺口"（书的打孔），既不凸出标签、也不需要任何小短线。
  连接线的起点就是同一个点（`paintedEdgePoint`），所以线与洞严丝合缝。
  之前那个看着像"多出一小截"的东西，是画在标签里、伸出边缘 3 pt 的短横线，已经删掉。
* **洞的方向**按边自动取：左边缘→右侧、右边缘→左侧、下边缘→上侧（之前下边缘画反了）。
* **包围盒也用同一个镜像角**：标签视图在翻转坐标里旋转，所以屏幕上的 AABB 要用 `-θ` 计算
  （`screenRotation(of:)`）。之前包围盒按 `+θ` 算，导致标签堆最上面那一张的顶部被窗口裁掉。
  现在有测试遍历三种边 × 七个角度 × 悬停与否，用"视图实际画出来的四个角"反查包围盒，
  确认没有任何一角越出面板（把这个符号改回去，测试会立刻报 12 处失败）。
* **画出来的位置 = 算出来的位置**：`EdgeLayoutEngine.drawnPoint(...)` 把"标签视图实际施加的变换"
  （绕被钉住那条边的中点旋转、再朝卡片滑动）写成同一个函数，`paintedEdgePoint` 只是它取边缘中点。
  之前屏幕坐标与 SwiftUI 翻转坐标混用，导致垂直项符号相反：旋转过的标签上，线会偏几 pt
  （下边缘还叠加了悬停方向写反，共偏约 9 pt）。现在有测试遍历三种边 × 五个角度 × 悬停两种状态，
  断言线端与"视图画出来的边缘"完全重合。
* **倾斜方向按边镜像**（`rotationSign(for:)`）：三条边上标签的倾斜看起来方向一致，
  都是"顺着这一排的方向倒"，不会出现某条边反着歪。
* **下边缘标签的标签文字竖排**：下 Dock 时标签是竖长条，文字横着会被裁；现在转 90° 沿书签方向排。

### 静止与悬停（第三轮修正）

* 标签**静止时全部贴在屏幕边缘的同一条线上**（旋转补偿 `alignToEdge`，旋转后外侧边仍然精确落在边上）；
* 悬停时被指到的那张**朝弹窗方向**滑出 `stagger`，其余保持不动——之前是实现成“静止时逐张向内错位、
  悬停时缩回”，方向正好相反，已经改掉；
* 面板包围盒包含这次滑动量，所以滑动时不会被裁。

### 位置算法（唯一实现）

`PreviewAnchor.solve(tagFrame:edge:cardSize:visible:usesConnector:)` 是唯一的弹窗定位实现：

1. 沿 `edge` 的反方向放置卡片（左→右、右→左、下→上），带 12 pt 间距（拟物为 14 pt 给连接线留空间）；
2. 把卡片整体夹进 `visible`（Dock 与菜单栏之外的可用区域），所以永远不会压到 Dock；
3. 洞洞放在标签朝向卡片那一侧的边缘内侧 6.5 pt；
4. 曲线从标签边缘（洞洞边缘）连到卡片近侧中点，控制点按边方向生成；
5. `panelFrame = 卡片 ∪ 曲线包围盒`，并且**强制不让它盖住自己的标签**（否则悬停会闪烁）。

这条算法对四条边、四个角、任何标签尺寸都成立，有单元测试覆盖（`PreviewAnchorTests`）。

### 标签包围盒（修掉“圆角被切掉”）

之前的 bug：面板只按标签的**原始矩形**取并集，而标签会旋转、会向内错位、悬停时还会抬起，
于是滚动到面板外面的部分（右侧两个圆角）被窗口裁掉。现在：

* `TagPlacement` 带 `rotationDegrees` 与 `perpendicularOffset`；
* `EdgeLayoutEngine.panelBounds(for:metrics:edge:)` 计算**旋转后的 AABB + 向内错位 + 一次悬停抬起 + 2 pt 余量**；
* 窗口层直接用这个包围盒开窗（实测：3 个标签时面板从 54×70 变成 68×76，圆角完整）。

## 5. 布局引擎

`EdgeLayoutEngine` 是纯函数：输入屏幕矩形、Dock 矩形、标签尺寸、数量上限，
输出每个标签的屏幕坐标。三种 Dock 位置共用一套逻辑：

| Dock | 主位置 | 溢出位置 |
|---|---|---|
| 左 | 左下角向上 | 左上角向下 |
| 右 | 右下角向上 | 右上角向下 |
| 下 | 左下角向右 | 右下角向左 |

模式为 `两侧分布` 时两个位置平均分配；模式为 `固定屏幕边` 时按锚点在选定边上排布
（居中时先算出这一组标签需要的长度再居中）；选定的边与 Dock 不同时整条边都可用。

* 默认标签厚度 ≤ Dock 厚度（手动指定时按绝对上限约束）；
* 主轴上的长度被限制（默认 ≈ 字号 + 11 pt），字号 9–12 pt；
* 标签之间不重叠，不与 Dock 重叠，不覆盖菜单栏（上边界取 `visibleFrame.maxY`）；
* 主位置放满才用溢出位置，绝不为了填满而两侧同时出现；
* 单元测试覆盖三个方向、三种模式、溢出、数量上限、手动尺寸、叠放、无 Dock 的情况，
  并断言「任意摆放不与 Dock 相交」。叠放模式下标签本来就会互相重叠，
  因此命中测试按 z 序从上层往下找（`placement(at:)`）。

## 6. 数据与可靠性

* FSEvents 监听 `HudEX.md` **所在目录**（同时覆盖「写临时文件再改名」的场景），
  350 ms 防抖；只有「文件签名（mtime + size + inode）」变化时才读取。
* 文件暂时为空 / 正在写入 / 格式损坏：保留上一次内容，3 秒后复查一次；
  确实被清空才隐藏标签。解析失败不会清屏，也不会崩溃。
* 只读取 UTF-8（其次 GB18030、Latin-1）；UTF-16 仅在带 BOM 时尝试，
  避免把普通文本解成乱码。
* 单文件上限 4 MB，超过就跳过并提示。

## 7. 权限、网络、启动项

* **不需要任何 TCC 权限**：不使用 Accessibility、Screen Recording、EventKit、网络。
* 开机启动：`SMAppService.mainApp.register()/unregister()`（macOS 13+），
  设置页读取的是系统 `status`，不是自己存的 bool。
* Bundle 为 `LSUIElement = true`，正常运行没有 Dock 图标；关闭菜单栏图标后，
  右键标签 → 设置… 或再次打开 HudEX.app 都能回到设置窗口。

## 8. 实测结果

见本文件末尾的「验证记录」，包含：

* Dock 左 / 右 / 下三种方向的标签位置（窗口列表实测）；
* 自动隐藏、Dock 尺寸变化、空文件、原子替换、损坏 Markdown；
* 空闲 5 分钟的 CPU / 内存 / 网络 / 唤醒；
* 71 项单元测试结果。

## 8b. 开发用的自检工具

* `HUDEX_SNAPSHOT=<目录>`：把 HudEX 自己的每个面板窗口用 `NSView.cacheDisplay` 渲染成 PNG，
  并额外输出一张 **scene** 合成图（把标签面板与卡片面板按屏幕坐标画到同一张画布上）——
  只有这样才能检查"线和洞到底接上没有"，因为它们在两个不同的窗口里
  （渲染自己的视图不需要任何屏幕录制权限；macOS 26 已经移除 `CGWindowListCreateImage`）。
  用于在看不到屏幕的情况下核对标签、卡片、连接线的实际样子。
* `HUDEX_TRACE=<文件>`：把布局计算（边、厚度、每个标签的矩形、设置段读写）落到一行行文本里。
* **单实例保护**：启动时如果已有另一份 HudEX 在跑，就把前台交给它并退出——
  两个实例会各自把设置写回同一个 `HudEX.md`，互相覆盖（这个坑真的踩到过）。

## 9. 已知限制

1. **Dock 长度无法精确测量**（macOS 26 全屏 Dock 窗口）。默认估算偏保守，
   极端情况下（Dock 图标非常多）可能提前进入溢出位置。可在设置里手动校准。
2. 标签只显示在「Dock 所在的那块屏幕」，暂不支持多屏同时显示。
3. 标签仍然可能被用户自己的全屏 App 覆盖在极少数窗口层级情形下；
   当前用 `.floating + fullScreenAuxiliary + canJoinAllApplications`，
   实测在普通窗口与全屏 Space 中可见。
4. 叠放时被压住的标签只能看到露出的部分；如果更希望一眼看全，可在「设置 › 外观」
   关掉叠放（或把重叠比例调小）。
5. 液态玻璃风格里的“卡片互相粘合”是紧凑对齐 + 连续圆角 + spring 过渡的近似，
   不是 Metal metaball 融合——真正的融合需要持续渲染，与“静止时不消耗”冲突。

## 10. 后续可以做的（本次未做，按用户要求先固定 v1）

* 用 Accessibility 精确测量 Dock（用户已明确 v1 不申请权限）。
* 多显示器分别显示；标签拖拽排序；从文件里给某个标签加提醒（目前的“提醒”由颜色阈值表达）。
* 真正的 first-run 引导（当前是设置页里的「创建示例文件」）。

## 11. 验证记录

（构建与测试命令、实测数字见 `docs/verification.md`。）
