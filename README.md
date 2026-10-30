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

One command installs it into an elyhorizon-launcher checkout, builds it
and puts it into the launcher, where every version, new ones included,
plays it:

```powershell
irm https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.ps1 | iex
```

The script finds (or clones)
[sambukuper/elyhorizon-launcher](https://github.com/sambukuper/elyhorizon-launcher),
applies the port as commits with `git am` (skipped when it is already in),
builds `horizon-client` and installs the build as the launcher's game-mod
build: the launcher swaps it into each version at launch and keeps each
version's own binary as `horizon-client.exe.upstream`. Options:
`-LauncherDir <path>` for an existing checkout, `-SkipBuild` to only
integrate, `-NoGameMod` to build without installing.

You need Windows x64, git, Rust 1.90+ ([rustup](https://rustup.rs)) and a
copy of Minecraft: Java Edition 26.3 (the launcher prepares the game's
resources from it). The `steam` feature is built in because the port ships
beside the [e4steam port](https://github.com/sambukuper/e4steam-rust) in
the same fork; e4mc itself needs no Steam.

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
| `install.ps1` | The installer the one-liner above runs |
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

Установка в elyhorizon-launcher одной командой, со сборкой и установкой в
лаунчер (играется из любой версии, включая будущие):

```powershell
irm https://raw.githubusercontent.com/sambukuper/e4mc-minecraft-rust/main/install.ps1 | iex
```

Скрипт находит (или клонирует)
[sambukuper/elyhorizon-launcher](https://github.com/sambukuper/elyhorizon-launcher),
накатывает порт коммитами через `git am` (пропускает, если он уже стоит),
собирает `horizon-client` и ставит сборку как game-mod в лаунчер: лаунчер
подменяет её в каждую версию при запуске, а родной exe версии сохраняет
рядом как `horizon-client.exe.upstream`. Параметры: `-LauncherDir <путь>`
для существующей копии, `-SkipBuild` только внедрить, `-NoGameMod` собрать
без установки.

Нужно: Windows x64, git, Rust 1.90+ ([rustup](https://rustup.rs)) и своя
копия Minecraft: Java Edition 26.3 (лаунчер готовит из неё ресурсы игры).
Фичя `steam` собрана потому, что порт стоит рядом со Steam-портом
([e4steam-rust](https://github.com/sambukuper/e4steam-rust)) в том же
форке; самому e4mc Steam не нужен.

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
