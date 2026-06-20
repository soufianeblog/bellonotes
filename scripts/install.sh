#!/usr/bin/env bash
#
# Bello Notes — one-command installer for macOS and Linux.
#
# This script bootstraps every tool required to build the app (Flutter and the
# platform toolchain), builds a release binary, and installs it onto the
# machine. It is safe to run from a fresh checkout *or* straight from the web:
#
#   curl -fsSL https://raw.githubusercontent.com/soufianeblog/bellonotes/main/scripts/install.sh | bash
#
# When piped from curl it will clone the repository automatically. Run with
# --help to see all options. By default every tool installation and the final
# install step ask for confirmation; pass --yes for a fully unattended run.
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/soufianeblog/bellonotes.git"
APP_NAME="Bello Notes"          # macOS .app bundle name (see AppInfo.xcconfig)
PKG_NAME="bellonotes"           # pubspec / linux binary name

# Runtime flags (overridable via CLI).
ASSUME_YES=0                    # --yes: never prompt
DO_INSTALL=1                    # --no-install: build only, don't install
PLATFORM="auto"                # --platform macos|linux|android|auto

# ─────────────────────────────────────────────────────────────────────────────
# Pretty output helpers
# ─────────────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"; C_BLUE="\033[34m"
  C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"
else
  C_RESET=""; C_BOLD=""; C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""
fi
info()  { printf "${C_BLUE}${C_BOLD}==>${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}!${C_RESET} %s\n" "$*"; }
err()   { printf "${C_RED}✗ %s${C_RESET}\n" "$*" >&2; }
die()   { err "$*"; exit 1; }

# Ask a yes/no question. Returns 0 for yes. Auto-yes under --yes.
confirm() {
  if [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  local prompt="$1"
  printf "${C_YELLOW}?${C_RESET} %s [y/N] " "$prompt"
  local reply=""
  read -r reply </dev/tty || reply=""
  case "$reply" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
${C_BOLD}Bello Notes installer${C_RESET}

Usage: install.sh [options]

Options:
  --platform <p>   Target platform: macos | linux | android | web | auto (default: auto)
  --yes            Non-interactive: assume "yes" to every prompt
  --no-install     Build the app but do not install/serve it
  --help           Show this help

Examples:
  ./scripts/install.sh                 # interactive, auto-detect desktop platform
  ./scripts/install.sh --yes           # unattended desktop install
  ./scripts/install.sh --platform android
  ./scripts/install.sh --platform web  # build the web app + serve it locally
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:-}"; shift 2 ;;
    --platform=*) PLATFORM="${1#*=}"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-install) DO_INSTALL=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

OS="$(uname -s)"

# Resolve "auto" to the host desktop platform.
if [ "$PLATFORM" = "auto" ]; then
  case "$OS" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *) die "Unsupported OS: $OS. Use the PowerShell installer on Windows." ;;
  esac
fi

# ─────────────────────────────────────────────────────────────────────────────
# Toolchain bootstrap
# ─────────────────────────────────────────────────────────────────────────────

# macOS: ensure Homebrew exists (used to install Flutter / CocoaPods).
ensure_homebrew() {
  if have brew; then ok "Homebrew present"; return; fi
  warn "Homebrew is required to install dependencies on macOS."
  confirm "Install Homebrew now?" || die "Cannot continue without Homebrew."
  info "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available on the current shell for Apple Silicon / Intel.
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  have brew || die "Homebrew installation failed."
}

ensure_git() {
  if have git; then return; fi
  info "git not found."
  case "$OS" in
    Darwin) ensure_homebrew; brew install git ;;
    Linux)  install_linux_pkgs git ;;
  esac
}

# Install packages with whichever Linux package manager is available.
install_linux_pkgs() {
  local pkgs="$*"
  if have apt-get; then sudo apt-get update -y && sudo apt-get install -y $pkgs
  elif have dnf; then sudo dnf install -y $pkgs
  elif have pacman; then sudo pacman -Sy --noconfirm $pkgs
  elif have zypper; then sudo zypper install -y $pkgs
  else die "No supported package manager (apt/dnf/pacman/zypper) found. Install manually: $pkgs"
  fi
}

ensure_flutter() {
  if have flutter; then ok "Flutter present ($(flutter --version 2>/dev/null | head -1))"; return; fi
  warn "Flutter SDK not found."
  confirm "Install the Flutter SDK now?" || die "Flutter is required to build the app."
  case "$OS" in
    Darwin)
      ensure_homebrew
      info "Installing Flutter via Homebrew…"
      brew install --cask flutter
      ;;
    Linux)
      # Homebrew's cask is macOS-only, so clone the stable channel directly.
      local dest="$HOME/.flutter"
      info "Cloning Flutter stable into $dest…"
      git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$dest"
      export PATH="$dest/bin:$PATH"
      warn "Add this to your shell profile to keep Flutter on PATH:"
      printf '    export PATH="%s/bin:$PATH"\n' "$dest"
      ;;
  esac
  have flutter || die "Flutter installation failed; open a new shell and retry."
}

# Per-platform extra toolchain (compilers / SDKs Flutter shells out to).
ensure_platform_toolchain() {
  case "$PLATFORM" in
    macos)
      # macOS desktop builds need the Xcode toolchain + CocoaPods.
      if ! xcode-select -p >/dev/null 2>&1; then
        warn "Xcode command line tools are missing."
        confirm "Trigger the Xcode command line tools installer?" && xcode-select --install || true
        warn "A full Xcode install (from the App Store) is required for macOS builds."
      fi
      if ! have pod; then
        warn "CocoaPods is required for macOS plugin builds."
        confirm "Install CocoaPods via Homebrew?" && { ensure_homebrew; brew install cocoapods; }
      fi
      ;;
    linux)
      # GTK desktop build dependencies.
      for bin in clang cmake ninja pkg-config; do
        if ! have "$bin"; then
          warn "Linux desktop builds need clang, cmake, ninja-build, pkg-config and GTK3 dev headers."
          confirm "Install Linux desktop build dependencies now?" && \
            install_linux_pkgs clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
          break
        fi
      done
      ;;
    android)
      # Android builds need a JDK and the Android SDK. We verify via flutter
      # doctor rather than trying to install Android Studio unattended.
      if ! flutter doctor 2>/dev/null | grep -q "Android toolchain"; then
        warn "Android toolchain incomplete."
      fi
      flutter doctor --android-licenses >/dev/null 2>&1 || true
      ;;
    web)
      # Web support ships with the Flutter SDK; just make sure it's enabled.
      flutter config --enable-web >/dev/null 2>&1 || true
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Source checkout
# ─────────────────────────────────────────────────────────────────────────────
# Locate the repo: if we're already inside it use it in place, otherwise clone.
locate_or_clone_repo() {
  # Are we inside the bellonotes repo already?
  if [ -f "pubspec.yaml" ] && grep -q "^name: $PKG_NAME" pubspec.yaml 2>/dev/null; then
    REPO_DIR="$(pwd)"
    ok "Building from current checkout: $REPO_DIR"
    return
  fi
  ensure_git
  REPO_DIR="${BELLONOTES_DIR:-$HOME/bellonotes}"
  if [ -d "$REPO_DIR/.git" ]; then
    info "Updating existing checkout at $REPO_DIR…"
    git -C "$REPO_DIR" pull --ff-only || warn "Could not fast-forward; using existing checkout."
  else
    info "Cloning $REPO_URL into $REPO_DIR…"
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
  fi
  cd "$REPO_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# Build + install
# ─────────────────────────────────────────────────────────────────────────────
build_app() {
  info "Fetching Dart/Flutter dependencies…"
  flutter pub get
  info "Building Bello Notes for $PLATFORM (release)…"
  case "$PLATFORM" in
    macos)   flutter build macos --release ;;
    linux)   flutter build linux --release ;;
    android) flutter build apk --release ;;
    web)     flutter build web --release ;;
    *) die "Unknown platform: $PLATFORM" ;;
  esac
  ok "Build complete."
}

install_app() {
  [ "$DO_INSTALL" -eq 1 ] || { warn "--no-install set; skipping installation."; return; }
  case "$PLATFORM" in
    macos)
      local src="build/macos/Build/Products/Release/$APP_NAME.app"
      [ -d "$src" ] || die "Build output not found: $src"
      local dest="/Applications/$APP_NAME.app"
      confirm "Install to $dest?" || { warn "Skipped install. App is at: $REPO_DIR/$src"; return; }
      rm -rf "$dest"
      cp -R "$src" "$dest"
      ok "Installed: $dest"
      info "Launch it from Spotlight or: open \"$dest\""
      ;;
    linux)
      local bundle="build/linux/x64/release/bundle"
      [ -d "$bundle" ] || bundle="build/linux/arm64/release/bundle"
      [ -d "$bundle" ] || die "Build bundle not found under build/linux/."
      local dest="$HOME/.local/lib/$PKG_NAME"
      confirm "Install to $dest (with a launcher in ~/.local/share/applications)?" \
        || { warn "Skipped install. Bundle is at: $REPO_DIR/$bundle"; return; }
      mkdir -p "$dest" "$HOME/.local/bin" "$HOME/.local/share/applications"
      cp -R "$bundle/." "$dest/"
      ln -sf "$dest/$PKG_NAME" "$HOME/.local/bin/$PKG_NAME"
      cat > "$HOME/.local/share/applications/$PKG_NAME.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=$dest/$PKG_NAME
Icon=$PKG_NAME
Categories=Office;Utility;
DESKTOP
      ok "Installed: $dest"
      info "Run it with: $PKG_NAME  (ensure ~/.local/bin is on your PATH)"
      ;;
    android)
      local apk="build/app/outputs/flutter-apk/app-release.apk"
      [ -f "$apk" ] || die "APK not found: $apk"
      if have adb && [ -n "$(adb devices | sed -n '2p')" ]; then
        confirm "Install the APK to the connected Android device via adb?" \
          && { adb install -r "$apk" && ok "Installed on device."; } \
          || warn "Skipped. APK is at: $REPO_DIR/$apk"
      else
        ok "APK built: $REPO_DIR/$apk"
        info "Copy it to your phone and open it, or connect a device and run: adb install -r \"$apk\""
      fi
      ;;
    web)
      local out="build/web"
      [ -d "$out" ] || die "Web build output not found: $out"
      ok "Web app built: $REPO_DIR/$out"
      info "Deploy the contents of '$out/' to any static host (GitHub Pages,"
      info "Netlify, Vercel, Firebase Hosting, S3, nginx, …). Note: the app must"
      info "be served over HTTP(S), not opened as a file:// URL."
      if [ "$ASSUME_YES" -eq 1 ]; then
        warn "Unattended mode: not starting a local server."
        return
      fi
      if confirm "Serve it locally now at http://localhost:8080 ?"; then
        if have python3; then
          info "Serving $out/ — press Ctrl+C to stop."
          ( cd "$out" && python3 -m http.server 8080 )
        else
          info "Python 3 not found; serving via Flutter instead."
          flutter run -d web-server --web-port 8080 --release
        fi
      fi
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
  info "Bello Notes installer — target: $PLATFORM"
  locate_or_clone_repo
  ensure_flutter
  ensure_platform_toolchain
  build_app
  install_app
  ok "Done."
}

main "$@"
