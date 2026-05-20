# Cross-Building & Cross-Testing

Slides & code.

Rust User Group Leipzig 2026-05-19

## Synosis

A tiny Rust binary that prints its own name and a description of the platform
it is running on. It is built and tested for three architectures:

| Architecture        | Cargo target triple              | Notes                |
|---------------------|----------------------------------|----------------------|
| x86_64              | `x86_64-unknown-linux-gnu`       | native host          |
| ARMv7 (32-bit)      | `armv7-unknown-linux-gnueabihf`  | hard-float           |
| ARMv8 (64-bit)      | `aarch64-unknown-linux-gnu`      | a.k.a. aarch64       |

## What it reports

When run, `crossdemo` prints:

- **Architecture** — Rust's `target_arch` (`x86_64` / `arm` / `aarch64`), a
  friendly family name, the pointer width, and the `uname` machine string.
- **Operating system** — kernel name and release (the `uname -r` equivalent)
  plus the full kernel version, obtained via the `uname(2)` syscall.
- **C library** — the libc flavour (glibc vs musl, determined at compile
  time), how the C runtime is linked (static/dynamic), and two glibc
  versions:
  - **runtime** — the glibc actually loaded into the process, read via
    `gnu_get_libc_version()`.
  - **built against** — the glibc the binary was *compiled* against, baked
    in at build time by `build.rs` from the `__GLIBC__` / `__GLIBC_MINOR__`
    header macros. When this differs from the runtime value, the binary was
    built on one glibc and run against another.
- **Network hardware** — *only when built with the `hardware` Cargo
  feature* — the first physical network interface, its kernel driver,
  PCI/virtio IDs and a friendly chip name, all read from sysfs. The
  `emulate-*` recipes enable this feature and exercise it against a network
  card emulated by qemu-system (see [emulate-\*](#emulate---full-system-emulation-with-emulated-hardware)).

Example output (ARMv8 build, run under emulation):

```
crossdemo 0.1.0
===============
Architecture:
  reported by Rust : aarch64
  family           : ARM (64-bit, ARMv8)
  pointer width    : 64-bit
  machine (uname)  : aarch64
Operating system:
  kernel           : Linux 6.8.0-117-generic
  kernel version   : #117~22.04.1-Ubuntu SMP ...
C library:
  type                  : glibc (GNU C Library)
  linkage               : dynamic
  glibc (runtime)       : 2.35
  glibc (built against) : 2.35
```

## Project layout

```
crossdemo/
├── Cargo.toml
├── build.rs                bakes in the compile-time glibc version
├── justfile                build/test/run recipes for every method
├── README.md
├── .cargo/config.toml      cross-linkers + qemu-user runners (in-repo)
├── src/
│   ├── lib.rs              platform-introspection logic + tests
│   ├── main.rs             thin wrapper that prints the platform info
│   └── hardware.rs         NIC probing (only with the `hardware` feature)
└── emulate/                full-system emulation track
    ├── setup.sh            downloads the Alpine guest assets
    ├── run.sh              assembles the initramfs + boots qemu-system
    ├── test-vm.sh          boots the cargo test binary inside a guest
    └── init                the guest's PID 1 (loads the NIC driver)
```

## Tests

The suite lives in `src/lib.rs` and runs on every architecture:

- `collect_is_well_formed` — gathering platform info never panics.
- `arch_specific_expectations` — **asserts different things per
  architecture** using `#[cfg(target_arch = ...)]`: 64-bit + family `x86`
  for x86_64, 32-bit ARMv7, 64-bit ARMv8, and panics on anything else.
- `glibc_version_matches_libc_kind` — glibc builds report a version,
  non-glibc builds do not.
- `glibc_build_version_is_plausible` — the baked-in compile-time glibc
  version, when present, is a well-formed `major.minor` pair.
- `probe_never_panics`, `known_models_resolve` — *only with the `hardware`
  feature, in `src/hardware.rs`* — NIC probing never panics, and the
  chip-ID table resolves the cards QEMU emulates.
- `vm_emulated_nic_is_a_qemu_chip` — *only when the test binary is built
  static-musl* — the first NIC the probe finds is bound to one of QEMU's
  emulated drivers (`e1000` / `virtio_net`). This would fail against
  arbitrary host hardware, so it is gated to musl and only meaningful when
  run inside an `emulate-test-vm-*` guest.

The ARM test binaries are executed under **qemu user-mode emulation**, wired
up via the `runner` keys in `.cargo/config.toml`.

## Prerequisites

Everything qemu/cross-related is configured inside the repo
(`.cargo/config.toml`); the only host-level setup is the packages below.

### Rust targets (rustup)

The native target is already present with any Rust install. Add the two ARM
standard libraries:

```sh
rustup target add armv7-unknown-linux-gnueabihf aarch64-unknown-linux-gnu
```

### System packages (apt, Debian/Ubuntu)

```sh
# GCC cross toolchains — provide the ARM linkers and the cross sysroots
# (ARM dynamic linker + glibc) used for linking and emulation.
sudo apt install gcc-arm-linux-gnueabihf gcc-aarch64-linux-gnu

# qemu user-mode emulation — runs the ARM binaries and test suites on an
# x86_64 host (provides qemu-arm and qemu-aarch64).
sudo apt install qemu-user

# Host C compiler — build.rs preprocesses <features.h> to read the
# compile-time glibc version. Usually already present on a dev machine.
sudo apt install gcc
```

The native x86_64 build needs no cross toolchain or emulator — only the host
C compiler for the `build.rs` glibc probe. The cross toolchains above supply
the C compiler used for the ARM probes.

### Emulation track (optional — only for the `emulate-*` recipes)

The full-system emulation track additionally needs full-machine emulators,
UEFI firmware for the aarch64 guest, `unsquashfs` to unpack the Alpine
modules, and static-musl Rust targets (the Alpine guests are a musl distro):

```sh
sudo apt install qemu-system-x86 qemu-system-arm qemu-efi-aarch64 squashfs-tools jq
rustup target add x86_64-unknown-linux-musl \
                  armv7-unknown-linux-musleabihf \
                  aarch64-unknown-linux-musl
```

`jq` is used by `emulate/test-vm.sh` to find the cargo-built test binary
inside `target/`.

The Alpine guest kernels and root filesystems are **downloaded** by
`just emulate-setup`; they are large and reproducible, so they are not
committed (see `emulate/.gitignore`).

## Building, testing and running with `just`

Run `just <recipe>` from the project root; plain `just` lists every recipe.

The recipes come in two parallel families that demonstrate two different
cross-compilation methods:

- **`host-*`** — uses the cross-toolchains installed on the host and runs the
  ARM binaries under qemu-user (configured via `.cargo/config.toml`). This is
  the method the [Prerequisites](#prerequisites) section sets up.
- **`cross-*`** — uses [`cross`](https://github.com/cross-rs/cross), which
  builds, tests and runs each target inside a prebuilt Docker image.

Each family offers `build`, `test` and `run`, for all targets at once or for
one target individually.

### host-\* — host toolchain + qemu-user

| Recipe                    | Action                                              |
|---------------------------|-----------------------------------------------------|
| `just host-build`         | build all three targets                             |
| `just host-build-x86_64`  | build only the native x86_64 binary                 |
| `just host-build-armv7`   | build only the ARMv7 (32-bit) binary                |
| `just host-build-armv8`   | build only the ARMv8 (64-bit) binary                |
| `just host-test`          | test all targets (x86_64 native, ARM via qemu-user) |
| `just host-test-x86_64`   | test only the native x86_64 build                   |
| `just host-test-armv7`    | test the ARMv7 build under qemu-user                |
| `just host-test-armv8`    | test the ARMv8 build under qemu-user                |
| `just host-run`           | build and run all targets                           |
| `just host-run-x86_64`    | run only the native x86_64 build                    |
| `just host-run-armv7`     | run the ARMv7 build under qemu-user                 |
| `just host-run-armv8`     | run the ARMv8 build under qemu-user                 |
| `just host-exec`          | run all pre-built binaries, no rebuild              |
| `just host-exec-x86_64`   | run the pre-built x86_64 binary (native)            |
| `just host-exec-armv7`    | run the pre-built ARMv7 binary under qemu-user      |
| `just host-exec-armv8`    | run the pre-built ARMv8 binary under qemu-user      |

Unlike `host-run-*`, the `host-exec-*` recipes **never rebuild** — they just
execute whatever binary is already in `target/<triple>/release/`. This is the
way to run an artifact produced by a `cross-*` recipe under the *host's*
qemu-user: e.g. `just cross-build-armv7` then `just host-exec-armv7`. Doing
that often shows a different `glibc (built against)` value (the cross image's
glibc) than `glibc (runtime)` (the host sysroot's).

### cross-\* — Docker-based, via `cross`

`cross` runs each target inside a prebuilt Docker image that bundles the
toolchain *and* qemu, so these recipes need **none** of the host packages
from [Prerequisites](#prerequisites) — only a running Docker daemon and the
`cross` binary (`cargo install cross`). Notes:

- The first invocation per target pulls a Docker image (a few hundred MB).
- `cross` supplies its own linker/runner inside the container and ignores
  the keys in `.cargo/config.toml`.
- For the host triple (x86_64) `cross` may build directly on the host
  instead of in a container.

| Recipe                     | Action                                  |
|----------------------------|-----------------------------------------|
| `just cross-build`         | build all three targets via cross       |
| `just cross-build-x86_64`  | build only the x86_64 binary via cross  |
| `just cross-build-armv7`   | build only the ARMv7 binary via cross   |
| `just cross-build-armv8`   | build only the ARMv8 binary via cross   |
| `just cross-test`          | test all three targets via cross        |
| `just cross-test-x86_64`   | test only the x86_64 build via cross    |
| `just cross-test-armv7`    | test the ARMv7 build via cross          |
| `just cross-test-armv8`    | test the ARMv8 build via cross          |
| `just cross-run`           | build and run all targets via cross     |
| `just cross-run-x86_64`    | run only the x86_64 build via cross     |
| `just cross-run-armv7`     | run the ARMv7 build via cross           |
| `just cross-run-armv8`     | run the ARMv8 build via cross           |
| `just cross-exec`          | run all pre-built binaries, no rebuild  |
| `just cross-exec-x86_64`   | run the pre-built x86_64 binary         |
| `just cross-exec-armv7`    | run the pre-built ARMv7 binary          |
| `just cross-exec-armv8`    | run the pre-built ARMv8 binary          |

The `cross-exec-*` recipes are the cross-side counterpart of `host-exec-*`:
they **never rebuild** and do not invoke the `cross` binary at all — they are
a plain `docker run` that executes a pre-built `target/<triple>/release/`
binary inside the cross Docker image, using that image's qemu and sysroot.
Running the *same* binary via `host-exec-*` and `cross-exec-*` is a useful
experiment: the reported `glibc (runtime)` differs because the host and the
cross image carry different sysroots.

The image tag is set by the `cross_tag` variable at the top of the
`justfile`; it must match your `cross` version (`"main"` for a git build of
cross, the version number for a release).

### emulate-\* — full-system emulation with emulated hardware

The `host-*` and `cross-*` families use qemu **user-mode** emulation, which
runs a single foreign-architecture *process* and cannot emulate hardware. The
`emulate-*` family uses qemu **full-system** emulation: it boots a real
Alpine Linux kernel in a virtual machine with an emulated network card, and
runs a binary built with the `hardware` Cargo feature so the demo probes that
card and reports its driver and chip model.

- Binaries are **static-musl** builds (the Alpine guest is a musl distro), so
  these builds report `C library: musl` rather than glibc.
- The guest is a small initramfs — an Alpine root filesystem + the binary +
  the NIC kernel modules — assembled by `emulate/run.sh`, booting to the
  `emulate/init` script.
- x86_64 and aarch64 get an emulated Intel **e1000** (PCI); the 32-bit ARM
  `virt` machine has no PCI host, so armv7 gets a **virtio-net** card on the
  MMIO transport. The demo reports whichever driver the guest kernel binds.
- x86_64 runs KVM-accelerated; the ARM guests are fully emulated (slower).

Run `just emulate-setup` once to download the Alpine guest assets.

| Recipe                       | Action                                        |
|------------------------------|-----------------------------------------------|
| `just emulate-setup`         | download the Alpine guest assets (one-time)   |
| `just emulate-build`         | build the hardware-enabled binary, all archs  |
| `just emulate-build-x86_64`  | build only the x86_64 emulation binary        |
| `just emulate-build-armv7`   | build only the ARMv7 emulation binary         |
| `just emulate-build-armv8`   | build only the ARMv8 emulation binary         |
| `just emulate-test`          | run the test suite *on the host*, fast        |
| `just emulate-test-vm`       | run the test suite *inside* every guest       |
| `just emulate-test-vm-x86_64`| run the test suite inside the x86_64 guest    |
| `just emulate-test-vm-armv7` | run the test suite inside the ARMv7 guest     |
| `just emulate-test-vm-armv8` | run the test suite inside the ARMv8 guest     |
| `just emulate-run`           | build + boot the guest, all architectures     |
| `just emulate-run-x86_64`    | build + boot the x86_64 guest                 |
| `just emulate-run-armv7`     | build + boot the ARMv7 guest                  |
| `just emulate-run-armv8`     | build + boot the ARMv8 guest                  |
| `just emulate-exec`          | boot every guest from built binaries          |
| `just emulate-exec-x86_64`   | boot the x86_64 guest, no rebuild             |
| `just emulate-exec-armv7`    | boot the ARMv7 guest, no rebuild              |
| `just emulate-exec-armv8`    | boot the ARMv8 guest, no rebuild              |

There are two flavours of test:

- **`emulate-test`** runs the suite *on the host* (fast, no VM). Six tests;
  the musl-only `vm_emulated_nic_is_a_qemu_chip` is excluded by `cfg`.
- **`emulate-test-vm-*`** builds the cargo test binary for the matching musl
  target (`cargo test --no-run`), drops it into the initramfs as the guest's
  payload, boots the VM, and reads libtest's verdict from the serial
  console. Seven tests pass, including the integration test that asserts the
  bound NIC driver is one of QEMU's emulated chips. This is a full
  round-trip: same code, executed inside an actual emulated machine against
  an actual emulated NIC.

### Other

| Recipe              | Action                                           |
|---------------------|--------------------------------------------------|
| `just`              | list all recipes                                 |
| `just clean`        | remove all build artifacts                       |
| `just emulate-clean`| remove generated initramfs images (keeps assets) |

Built binaries land in `target/<triple>/release/crossdemo`.

## Incremental recompilation across targets

Cargo's automatic recompile-on-change works for the ARM targets exactly as it
does for the host — no manual rebuilds required:

- **Builds are per-target.** Each triple gets its own directory under
  `target/` (e.g. `target/aarch64-unknown-linux-gnu/`) with an independent
  fingerprint database. Editing a source file and re-running
  `just host-run-armv7` recompiles only what changed for that target.
- **The cross settings are not command-line arguments.** The `linker` and
  `runner` live in `.cargo/config.toml`, which Cargo re-reads on every
  invocation — so they are applied automatically and nothing is lost between
  runs. The `host-*` recipes are plain `cargo build/run/test --target <triple>`.
- **Targets do not invalidate each other.** Because the build directories are
  separate, alternating between architectures (e.g. `just host-run-armv7` and
  `just host-run-x86_64`) does not cause rebuild thrashing — each keeps its
  own warm incremental cache.
- **Caveat — first build per target.** The *initial* build of a given triple
  is a full build (it must compile dependencies and link against that
  target's std from scratch). Every change after that is incremental.
- Editing `.cargo/config.toml` itself (e.g. changing the `linker`) is
  detected by Cargo and triggers a rebuild/relink as needed. Changing only
  the `runner` does not, since it affects execution rather than compilation.

## Notes

- Under qemu-user, `uname` reports the **host** kernel release. qemu's
  `-r <release>` flag can override this if deterministic output is needed.
- qemu-user emulates a single Linux process and cannot emulate hardware;
  emulating a network card needs qemu **full-system** emulation, which is
  what the `emulate-*` recipes do.
- The `emulate-*` guests run an Alpine kernel, so `uname` there reports the
  Alpine kernel release (e.g. `6.18.22-0-virt`) rather than the host's.
