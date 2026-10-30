# Applying the port to elyhorizon-launcher

`e4mc-port.patch` is `git format-patch` output: four commits carrying the
whole port, exactly the ones the launcher checkout holds after installing.

- base: the e4steam port already applied (its `crates\horizon-steam` in),
  on **sambukuper/elyhorizon-launcher**: the e4mc integration builds on the
  Steam port's friends plumbing. Cloning the fork's `main` and running
  `install.ps1` is the supported path; by hand, apply the e4steam patch
  first ([e4steam-rust](https://github.com/sambukuper/e4steam-rust)), then
  this one;
- `0001` **Publish the world to anyone: e4mc ported**: the crate (the
  broker, the QUIC control channel, the guest stream bridges) and its
  workspace entry;
- `0002` **Open to LAN publishes the world on its own**: the Ports start
  with the world, as the original mods did;
- `0003` **Format options_ui**, `0004` **The world options screen and
  /publish start the ports too**: the remaining integration (the world
  options screen's Open to LAN path and the `/publish` command included).

By hand:

```sh
git clone https://github.com/sambukuper/elyhorizon-launcher.git
cd elyhorizon-launcher
git am --3way /path/to/e4mc-minecraft-rust/horizon-integration/e4mc-port.patch
cargo build --release -p horizon-client --features mods,steam
```

`install.ps1` does the same, plus the build and the install into the
launcher's game-mod folder, in one command.

On Linux the same by hand, without the `steam` feature (the port's code is
platform-free; the launcher names the binary `horizon-client` there):

```sh
git clone https://github.com/sambukuper/elyhorizon-launcher.git
cd elyhorizon-launcher
git am --3way /path/to/e4mc-minecraft-rust/horizon-integration/e4mc-port.patch
cargo build --release -p horizon-client --features mods
```

`install.sh` does the same, plus the install into the launcher's game-mod
folder (`~/.local/share/elyhorizon-launcher/game-mod`) and into every
installed version, in one command.

Once applied, `crates/horizon-e4mc` in the launcher is the source of truth;
the standalone crate in this repository's `horizon-e4mc/` is the same code
(`cargo test` works there on its own; the codec tests and the live relay
probe). The original Java mod is kept in `upstream-e4mc/` for reference.
