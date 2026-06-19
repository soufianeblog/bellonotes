# Bello Notes

A fast, private, cross-platform notes app built with Flutter. Rich-text notes
with folders, tables, images and checklists — stored locally in SQLite, with no
account and no cloud lock-in. Part of [bellocloud.com](https://bellocloud.com).

> Open source, made by [@soufianeblog](https://x.com/soufianeblog).

---

## Features

- **Rich text editor** — headings, bold/italic/underline, colours, highlights,
  checklists, alignment, fonts and font sizes (powered by `flutter_quill`).
- **Tables & images** — insert tables with per-cell colours, and resizable,
  linkable images.
- **Folders & trash** — organise notes into folders, multi-select, and recover
  from a trash bin before permanent deletion.
- **Local-first storage** — everything lives in a local SQLite database; images
  are stored alongside it. No sign-in, no telemetry.
- **Export / import** — back up or move everything as a single `.zip` archive.
- **Markdown & HTML** — paste/convert between rich text, Markdown and HTML.
- **Localized** — English, French, Spanish, Italian, Arabic and Chinese.
- **Adaptive UI** — desktop (resizable sidebars), tablet, and mobile layouts,
  with light/dark themes and custom accent colours.

## Supported platforms

| Platform | Status | Artifact |
|----------|--------|----------|
| macOS    | ✅ | `.app` bundle |
| Windows  | ✅ | `.exe` + bundle |
| Android  | ✅ | `.apk` |
| Linux    | ✅ | bundle + `.desktop` launcher |
| iOS      | ⚙️ buildable | `.app` (no installer script) |

---

## Install (one line)

The installer scripts bootstrap everything they need — Flutter and the platform
build tools — then build and install the app. They prompt before installing any
tool and before placing the app on your system. Pass the unattended flag
(`--yes` / `-Yes`) to skip prompts.

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/soufianeblog/bellonotes/main/scripts/install.sh | bash
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/soufianeblog/bellonotes/main/scripts/install.ps1 | iex
```

### Android

From a checkout (with a phone connected and USB debugging enabled):

```bash
./scripts/install.sh --platform android        # macOS / Linux
.\scripts\install.ps1 -Platform android         # Windows
```

The script builds a release APK and, if a device is detected over `adb`, offers
to install it. Otherwise it prints the APK path so you can copy it to your phone.

### What the installer does

1. Detects (or clones) the repository into `~/bellonotes`.
2. Checks for Flutter and the platform toolchain; offers to install anything
   missing (Homebrew/winget/your Linux package manager).
3. Runs `flutter pub get` and a `--release` build.
4. Asks where to install and copies the app there, creating a launcher:
   - **macOS** → `/Applications/Bello Notes.app`
   - **Windows** → `%LOCALAPPDATA%\Programs\Bello Notes` + Start Menu shortcut
   - **Linux** → `~/.local/lib/bellonotes` + `~/.local/share/applications` entry
   - **Android** → installs to the connected device, or prints the APK path

Useful flags: `--help`, `--yes` (`-Yes`), `--no-install` (`-NoInstall`),
`--platform` (`-Platform`).

---

## Build from source (manual)

If you'd rather not use the installer:

```bash
# 1. Install Flutter (stable):  https://docs.flutter.dev/get-started/install
flutter --version

# 2. Clone and fetch dependencies
git clone https://github.com/soufianeblog/bellonotes.git
cd bellonotes
flutter pub get

# 3. Run in development
flutter run

# 4. Or build a release artifact for your platform
flutter build macos --release      # → build/macos/Build/Products/Release/Bello Notes.app
flutter build windows --release    # → build/windows/x64/runner/Release/
flutter build linux --release      # → build/linux/<arch>/release/bundle/
flutter build apk --release        # → build/app/outputs/flutter-apk/app-release.apk
```

Run `flutter doctor` to confirm your platform toolchain is set up.

### Tests & analysis

```bash
flutter analyze
flutter test
```

---

## Project structure

```
lib/
  main.dart                 App entry point, theme, providers, localization
  l10n/strings.dart         Lightweight in-app localization table
  models/                   Plain data models (Note, Folder) + (de)serialization
  providers/                ChangeNotifier state: settings, notes, folders
  screens/                  Full-page UIs: home, settings, about, error log
  widgets/                  Reusable UI: editor, folder sidebar, notes sidebar
  services/                 Non-UI logic: SQLite, export/import, HTML, logging
scripts/                    One-command installers (install.sh / install.ps1)
test/                       Unit & widget tests
```

A short header at the top of each Dart file explains that file's role, and
public classes and methods carry doc comments.

---

## Contributing

Issues and pull requests are welcome. Please run `flutter analyze` and
`flutter test` before opening a PR, and keep the existing comment style
(a one-line purpose header per file, doc comments on public APIs).

## License

Released under the MIT License — see [LICENSE](LICENSE).
