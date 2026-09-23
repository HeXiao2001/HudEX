# HudEX

[English](README.en.md) · **中文**

**一直存在，尽可能不打扰。**（Always present, almost invisible.）

HudEX 在你屏幕边缘空出来的地方——通常是 Dock 旁边——放几个纯色小书签，
每个书签是一个你正在推进的项目。鼠标悬停时弹出一张小卡片，告诉你这个项目
做到哪了、下一步是什么、最近一次聊的是什么。

这些内容全部来自**一个 Markdown 文件**，你自己写、AI 写都行。

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

它**不是**任务管理器、日历、看板、笔记库，也不是 AI Agent——刻意不做这些。

## 快速开始

**安装（推荐用拖拽版）**

1. 下载 **`HudEX-1.0.4.dmg`** 并打开，把 **HudEX** 拖到窗口里的 **Applications** 快捷方式上。
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
   （`~/Library/Application Support/HudEX/HudEX.md`）并打开「开始使用」页，
   告诉你文件在哪里、选哪种外观。

> 想放在别处？在「开始使用」页点「选择文件…」选你自己的 Markdown 文件即可——
> macOS 会为该文件夹问一次，答不答应由你决定。


## 文件格式

```markdown
## 网站改版                  ← 一个 `##` 就是一个项目

短名：WEB                    ← 可选：书签上显示的字
状态：进行中                 ← 进行中 / 暂停 / 归档 / 已完成
更新：2026-09-12 16:30       ← 决定书签颜色
优先级：高                   ← 可选：给标签上的洞洞上色

### 当前                     ← 小节；当前 / 下一步 / 最新对话 / 备注 会被识别
新版首页在评审中，站点其他页面还是旧版。

### 下一步
补齐移动端断点，然后把文案交给团队。

### 最新对话
首页布局评审
```

* `###` 标题完全自由：上面四个会被识别并显示在悬停卡片里，其他标题
  （比如 `### 数据来源`）会显示在「完整窗口」中。
* 项目级可选字段还有：`顺序：1`（决定标签先后）、
  `颜色：#4C6FA0` 或 `颜色：绿色`（单独覆盖标签颜色）。
* 英文键名同样可用（`short:` `status:` `updated:` `order:` `color:` `priority:`），中英文可以混写。
* 只处理文字和普通 `http(s)` 链接；图片、附件、嵌入一律不加载、不下载、不渲染。
* 没写 `短名` 的项目会自动生成缩写（`GeoRule` → `GR`，`Reading list` → `RL`）。

示例文件：[`Examples/HudEX.md`](Examples/HudEX.md)（英文）·
[`Examples/HudEX.zh.md`](Examples/HudEX.zh.md)（中文）

### Apple 提醒事项同步

在 **设置 → 数据源 → Apple 提醒事项同步** 中，把当前文件原地转换成版本化 JSON；路径、项目和现有设置会保留。JSON 是项目与提醒的唯一主文件，默认自动与 Apple 提醒事项双向同步，也可关闭自动同步后手动触发。

```json
{
  "schemaVersion": 2,
  "sourceID": "a-stable-source-uuid",
  "hudexVersion": "1.0.4",
  "aiInstructions": [
    "This file is the source of truth for HudEX projects and reminders.",
    "Preserve schemaVersion, sourceID, stable project IDs, and stable reminder IDs when editing this file.",
    "Keep project reminders in each project's reminders array; edit or delete them by their stable id.",
    "HudEX uses one Apple Reminders list named 'HudEX · Synced'. Prefix native reminder titles with the project's shortTitle and ' · ' to assign them to a project.",
    "To create a project from Apple Reminders, add a reminder titled '@project SHORT | Project title'; SHORT must be unique. HudEX writes the new project to this file before consuming that command reminder.",
    "Give every project a distinct shortTitle so reminders can be assigned unambiguously.",
    "Preserve settings and project sections. HudEX updates hudexVersion during synchronization."
  ],
  "projects": [{
    "id": "website-redesign",
    "title": "网站改版",
    "shortTitle": "WEB",
    "status": "进行中",
    "sections": [{ "id": "next", "title": "下一步", "body": "完成移动端断点" }],
    "reminders": [{
      "id": "a-stable-uuid",
      "title": "交付移动端断点",
      "dueDate": "2026-10-01T09:00:00Z",
      "isCompleted": false
    }]
  }]
}
```

Reminders 中只维护一个 `HudEX · Synced` 列表，提醒标题显示为「项目短名 · 提醒标题」。用此前缀新增提醒可指定项目，每个项目可以有多个提醒。创建项目时新增 `@project 短名 | 项目名称` 提醒（短名需唯一）；HudEX 会先把项目写入主文件，再移除这条命令。两边的新增、修改、完成和删除会自动同步，同一条提醒两边都改动时按修改时间合并。切换主文件后，旧文件对应的 HudEX 提醒会清理；早期版本生成的项目列表会迁移并删除。普通 Reminders 列表不会被 HudEX 管理。转换前建议备份。

JSON 顶层的 `schemaVersion` 表示文件格式，`hudexVersion` 表示最后同步它的 HudEX 发布版本。`aiInstructions` 是给后续 AI 编辑者的持续规则；请保留 `sourceID`、项目 ID 和提醒 ID，并确保项目短名唯一。

## 三种外观风格

在 **设置 → 外观** 里选择，每个选项自己就是预览图。

| 拟物（默认） | 磨砂玻璃 | 极简 |
|---|---|---|
| ![拟物](docs/images/style-skeuomorphic.png) | ![磨砂](docs/images/style-frosted.png) | ![极简](docs/images/style-minimal.png) |
| 标签同色的纸张卡片、带横线；标签上的洞洞用一条曲线连到卡片。 | 半透明材质，任何背景下文字都清楚。 | 只有线框。 |

每个项目的连接线都不一样——方向、弧度甚至偶尔的 S 形，都由项目名的稳定哈希决定，
所以同一个标签每次悬停都一样，静止时也不播放任何动画。

## 内容归你管

文件是你的：可以自己手写，也可以让 AI 实时或定期帮你整理，还可以把它放在任意
一个会被云服务（iCloud 云盘、OneDrive、Dropbox、WebDAV、git 仓库……）同步的
目录里。Markdown 模式下 HudEX 只读项目内容；JSON 模式下提醒事项同步会更新任务字段。
两台 Mac 也可以指向同一份同步过来的文件。

Markdown 模式下 HudEX 只写下面那段设置；JSON 模式下还会更新提醒数据与同步元信息。

## 设置就写在 Markdown 里

`HudEX.md` 最下面是一段自带说明的设置段：每个选项**上面一行说明、下面一行 `名称：值`**。

```markdown
# HudEX 设置

> 外观风格：skeuomorphic（拟物）/ frosted（磨砂）/ minimal（极简）
外观风格：skeuomorphic

> 标签伸进屏幕的宽度，单位 pt；0 = 跟随 Dock 厚度
标签宽度：0
```

改文件里的值，HudEX 立刻生效；在应用里改了设置，HudEX 也会写回这一段
（1.2 秒防抖、原子替换，上面的项目内容一字不动）。所以这个文件完全可以
由人或者 AI 来驱动：布局、颜色、阈值、数量上限，连风格都能改。

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

不调用 AI、不接入 HudEX 自己的云同步、不内置编辑器、不用 WebView/Electron/Node、不存历史、
自动滚动、不做进度条、不加载图片附件、没有手机端。
「编辑」就是「用你系统的默认 Markdown 程序打开 `HudEX.md`」，
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
