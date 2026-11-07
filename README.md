# Hatstand

A small macOS menu bar app for switching the Claude desktop app between separate **instances**, such as Work and Personal. Each instance has its own sign-in, chats, settings, MCP servers and Claude Code data. Only one instance runs at a time.

> Hatstand is an unofficial, independent project. It isn't made by or affiliated with Anthropic.

## What it does

- Shows the running instance's name in the menu bar.
- Lists your instances in a menu. Click one to switch: Hatstand quits Claude fully, then reopens it as that instance.
- **Manage Instances** window to add, rename and remove instances and see where their data lives.
- Settings: open at login, confirm before switching, and where to find Claude.

## How it works

Claude for desktop is an Electron app. Hatstand launches it with two settings that keep each instance's data separate:

| Setting | What it holds |
| --- | --- |
| `--user-data-dir=<folder>` (Electron argument) | The app's own data: sign-in, chats, settings, MCP config and Cowork VM files. |
| `CLAUDE_CONFIG_DIR=<folder>` (environment variable) | Claude Code data for the Code tab: settings, sessions and its sign-in. |

The **default instance** uses neither, so Claude uses its normal locations (`~/Library/Application Support/Claude`, `~/.claude` and `~/.claude.json`). Opening Claude from the Dock, Spotlight or a login item always opens the default instance.

Hatstand never modifies, copies or re-signs Claude.app, and never moves Claude's data folders. It only launches and quits Claude.

New instances are created in `~/Library/Application Support/Hatstand/Instances/<Name>/` (or a folder you choose), with `app-data` and `claude-code` folders inside. You can also point an instance at folders you already have.

To work out which instance is running, Hatstand reads the launch arguments of Claude's main process and matches `--user-data-dir` against your instances.

Hatstand's own settings are saved in `~/Library/Application Support/Hatstand/config.json`.

## Building

You need Xcode 16 or later (developed with Xcode 27). Hatstand runs on macOS 14 Sonoma or later.

1. Clone the repository and open `Hatstand.xcodeproj`.
2. Choose **Product › Run**.

Or build from the command line:

```bash
xcodebuild -project Hatstand.xcodeproj -scheme Hatstand -configuration Release -derivedDataPath build build
```

The app is at `build/Build/Products/Release/Hatstand.app`. Move it to `/Applications`.

Run the unit tests with:

```bash
xcodebuild -project Hatstand.xcodeproj -scheme Hatstand -derivedDataPath build test
```

The app is signed to run locally only. It isn't signed with a Developer ID or notarised, so you need to build it yourself.

If you'd like to use your own bundle identifier, change `PRODUCT_BUNDLE_IDENTIFIER` in the project's build settings.

## Tips

- **Move the menu bar item next to Claude's.** Hold ⌘ and drag the Hatstand item along the menu bar.
- **Importing an existing setup.** In Manage Instances, click **+**, choose **Use existing folders**, then pick the app data folder and (optionally) the Claude Code folder you already use.
- **The first time a new instance opens**, Claude shows its sign-in screen. Sign in with the account you want for that instance.

## Limitations

- **Unofficial.** Claude updates may change how it handles these settings and stop Hatstand working.
- **Update restarts return to the default instance.** When Claude restarts itself after an update, it drops its launch settings and comes back as the default instance. Hatstand shows this honestly; switch back from the menu if you need to.
- **One instance at a time.** Switching always quits Claude first, so finish anything in progress before you switch.
- **Opening Claude directly** (Dock, Spotlight, login item) always opens the default instance. Hatstand doesn't intercept it.

## Licence

MIT. See [LICENSE](LICENSE).
