# HudEX

**English** · [中文](README.md)

**Always present, almost invisible.**

HudEX puts a handful of solid-colour bookmarks in the free space along the edge
of your screen — normally right next to the Dock. Each bookmark is one project
you are juggling. Hover it and a small card shows where that project stands,
what is next, and the name of the most recent conversation about it.

Project context and reminders come from **one JSON file** that you — or an AI — can edit.

![HudEX overview: hover card, Dock bookmarks, layout options](docs/images/overview.jpg)

*Hover card over the Dock bookmarks · a left-edge Dock with its card · the layout
pane (here pinning the bookmarks to the right edge) · the bookmarks up close.*

## What it is

A tiny, always-on display of *recent project context*, for anyone who keeps
several projects moving at once: a launch, a report, a side project, a reading
list, a room you are renovating.

It answers four questions without you opening anything:

1. Which projects am I in the middle of?
2. Where did each one get to?
3. What is the next step?
4. Which one has gone quiet?

It shows project context at the screen edge and syncs actionable tasks with Apple Reminders.

## Quick start

**Install (the drag-and-drop disk image is the recommended way)**

1. Download [**`HudEX-1.0.6.dmg`** from GitHub Releases](https://github.com/HeXiao2001/HudEX/releases/download/v1.0.6/HudEX-1.0.6.dmg), open it, and drag **HudEX** onto the
   **Applications** shortcut in the window.
2. **The first launch is blocked by macOS** — HudEX is ad-hoc signed rather than
   notarised (a paid Apple account is not involved), and this happens once:
   - double-clicking HudEX shows *"Apple could not verify HudEX is free of
     malware"*;
   - open **System Settings → Privacy & Security** and scroll to *Security*;
   - there is a line saying HudEX was blocked because it is from an unidentified
     developer — click **Open Anyway**;
   - confirm with your password or Touch ID, then click **Open** once more.
3. That is it. HudEX is signed locally (ad-hoc) and makes no network requests.
   It needs no system access for bookmarks; only Reminders sync requests full
   Reminders access. It does not use Accessibility, Screen Recording, or
   notifications. The "blocked" line in Settings disappears once it has opened.
4. On the first launch HudEX creates its own file
   (`~/Library/Application Support/HudEX/HudEX.json`) and opens a short Welcome
   pane: where the file lives, and which look you want.

> Prefer your own file? Choose it in the Welcome pane — macOS will ask for that
> folder once, and the answer is yours.


## One JSON file

HudEX defaults to `~/Library/Application Support/HudEX/HudEX.json`. Its `projects`, `reminders`, and `settings` live in that single file. Use **Settings → Source** to migrate an older `HudEX.md`: HudEX preserves project content and settings, writes the JSON file, then removes the old Markdown file. Keep your own backup if needed.

```json
{
  "schemaVersion": 6,
  "sourceID": "stable-source-uuid",
  "projects": [{
    "id": "website-redesign",
    "title": "Website redesign",
    "shortTitle": "WEB",
    "sections": [{ "id": "next", "title": "Next", "body": "Finish the mobile layout and send it for review" }]
  }],
  "reminders": [
    { "id": "stable-task-uuid-1", "projectID": "website-redesign", "title": "Finish mobile layout" },
    { "id": "stable-task-uuid-2", "projectID": "website-redesign", "title": "Send layout for review", "dueDate": "2026-10-01T09:00:00Z" }
  ],
  "settings": {}
}
```

Apple Reminders uses just one list named `HudEX`. Projects remain in the JSON `projects` array; a reminder's `projectID` links it to a project. A reminder without `projectID` is standalone. A project may have many reminders. A timed `dueDate` creates a system alert. Additions, edits, completion, and deletion sync in both directions. Tasks in older `HudEX · Inbox`, `HudEX · Synced`, and project lists migrate into the single list, then empty lists are removed. A task created directly in Apple Reminders is standalone unless its title starts with a unique project short title followed by ` · `.

Reminders also support `startDate`, `location`, `priority` (0 none, 1 high, 5 medium, 9 low), `earlyReminderMinutes`, `repeatRule` (for example `{"frequency":"weekly","interval":1}`), and a coordinate-based `locationAlert` (`title`, `latitude`, `longitude`, `radiusMeters`, and `trigger`: `arrive` or `leave`). These sync with Apple Reminders, and project cards/details display place and priority. `isFlagged` and `tags` can be stored in JSON, but Apple's public EventKit API does not sync native flags or tags. Select the `HudEX` list for Apple's desktop Reminders widget.

Generated JSON contains full `aiInstructions` for AI editors: derive actionable tasks from next steps and commitments, create new UUIDs, preserve existing IDs and sync metadata, never guess a due time, and keep general notes out of the task list. The legacy Markdown examples remain under [`Examples/`](Examples/HudEX.md) for migration reference.

You can give an AI editor this prompt with the existing file:

> Edit only the supplied HudEX.json and follow its aiInstructions. Extract concrete actions from each project's next steps and explicit commitments into the top-level reminders array. Set each reminder's projectID to its project's id; a project may have many reminders. Set ISO 8601 dueDate/startDate only when the source gives unambiguous dates and times. Use location when a place is clear, and locationAlert only when exact coordinates are known. Set priority, earlyReminderMinutes, and repeatRule only when explicitly specified. Use a new UUID for a new reminder. Preserve existing ids, sourceID, reminderIdentifier, modifiedAt, and syncFingerprint when editing an existing reminder. Keep settings, project sections, and unrelated content. Return one complete valid JSON file; do not create a separate reminders file.

## First launch

Two things happen on their own:

1. HudEX creates its own file at
   `~/Library/Application Support/HudEX/HudEX.json` — that folder needs no
   authorisation;
2. Settings opens on a **Welcome** pane: where the file is, whether it parsed,
   and which look you want (skeuomorphic by default). The pane disappears once
   there is something to show.

Watching a file somewhere else (Documents, a synced folder, a git checkout) is a
choice you make in that pane — macOS asks for that folder once.

## Where the bookmarks may appear (Settings → General → Desktop)

**Only on the main desktop** is on by default: the bookmarks stay on the desktop
they were created on (desktop 1 when HudEX starts at login) and never appear over
a full-screen app. Turn it off and they follow you to every desktop again.

## Styles

Pick one in **Settings → Appearance**; each option previews itself.

| Skeuomorphic (default) | Frosted glass | Minimal |
|---|---|---|
| ![skeuomorphic](docs/images/style-skeuomorphic.png) | ![frosted](docs/images/style-frosted.png) | ![minimal](docs/images/style-minimal.png) |
| Coloured paper card with ruled lines; a punched hole joins it to the bookmark with its own little string. | Translucent pane, readable over any background. | Outlines only. |

Every string hangs differently — direction, curve and even the occasional
S-bend come from a stable hash of the project, so the same bookmark always
hangs the same way, and nothing animates while the pointer is still.

## Content and settings in one file

You or an AI can edit `HudEX.json`. Project context, reminders, and settings live together, and the file can sit in a folder mirrored by your own sync client. Settings use the top-level `settings` object and are written back to the same file. HudEX does not call an AI service or connect to an email account.

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

Bookmarks are never wider than the Dock, never overlap it and never cover the
menu bar.

**By default they only ever appear in one place**: whatever does not fit is
reported in Settings instead of being drawn somewhere else. Turn on
*Allow a second position for overflow* in Settings → Layout (or
`Overflow slot：on` in the file) if you would rather use both ends of the edge.

## Permissions, network, resources

* **Permissions only when needed.** Bookmarks need no Accessibility or Screen
  Recording access. Reminders sync requests full Reminders access; no network.
  Dock position and thickness come from the system's reserved screen area and
  the Dock's own preferences; screen changes arrive as ordinary notifications.
* **No polling.** No timers except a single one at midnight (colour rollover)
  and a once-a-minute refresh while a card is on screen.
* Measured idle cost: **~0 % CPU, ~16 MB, ~0.1 wakeups/s, 0 network**.

## What it deliberately does not do

No AI calls, no built-in cloud file sync, no built-in editor, no WebView/Electron/Node, no
history, no auto-scroll, no progress bars, no image attachments, no mobile app.
Editing means opening `HudEX.json` in your preferred JSON editor.
Syncing is your sync client's job (the file just has to be local and up to date),
and how the content gets written is yours: by hand, by an AI, or by whatever
already produces your notes.

## Repository layout

```
Sources/HudEXCore     parsing / layout / colour / file signatures — pure logic, unit tested
Sources/HudEXApp      AppKit shell (panels, status item, settings window) + SwiftUI views
Tests/HudEXCoreTests  123 tests: parser, layout modes, stacking, palette, sync, i18n
Examples/             example documents (English + Chinese)
docs/                 design and verification notes
script/               build / install / asset scripts (script/demo.swift sweeps the bookmarks for demo recordings)
```

```bash
swift script/demo.swift 3   # sweeps the bookmarks (for screen recordings)
swift test                  # 123 tests
./script/build_and_run.sh # build + bundle + sign + run
./script/install.sh       # copy to /Applications
```

## Licence

Not chosen yet — add one before publishing.
