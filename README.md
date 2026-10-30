<div align="center">

# e4mc-minecraft-rust

### Public multiplayer for [elyhorizon-launcher](https://github.com/sambukuper/elyhorizon-launcher): [e4mc](https://modrinth.com/project/qANg5Jrr), ported to Rust

**English** · [🇷🇺 Русский](#русская-версия)

</div>

e4mc opens a Minecraft singleplayer world to anyone, anywhere: the world
gets an address like `mc.e4mc.link/xxxx` on a public relay, and whoever
holds the address joins. No port forwarding, no VPN, no accounts. The
original mod is Java (Fabric / Forge / NeoForge). Horizon cannot run Java
mods: it is Minecraft 26.3 rewritten in Rust. So this project implements
the mod's behaviour natively in Rust.

Already have the launcher? One command puts the port into it, with nothing
to build: the modded client comes from the fork's releases, so `curl` and
`tar` are enough.

```sh
curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash -s -- --download
```

The client lands in the launcher's `game-mod/` folder next to a
`game-version.txt` for the game the release was built from, and the
launcher (0.3.0+ of the fork) swaps it into every matching version at
launch, new ones included.

Or build it yourself: one command installs it into an elyhorizon-launcher
checkout, builds it and puts it into the launcher, where every version,
new ones included, plays it:

```powershell
# Windows
irm https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.ps1 | iex
```
```sh
# Linux, from source
curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash
```

The scripts find (or clone)
[sambukuper/elyhorizon-launcher](https://github.com/sambukuper/elyhorizon-launcher),
apply the port as commits with `git am` (skipped when it is already in),
build `horizon-client` and install the build as the launcher's game-mod
build: the launcher swaps it into each version at launch and keeps each
version's own binary as `horizon-client.exe.upstream` (on Linux,
`horizon-client.upstream`). Options: `-LauncherDir <path>` /
`--launcher-dir <path>` for an existing checkout, `-SkipBuild` /
`--skip-build` to only integrate, `-NoGameMod` / `--no-game-mod` to build
without installing. On Linux, `--with-launcher` also builds the launcher
itself, and `--data-dir` picks the launcher's data folder.

Building needs git, Rust 1.90+ ([rustup](https://rustup.rs)) and a copy of
Minecraft: Java Edition 26.3 (the launcher prepares the game's resources
from it), on Windows x64 or Linux x64; `--download` needs only the copy of
Minecraft. e4mc needs no Steam anywhere, on any platform. The launcher is
a GPUI program: building it on Linux needs its
desktop packages, `libxkbcommon-x11-dev libwayland-dev libx11-xcb-dev
libfontconfig-dev libvulkan-dev libasound2-dev libudev-dev` on
Debian/Ubuntu (`libxkbcommon-devel wayland-devel libxcb-devel
fontconfig-devel vulkan-loader-devel alsa-lib-devel systemd-devel` on
Fedora), or use the launcher release's own Linux build and let the script
only install the game.

## Linux

The same flow with Linux paths:

- `--download` skips the build: it takes
  `horizon-client-linux-x86_64.tar.gz` from the newest
  [fork release](https://github.com/sambukuper/elyhorizon-launcher/releases),
  reads the Minecraft version pinned at that release's tag, and installs it
  as the game-mod build. No git, no Rust, no half-hour compile.
- The launcher's data folder is `~/.local/share/elyhorizon-launcher` (or
  `$XDG_DATA_HOME/elyhorizon-launcher`; `HORIZON_LAUNCHER_HOME` and
  `--data-dir` override it); the game's own data is `~/.local/share/horizon`.
- The build is `cargo build --release -p horizon-client --features mods`;
  `game-mod/` holds only the game binary and `game-version.txt`.
- Versions are the launcher's (`versions/v0.2.97/` with its `.installed`
  marker); the script swaps the build into each and keeps the version's own
  binary as `horizon-client.upstream`. A version of another Minecraft
  version is left alone: the launcher would ignore the build there anyway.
- To go back to vanilla: clear `~/.local/share/elyhorizon-launcher/game-mod`
  and rename each `horizon-client.upstream` back to `horizon-client`.

## What carries over from the mod

- **Open to LAN is the whole interface**, as in the mod: the world
  publishes itself the moment it opens to the network, and the chat shows
  the address. **Play with Friends** has the details, the copy button and
  **Stop Publishing**.
- **The real relay**: `broker.e4mc.link` picks one, a QUIC session (ALPN
  `quiclime`) carries the varint-JSON control channel, the relay assigns
  the domain, and one QUIC stream per guest bridges the guest and the
  integrated server byte for byte.
- **3-second keep-alives**, the guest counter, the stop that disconnects
  guests cleanly (the CONNECTION_CLOSE actually reaches them).
- The relay only opens a stream for a guest after a valid Minecraft
  handshake, which the port relies on rather than works around.

Not ported: the mod's DNS-level aliasing (`is-this-a-minecraft-server`
magic) and its ban/whitelist command tweaks, which live in Java mixins
Horizon has no counterpart for. Cross-play with the Java mod works for
guests: the relay side is the same, so a Java player joins a Horizon
world's address the normal way.

## Layout

| Path | What |
| --- | --- |
| `horizon-e4mc/` | The port as a standalone crate (`cargo test` works here on its own) |
| `horizon-integration/e4mc-port.patch` | The port as commits, `git am`-able on the launcher |
| `install.ps1` | The Windows installer the one-liner above runs |
| `install.sh` | The Linux installer: same flow, no Steam, `--download` for the prebuilt client, `--with-launcher` builds the launcher too |
| `upstream-e4mc/` | The original Java mod, for reference (its own MIT licence) |

The launcher checkout stays the source of truth once installed: the patch
is exactly the commits it holds.

<a id="русская-версия"></a>
## 🇷🇺 Русская версия

e4mc открывает одиночный мир Minecraft кому угодно и откуда угодно: мир
получает адрес вида `mc.e4mc.link/xxxx` на публичном релее, и любой, у кого
есть адрес, заходит. Без проброса портов, VPN и аккаунтов. Оригинальный мод
написан на Java (Fabric / Forge / NeoForge). Horizon не запускает Java-моды:
это Minecraft 26.3, переписанный на Rust. Поэтому этот проект повторяет
поведение мода нативно, на Rust.

Лаунчер уже стоит? Одна команда ставит порт без сборки: готовый клиент
берётся из релизов форка, нужны только curl и tar.

```sh
curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash -s -- --download
```

Клиент ложится в `game-mod/` рядом с `game-version.txt` для своей версии
игры. Лаунчер (0.3.0+ форка) подменяет его в каждой подходящей версии при
запуске, новые тоже.

Или собрать самому: установка в elyhorizon-launcher одной командой, со
сборкой и установкой в лаунчер (играется из любой версии, включая будущие):

```powershell
irm https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.ps1 | iex
```
```sh
curl -fsSL https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.sh | bash
```

Скрипт находит (или клонирует)
[sambukuper/elyhorizon-launcher](https://github.com/sambukuper/elyhorizon-launcher),
накатывает порт коммитами через `git am` (пропускает, если он уже стоит),
собирает `horizon-client` и ставит сборку как game-mod в лаунчер: лаунчер
подменяет её в каждую версию при запуске, а родной exe версии сохраняет
рядом как `horizon-client.exe.upstream` (на Linux: `horizon-client.upstream`).
Параметры: `-LauncherDir <путь>` / `--launcher-dir <путь>` для существующей
копии, `-SkipBuild` / `--skip-build` только внедрить, `-NoGameMod` /
`--no-game-mod` собрать без установки. На Linux `--with-launcher` собирает
ещё и сам лаунчер, `--data-dir` задаёт папку данных лаунчера.

Нужно для сборки: git, Rust 1.90+ ([rustup](https://rustup.rs)) и своя копия
Minecraft: Java Edition 26.3 (лаунчер готовит из неё ресурсы игры), на
Windows x64 или Linux x64. Варианту `--download` сборка не нужна, только
своя копия Minecraft. Steam e4mc не нужен нигде и ни на какой платформе.
Лаунчер — программа на GPUI: сборка на Linux требует пакетов рабочего стола
(`libxkbcommon-x11-dev libwayland-dev libx11-xcb-dev libfontconfig-dev
libvulkan-dev libasound2-dev libudev-dev` в Debian/Ubuntu,
`libxkbcommon-devel wayland-devel libxcb-devel fontconfig-devel
vulkan-loader-devel alsa-lib-devel systemd-devel` в Fedora) — либо возьмите
готовый Linux-релиз лаунчера, а скрипту оставьте только игру.

### Linux

Тот же поток, тот же результат; различаются пути и сборка:

- `--download` обходится без сборки: берёт
  `horizon-client-linux-x86_64.tar.gz` из свежего
  [релиза форка](https://github.com/sambukuper/elyhorizon-launcher/releases),
  читает версию Minecraft, закреплённую в теге этого релиза, и ставит
  клиент как game-mod. Ни git, ни Rust, ни получаса компиляции.
- Данные лаунчера: `~/.local/share/elyhorizon-launcher` (или
  `$XDG_DATA_HOME/elyhorizon-launcher`; `HORIZON_LAUNCHER_HOME` и
  `--data-dir` переопределяют), данные игры: `~/.local/share/horizon`.
- Сборка: `cargo build --release -p horizon-client --features mods`; в
  `game-mod/` только бинарь и `game-version.txt`.
- Версии ставит лаунчер (`versions/v0.2.97/` с маркером `.installed`);
  скрипт подменяет бинарь в каждой, а родной сохраняет как
  `horizon-client.upstream`. Версия под другую версию Minecraft не
  трогается: лаунчер её сборку всё равно бы проигнорировал.
- Откат к ваниле: очистить `~/.local/share/elyhorizon-launcher/game-mod` и
  вернуть каждый `horizon-client.upstream` на место `horizon-client`.

Как в игре: откройте мир, Esc, «Открыть для сети»: мир сам публикуется, и
в чате появляется адрес `mc.e4mc.link/xxxx`. Отдайте его другу, он вставит
адрес в «Прямое подключение» у себя. Пауза, Play with Friends: там кнопка
копирования и Stop Publishing.

## Credits and license

- [e4mc](https://modrinth.com/project/qANg5Jrr) by vgskye and
  contributors (MIT), the mod this port reimplements; the broker, the
  protocol and the flow are its. The original source is kept in
  `upstream-e4mc/` with its own licence.
- [Horizon](https://github.com/horizon-rust/horizon): the game and the
  launcher this integrates into; this repository's port code follows its
  GPL-3.0-only licence ([LICENSE](LICENSE)).
- Not an official Minecraft product; not affiliated with Mojang or
  Microsoft.
