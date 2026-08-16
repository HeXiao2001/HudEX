# 系统性修复：Dock 跟随、面板宽度对齐、设置界面重设计

## 问题与根因

1. **放大跟随失效**：`estimatedDockExclusionRect`/`estimatedVerticalDockExclusionRect` 的 AX 路径命中后直接 return，`mouseLocation` 被完全忽略——鼠标放大区扩展估算只在"无辅助功能权限"的兜底路径生效。**授权 Accessibility 后跟随反而失效**（Dock 的 AX 矩形在图标放大时基本不动）。
2. **面板宽度错位**：厚度公式 `max(54, band-10)` 与条带居中导致面板（x=5..59）和 Dock 实际视觉矩形（x=10..53）既不对齐也不贴合。
3. **设置界面**：窗口 560×460 / hosting 560×480 / TabView 540×420 尺寸互相矛盾；每次刷新整棵 SwiftUI 树重建丢状态；无分组无图示、纯英文。

## 修改内容

### 1. 修复放大跟随（HUDWindowManager.swift）
- 两个排除矩形方法的 AX 路径：命中 AX 后**不再忽略鼠标**——把 AX 矩形与"鼠标周围放大区"（半径 `max(210, band*2.4)`）做**并集**再 clamp 到屏幕，兜底路径保持不变。底部（X 轴）和侧边（Y 轴）各自处理；垂直路径补上缺失的 `screenFrame.contains(mouse)` 守卫。

### 2. 面板宽度自动对齐 + 可微调
- `HUDModels.swift`：新配置 `sidePanelExtraWidth: Double = 12`（0–40），带解码默认值与测试。
- `frameForVerticalDockSlot`：厚度改为 **Dock 视觉宽度（AX 矩形宽，兜底用条带宽）+ sidePanelExtraWidth**，clamp [54, 160]；x 改为按 Dock 视觉矩形居中对齐（AX midX，兜底条带中心）。不再借用 `config.height` 当厚度。

### 3. 设置界面重设计（用户已选：侧边栏 + 图示 + 中英双语）
- **SettingsWindowController.swift**：窗口 720×520、可缩放（最小 640×460）；`updateConfig` 改为更新既有 `NSHostingView.rootView`（不再整树重建、保留选中状态）；修掉尺寸不一致。
- **SettingsView.swift 重写**：
  - 左侧栏导航（4 页：布局 / 外观 / 内容 / 高级），右侧详情，仿系统设置；
  - 新组件 **DockLayoutPreview** 布局示意图：迷你屏幕 + 按真实方位画的 Dock + 两块面板（Now Queue / Context Card）高亮，实时反映开关/背景/文字模式（禁用面板虚线灰显）；
  - 选项重组进分组 Section（图标+标题+说明文字），"侧面板加宽"步进器放布局页；
- **本地化**：`Sources/DeskHUDApp/Resources/Localizable.xcstrings`（英文 key + zh-Hans 翻译），设置全部文案 + 菜单栏菜单项走 String Catalog，跟随系统语言；`Package.swift` 声明 resources，`build_and_run.sh`/`make_release.sh` 打 bundle 时补拷 SPM 的 `*.resources`（Bundle.module）进 Contents/Resources——这是手工组装 bundle 的关键配套改动。
- 抽出 `Windowing/DockSideDetector.swift`（DockSide 枚举 + 屏幕检测静态方法），窗口管理与示意图共用，消除重复。

### 4. 验证与打包（不发布）
- `swift build` + 测试（新增 sidePanelExtraWidth 解码测试）；
- 截图验证 HUD 面板新宽度对齐效果；设置窗口由你上手验收；
- 重新打包 `v0.2.1` DMG（等你测试通过后，再 gh auth login + 发布）。

## 提交顺序
1. `fix: union AX dock rect with mouse magnification zone so follow works with Accessibility on`
2. `feat: side panels auto-align to Dock visual width with configurable extra margin`
3. `feat: settings redesign — sidebar navigation, live layout preview, zh/en localization`
4. `chore: bundle SPM resources into app bundle, sync schema`
5. 打包 v0.2.1（本地）

## 风险
- SPM String Catalog 资源在手工组装 .app 里的加载路径（Bundle.module）是主要技术风险，脚本改动会重点验证；若 xcstrings 在 bundle 里不生效，回退为内置 JSON 词典方案（不改变用户可见效果）。