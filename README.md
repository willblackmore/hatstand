# Hatstand

Run multiple Claude accounts on one Mac. Hatstand is a small macOS menu bar app that switches the Claude desktop app between separate **instances**, such as Work and Personal, without signing out and back in. Each instance has its own sign-in, chats, settings, MCP servers and Claude Code data. Only one instance runs at a time.

**Website:** [willblackmore.github.io/hatstand](https://willblackmore.github.io/hatstand/)

> Hatstand is an unofficial, independent project. It isn't made by or affiliated with Anthropic.

## Install

1. Download **[Hatstand.dmg](https://github.com/willblackmore/hatstand/releases/latest/download/Hatstand.dmg)** from the [latest release](https://github.com/willblackmore/hatstand/releases/latest).
2. Open it and drag **Hatstand** into **Applications**.
3. Open Hatstand from Applications. The first time, macOS will say it can't check the app for malicious software. Click **Done**.
4. Open **System Settings › Privacy & Security**, scroll down to the message about Hatstand and click **Open Anyway**. Confirm with your password or Touch ID.

You only need to do steps 3 and 4 once. macOS asks because Hatstand isn't signed with an Apple Developer ID or notarised. If you'd rather not trust a downloaded build, [build it yourself](#building).

Hatstand needs macOS 14 Sonoma or later, on Apple silicon or Intel.

## What it does

- Shows the running instance's name in the menu bar.
- Lists your instances in a menu. Click one to switch: Hatstand quits Claude fully, then reopens it as that instance.
- **Manage Instances** window to add, rename and remove instances and see where their data lives.
- Settings: open at login, confirm before switching, and where to find Claude.
- Tells you when a new version is out. Once a day it asks GitHub whether there’s a newer release; you can turn this off in Settings. It never downloads anything without asking.

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

You need Apple's free Command Line Tools. You don't need Xcode, though it works too if you have it. To install the tools, run:

```bash
xcode-select --install
```

Then clone the repository and build Hatstand:

```bash
scripts/build.sh
```

The app is at `build/Hatstand.app`. Move it to `/Applications`. Hatstand runs on macOS 14 Sonoma or later.

Run the unit tests with:

```bash
scripts/build.sh --test
```

`swift build` compiles the code but doesn't make Mac apps, so the script puts `Hatstand.app` together itself: it writes the `Info.plist`, copies in the icons from `design/` and signs the app ad hoc.

### Releases

To make the downloadable disk image, run:

```bash
scripts/make-release.sh
```

It builds a universal copy and saves it as `dist/Hatstand.dmg`. Upload that file to a GitHub release tagged with the version number, for example `v1.0`. Set `VERSION` (and bump `BUILD_NUMBER`) at the top of `scripts/build.sh` first: the tag must match `VERSION`, because that's how Hatstand's update check spots a new release. Keep the file name as `Hatstand.dmg` so the download link always gets the latest version.

The app is signed to run locally only (ad hoc). It isn't signed with a Developer ID or notarised.

If you'd like to use your own bundle identifier, change `BUNDLE_ID` at the top of `scripts/build.sh`.

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
