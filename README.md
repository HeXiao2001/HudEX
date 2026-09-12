# HudEX

**Always present, almost invisible.**

HudEX 是常驻在 macOS 屏幕边缘的「近期项目上下文显示器」。
它只在 Dock 没有占用的边缘空间里放几个纯色小标签，鼠标悬停时才展开简介。

它不是任务管理器、不是看板、不是知识库、不是 AI：只是让你同时推进几个项目时，
随时知道「每个项目最近做到哪、下一步做什么、最近一次重要的对话叫什么」。

## 一分钟上手

1. 在 Obsidian / 任意编辑器里写好一个 `HudEX.md`（格式见下）。
2. 打开 HudEX，在「设置 › 数据源」里选中这个文件。
3. 完成。之后 HudEX 只做两件事：读这个文件、在边缘显示标签。

默认会依次尝试：`~/Documents/HudEX.md`、`~/Library/CloudStorage/OneDrive-*/HudEX.md`、
`~/Desktop/HudEX.md`。也可以在设置里指定任意路径。

## 数据格式

```markdown
# HudEX

## GeoRule

短名：GR
状态：进行中
更新：2026-09-12 16:30

### 当前

2019-01、2019-02、2019-12 三期正式数据已经开始运行。

### 下一步

检查规则稳定性、K 数量和 h 是否触及搜索边界。

### 最新对话

模型发展总结20260907

### 备注

- 需要整理实验脚本最新版本
```

* `##` 是一个项目；`#` 是可选的文档标题。
* 项目下面可以有 `短名：`、`状态：`、`更新：`；短名不写就自动生成。
* 内置小节：`当前` / `下一步` / `最新对话` / `备注`。
* 其他 `### 标题` 也允许存在，会在「完整窗口」里原样显示。
* 图片、附件、嵌入一律不加载；普通网页链接可以点击，交给系统浏览器打开。

标签颜色就是状态：绿（最近更新）、黄（需要关注）、橙（开始变旧）、灰（长时间未更新）、
蓝灰（暂停 / 归档 / 已完成）。阈值可以在设置里调整。

## 交互

| 操作 | 结果 |
|------|------|
| 鼠标悬停标签 | 弹出简介窗口（项目名 / 当前 / 下一步 / 最新对话） |
| 右键标签 | 打开项目完整内容、打开 Markdown 文件（编辑）、重新载入、设置…、退出 |
| 菜单栏图标 | 同样的入口；可以随时关掉，右键标签仍然能进设置 |
| 再次打开 HudEX.app | 直接打开设置窗口（菜单栏图标关掉后的第二条恢复路径） |

## 明确不做的事

不联网、不调用任何 AI、不内置编辑器、不用 WebView / Electron / Node、不存历史、
不做自动滚动和轮播、不显示进度条、不加载图片附件、不修改 Dock。

编辑就是「用系统默认程序打开 `HudEX.md`」——你在 Obsidian 里改，HudEX 自己刷新。

## 权限

**不需要任何 TCC 权限**：不使用辅助功能、不使用屏幕录制、不联网。
Dock 的位置和厚度来自系统保留区和 Dock 的偏好设置，屏幕变化通过系统通知获知，
标签尺寸和数量都可以在设置里手动固定，因此也不需要持续监测 Dock。

## 构建

```bash
./script/build_and_run.sh              # 构建 dist/HudEX.app 并启动
./script/build_and_run.sh --no-launch  # 只构建
./script/build_and_run.sh --release    # Release 构建
swift test --disable-sandbox           # 单元测试（71 项）
```

要求 macOS 26 / Xcode 26。工程是纯 SwiftPM（`HudEXCore` + `HudEXApp`），
app bundle 由脚本组装（`LSUIElement`，无 Dock 图标）。

## 结构

```
Sources/HudEXCore    解析 / 布局 / 颜色 / 文件签名 —— 纯逻辑，可单元测试
Sources/HudEXApp     AppKit 窗口与状态栏 + SwiftUI 内容视图
Tests/HudEXCoreTests 71 项测试：解析、布局、颜色、文件监听、稳定 ID
Examples/HudEX.md    示例数据文件
```

设计说明与迁移记录见 `docs/HudEX-v1.md`。
