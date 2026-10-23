# Chum

A Spotlight replacement for macOS.

Press one hotkey and type. Chum searches everything at once — installed apps, window commands, clipboard history, snippets, and quick calculations — and acts on the top result. It's a native menu-bar app that works out of the box: a full set of window-management commands ships ready to use, clipboard history is on from the first launch, and every hotkey is optional but configurable.

## Why it over Spotlight

- **One search bar, everything in it** — apps, window commands, your clipboard history, snippets, shortcuts, and math. No separate tools to learn
- **Sane defaults** — 27 ready-made window commands (halves, thirds, quarters, sixths, Maximize, and more), clipboard history with pinned items, and a calculator that just answers; nothing to configure before it's useful
- **Window management built in** — the same launcher runs your window layouts, with global hotkeys, a menu bar menu, and a `chum://` URL scheme for scripts
- **System-wide text snippets** — type a keyword anywhere and it expands; the launcher also searches and copies them
- **A hyper key** — Caps Lock becomes ⌃⌥⇧⌘, a modifier no other app uses, so hotkeys never conflict
- **Native and lightweight** — SwiftUI menu-bar app, no Dock icon, no account, free

## The launcher

Press the launcher hotkey (Settings → General to record it) and type. Results appear below the bar as you type, grouped by section; Return picks the top result, ↑↓ walk the list, Esc closes.

- **App launching** — search and launch any installed app with real app icons; apps you've bound to a shortcut show their hotkey
- **Calculator** — type math (`2^10*2`), unit conversions (`5 km to miles`, `72 f`), or currency (`10 usd to eur`) and the result appears above all other results; Return copies it. Bare amounts (`25 eur`) convert to your base currency, bare units (`5 km`) follow your preferred system (Settings → General → Calculator). Currency uses ECB daily reference rates, fetched at most once a day, cached on disk, and usable offline
- **Clipboard history** — every copy is captured (up to the configured limit, 100 by default); search matches the full content of each item, not just the first line, and selecting pastes straight into the frontmost app. A dedicated hotkey (Settings → Window) opens the launcher on the Clipboard tab
- **Snippets** — the Snippets tab lists your snippets; select to copy the resolved text (with template variables filled in)
- **Scratchpad** — a quick-notes pad that persists across opens and relaunches: ⌘N (or the New button) starts a fresh note, ⌘P lists all notes as one-line excerpts with their last-edited time, Return opens one. The editor footer has Copy and Delete. A dedicated hotkey (Settings → Scratchpad) opens the launcher straight on it
- **Tools view** — ↓, Tab, or the list button next to the search bar opens the unified view: every tool as a compact row (Scratchpad, Clipboard, Snippets, Text Transformer, AI Chat — with ⌘-number badges, so Cmd+1..5 opens them from anywhere), then your favorites, then the last things you used. The "On open" setting (Settings → General, Compact or Full) shows it immediately whenever the launcher opens
- **Text Transformer** — select text in any app, open the tool (its own hotkey in Settings → Tools, or from the tools view) and pick a case transformation with a live preview of the result (UPPERCASE, lowercase, Title Case, Sentence case, camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE, tOGGLE cASE); Return replaces the selection in the original app. Your clipboard is borrowed for a moment and restored, and nothing lands in clipboard history
- **AI Chat** — a minimal BYOK chat: pick a provider (OpenAI, Anthropic, Google, Mistral, OpenRouter), store the API key locally on your Mac, and chat from the launcher. No sidebar — ⌘P (or the clock button) lists previous discussions, ⌘N starts a new one. Hover an AI reply for a copy button, or copy the whole discussion from the header. Requests go straight from your Mac to the provider
- **Favorites & recent activity** — press ↓ with an empty search for the unified view: every tool as a compact row first, then your favorites, then the last things you used
- **Recent activity** — entering a category without typing shows recently used items from that category; searching inside a category scopes the search to it, the main search fuzzy-searches everything
- **Cmd+,** opens Settings from anywhere in the launcher

## Window management

- **Custom window commands** — size in % of the display or absolute points, a two-axis anchor (pin left/center/right and top/center/bottom independently, or keep either axis to build move-style commands), and X/Y offsets with negative values
- **27 built-in commands** — halves, corner quarters, column fourths, thirds, sixths, Maximize / Maximize Height / Maximize Width, Reasonable Size — all editable, hideable, deletable, and restorable
- **Global hotkeys** per command, recorded in-app
- **Action hotkeys** — Center, Move Left/Right/Up/Down, Next Display (move the focused window to the next display, preserving its relative position and size)
- **Next Window hotkey** — cycle through the front app's windows via Accessibility, independent of the system "Move focus to next window" shortcut
- **Restore** — undo the last window change, per window
- **Menu bar pinning** — choose exactly which commands and shortcuts appear in the menu bar
- **Edge gap** — keep windows off the screen edges with presets (Small, Medium, Large, Extra Large)

## Snippets

- **Text expansion** — type a keyword anywhere on the system and it expands into predefined text, instantly: the keyword is selected and the expansion pasted over it in one shot (your clipboard is borrowed for a moment and restored right after; it never lands in the clipboard history). Requires Input Monitoring permission (prompted on first enable in Settings → General)
- **Template variables** — insert dynamic content into your snippets using `{{variable}}` syntax:

| Variable | Result | Example |
| --- | --- | --- |
| `{{clipboard}}` | Current clipboard text | `{{clipboard}}` pastes whatever you copied |
| `{{date}}` | Today's date (yyyy-MM-dd) | `{{date}}` → 2026-09-16 |
| `{{date -1}}` | Yesterday | `{{date -1}}` → 2026-09-15 |
| `{{date +7}}` | One week ahead | `{{date +7}}` → 2026-09-23 |
| `{{date:MMMM d, yyyy}}` | Custom date format | `{{date:MMMM d, yyyy}}` → September 16, 2026 |
| `{{date -1:yyyy/MM/dd}}` | Offset with custom format | `{{date -1:yyyy/MM/dd}}` → 2026/09/15 |
| `{{time}}` | Current time (HH:mm:ss) | `{{time}}` → 14:32:05 |

  Date formats use standard ICU/DateFormatter patterns. Unknown variables (e.g. `{{unknown}}`) pass through as-is.

- **Snippet management** — create, edit, enable/disable, and delete snippets in Settings → Snippets

## Hyper key

- **Caps Lock → ⌃⌥⇧⌘** — hold Caps Lock as a "hyper" modifier and bind conflict-free hotkeys to your window commands and shortcuts. A lone Caps Lock tap does nothing (Settings → General → Hyper Key)
- **✦ display** — hyper combos render as `✦K` in the command list, the Launcher, and Chum's built-in shortcut recorder; record them directly by holding Caps Lock while recording
- **No lock, no LED** — while enabled, Caps Lock is remapped at the driver level (to F18) so the lock state and LED stay off; this reverts when the hyper key is disabled or Chum quits, and replaces any Caps Lock remap from System Settings while active
- Requires Accessibility and Input Monitoring permissions; quit other Caps Lock remappers (e.g. Hyperkey.app) first — two active remappers on the same key conflict

## Other

- **App, URL & Folder shortcuts** — bind global hotkeys to launch/activate an app, open a URL, or open a folder or file in Finder / its default app; pin shortcuts to the menu bar. Any installed app can be added as a shortcut right from the launcher: ⌘K on its row (or right-click → Options…), name autofilled, hotkey set in the same place
- **URL scheme** — apply commands from scripts, shells, or other apps
- **Export / Import** — back up and restore all commands and shortcuts to a JSON file
- **Launch at login**
- **Check for Updates** — in-app updater that downloads and installs new releases from GitHub
- **Panel appearance** — dark mode uses a darker, Spotlight-like panel material; "Slight transparency" (General settings) keeps a subtle 85% translucency, off renders it fully opaque

## Requirements

- macOS 13 Ventura or later (developed on macOS 26)
- To build: Xcode Command Line Tools — full Xcode is **not** required

## Install from source

```bash
git clone <repo-url>
cd chum
Scripts/package_app.sh        # release build → ./Chum.app
Scripts/install.sh --force    # copy to /Applications
```

Launch the app and grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility). Window control on macOS requires it. Snippet expansion and the hyper key additionally require **Input Monitoring** permission (prompted on first enable).

### Stable permissions across rebuilds (recommended)

Ad-hoc–signed builds lose their Accessibility grant on every rebuild (macOS keys the grant to the binary's signature hash). Fix it once by signing with a self-signed certificate:

1. Keychain Access → **Certificate Assistant → Create a Certificate…**
2. Name: `Chum` · Identity Type: **Self Signed Root** · Certificate Type: **Code Signing**
3. Export the identity and build:

```bash
echo 'export CODESIGN_IDENTITY="Chum"' >> ~/.zshrc
source ~/.zshrc
Scripts/update.sh
```

Alternatively, put the certificate name in `Scripts/codesign-identity` (git-ignored) — the build script picks it up automatically.

Re-grant Accessibility one last time — after that, rebuilds keep the permission.

## Usage

- **Launcher** — press the global hotkey (configurable in Settings → General); type to search everything; ↓, Tab, or the list button opens the tools/favorites/recents view; ↑↓ to navigate results, Return to select, ⌘K (or right-click) opens the row's options modal (favorites, add as shortcut, hotkey), Esc steps back (category → tools view → empty search → close), Cmd+, to open Settings, Cmd+1..5 to jump straight to a tool
- **Calculator** — type math, a unit conversion, or a currency amount in the launcher; Return copies the result
- **Clipboard History** — press the clipboard hotkey (Settings → Window) to open the launcher on the Clipboard tab, or get there via the actions list / search; type to filter the full history and select to paste into the frontmost app
- **Scratchpad** — press the scratchpad hotkey (Settings → Scratchpad) to open the launcher on the Scratchpad tab; press again to close. Inside it: ⌘N new note, ⌘P notes list, Return opens, Esc goes back
- **Text Transformer** — select text, open the tool (Settings → Tools hotkey or its ⌘-number), pick a transformation with ↑↓, Return replaces the selection
- **Window commands** — trigger from the launcher, a global hotkey, the menu bar, or the URL scheme
- **Hyper key** — enable in Settings → General, then hold Caps Lock while recording a command or shortcut hotkey; it registers as ⌃⌥⇧⌘+key and displays as `✦K`

### Settings

| Section | Contents |
| --- | --- |
| **General** | Launcher hotkey, on-open view (Empty Search / Tools & Recents), slight-transparency toggle, Clipboard/Snippets tab toggles, calculator (base currency, preferred units), snippet expansion toggle, hyper key toggle and ✦ display, export/import, launch at login, update checks, Accessibility status, URL scheme reference |
| **Window** | Clipboard History / Restore / Next Window hotkeys, action hotkeys (Center, Move Left/Right/Up/Down, Next Display), edge gap presets |
| **Commands** | Add, duplicate, delete, and edit window commands: name, hotkey, size, anchor, offsets, pinning, with a live preview |
| **Shortcuts** | Add shortcuts of three kinds (App, URL/Link, Folder/File), each with its own global hotkey; grouped by type |
| **Snippets** | Create text snippets with keywords and template variables; toggle individual snippets on/off; grouped by enabled/disabled |
| **Clipboard** | Monitor toggle, history size, auto-clear interval, clear history |
| **Text Transformer** | Open hotkey; the transformation list — reorder and enable/disable each one |
| **AI Chat** | Open hotkey; provider, model, and API key; delete all discussions |
| **Scratchpad** | Scratchpad hotkey, delete all notes |

### URL scheme

```bash
open "chum://apply?name=Left%20Half"   # apply a saved command by name
open "chum://launcher"                 # open the launcher
open "chum://command?position=center&relativeWidth=0.5&relativeHeight=0.5"
```

`command` params: `position` (`topLeft`…`bottomRight`), `absoluteWidth`/`absoluteHeight` (points), `relativeWidth`/`relativeHeight` (fraction of the display), and `absolute`/`relativeXOffset`/`YOffset`.

## Updating

- In-app: menu bar icon → **Settings** → **General** → **Check for Updates** (or search "Check for Updates" in the Launcher)
- From source: `Scripts/update.sh` (release build → install to /Applications → relaunch)

## Releases

Releases are automated: pushing a `v*` tag (e.g. `v0.9.0`) runs the GitHub
Actions workflow, which tests, builds, and attaches a signed DMG to the
release. The app's version comes from the tag.

## Icons

Drop the two source files into `Resources/` and rebuild:

| File | Purpose | Notes |
| --- | --- | --- |
| `Resources/AppIconSource.png` | App icon (Finder, Dock, Activity Monitor) | 1024x1024 PNG recommended |
| `Resources/MenuBarIcon.png` | Menu bar icon | Small monochrome PNG; rendered as a template image so it adapts to light/dark menu bars |

```bash
Scripts/make_icons.sh   # AppIconSource.png → Resources/AppIcon.icns
Scripts/update.sh
```

## How it works

- The launcher is a borderless, non-activating `NSPanel` that stays floating across all spaces; it captures the frontmost window on open so window commands target the right app
- The usable area is the screen's `visibleFrame` inset by the edge gap; the anchor pins the window to it, offsets shift the frame, and % sizes are relative to that area
- Windows are moved and resized through the macOS Accessibility API (`AXUIElement`)
- The calculator is a pure recursive-descent parser (math, units, currency); exchange rates come from the ECB via frankfurter.dev, cached at `~/Library/Application Support/Chum/rates.json` and refreshed at most once a day
- Clipboard history polls `NSPasteboard.general.changeCount` every 0.5s and stores items in a versioned JSON file
- Snippet expansion uses a listen-only `CGEvent` tap to detect keywords and injects expansion text via `CGEvent`. Template variables (`{{date}}`, `{{clipboard}}`, `{{time}}`) are resolved before injection
- The hyper key remaps Caps Lock to F18 at the HID driver level (`hidutil`, so the lock state and LED stay off), detects press/release via IOKit HID, and rewrites session events to carry ⌃⌥⇧⌘ while held — so shortcut recorders and hotkey matching see the full combo in any app
- Commands persist in `~/Library/Application Support/Chum/commands.json`; app/URL/folder shortcuts in `appShortcuts.json`; clipboard history in `clipboard.json`; snippets in `snippets.json`

## Development

```bash
swift build                  # debug build
swift run ChumTests    # test harness
Scripts/dev.sh               # debug build + relaunch app
Scripts/package_app.sh       # release build + .app bundle
```

Built with Swift Package Manager only — no Xcode project needed. See [AGENTS.md](AGENTS.md) for architecture notes and platform gotchas, and [ROADMAP.md](ROADMAP.md) for planned features.

## Acknowledgments

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- Command set inspired by [Raycast's window management](https://manual.raycast.com/window-management)
