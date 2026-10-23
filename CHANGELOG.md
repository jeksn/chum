# Changelog

## v1.0.0 — Chum (Oct 24, 2026)

- **Renamed Trast → Chum**. New bundle id (`com.chum.app`), new `chum://` URL scheme, new signing identity — Chum is a fresh app to macOS, so grant Accessibility and Input Monitoring once on first use
- Settings, hotkeys, commands, snippets, notes, chats, colors, and clipboard history all move over with the old app's data (one-time migration of the preferences domain and the Application Support folder)
- The launcher keeps its shape: bird logo in the search bar, native crossfades between tools, and the sidebar Scratchpad and AI Chat from v0.12.0
- CI signs with the Chum certificate; `package_app.sh` falls back to ad-hoc with a warning when the named identity is missing from the keychain instead of failing the build

## v0.12.0 — Sidebars, archive, Color Picker (Oct 23, 2026)

- **Scratchpad and AI Chat sidebars**: both tools show a persistent list beside the editor/conversation (notes and previous discussions were a Cmd+P full-screen swap before) — click a row to open it, ⌘N makes a new one, and the panel widens and fades smoothly between the search bar and the tools
- **Archive**: right-click a note or chat to Archive or Delete it; a Notes/Chats | Archive toggle at the top of the sidebar lists archived items with Unarchive — the editor never opens an archived note and archived chats never auto-open
- **Color Picker**: an eyedropper tool (own hotkey, Settings → Color Picker) that saves picked colors to a list in the launcher; Return copies the hex, the row context menu copies RGB/HSL or removes the color
- **AI Chat markdown**: assistant replies render as markdown — headings, lists, quotes, tables, and fenced code blocks; raw markdown is kept on copy
- **Uniform window spacing**: the gap setting now also applies between windows — two half commands leave the same space in the middle as on the screen edges, and every layout gets it all the way around
- **Half-size cycling** (Settings → Window → Cycle half sizes): pressing a half command again steps 1/2 → 1/3 → 2/3, like Raycast
- **Window fixes**: floating panels (Helium) now resize correctly — hotkeys follow keyboard focus instead of the frontmost app; apps that enforce a minimum window size keep their anchored edge on the screen instead of hanging off it, with a HUD explaining the limit
- **Hyperkey reliability**: the engine runs its event tap on a dedicated thread and now heals itself — a watchdog rebuilds the tap when it silently stops receiving events (wake-from-sleep, Secure Input aftermath) within seconds of your next keystroke
- **Launcher**: reopens on the category you left it on; "Add New Snippet" row in the Snippets tool; Cmd+K always opens the row options modal; the single amber accent is the bird logo in the search bar — everything else is native

## v0.11.0 — Unified launcher, configurable tools (Oct 3, 2026)

- **One launcher surface**: the old Tab action mode is gone — ↓, Tab, or the list button opens the unified view with every tool as a compact row (⌘-numbered, so Cmd+1..5 jumps straight to a tool), then your favorites, then the last things you used. A new "On open" setting (General) picks between **Compact** (bare search bar) and **Full** (the unified view) whenever the launcher opens
- **Every tool is searchable**: typing finds Text Transformer and AI Chat alongside everything else
- **Esc steps back one level at a time**: typed search → main view → close
- **Text Transformer settings**: its own tab listing every transformation with enable/disable toggles and playlist-style drag-to-reorder — the tool shows exactly your list, in your order
- **AI Chat settings**: its own tab with the hotkey, provider picker, and API key (stored locally, ready for the chat interface in a future release)
- **Fixes**: favorited rows (which travel between the favorites and search sections) stopped painting their selection/hover highlight — rows now derive highlight state directly from the view model; a typed search no longer needs two Esc presses to go back

## v0.10.0 — Launcher tools: Text Transformer, notes, favorites (Sep 30, 2026)

- Actions view rebuilt as **Tools + Browse**: interactive tools are tiles in a wrapping grid (Scratchpad, Clipboard, Snippets, Text Transformer, AI Chat) above a compact list of categories (Window Commands, Shortcuts, Apps, Trast) — new tools no longer lengthen a list, and arrow keys now follow the layout instead of a flat wrap
- **Text Transformer**: select text in any app, open the tool (its own hotkey in Settings → Tools), pick a case transformation with a live preview (UPPERCASE, lowercase, Title Case, Sentence case, camelCase, PascalCase, snake_case, kebab-case, CONSTANT_CASE, tOGGLE cASE), and press Return — the selection is replaced in place and your clipboard is untouched
- **Scratchpad notes**: the Scratchpad now holds multiple notes — ⌘N starts a new one, ⌘P lists them as one-line excerpts with last-edited times, Return opens, Delete cleans up; your existing scratchpad text migrates to the first note
- **Favorites**: right-click any result (or press ⌘K on the highlighted row) to pin apps, commands, and shortcuts as favorites; favorited rows show a star
- **Recent activity**: press ↓ on an empty search to see your favorites and the last things you used, favorites pinned on top
- **AI Chat groundwork**: provider picker (OpenAI, Anthropic, Google, Mistral, OpenRouter) and API key storage in the new Settings → Tools tab, with a dedicated hotkey — the chat interface ships in a future release

## v0.9.0 — Launcher calculator, live app list (Sep 30, 2026)

- Launcher calculator: type math (`2^10*2`), unit conversions (`5 km to miles`, `72 f`), or currency (`10 usd to eur`) in the launcher and press Return to copy the result; the result row appears above all other results
- Bare amounts (`25 eur`) convert to your base currency and bare units (`5 km`) follow your preferred unit system — both configurable in Settings → General → Calculator
- Currency rates are ECB daily reference rates, fetched at most once a day, cached on disk, and usable offline
- Apps installed while Trast is running now appear in the launcher without a relaunch — app directories are watched, rescans are debounced so half-copied bundles are never picked up, and existing entries are reused so only new apps pay the load

## v0.8.0 — Scratchpad, launcher performance (Sep 29, 2026)

- Launcher Scratchpad: a category for jotting quick notes, with its own hotkey (Settings → Scratchpad to record it), copy-to-clipboard and clear buttons; text persists between opens
- Launcher performance: results are computed once per keystroke from a precomputed search index instead of re-ranking every item on every row render — search and arrow-key navigation now track keystrokes with no lag; searching inside a category only scores that category's items
- Snippet expansion reworked: selects the typed keyword and pastes the expansion in one shot instead of backspacing and typing — fixes keyword residue in browser address bars and multiline-safe, single-frame expansion; clipboard history stays clean (pasteboard saved and restored)
- Next Window cycling fixed for apps with three or more windows: a stable per-app round-robin order replaces the z-order-following index math that degraded to toggling the top two windows
- App icons downsampled once at scan time instead of rescaling full-size icons on every row render

## v0.7.0 — Native hyper key (Sep 22, 2026)

- Caps Lock → ⌃⌥⇧⌘: hold Caps Lock as a "hyper" modifier, a combo no other app uses, and bind conflict-free hotkeys to window commands and shortcuts; a lone Caps Lock tap does nothing (Settings → General → Hyper Key)
- While the hyper key is enabled, Caps Lock is remapped at the driver level (to F18) so the lock state and LED stay off; reverts when disabled or Trast quits
- Hyper combos display as ✦K in the command list, Launcher, and the shortcut recorder — record Caps Lock + key directly
- Custom hotkey recorder replaces KeyboardShortcuts.Recorder everywhere: same storage, ✦ rendering, menu key equivalents (⌘W etc.) record instead of firing, no packaged-app resource bundle crash
- Requires Accessibility and Input Monitoring permissions; quit Hyperkey.app or other Caps Lock remappers first

## v0.6.0 — Rename to Trast (Sep 17, 2026)

- Renamed from Trast to Trast across the entire app
- New bundle ID `com.trast.app` and URL scheme `trast://`
- Config migration: existing Trast settings auto-copied to Trast on first launch
- Dynamic accessibility status in the menu bar (updates without relaunch)
- Removed app name from the settings window title

## v0.5.0 — Launcher redesign, snippet hardening (Sep 17, 2026)

- Two-mode launcher: search and actions grid with Tab to switch, animated blur-and-fade transitions
- Clipboard and Snippets tabs integrated into the launcher with live content
- Cmd+1..6 to jump to a category from anywhere
- Recent items shown when entering a category without typing
- Rotating placeholder text in the search bar
- Snippet expansion hardened: buffer resets on mouse clicks and app switches, private CGEventSource to prevent key suppression, magic tag to avoid self-feedback
- Snippet template variables: `{{clipboard}}`, `{{date}}`, `{{date -1}}`, `{{time}}`, custom date formats
- Clipboard History fixed in All tab, clipboard deduplication improvements
- Settings opening from launcher reliability fix

## v0.4.0 — Launcher: apps, clipboard, snippets (Sep 16, 2026)

- Spotlight-style launcher replaces the Quick Picker as the main interface
- App launching: search and launch any installed app with real icons
- Clipboard history: polls pasteboard, stores up to 100 items, searchable in the launcher, paste-on-select
- Snippet expansion: type a keyword to expand into predefined text (requires Input Monitoring permission)
- Edge gap presets: Small (10px), Medium (20px), Large (40px), Extra Large (60px)
- Inter-window gap support in LayoutEngine (not yet exposed in CommandApplier)
- Launcher transparency slider (5% steps)
- Settings redesigned as 3-column app layout with section headings
- Slimmed down menu bar, Launcher promoted to primary interface

## v0.3.0 — Presets, Next Display, export/import (Sep 14, 2026)

- Command presets: quick-apply common layouts from the launcher
- Next Display action: move the focused window to the next display, preserving relative position and size
- Config export/import: back up and restore commands and shortcuts as JSON
- Recently-used ordering in the launcher with UsageTracker
- Fuzzy match highlighting in search results
- App shortcuts submenu in the menu bar
- Next Window menu item
- Auto-update check on launch
- Native menu key equivalents for pinned commands

## v0.2.0 — App, URL, and folder shortcuts (Sep 10, 2026)

- App shortcuts: bind global hotkeys to launch or activate apps
- URL/Link shortcuts: open a URL from a global hotkey
- Folder/File shortcuts: open files and folders in Finder or their default app
- Next Window global hotkey: cycle through the front app's windows via Accessibility (independent of the system shortcut)

## v0.1.4 — CI fixes (Sep 6, 2026)

- Fixed resource bundle patch target for CI builds

## v0.1.0–v0.1.3 — Initial release (Sep 6, 2026)

- Window management: custom commands with two-axis anchors, percent/point sizes, X/Y offsets
- 27 built-in commands (halves, quarters, thirds, sixths, maximize, center, move)
- Global hotkeys per command, recorded in-app
- Menu bar pinning: choose which commands appear in the menu bar
- Restore: undo the last window change per window
- Settings UI with command editor and live preview
- In-app Check for Updates
- Release pipeline with GitHub Actions (build, test, DMG, auto-publish)
- Stable code signing support
- App icon and menu bar icon
