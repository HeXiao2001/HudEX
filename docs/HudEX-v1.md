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

## 9. 已知限制

1. **Dock 长度无法精确测量**（macOS 26 全屏 Dock 窗口）。默认估算偏保守，
   极端情况下（Dock 图标非常多）可能提前进入溢出位置。可在设置里手动校准。
2. 标签只显示在「Dock 所在的那块屏幕」，暂不支持多屏同时显示。
3. 标签仍然可能被用户自己的全屏 App 覆盖在极少数窗口层级情形下；
   当前用 `.floating + fullScreenAuxiliary + canJoinAllApplications`，
   实测在普通窗口与全屏 Space 中可见。
4. 叠放时被压住的标签只能看到露出的部分；如果更希望一眼看全，可在「设置 › 外观」
   关掉叠放（或把重叠比例调小）。

## 10. 后续可以做的（本次未做，按用户要求先固定 v1）

* 用 Accessibility 精确测量 Dock（用户已明确 v1 不申请权限）。
* 多显示器分别显示；标签拖拽排序；从文件里给某个标签加提醒（目前的“提醒”由颜色阈值表达）。
* 真正的 first-run 引导（当前是设置页里的「创建示例文件」）。

## 11. 验证记录

（构建与测试命令、实测数字见 `docs/verification.md`。）
