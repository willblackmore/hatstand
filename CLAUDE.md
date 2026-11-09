# Hatstand — project brief

Hatstand is a small macOS menu bar app for switching the Claude desktop app between separate **instances** (for example Work and Personal), each with its own sign-in, chats, settings, MCP servers and Claude Code data. Only one instance runs at a time.

It's open source on GitHub (MIT licence) for people to build themselves. No Developer ID signing or notarisation for now.

Use British English in all UI text, comments and docs.

---

## How it works

The Claude desktop app is an Electron app. Two launch settings give an instance full isolation:

- `--user-data-dir=<folder>` (Electron flag): the app's own data — sign-in, chats, settings, MCP config, Cowork VM files.
- `CLAUDE_CONFIG_DIR=<folder>` (environment variable): the Claude Code data used by the Code tab inside the app — settings, sessions, and its login (which is stored in the Keychain keyed to this folder, so each instance gets its own Code login).

Without either, Claude uses its normal locations (`~/Library/Application Support/Claude`, `~/.claude`, `~/.claude.json`). That is the **default instance**.

Rules:

- **Never modify, copy or re-sign Claude.app.** On some machines it's managed by MDM. Hatstand only launches and quits it.
- **Never move or swap Claude's data folders.** Symlinking or moving folders breaks Cowork's VM. Each instance's data stays where it was created.
- **One instance at a time.** Switching always quits Claude fully before launching the next instance.

---

## Instances

### Default instance

- Represents Claude's normal data locations. Always exists, can't be removed.
- Only its **name** is editable (initially "Default").
- Launched with no extra arguments and **without** `CLAUDE_CONFIG_DIR`.
- Opening Claude directly (Dock, Spotlight, login item) always opens the default instance. Hatstand does **not** watch for this or relaunch anything.

### Other instances

Each has:

- `id` (UUID), `name`
- `appDataPath` — passed as `--user-data-dir`
- `claudeCodePath` — passed as `CLAUDE_CONFIG_DIR`

New instances created by Hatstand use this layout inside the folder the user picks:

```
<chosen parent>/<Instance name>/
├── app-data/       → --user-data-dir
└── claude-code/    → CLAUDE_CONFIG_DIR
```

Default parent folder suggestion: `~/Library/Application Support/Hatstand/Instances` (not iCloud-synced). The user can choose any other folder.

**Use existing folders:** when adding an instance, the user can instead pick an existing app data folder and (optionally) an existing Claude Code folder.

Validation:

- Paths must not be Claude's default locations, or inside them.
- No two instances may share a path.
- Warn (don't block) if a path is inside an iCloud-synced folder (Desktop, Documents, iCloud Drive).
- Instance names must be unique and non-empty.

### Storage

Store the instance list and settings as JSON at:

`~/Library/Application Support/Hatstand/config.json`

The app used to be called CSwitcher. On launch, if there's no config at the new path but there is one at `~/Library/Application Support/CSwitcher/config.json`, copy it across (copy, don't move). Never move instance folders that were created under the old `CSwitcher/Instances` folder: the config stores their full paths, so they keep working where they are.

Write atomically. Standardise all paths (resolve `~`, symlinks, trailing slashes) before saving or comparing.

---

## Behaviour

### Finding Claude

- Claude.app path: setting, default `/Applications/Claude.app`.
- Read its bundle identifier from the app's `Info.plist` at runtime rather than hard-coding it (expected to be `com.anthropic.claudefordesktop`, but verify).
- If Claude.app isn't found, show this in the menu and Settings, with a button to locate it.

### Detecting the running instance

- Use `NSRunningApplication` for the bundle ID, plus `NSWorkspace` launch/terminate notifications to stay up to date.
- Work out which instance is running by reading the main process's arguments (`sysctl` with `KERN_PROCARGS2`; fall back to `ps -o args= -p <pid>` if needed) and matching `--user-data-dir` against known instances.
  - No `--user-data-dir` → default instance.
  - A path that matches no instance → show "Unknown instance".
- Note: when Claude restarts itself after an update it drops its launch settings and comes back as the default instance. Detection must reflect that honestly — that's the intended behaviour, not a bug to work around.

### Launching an instance

- Use `NSWorkspace.openApplication(at:configuration:)`:
  - default instance: no arguments, and make sure `CLAUDE_CONFIG_DIR` is not passed through.
  - other instances: `arguments = ["--user-data-dir=<appDataPath>"]`, `environment = ["CLAUDE_CONFIG_DIR": <claudeCodePath>]`.
- Verify the environment variable actually reaches the launched app. If it doesn't, fall back to `/usr/bin/open -a <Claude.app> --env CLAUDE_CONFIG_DIR=<path> --args --user-data-dir=<path>`.
- Create the instance folders if they're missing.

### Clicking an instance in the menu

- **It's the running instance:** bring Claude to the front.
- **Claude isn't running:** launch that instance.
- **Another instance is running:** if "Confirm before switching" is on, show a standard alert ("Switch to Personal? Claude will quit and reopen."). Then switch.

### Switching

1. Ask Claude to quit gracefully (`terminate()`).
2. Wait until the main process **and** all processes whose executable lives inside the Claude.app bundle (helpers, Code sessions, VM-related processes) have exited. Enumerate with `proc_listallpids` + `proc_pidpath`.
3. Timeout around 20 seconds. On timeout, show an alert offering **Force Quit** or **Cancel**.
4. Launch the chosen instance.
5. Show progress while switching (e.g. "Switching…" in the menu bar title) and ignore further clicks until done.

### Update check

- `UpdateChecker` asks GitHub's API for the latest release (`repos/willblackmore/hatstand/releases/latest`) about 10 seconds after launch and then once a day, if "Check for updates automatically" is on (default: on).
- It compares the release tag (`v1.1`) with `CFBundleShortVersionString` numerically. If newer, the menu shows "Update Available: Hatstand 1.1…", which offers to open the release page.
- It never downloads or installs anything itself. "Check for Updates…" in the menu and **Check Now** in Settings check straight away and always report the result.
- Release tags must match the app's version (`MARKETING_VERSION`), with a leading `v`.

---

## UI

Aim for a native macOS look and feel using system controls, fonts, colours and SF Symbols.

### Menu bar item

- Built with AppKit: `NSStatusItem` + `NSMenu` (better native fidelity than SwiftUI `MenuBarExtra` for section headers and subtitles). SwiftUI is fine for windows.
- Shows the Hatstand icon (template image, see below) followed by the **name of the running instance**. When Claude isn't running, show the default instance's name.
- Users can Cmd-drag it to sit next to Claude's own menu bar icon. Mention this in the README.

### Menu

```
YOUR INSTANCES              ← section header (NSMenuItem.sectionHeader)
✓ Work                      ← tick = currently running instance
  Default instance          ← subtitle, ONLY on the default instance
  Personal
  Another one
─────────────
⬇ Update Available: Hatstand 1.1…   ← only when there's a newer release
─────────────
⚙ Manage Instances…
  Settings…
  Check for Updates…
─────────────
  Quit Hatstand
```

- Running instance: standard checkmark (`state = .on`). Don't use Claude's logo.
- Default instance: subtitle "Default instance" (`NSMenuItem.subtitle`, macOS 14.4+; on older versions fall back to an attributed title or omit).
- If Claude.app can't be found, show a disabled warning item.

### Manage instances window

Standard settings-style window, designed by you:

- Sidebar list of instances (name, plus "Default instance" under the default). `+` / `−` buttons under the list, as in standard macOS lists.
- Detail pane for the selected instance:
  - Name (editable)
  - App data folder and Claude Code folder (read-only paths, with **Show in Finder** buttons). Default instance shows Claude's normal locations.
  - **Open** / **Switch to this instance** button.
- `−` removes an instance: confirmation alert with a checkbox "Also move its folders to the Bin". Never hard-delete. Disabled for the default instance and the running instance.

### Add instance sheet

- Name
- Choice: **Create new folders** (with location picker, default as above) or **Use existing folders** (two folder pickers; Claude Code folder optional — if left empty, create `claude-code/` next to the app data folder).
- Validation messages inline. **Add** / **Cancel** buttons.
- After adding, offer to open the new instance now. Explain that the first launch shows Claude's sign-in screen.

### Settings

Either a tab in the Manage window or a standard Settings window:

- Open Hatstand at login (`SMAppService.mainApp`)
- Confirm before switching (default: on)
- Check for updates automatically (default: on), with **Check Now**
- Claude app location (path + **Choose…**)

---

## Technical requirements

- Swift, SwiftUI for windows, AppKit for the status item and menu.
- Minimum macOS 14. Developed and tested on macOS 27.
- `LSUIElement = YES` (no Dock icon).
- App Sandbox **off** (needs to launch Claude with arguments, read other processes' arguments, and use user-chosen folders freely).
- Signing for development: "Sign to Run Locally".
- Keep it small and dependency-free (no third-party packages).
- Structure suggestion: `InstanceStore` (model + persistence), `ClaudeController` (find, detect, launch, quit, switch), `StatusMenuController` (NSStatusItem/NSMenu), SwiftUI views for Manage, Add and Settings.
- Unit-test the pure logic: path standardisation and validation, argument parsing, instance matching.
- Build from the command line with `xcodebuild` to check for errors.
- It must also build with just the Command Line Tools: `Package.swift` plus `scripts/build-without-xcode.sh` (which writes the `Info.plist` and copies the icons in itself). If you change Info.plist keys, assets or the bundle ID in the Xcode project, update the script to match. Check with `DEVELOPER_DIR=/Library/Developer/CommandLineTools scripts/build-without-xcode.sh` (and `--test`).

---

## Assets

### Menu bar icon

A solid top hat: `design/menubar-icon.svg`, copied to `Hatstand/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.svg`. It's a **template image** (Render As: Template Image, Preserve Vector Data), so the fill colour is ignored and it adapts to light and dark menu bars. Keep the crown and brim as one solid shape: splitting them stops it reading as a hat.

### App icon

An angular top hat (orange `#D97757`, cream band `#FAF9F5`, on `#131313`): `design/app-icon.svg`. The PNG sizes in `AppIcon.appiconset` are exported from it. If the SVG changes, re-export every size with transparent corners and keep the drop shadow. Don't use Anthropic's or Claude's logo anywhere in the repo.

---

## Out of scope (for now)

- Running instances side by side.
- Terminal `claude` CLI aliases or setup.
- Per-instance Dock icons, or any change to Claude.app.
- Watching for Claude opened directly and relaunching it as another instance.
- Developer ID signing, notarisation, automatic installation of updates (Sparkle). Hatstand only tells people about updates.

---

## Suggested build order

1. Model, persistence, path standardisation and validation (with tests).
2. `ClaudeController`: find Claude, detect running instance, launch, quit and wait, switch.
3. Status item and menu, wired to the controller.
4. Manage instances window, Add sheet, Settings, launch at login.
5. README: what it does, how it works, how to build, limitations (unofficial; Claude updates may change behaviour; update restarts return to the default instance), Cmd-drag tip.
