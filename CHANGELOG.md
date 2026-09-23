# Changelog

## 1.0.3 — 2026-09-23

Apple Reminders is now an additional entry point for project tasks.

* Convert the current project file in place to versioned JSON while preserving
  its path, projects, sections and settings.
* Sync each HudEX project with its own Reminders list. Reminder titles, notes,
  due dates, completion, priority, creation and deletion sync in both directions.
* Request full Reminders access only when the user starts synchronization.
* Keep Markdown sources supported for existing workflows.

## 1.0.2 — 2026-09-13

The bookmarks can now stay out of the way.

* **Only on the main desktop** (Settings → General → Desktop, on by default): the
  bookmarks stay on the desktop they were created on — desktop 1 when HudEX
  starts at login — and never appear over a full-screen app. Turn it off and they
  follow you to every desktop again, as before.
* Settable from the file too: `Main desktop only：on` (or `只在主桌面：on`).

## 1.0.1 — 2026-09-13

Starting up, for real this time, and a first run that explains itself.

**First launch**

* HudEX now writes its own file — `~/Library/Application Support/HudEX/HudEX.md` —
  the first time it runs. That folder belongs to HudEX, so nothing has to be
  authorised. To watch a file somewhere else (Documents, a synced folder, a git
  checkout), pick it yourself: macOS asks for that folder once, and the answer
  is yours.
* Settings opens on a short **Welcome** pane the first time: where the file is,
  whether it parsed, and which look you want (skeuomorphic by default). The pane
  disappears once there is something to show.

**Starting badly is now survivable**

* A launch that never reaches its first six healthy seconds is noticed; two in a
  row and HudEX clears the manual Dock calibration and turns stacking off (never
  touching your Markdown) so it can start again at all.
* A second launch checks with the kernel that the other copy is really alive
  before handing over, so a stale LaunchServices entry can no longer make a fresh
  launch quit instantly.
* The recovery case writes `~/Library/Logs/HudEX/last-launch.txt`, and Settings
  lists any macOS crash reports for HudEX with a button that reveals the folder.

**No permissions, provably**

* Removed the `CGWindowListCopyWindowInfo` probe (a Screen Recording API that
  returned nothing on macOS 26 anyway). The binary now links no permission-gated
  API at all: the Dock's position comes from its public preferences and the
  screen's reserved area.

**Settings that explain themselves**

* The Layout pane leads with a diagram drawn by the real layout engine, plus one
  plain sentence: "Bookmarks appear along the left edge — beside the Dock,
  growing away from it."
* The Source pane says who owns the content: write it by hand, have an AI keep it
  tidy, or keep it in any folder a sync service mirrors. HudEX reads it, and
  writes nothing back except the settings block at the bottom.
* Bookmarks live in one place only by default; the overflow slot is opt-in.
* Style previews use ordinary sample content (SHOP / Shopping list) instead of a
  project name.

**Installation**

* `HudEX-1.0.1.dmg` is the recommended download: drag the app onto the
  Applications shortcut in a plain window, no installer pages.
* `script/make_package.sh` builds both artefacts from one bundle and refuses to
  package a stale or invisible build (`script/smoke_test.sh` launches it and
  checks that it actually appears).

**Fixed**

* The app could launch with no status item, no bookmarks and no windows at all —
  a missing `NSApplicationDelegate` assignment in `main()`. The smoke test above
  is what now stops that from shipping.

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
