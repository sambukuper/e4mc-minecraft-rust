#!/usr/bin/env bash
# e4mc-minecraft-rust installer for Linux.
#
# Puts the e4mc Rust port (public multiplayer over the e4mc relay) into an
# elyhorizon-launcher checkout, builds it, and installs it into the
# launcher's game versions:
#   1. finds an elyhorizon-launcher clone (or clones sambukuper's fork),
#   2. applies the port with `git am` (skipped when it is already in),
#   3. builds horizon-client with the `mods` feature (no Steam: e4mc needs
#      no Steam library and the launcher copies only what sits in game-mod),
#   4. installs the built game as the launcher's game-mod build: every
#      installed version, new ones included, plays it (the launcher swaps
#      it in at launch; each version's own binary is kept as .upstream).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash
#   ./install.sh [--launcher-dir DIR] [--data-dir DIR] [--patch FILE] [--skip-build] [--no-game-mod] [--with-launcher]
#
# Requirements: Linux x64, git, Rust 1.90+ (rustup), curl. The game needs its
# resources prepared from your own copy of Minecraft (the launcher's Play
# page does that).
set -euo pipefail

LauncherRepo="https://github.com/sambukuper/elyhorizon-launcher.git"
PatchUrl="https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/horizon-integration/e4mc-port.patch"

LauncherDir=""
DataDirArg=""
PatchPath=""
SkipBuild=0
NoGameMod=0
WithLauncher=0

usage() {
    cat <<'EOF'
e4mc-minecraft-rust installer for Linux.

Installs the e4mc Rust port into an elyhorizon-launcher checkout, builds it
and puts it into the launcher's game versions.

Usage:
  curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash
  ./install.sh [options]

Options:
  --launcher-dir DIR  an existing elyhorizon-launcher checkout (default: one
                      next to the current directory, or a fresh clone)
  --data-dir DIR      the launcher's data folder (default: $XDG_DATA_HOME/elyhorizon-launcher)
  --patch FILE        apply a local patch instead of downloading it
  --skip-build        only integrate; install an existing target/release build
  --no-game-mod       build into the checkout without installing as the game-mod build
  --with-launcher     also build the launcher (needs GPUI's system packages)
  -h, --help          this text
EOF
}

fail() {
    printf '\ne4mc: %s\n' "$1" >&2
    exit 1
}

step() {
    printf '\n== e4mc: %s\n' "$1"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --launcher-dir)   LauncherDir="${2:?--launcher-dir needs a path}"; shift 2 ;;
        --data-dir)       DataDirArg="${2:?--data-dir needs a path}"; shift 2 ;;
        --patch)          PatchPath="${2:?--patch needs a file}"; shift 2 ;;
        --skip-build)     SkipBuild=1; shift ;;
        --no-game-mod)    NoGameMod=1; shift ;;
        --with-launcher)  WithLauncher=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                fail "unknown option $1 (see --help)" ;;
    esac
done

# The launcher's data folder, as launcher/src/backend.rs data_dir() resolves it:
# HORIZON_LAUNCHER_HOME, else dirs::data_dir(): $XDG_DATA_HOME/elyhorizon-launcher.
data_dir() {
    if [ -n "$DataDirArg" ]; then
        printf '%s\n' "$DataDirArg"
    elif [ -n "${HORIZON_LAUNCHER_HOME:-}" ]; then
        printf '%s\n' "$HORIZON_LAUNCHER_HOME"
    else
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/elyhorizon-launcher"
    fi
}

# The Minecraft version the checkout's game targets (horizon-core's
# VANILLA_VERSION), the same value the launcher falls back to.
game_version_of() {
    local file="$1/crates/horizon-core/src/version.rs" version=""
    if [ -f "$file" ]; then
        version=$(sed -n 's/^pub const VANILLA_VERSION: &str = "\(.*\)";$/\1/p' "$file" | head -n 1)
    fi
    printf '%s\n' "${version:-26.3}"
}

# A version folder's game, from its research-lock.json (the launcher's own
# source, backend.rs game_version_at); our version when it says nothing.
version_of_version_dir() {
    local dir="$1" version=""
    if [ -f "$dir/research-lock.json" ]; then
        version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$dir/research-lock.json" | head -n 1)
    fi
    printf '%s\n' "${version:-$GameVersion}"
}

step "finding the launcher"
command -v git >/dev/null || fail "git is required."
if [ -z "$LauncherDir" ]; then
    for candidate in "$PWD/elyhorizon-launcher" "$PWD/../elyhorizon-launcher" "$PWD"; do
        if [ -d "$candidate/crates/horizon-client" ]; then
            LauncherDir="$candidate"
            break
        fi
    done
fi
if [ -z "$LauncherDir" ]; then
    echo "No elyhorizon-launcher found here; cloning $LauncherRepo (this can take a minute)..."
    git clone --branch main "$LauncherRepo" elyhorizon-launcher ||
        fail "git clone failed. Is git installed and reachable? You can also pass --launcher-dir <path to your checkout>."
    LauncherDir="$PWD/elyhorizon-launcher"
fi
LauncherDir=$(cd "$LauncherDir" && pwd)
if [ ! -f "$LauncherDir/Cargo.toml" ] || [ ! -d "$LauncherDir/crates/horizon-client" ]; then
    fail "$LauncherDir is not an elyhorizon-launcher checkout (no Cargo.toml / crates/horizon-client)."
fi
echo "Launcher: $LauncherDir"
GameVersion=$(game_version_of "$LauncherDir")
echo "Game: $GameVersion"

step "integrating the port"
if [ -d "$LauncherDir/crates/horizon-e4mc" ]; then
    echo "crates/horizon-e4mc already exists: the port is in, nothing to apply."
else
    if [ ! -d "$LauncherDir/crates/horizon-steam" ]; then
        fail "this checkout has no Steam port (crates/horizon-steam); e4mc's integration builds on it. Clone $LauncherRepo (or pull its main) and try again."
    fi
    if [ -z "$PatchPath" ]; then
        PatchPath=$(mktemp)
        echo "Downloading the port patch..."
        curl -fsSL "$PatchUrl" -o "$PatchPath" ||
            fail "couldn't download the patch: $PatchUrl"
    fi
    if [ ! -f "$PatchPath" ]; then
        fail "patch file not found: $PatchPath"
    fi
    # git am needs an identity; supply one only when the machine has none.
    identity=()
    if [ -z "$(git -C "$LauncherDir" config user.email || true)" ]; then
        identity=(-c user.name="e4mc installer" -c user.email="e4mc@localhost")
    fi
    echo "Applying the port as commits (git am)..."
    if ! git -C "$LauncherDir" "${identity[@]}" am --3way "$PatchPath"; then
        git -C "$LauncherDir" am --abort 2>/dev/null || true
        fail "the patch didn't apply: this checkout isn't the base the port was made on. Clone $LauncherRepo (or pull its main) and try again."
    fi
    echo "Applied: horizon-e4mc crate, client integration, auto-publish, docs (4 commits)."
fi

GameBinary="$LauncherDir/target/release/horizon-client"
if [ "$SkipBuild" = 1 ]; then
    step "skipping the build (--skip-build)"
    if [ ! -x "$GameBinary" ]; then
        echo "No build at $GameBinary yet; nothing to install."
        echo "Build later with:"
        echo "  cd \"$LauncherDir\""
        echo "  cargo build --release -p horizon-client --features mods"
        exit 0
    fi
    echo "Installing the existing build at $GameBinary."
else
    step "building the game (cargo release; half an hour on a laptop)"
    command -v cargo >/dev/null || fail "cargo is required; Rust 1.90+ from https://rustup.rs"
    (
        cd "$LauncherDir"
        cargo build --release -p horizon-client --features mods
    ) || fail "cargo build failed. Rust 1.90+ is required: https://rustup.rs then try again."
fi
if [ ! -x "$GameBinary" ]; then
    fail "the build finished but horizon-client isn't at $GameBinary."
fi

if [ "$WithLauncher" = 1 ]; then
    step "building the launcher (GPUI; needs the desktop's development packages)"
    if [ ! -f "$LauncherDir/launcher/Cargo.toml" ]; then
        fail "no launcher/ workspace in $LauncherDir."
    fi
    echo "Debian/Ubuntu packages: sudo apt-get install -y libxkbcommon-x11-dev libwayland-dev libx11-xcb-dev libfontconfig-dev libvulkan-dev libasound2-dev libudev-dev"
    echo "Fedora: sudo dnf install -y libxkbcommon-devel wayland-devel libxcb-devel fontconfig-devel vulkan-loader-devel alsa-lib-devel systemd-devel"
    (
        cd "$LauncherDir/launcher"
        cargo build --release
    ) || fail "the launcher didn't build; install the packages listed above and try again."
    echo "Launcher: $LauncherDir/launcher/target/release/elyhorizon-launcher"
fi

if [ "$NoGameMod" = 1 ]; then
    step "skipping the game-mod install (--no-game-mod)"
else
    step "installing as the launcher's game-mod build"
    # The launcher (0.3.0+ of the fork) swaps the game-mod build into every
    # version at launch, new versions included: this is what keeps the mod
    # in after the launcher updates the game.
    ModDir="$(data_dir)/game-mod"
    mkdir -p "$ModDir"
    # Executable: the launcher copies the file as it finds it (std::fs::copy keeps the mode).
    install -m 0755 "$GameBinary" "$ModDir/horizon-client"
    # Which game the build is for; the launcher checks it before swapping in.
    printf '%s\n' "$GameVersion" > "$ModDir/game-version.txt"
    echo "Kept in $ModDir"
    Versions="$(data_dir)/versions"
    if [ -d "$Versions" ]; then
        installed=0
        skipped=0
        for dir in "$Versions"/*/; do
            [ -d "$dir" ] || continue
            tag=$(basename "$dir")
            # Versions without the launcher's marker are incomplete and left alone.
            [ -f "$dir/.installed" ] || continue
            target="$dir/horizon-client"
            theirs=$(version_of_version_dir "$dir")
            if [ "$theirs" != "$GameVersion" ]; then
                echo "  $tag plays game $theirs, not $GameVersion: left alone (the launcher would ignore the build)."
                skipped=$((skipped + 1))
                continue
            fi
            # The version's own binary is kept once; a second install never overwrites it,
            # and one that already is the mod is not "kept" over the real original.
            if [ -f "$target" ] && [ ! -e "$target.upstream" ] && ! cmp -s "$GameBinary" "$target"; then
                cp -p "$target" "$target.upstream"
            fi
            install -m 0755 "$GameBinary" "$target"
            # The mod's companions (a Steam API library on Windows; nothing on Linux so far).
            for file in "$ModDir"/*; do
                [ -f "$file" ] || continue
                name=$(basename "$file")
                case "$name" in
                    horizon-client|game-version.txt|*.upstream) continue ;;
                esac
                cp -p "$file" "$dir/$name"
            done
            installed=$((installed + 1))
        done
        echo "Every installed version plays it now ($installed updated, $skipped skipped)."
    else
        echo "No installed versions yet: the launcher will apply it to the first one."
        echo "(Game versions live in $(data_dir)/versions; is the launcher installed and has it installed a version?)"
    fi
fi

step "done"
cat <<EOF
To play:
  1. Prepare the game's resources from your own Minecraft (the launcher's Play page, or horizon-prepare).
  2. Start the game from the launcher (any version; e4mc needs no Steam and no port forwarding).
     Without a launcher build yet: run this script again with --with-launcher, or start
     $LauncherDir/launcher/target/release/elyhorizon-launcher.
  3. Open a world, pause, Open to LAN: the world publishes itself and the chat shows
     its address (something like mc.e4mc.link/xxxx); anyone with it joins.
     Play with Friends has the details, and Stop Publishing takes it down.

To go back to vanilla: empty the game-mod folder and rename each version's
horizon-client.upstream back to horizon-client.

The port's documentation is docs/e4mc.md in the launcher checkout.
EOF
