#!/usr/bin/env bash
# e4mc-minecraft-rust installer for Linux.
#
# Puts the e4mc Rust port (public multiplayer over the e4mc relay) into the
# elyhorizon-launcher's game versions. Two ways in:
#
#   --download  take the prebuilt modded client from the fork's GitHub releases.
#               No git, no Rust, nothing to build; curl and tar are enough.
#   default     find an elyhorizon-launcher checkout (or clone sambukuper's
#               fork), apply the port with `git am` (skipped when it is
#               already in) and build horizon-client with the `mods` feature
#               (no Steam: e4mc needs no Steam library).
#
# Either way the client lands in the launcher's game-mod folder, and every
# installed version plays it (the launcher swaps it in at launch; each
# version's own binary is kept as .upstream).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash -s -- --download
#   ./install.sh --download [--data-dir DIR] [--no-game-mod]
#   ./install.sh [--launcher-dir DIR] [--data-dir DIR] [--patch FILE] [--skip-build] [--no-game-mod] [--with-launcher]
#
# Requirements: Linux x64, curl, tar. The default (source) route also wants git
# and Rust 1.90+ (rustup). The game needs its resources prepared from your own
# copy of Minecraft (the launcher's Play page does that) and the fork's
# launcher 0.3.0+ (it is what swaps the game-mod build in).
set -euo pipefail

LauncherRepo="https://github.com/sambukuper/elyhorizon-launcher.git"
PatchUrl="https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/horizon-integration/e4mc-port.patch"
VersionUrl="https://raw.githubusercontent.com/sambukuper/elyhorizon-launcher/{ref}/crates/horizon-core/src/version.rs"
ForkReleases="https://github.com/sambukuper/elyhorizon-launcher/releases"

LauncherDir=""
DataDirArg=""
PatchPath=""
ReleaseTag=""
Download=0
SkipBuild=0
NoGameMod=0
WithLauncher=0

usage() {
    cat <<'EOF'
e4mc-minecraft-rust installer for Linux.

Installs the e4mc Rust port into the launcher's game-mod folder, so every
installed version plays it.

Usage:
  curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash -s -- --download
  ./install.sh [options]

Options:
  --download          install the prebuilt client from the fork's releases
                      (no git, no Rust, nothing to build); this is what a
                      player with the launcher already installed wants
  --launcher-dir DIR  an existing elyhorizon-launcher checkout (default: one
                      next to the current directory, or a fresh clone)
  --data-dir DIR      the launcher's data folder (default: $XDG_DATA_HOME/elyhorizon-launcher)
  --patch FILE        apply a local patch instead of downloading it
  --skip-build        only integrate; install an existing target/release build
  --no-game-mod       build (or download) without installing into the launcher
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
        --download)       Download=1; shift ;;
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

if [ "$Download" = 1 ]; then
    if [ "$WithLauncher" = 1 ]; then
        fail "--download has no checkout to build the launcher from; drop --with-launcher."
    fi
    if [ -n "$LauncherDir" ]; then
        fail "--download needs no checkout; drop --launcher-dir."
    fi
    if [ -n "$PatchPath" ]; then
        fail "--download installs the prebuilt client and applies no patch; drop --patch."
    fi
    if [ "$SkipBuild" = 1 ]; then
        fail "--download already skips the build; drop --skip-build."
    fi
fi

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

# The game version a ref of the launcher pins (horizon-core's VANILLA_VERSION),
# for the download route: the release's tag is the commit its client was built
# from, so that is the version the prebuilt binary plays.
pinned_version() {
    local ref="$1" file version=""
    file=$(mktemp)
    if curl -fsSL "${VersionUrl/\{ref\}/$ref}" -o "$file" 2>/dev/null; then
        version=$(sed -n 's/^pub const VANILLA_VERSION: &str = "\(.*\)";$/\1/p' "$file" | head -n 1)
    fi
    rm -f "$file"
    printf '%s\n' "$version"
}

# A version folder's game, from its research-lock.json (the launcher's own
# source, backend.rs game_version_at); the fallback when it says nothing.
version_of_version_dir() {
    local dir="$1" fallback="${2:-}" version=""
    if [ -f "$dir/research-lock.json" ]; then
        version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$dir/research-lock.json" | head -n 1)
    fi
    printf '%s\n' "${version:-$fallback}"
}

# The game the launcher's installed versions already play; what the prebuilt
# client has to match to be swapped in. Empty when nothing is installed yet.
installed_game_version() {
    local versions dir version
    versions="$(data_dir)/versions"
    [ -d "$versions" ] || return 0
    for dir in "$versions"/*/; do
        [ -f "$dir/.installed" ] || continue
        version=$(version_of_version_dir "$dir" "")
        if [ -n "$version" ]; then
            printf '%s\n' "$version"
            return 0
        fi
    done
}

# The newest release asset whose name has a pattern; the releases API lists
# the newest first, so the first hit is the one to take. Sets ReleaseTag.
release_asset() {
    local pattern="$1" list url
    list=$(mktemp)
    curl -fsSL "https://api.github.com/repos/sambukuper/elyhorizon-launcher/releases?per_page=30" -o "$list" ||
        { rm -f "$list"; fail "couldn't reach GitHub's releases API; is the network up?"; }
    url=$(grep -o '"browser_download_url": *"[^"]*'"$pattern"'"' "$list" |
        head -n 1 | sed 's/.*"browser_download_url": *"//; s/"$//')
    rm -f "$list"
    if [ -n "$url" ]; then
        ReleaseTag=${url#*/download/}
        ReleaseTag=${ReleaseTag%%/*}
    fi
    printf '%s\n' "$url"
}

download_client() {
    local url archive dir
    url=$(release_asset 'horizon-client-linux-x86_64\.tar\.gz')
    if [ -z "$url" ]; then
        fail "no release carries horizon-client-linux-x86_64.tar.gz yet: $ForkReleases"
    fi
    GameVersion=$(pinned_version "$ReleaseTag")
    if [ -z "$GameVersion" ]; then
        GameVersion=$(pinned_version main)
    fi
    if [ -z "$GameVersion" ]; then
        GameVersion=$(installed_game_version)
    fi
    echo "Game: ${GameVersion:-26.3}"
    GameVersion=${GameVersion:-26.3}
    echo "Downloading $url"
    archive=$(mktemp)
    curl -fL --progress-bar "$url" -o "$archive" ||
        { rm -f "$archive"; fail "download failed: $url"; }
    dir=$(mktemp -d)
    tar xzf "$archive" -C "$dir" horizon-client ||
        { rm -rf "$archive" "$dir"; fail "the archive has no horizon-client."; }
    rm -f "$archive"
    GameBinary="$dir/horizon-client"
    chmod 0755 "$GameBinary"
}

build_from_source() {
    step "finding the launcher"
    command -v git >/dev/null || fail "git is required (or use --download)."
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
        command -v cargo >/dev/null || fail "cargo is required; Rust 1.90+ from https://rustup.rs (or use --download)."
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
}

if [ "$Download" = 1 ]; then
    step "the prebuilt modded client"
    command -v curl >/dev/null || fail "curl is required."
    command -v tar >/dev/null || fail "tar is required."
    download_client
    echo "Client: $GameBinary"
else
    build_from_source
fi

if [ "$NoGameMod" = 1 ]; then
    step "skipping the game-mod install (--no-game-mod)"
    echo "The client is at $GameBinary."
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
            theirs=$(version_of_version_dir "$dir" "$GameVersion")
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
            # The mod's companions (none today; the launcher copies whatever sits beside the build).
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
        if [ "$installed" -eq 0 ]; then
            if [ "$skipped" -gt 0 ]; then
                echo "No installed version plays game $GameVersion: the ones above were left alone."
                echo "Install a $GameVersion version in the launcher; it takes the game-mod build, and so will new ones."
            else
                echo "No complete versions found: the launcher will apply it to the first one."
            fi
        else
            echo "Every installed version plays it now ($installed updated, $skipped skipped)."
        fi
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
     This needs the fork's launcher 0.3.0+, the one that swaps the game-mod build in.
  3. Open a world, pause, Open to LAN: the world publishes itself and the chat shows
     its address (something like mc.e4mc.link/xxxx); anyone with it joins.
     Play with Friends has the details, and Stop Publishing takes it down.

To go back to vanilla: empty the game-mod folder and rename each version's
horizon-client.upstream back to horizon-client.
EOF
if [ "$Download" = 0 ]; then
    cat <<EOF

The port's documentation is docs/e4mc.md in the launcher checkout.
EOF
fi
