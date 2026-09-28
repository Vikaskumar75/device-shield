# device_shield

Runtime device-security checks for Flutter apps on Android and iOS: root,
jailbreak, emulator, debugger and mock-location detection, plus screen capture
protection.

| Folder | Contents |
|---|---|
| [`app/`](app/) | The Flutter plugin package, with its [example app](app/example/). Its [README](app/README.md) is the package's pub.dev page. |
| [`website/`](website/) | The landing page and documentation site, published to [vikaskumar75.github.io/device-shield](https://vikaskumar75.github.io/device-shield/) |

## Prerequisites

| Tool | Version | Needed for | Installed by `app/tool/setup.sh` |
|---|---|---|---|
| macOS | | iOS builds and Swift tooling (Dart and Android work on any OS) | — |
| [Homebrew](https://brew.sh) | | Installing the tools below | No |
| Flutter | 3.44.8, pinned in `app/.fvmrc` | Everything | Optional, via [fvm](https://fvm.app) |
| Xcode | 16 or later (tested with 27) | iOS builds, `swift format` | No (App Store) |
| Android Studio, or the Android SDK command-line tools | SDK 36 | Android builds | No |
| JDK | 17+. Android Studio's bundled JDK works | Android builds, Gradle | `openjdk@17`, only if none is found |
| Node.js | 22.12+ | The docs site in `website/` | Yes |
| [GitHub CLI](https://cli.github.com) (`gh`) | Recent | `/fix-issue`, opening PRs | Yes. Then run `gh auth login` |
| ktlint, detekt | 1.8.0, 1.23.8 | Kotlin linting | Yes |
| SwiftLint | Recent | Swift linting | Yes |

## Set up

```bash
git clone https://github.com/Vikaskumar75/device-shield.git
cd device-shield
app/tool/setup.sh
```

The setup script checks every prerequisite, offers to install the missing
command-line tools with Homebrew, and fetches the Dart and npm dependencies.
Re-running it is safe. Use `--check` to only report what's missing, or
`--yes` to install without prompts. It never uses `sudo` and never edits your
shell profile. When a step needs that, it prints the command for you to run.

> **Known issue:** the iOS example app can't build in place while the package
> folder is named `app`. It's a Flutter bug that affects any plugin example
> nested in a folder whose name doesn't match the package (F10 in
> [docs/HANDOVER.md](docs/HANDOVER.md)). Apps that depend on the plugin aren't affected.

## Everyday commands

| Task | Command |
|---|---|
| Run every check CI runs | `app/tool/check.sh` |
| Run the example app | `cd app/example && flutter run` |
| Preview the docs site | `npm run dev --prefix website` |
| Fix a GitHub issue with Claude Code | `/fix-issue <number>` in a Claude Code session |

Coding rules and the full list of CI checks are in
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md). Current state and open issues are
in [docs/HANDOVER.md](docs/HANDOVER.md). All other project documents (plans,
architecture, feature designs, reports) are in [`docs/`](docs/).

## License

BSD 3-Clause. See [LICENSE](LICENSE).
