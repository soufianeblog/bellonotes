<#
.SYNOPSIS
    Bello Notes — one-command installer for Windows.

.DESCRIPTION
    Bootstraps the tools required to build the app (Flutter and the Visual
    Studio C++ build tools), builds a release binary, and installs it for the
    current user. Works from a fresh checkout or straight from the web:

        irm https://raw.githubusercontent.com/soufianeblog/bellonotes/main/scripts/install.ps1 | iex

    When run via `iex` it clones the repository automatically. By default every
    tool installation and the final install step ask for confirmation; pass
    -Yes for a fully unattended run.

.PARAMETER Platform
    Target platform: windows | android | web. Default: windows.

.PARAMETER Yes
    Non-interactive: assume "yes" to every prompt.

.PARAMETER NoInstall
    Build the app but do not install/serve it.

.EXAMPLE
    .\scripts\install.ps1
.EXAMPLE
    .\scripts\install.ps1 -Yes
.EXAMPLE
    .\scripts\install.ps1 -Platform android
.EXAMPLE
    .\scripts\install.ps1 -Platform web
#>
[CmdletBinding()]
param(
    [ValidateSet('windows', 'android', 'web')]
    [string]$Platform = 'windows',
    [switch]$Yes,
    [switch]$NoInstall
)

$ErrorActionPreference = 'Stop'

# ── Configuration ───────────────────────────────────────────────────────────
$RepoUrl  = 'https://github.com/soufianeblog/bellonotes.git'
$AppName  = 'Bello Notes'
$PkgName  = 'bellonotes'

# ── Output helpers ──────────────────────────────────────────────────────────
function Write-Info($m) { Write-Host "==> $m" -ForegroundColor Blue }
function Write-Ok($m)   { Write-Host "[ok] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)        { Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

# Ask a yes/no question. Returns $true for yes. Auto-yes under -Yes.
function Confirm-Step($prompt) {
    if ($Yes) { return $true }
    $reply = Read-Host "$prompt [y/N]"
    return $reply -match '^(y|yes)$'
}

function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# Refresh PATH in the current session after an installer modifies it.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

# ── Toolchain bootstrap ─────────────────────────────────────────────────────

# winget ships with modern Windows 10/11 and drives all our installs.
function Assert-Winget {
    if (Have winget) { return }
    Die "winget (App Installer) is required but was not found. Install 'App Installer' from the Microsoft Store, then re-run."
}

function Ensure-Git {
    if (Have git) { return }
    Write-Info "git not found."
    if (-not (Confirm-Step "Install Git via winget?")) { Die "git is required." }
    Assert-Winget
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Update-SessionPath
    if (-not (Have git)) { Die "git installation failed; open a new terminal and retry." }
}

function Ensure-Flutter {
    if (Have flutter) { Write-Ok "Flutter present"; return }
    Write-Warn2 "Flutter SDK not found."
    if (-not (Confirm-Step "Install the Flutter SDK via winget?")) { Die "Flutter is required to build the app." }
    Assert-Winget
    winget install --id Flutter.Flutter -e --source winget --accept-package-agreements --accept-source-agreements
    Update-SessionPath
    if (-not (Have flutter)) {
        Die "Flutter was installed but isn't on PATH yet. Open a new terminal and re-run this script."
    }
}

function Ensure-PlatformToolchain {
    switch ($Platform) {
        'windows' {
            # Windows desktop builds need the MSVC C++ "Desktop development"
            # workload. Detect it via flutter doctor; offer the VS Build Tools.
            $doctor = (flutter doctor 2>&1) -join "`n"
            if ($doctor -match 'Visual Studio.*(not installed|missing)') {
                Write-Warn2 "Visual Studio C++ build tools are required for Windows desktop builds."
                if (Confirm-Step "Install Visual Studio 2022 Build Tools (C++ workload) via winget?") {
                    Assert-Winget
                    winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
                        --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" `
                        --accept-package-agreements --accept-source-agreements
                    Update-SessionPath
                }
            }
        }
        'android' {
            # Building an APK needs a JDK + Android SDK. Verify rather than
            # silently installing Android Studio.
            $doctor = (flutter doctor 2>&1) -join "`n"
            if ($doctor -notmatch 'Android toolchain') {
                Write-Warn2 "Android toolchain incomplete. Install Android Studio (and run 'flutter doctor --android-licenses')."
            }
        }
        'web' {
            # Web support ships with Flutter; just make sure it's enabled.
            flutter config --enable-web | Out-Null
        }
    }
}

# ── Source checkout ─────────────────────────────────────────────────────────
function Resolve-Repo {
    if ((Test-Path 'pubspec.yaml') -and (Select-String -Path 'pubspec.yaml' -Pattern "^name: $PkgName" -Quiet)) {
        $script:RepoDir = (Get-Location).Path
        Write-Ok "Building from current checkout: $RepoDir"
        return
    }
    Ensure-Git
    $script:RepoDir = if ($env:BELLONOTES_DIR) { $env:BELLONOTES_DIR } else { Join-Path $HOME 'bellonotes' }
    if (Test-Path (Join-Path $RepoDir '.git')) {
        Write-Info "Updating existing checkout at $RepoDir…"
        git -C $RepoDir pull --ff-only
    } else {
        Write-Info "Cloning $RepoUrl into $RepoDir…"
        git clone --depth 1 $RepoUrl $RepoDir
    }
    Set-Location $RepoDir
}

# ── Build + install ─────────────────────────────────────────────────────────
function Build-App {
    Write-Info "Fetching Dart/Flutter dependencies…"
    flutter pub get
    Write-Info "Building Bello Notes for $Platform (release)…"
    switch ($Platform) {
        'windows' { flutter build windows --release }
        'android' { flutter build apk --release }
        'web'     { flutter build web --release }
    }
    Write-Ok "Build complete."
}

function Install-App {
    if ($NoInstall) { Write-Warn2 "-NoInstall set; skipping installation."; return }
    switch ($Platform) {
        'windows' {
            $src = Join-Path $RepoDir 'build\windows\x64\runner\Release'
            if (-not (Test-Path $src)) { Die "Build output not found: $src" }
            $dest = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
            if (-not (Confirm-Step "Install to $dest?")) { Write-Warn2 "Skipped install. Build is at: $src"; return }
            if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -Recurse -Force "$src\*" $dest
            # Start Menu shortcut so the app is launchable like any other.
            $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
            $shortcut  = Join-Path $startMenu "$AppName.lnk"
            $ws = New-Object -ComObject WScript.Shell
            $lnk = $ws.CreateShortcut($shortcut)
            $lnk.TargetPath = Join-Path $dest "$PkgName.exe"
            $lnk.WorkingDirectory = $dest
            $lnk.Save()
            Write-Ok "Installed: $dest"
            Write-Info "Launch it from the Start Menu, or run: `"$($lnk.TargetPath)`""
        }
        'android' {
            $apk = Join-Path $RepoDir 'build\app\outputs\flutter-apk\app-release.apk'
            if (-not (Test-Path $apk)) { Die "APK not found: $apk" }
            $devices = if (Have adb) { (adb devices) | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice' } } else { @() }
            if ($devices) {
                if (Confirm-Step "Install the APK to the connected Android device via adb?") {
                    adb install -r $apk
                    Write-Ok "Installed on device."
                } else { Write-Warn2 "Skipped. APK is at: $apk" }
            } else {
                Write-Ok "APK built: $apk"
                Write-Info "Copy it to your phone and open it, or connect a device and run: adb install -r `"$apk`""
            }
        }
        'web' {
            $out = Join-Path $RepoDir 'build\web'
            if (-not (Test-Path $out)) { Die "Web build output not found: $out" }
            Write-Ok "Web app built: $out"
            Write-Info "Deploy the contents of '$out\' to any static host (GitHub Pages,"
            Write-Info "Netlify, Vercel, Firebase Hosting, S3, IIS, …). Serve over HTTP(S),"
            Write-Info "not as a file:// URL."
            if ($Yes) { Write-Warn2 "Unattended mode: not starting a local server."; return }
            if (Confirm-Step "Serve it locally now at http://localhost:8080 ?") {
                Write-Info "Serving via Flutter — press Ctrl+C to stop."
                flutter run -d web-server --web-port 8080 --release
            }
        }
    }
}

# ── Main ────────────────────────────────────────────────────────────────────
Write-Info "Bello Notes installer — target: $Platform"
Resolve-Repo
Ensure-Flutter
Ensure-PlatformToolchain
Build-App
Install-App
Write-Ok "Done."
