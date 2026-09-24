# HudEX

[English](README.en.md) · **中文**

**一直存在，尽可能不打扰。**（Always present, almost invisible.）

HudEX 在你屏幕边缘空出来的地方——通常是 Dock 旁边——放几个纯色小书签，
每个书签是一个你正在推进的项目。鼠标悬停时弹出一张小卡片，告诉你这个项目
做到哪了、下一步是什么、最近一次聊的是什么。

这些内容与提醒事项全部来自**一个 JSON 文件**，你自己写、AI 写都行。

![HudEX 总览：悬停卡片、Dock 旁的书签、布局设置](docs/images/overview.jpg)

*Dock 下方书签的悬停卡片 · Dock 在左侧时的书签与卡片 · 布局设置（这里把书签固定到屏幕右边）· 书签特写*

## 它是什么

一个常驻的「近期项目上下文」小显示器，适合任何同时推进几件事的人：
一次上线、一份报告、一个副业、一张书单、一间正在收拾的房间。

它回答四个问题，不用你打开任何东西：

1. 我现在手上有哪些项目？
2. 每个项目做到哪了？
3. 下一步要做什么？
4. 哪一个已经放了很久没动？

它把项目上下文显示在屏幕边缘，并与 Apple 提醒事项同步具体任务。

## 快速开始

**安装（推荐用拖拽版）**

1. 从 [GitHub Releases 下载 `HudEX-1.0.6.dmg`](https://github.com/HeXiao2001/HudEX/releases/download/v1.0.6/HudEX-1.0.6.dmg) 并打开，把 **HudEX** 拖到窗口里的 **Applications** 快捷方式上。
2. **第一次打开会被系统拦下来**——因为 HudEX 没有做 Apple 公证签名（个人开发者没有付费账号），
   这一步只需要做一次：
   - 直接双击 HudEX 会看到「Apple 无法验证此 App 是否包含恶意软件」；
   - 打开 **系统设置 → 隐私与安全性**，往下滚到「安全性」；
   - 会看到一行 *「已阻止使用 HudEX，因为来自身份不明的开发者」*，点右边的 **仍要打开**；
   - 输入你的开机密码（或 Touch ID）确认，然后再点一次 **打开**。
3. 之后就能正常启动了。HudEX 只做**本地 ad-hoc 签名**，没有任何网络请求，
   默认不需要系统权限；只有启用 Reminders 同步时，才会请求完整的提醒事项访问权限。
   不需要辅助功能、屏幕录制或通知。系统设置里那条
   「已阻止」的记录在成功打开后就不再出现。
4. 第一次启动时 HudEX 会自己创建文件
   （`~/Library/Application Support/HudEX/HudEX.json`）并打开「开始使用」页，
   告诉你文件在哪里、选哪种外观。

> 想放在别处？在「开始使用」页点「选择文件…」选你自己的 JSON 文件即可——
> macOS 会为该文件夹问一次，答不答应由你决定。


## 一个 JSON 文件

HudEX 默认使用 `~/Library/Application Support/HudEX/HudEX.json`。`projects`、`reminders` 和 `settings` 都在这一个文件中。旧版 `HudEX.md` 可在 **设置 → 数据源** 一次性迁移：保留项目和设置，写入 `.json` 后删除旧 `.md`。迁移前请自行备份需要留存的版本。

```json
{
  "schemaVersion": 6,
  "sourceID": "stable-source-uuid",
  "projects": [{
    "id": "website-redesign",
    "title": "网站改版",
    "shortTitle": "WEB",
    "status": "进行中",
    "sections": [{ "id": "next", "title": "下一步", "body": "完成移动端断点并交给团队评审" }]
  }],
  "reminders": [
    { "id": "stable-task-uuid-1", "projectID": "website-redesign", "title": "完成移动端断点" },
    { "id": "stable-task-uuid-2", "projectID": "website-redesign", "title": "提交团队评审", "dueDate": "2026-10-01T09:00:00Z" }
  ],
  "settings": {}
}
```

Apple 提醒事项只使用一个名为 `HudEX` 的列表。项目标签仍由 JSON 的 `projects` 定义，提醒用 `projectID` 与项目关联；没有 `projectID` 的提醒是独立任务。一个项目可以有多条提醒。有明确时间的 `dueDate` 会设置提醒时间和系统闹铃。两边的新增、修改、完成与删除会同步；旧版 `HudEX · Inbox`、`HudEX · Synced` 和项目列表中的任务会迁入单一列表，空列表会清理。直接在 Apple 提醒事项新建的任务默认是独立任务；若标题以唯一的“项目短名 · ”开头，HudEX 会将它关联到该项目。

提醒还支持 `startDate`、`location`、`priority`（0 无、1 高、5 中、9 低）、`earlyReminderMinutes`、`repeatRule`（如 `{"frequency":"weekly","interval":1}`）以及带坐标的 `locationAlert`（`title`、`latitude`、`longitude`、`radiusMeters`、`trigger` 为 `arrive` 或 `leave`）。这些字段与系统提醒事项双向同步，悬停卡片和项目详情会显示位置与优先级。`isFlagged`、`tags` 可以保存在 JSON 中，但 Apple 公开的 EventKit 接口暂不支持同步原生旗标和标签。桌面上的 Apple 提醒事项组件请选择 `HudEX` 列表。

应用创建的 JSON 会附带完整 `aiInstructions`：让 AI 从「下一步」和明确承诺中提取具体行动，使用新 UUID 创建提醒，保持已有 ID 和同步元数据，不猜测截止时间，也不把一般备注变成任务。项目内容和提醒都写回同一个文件。旧版 Markdown 示例仍在 [`Examples/HudEX.md`](Examples/HudEX.md)，仅用于迁移参考。

把现有文件交给 AI 编辑时，可以直接使用这段提示词：

> 请只编辑我提供的 HudEX.json，并遵守其中的 aiInstructions。整理 projects 的内容，从每个项目的「下一步」和明确承诺中提取可执行的提醒事项，写入顶层 reminders 数组。每个提醒用对应项目的 id 作为 projectID；一个项目可以有多条提醒。仅在原文给出明确日期和时间时填写 ISO 8601 dueDate/startDate，不能猜测时间；有明确地点时写 location，只有知道精确坐标才写 locationAlert。明确提到优先级、提前提醒或重复规则时，分别写 priority、earlyReminderMinutes、repeatRule。新增提醒使用新的 UUID；修改已有提醒时保留 id、sourceID、reminderIdentifier、modifiedAt 和 syncFingerprint。保留现有 settings、项目章节及其他未要求修改的内容。输出完整、有效的单个 JSON 文件，不要另建提醒事项文件。

## 三种外观风格

在 **设置 → 外观** 里选择，每个选项自己就是预览图。

| 拟物（默认） | 磨砂玻璃 | 极简 |
|---|---|---|
| ![拟物](docs/images/style-skeuomorphic.png) | ![磨砂](docs/images/style-frosted.png) | ![极简](docs/images/style-minimal.png) |
| 标签同色的纸张卡片、带横线；标签上的洞洞用一条曲线连到卡片。 | 半透明材质，任何背景下文字都清楚。 | 只有线框。 |

每个项目的连接线都不一样——方向、弧度甚至偶尔的 S 形，都由项目名的稳定哈希决定，
所以同一个标签每次悬停都一样，静止时也不播放任何动画。

## 内容与设置都在同一个文件

你可以自己或让 AI 编辑 `HudEX.json`。项目内容、提醒事项和设置都在其中；文件也可以放到你自己的云盘同步目录。设置使用顶层 `settings` 对象，在应用里修改后会写回同一文件。HudEX 不调用 AI 服务，也不内置邮箱连接。

## 标签放在哪

| Dock 位置 | 主位置 | 溢出位置 |
|---|---|---|
| 左 | 左下角，向上排 | 左上角，向下排 |
| 右 | 右下角，向上排 | 右上角，向下排 |
| 下 | 左下角，向右排 | 右下角，向左排 |

三种模式：**跟随 Dock**（默认）、**Dock 那条边两侧分布**、
**固定屏幕边**（自选左/右/下 + 起点/居中/终点 + 偏移）——所以 Dock 在左边时，
标签也可以放到屏幕右边。

标签永远不会比 Dock 厚、不会压住 Dock、也不会盖住菜单栏。

**默认只在同一个地方显示**：放不下的项目会在设置里提示数量，而不会跑到边上另一处去画。
如果确实想用同一条边的两端，可以在 设置 → 布局 里打开「允许使用第二个溢出位置」
（或者在文件里写 `溢出位置：on`）。

## 权限、网络、资源占用

* **权限按需申请**：Dock 标签不需要辅助功能或屏幕录制；只有启用 Reminders 同步时，才申请提醒事项完整访问权限。不联网。Dock 的位置与厚度来自系统保留区和 Dock 偏好设置，屏幕变化通过系统通知获知。
* **没有轮询**：除了午夜那次（刷新颜色）和卡片在屏时每分钟一次，没有任何定时器。
* 实测空闲占用：**≈0% CPU、≈16 MB 内存、≈0.1 次唤醒/秒、0 网络请求**。

## 明确不做的事

不调用 AI、不接入 HudEX 自己的云文件同步、不内置编辑器、不用 WebView/Electron/Node、不存历史、
自动滚动、不做进度条、不加载图片附件、没有手机端。
「编辑」就是用你系统默认的 JSON 编辑器打开 `HudEX.json`，
同步交给同步客户端——文件只要在本地是新的就行；内容由谁写、怎么写，也完全由你决定
（手写、让 AI 整理、或者用你已有的笔记流程）。

## 工程结构

```
Sources/HudEXCore     解析 / 布局 / 颜色 / 文件签名 —— 纯逻辑，有单元测试
Sources/HudEXApp      AppKit 外壳（面板、状态栏菜单、设置窗口）+ SwiftUI 视图
Tests/HudEXCoreTests  123 项测试：解析、布局模式、叠放、调色板、双向同步、本地化
Examples/             示例文件（英文 + 中文）
docs/                 设计说明与验证记录
script/               构建 / 安装 / 资源脚本（script/demo.swift 可以自动扫过标签，方便录演示）
```

```bash
swift test                # 123 项测试
./script/build_and_run.sh # 构建 + 组 bundle + 签名 + 启动
./script/install.sh       # 安装到 /Applications
```

## 许可

尚未选择——发布前请先补一个。
