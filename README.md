# HudEX

**Always present, almost invisible.**

HudEX puts a handful of solid-colour bookmarks in the free space along the edge
of your screen — normally right next to the Dock. Each bookmark is one project
you are juggling. Hover it and a small card shows where that project stands,
what is next, and the name of the most recent conversation about it.

Everything comes from **one Markdown file** that you — or an AI — can edit.

![HudEX tags and hover card](docs/images/style-skeuomorphic.png)

## What it is

A tiny, always-on display of *recent project context*, for anyone who keeps
several projects moving at once: a launch, a report, a side project, a reading
list, a room you are renovating.

It answers four questions without you opening anything:

1. Which projects am I in the middle of?
2. Where did each one get to?
3. What is the next step?
4. Which one has gone quiet?

It is **not** a task manager, a calendar, a Kanban board, a note archive or an
AI agent — and it deliberately isn't.

## Quick start

```bash
git clone <this repo> && cd HudEX
./script/build_and_run.sh          # builds dist/HudEX.app and launches it
```

Then open **Settings → Source** and pick your `HudEX.md` (or press
*Create Example File*). That's it — HudEX only ever reads and writes that one
file, plus its own settings block at the bottom of it.

Requires macOS 26 and Xcode 26 (SwiftPM only, no Xcode project).

## The file

```markdown
## Website redesign          ← one project per `##` heading

short: WEB                   ← optional: the label on the bookmark
status: active               ← active / paused / archived / done
updated: 2026-09-12 16:30    ← drives the colour
priority: high               ← optional: colours the punched hole

### Current                  ← sections; 当前 / 下一步 / 最新对话 / 备注 are
The new homepage is in review; the rest of the site still uses the old layout.

### Next
Finish the mobile breakpoints, then hand the copy over to the team.

### Latest conversation
Homepage layout review
```

* `###` headings are free-form: the four above are recognised and shown in the
  hover card, any other heading (`### Data sources`, …) renders in the full view.
* Extra per-project keys: `order: 1` (position among the bookmarks),
  `color: #4C6FA0` or `color: teal` (override the bookmark colour).
* Chinese keys work too (`短名：`, `状态：`, `更新：`, `顺序：`, `颜色：`, `优先级：`) —
  the two spellings can even be mixed in one file.
* Only text and ordinary `http(s)` links. Images, attachments and embeds are
  never loaded, downloaded or rendered.
* A project with no `short:` gets an abbreviation derived from its title
  (`GeoRule` → `GR`, `Reading list` → `RL`).

Examples: [`Examples/HudEX.md`](Examples/HudEX.md) (English) ·
[`Examples/HudEX.zh.md`](Examples/HudEX.zh.md) (中文)

## Styles

Pick one in **Settings → Appearance**; each option previews itself.

| Skeuomorphic (default) | Frosted glass | Minimal |
|---|---|---|
| ![skeuomorphic](docs/images/style-skeuomorphic.png) | ![frosted](docs/images/style-frosted.png) | ![minimal](docs/images/style-minimal.png) |
| Coloured paper card with ruled lines; a punched hole joins it to the bookmark with its own little string. | Translucent pane, readable over any background. | Outlines only. |

Every string hangs differently — direction, curve and even the occasional
S-bend come from a stable hash of the project, so the same bookmark always
hangs the same way, and nothing animates while the pointer is still.

## Settings live in the file

The bottom of `HudEX.md` holds a documented settings block — one guide line,
then one `key：value` line per option:

```markdown
# HudEX Settings

> Appearance style: skeuomorphic / frosted / minimal
Appearance style：skeuomorphic

> Tag width into the screen, in points. 0 = follow the Dock thickness
Tag width：0
```

Change a value there and HudEX applies it. Change a setting in the app and
HudEX writes it back (debounced, atomically; your project content above is left
untouched). That makes the file fully driveable by a person or an AI — layout,
colours, thresholds, counts, even the style.

## Where the bookmarks go

| Dock | Primary position | Overflow |
|---|---|---|
| Left | bottom-left, growing up | top-left, growing down |
| Right | bottom-right, growing up | top-right, growing down |
| Bottom | bottom-left, growing right | bottom-right, growing left |

Three modes: **follow the Dock** (default), **split both sides of the Dock's
edge**, or **pin to a screen edge of your choice** (left/right/bottom, anchored
start/centre/end, with an offset) — so a left Dock can show bookmarks on the
right edge if you prefer.

Bookmarks are never wider than the Dock, never overlap it, never cover the menu
bar, and overflow only starts once the primary position is full.

## Permissions, network, resources

* **No permissions at all.** No Accessibility, no Screen Recording, no network.
  Dock position and thickness come from the system's reserved screen area and
  the Dock's own preferences; screen changes arrive as ordinary notifications.
* **No polling.** No timers except a single one at midnight (colour rollover)
  and a once-a-minute refresh while a card is on screen.
* Measured idle cost: **~0 % CPU, ~16 MB, ~0.1 wakeups/s, 0 network**.

## What it deliberately does not do

No AI calls, no sync service, no built-in editor, no WebView/Electron/Node, no
history, no auto-scroll, no progress bars, no image attachments, no mobile app.
Editing means "open `HudEX.md` in whatever your default Markdown editor is".
Syncing is your sync client's job (the file just has to be local and up to date).

## Repository layout

```
Sources/HudEXCore     parsing / layout / colour / file signatures — pure logic, unit tested
Sources/HudEXApp      AppKit shell (panels, status item, settings window) + SwiftUI views
Tests/HudEXCoreTests  123 tests: parser, layout modes, stacking, palette, sync, i18n
Examples/             example documents (English + Chinese)
docs/                 design and verification notes
script/               build / install / asset scripts
```

```bash
swift test                # 123 tests
./script/build_and_run.sh # build + bundle + sign + run
./script/install.sh       # copy to /Applications
```

## Licence

Not chosen yet — add one before publishing.
