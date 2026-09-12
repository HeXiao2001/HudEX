# Changelog

## 1.0.0 — 2026-09-12

First public release. HudEX is a rewrite of the earlier DeskHUD/DockCue
experiments into one idea: *always present, almost invisible* — a few solid
colour bookmarks along the edge of the screen that show the recent context of
the projects you are juggling.

**The bookmarks**

* One bookmark per project, taken from a single Markdown file (`HudEX.md`).
  `##` is a project, `###` is a section; `当前 / 下一步 / 最新对话 / 备注`
  (or `Current / Next / Latest conversation / Notes`) are recognised, any other
  heading works too.
* Per-project `短名 / 状态 / 更新 / 顺序 / 颜色 / 优先级` (and the English
  spellings). Colour follows the update date; priority colours the punched hole.
* Smoothly stacked like bookmarks, with a configurable overlap, slant and layer
  offset. Nothing animates while the pointer is still.

**The hover card**

* One reusable panel, resized to the content the file actually contains: every
  section in the file is drawn, in file order.
* Three styles — skeuomorphic coloured paper with ruled lines and a string that
  leaves a punched hole, frosted glass, and a minimal outline. Each style
  previews itself in Settings.
* Bounded to the screen: never clipped, never over the menu bar.

**The rest**

* Three layout modes: follow the Dock, both sides of the Dock's edge, or a fixed
  screen edge. Bookmarks are never wider than the Dock and never cover it.
* By default bookmarks live in exactly one place; the overflow slot is opt-in.
* Settings live in a documented block at the bottom of the same Markdown file —
  every option has a one-line guide above it, and edits round-trip both ways.
* English and Simplified Chinese, following the system language.
* No permissions, no network, no polling: measured idle cost ≈0 % CPU,
  ≈16 MB, ≈0.1 wakeups/s.
* Menu-bar app (Launchpad-visible, no Dock icon), optional launch at login.

**Install**

`HudEX-1.0.0.pkg` (Installer) or `HudEX-1.0.0.dmg` (drag to Applications).
HudEX is ad-hoc signed rather than notarised, so the first launch asks for one
confirmation: right-click the app → **Open** → **Open**.
