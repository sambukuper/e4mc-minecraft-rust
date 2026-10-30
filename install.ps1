# e4mc-minecraft-rust installer.
#
# Puts the e4mc Rust port (public multiplayer over the e4mc relay) into an
# elyhorizon-launcher checkout, builds it, and installs it into the
# launcher's game versions:
#   1. finds an elyhorizon-launcher clone (or clones sambukuper's fork),
#   2. applies the port with `git am` (skipped when it is already in),
#   3. builds horizon-client with the `mods` feature (no Steam: e4mc needs
#      no Steam library),
#   4. installs the built game as the launcher's game-mod build: every
#      installed version, new ones included, plays it (the launcher swaps
#      it in at launch; each version's own binary is kept as .upstream).
#
# Usage:
#   irm https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.ps1 | iex
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-LauncherDir <path>] [-SkipBuild] [-PatchPath <file>] [-NoGameMod]
#
# Requirements: git, Rust 1.90+ (rustup), Windows x64. The game needs its
# resources prepared from your own copy of Minecraft (the launcher's Play
# page does that). e4mc itself needs no Steam and no port forwarding.
param(
    # An existing elyhorizon-launcher checkout. Default: one next to the
    # current directory, or a fresh clone of the fork made here.
    [string]$LauncherDir = "",
    # Apply a local patch file instead of downloading it (offline, testing).
    [string]$PatchPath = "",
    # Build the game after integrating the port.
    [switch]$SkipBuild,
    # Only build into the launcher checkout; don't install as the game-mod build.
    [switch]$NoGameMod
)

$ErrorActionPreference = "Stop"
$LauncherRepo = "https://github.com/sambukuper/elyhorizon-launcher.git"
$PatchUrl = "https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/horizon-integration/e4mc-port.patch"
$DataDir = Join-Path $env:APPDATA "elyhorizon-launcher"

function Fail($message) {
    Write-Host ""
    Write-Host "e4mc: $message" -ForegroundColor Red
    exit 1
}
function Step($message) {
    Write-Host ""
    Write-Host "== e4mc: $message" -ForegroundColor Cyan
}

Step "finding the launcher"
if (-not $LauncherDir) {
    foreach ($candidate in @("$PWD\elyhorizon-launcher", "$PWD\..\elyhorizon-launcher", "$PWD")) {
        if (Test-Path "$candidate\crates\horizon-client") {
            $LauncherDir = $candidate
            break
        }
    }
}
if (-not $LauncherDir) {
    Write-Host "No elyhorizon-launcher found here; cloning $LauncherRepo (this can take a minute)..."
    git clone --branch main $LauncherRepo elyhorizon-launcher
    if ($LASTEXITCODE -ne 0) { Fail "git clone failed. Is git installed and reachable? You can also pass -LauncherDir <path to your checkout>." }
    $LauncherDir = "$PWD\elyhorizon-launcher"
}
$LauncherDir = (Resolve-Path $LauncherDir).Path
if (-not (Test-Path "$LauncherDir\Cargo.toml") -or -not (Test-Path "$LauncherDir\crates\horizon-client")) {
    Fail "$LauncherDir is not an elyhorizon-launcher checkout (no Cargo.toml / crates\horizon-client)."
}
Write-Host "Launcher: $LauncherDir"

Step "integrating the port"
if (Test-Path "$LauncherDir\crates\horizon-e4mc") {
    Write-Host "crates\horizon-e4mc already exists: the port is in, nothing to apply."
} else {
    if ($PatchPath) {
        if (-not (Test-Path $PatchPath)) { Fail "patch file not found: $PatchPath" }
        $patch = (Resolve-Path $PatchPath).Path
    } else {
        $patch = Join-Path $env:TEMP "e4mc-port.patch"
        Write-Host "Downloading the port patch..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $PatchUrl -OutFile $patch -UseBasicParsing
        } catch {
            Fail "couldn't download the patch: $($_.Exception.Message)"
        }
    }
    # git am needs an identity; supply one only when the machine has none.
    $identity = @()
    if (-not (git config user.email)) {
        $identity = @("-c", "user.name=e4mc installer", "-c", "user.email=e4mc@localhost")
    }
    Write-Host "Applying the port as commits (git am)..."
    git -C $LauncherDir @identity am --3way $patch
    if ($LASTEXITCODE -ne 0) {
        git -C $LauncherDir am --abort 2>$null
        Fail "the patch didn't apply: this checkout isn't the base the port was made on. Clone $LauncherRepo (or pull its main) and try again."
    }
    Write-Host "Applied: horizon-e4mc crate, client integration, auto-publish, docs (4 commits)."
}

if ($SkipBuild) {
    Step "skipping the build (-SkipBuild)"
    Write-Host "Build later with:"
    Write-Host "  cd `"$LauncherDir`""
    Write-Host "  cargo build --release -p horizon-client --features mods"
    exit 0
}

Step "building the game (cargo release; half an hour on a laptop)"
Push-Location $LauncherDir
try {
    cargo build --release -p horizon-client --features mods
    if ($LASTEXITCODE -ne 0) {
        Fail "cargo build failed. Rust 1.90+ is required: https://rustup.rs then try again."
    }
} finally {
    Pop-Location
}
$GameExe = "$LauncherDir\target\release\horizon-client.exe"
if (-not (Test-Path $GameExe)) { Fail "the build finished but horizon-client.exe isn't at $GameExe." }

if ($NoGameMod) {
    Step "skipping the game-mod install (-NoGameMod)"
} else {
    Step "installing as the launcher's game-mod build"
    # The launcher (0.3.0+ of the fork) swaps the game-mod build into every
    # version at launch, new versions included: this is what keeps the mod
    # in after the launcher updates the game.
    $ModDir = Join-Path $DataDir "game-mod"
    New-Item -ItemType Directory -Force -Path $ModDir | Out-Null
    Copy-Item $GameExe (Join-Path $ModDir "horizon-client.exe") -Force
    # Which game the build is for; the launcher checks it before swapping in.
    "26.3" | Set-Content (Join-Path $ModDir "game-version.txt")
    Write-Host "Kept in $ModDir"
    $Versions = Join-Path $DataDir "versions"
    if (Test-Path $Versions) {
        # Version folders already installed get the build now; ones without
        # a .installed marker are incomplete and left alone.
        Get-ChildItem $Versions -Directory | ForEach-Object {
            if (-not (Test-Path (Join-Path $_.FullName ".installed"))) { return }
            $Exe = Join-Path $_.FullName "horizon-client.exe"
            if ((Test-Path $Exe) -and -not (Test-Path "$Exe.upstream")) {
                Copy-Item $Exe "$Exe.upstream" -Force
            }
            Copy-Item $GameExe $Exe -Force
        }
        Write-Host "Every installed version plays it now."
    } else {
        Write-Host "No installed versions yet: the launcher will apply it to the first one."
    }
}

Step "done"
Write-Host "To play:"
Write-Host "  1. Prepare the game's resources from your own Minecraft (the launcher's Play page, or horizon-prepare)."
Write-Host "  2. Start the game from the launcher (any version; e4mc needs no Steam and no port forwarding)."
Write-Host "  3. Open a world, pause, Open to LAN: the world publishes itself and the chat shows"
Write-Host "     its address (something like mc.e4mc.link/xxxx); anyone with it joins."
Write-Host "     Play with Friends has the details, and Stop Publishing takes it down."
Write-Host ""
Write-Host "To go back to vanilla: empty the game-mod folder and rename each version's"
Write-Host "horizon-client.exe.upstream back to horizon-client.exe."
Write-Host ""
Write-Host "The port's documentation is docs\e4mc.md in the launcher checkout."
