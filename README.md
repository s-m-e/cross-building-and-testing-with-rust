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
├── justfile                build/test recipes for all three targets
├── README.md
├── .cargo/config.toml      cross-linkers + qemu-user runners (in-repo)
└── src/
    ├── lib.rs              all platform-introspection logic + tests
    └── main.rs             thin wrapper that prints the platform info
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

## Building and testing with `just`

Run `just <recipe>` from the project root.

### Build

| Recipe         | Action                                            |
|----------------|---------------------------------------------------|
| `just`         | default — build release binaries for all targets  |
| `just build`   | build all three targets                           |
| `just x86_64`  | build only the native x86_64 binary               |
| `just armv7`   | build only the ARMv7 (32-bit) binary              |
| `just armv8`   | build only the ARMv8 (64-bit) binary              |

### Test

| Recipe              | Action                                                  |
|---------------------|---------------------------------------------------------|
| `just test`         | run the suite on all targets (x86_64 native, ARM via qemu) |
| `just test-x86_64`  | test only the native x86_64 build                       |
| `just test-armv7`   | test the ARMv7 build under qemu-user                    |
| `just test-armv8`   | test the ARMv8 build under qemu-user                    |

### Run

| Recipe             | Action                                                   |
|--------------------|----------------------------------------------------------|
| `just run`         | build and run the binary on all targets (x86_64 native, ARM via qemu) |
| `just run-x86_64`  | run only the native x86_64 build                         |
| `just run-armv7`   | run the ARMv7 build under qemu-user                      |
| `just run-armv8`   | run the ARMv8 build under qemu-user                      |

### Other

| Recipe        | Action                       |
|---------------|------------------------------|
| `just clean`  | remove all build artifacts   |

Built binaries land in `target/<triple>/release/crossdemo`.

## Incremental recompilation across targets

Cargo's automatic recompile-on-change works for the ARM targets exactly as it
does for the host — no manual rebuilds required:

- **Builds are per-target.** Each triple gets its own directory under
  `target/` (e.g. `target/aarch64-unknown-linux-gnu/`) with an independent
  fingerprint database. Editing a source file and re-running `just run-armv7`
  recompiles only what changed for that target.
- **The cross settings are not command-line arguments.** The `linker` and
  `runner` live in `.cargo/config.toml`, which Cargo re-reads on every
  invocation — so they are applied automatically and nothing is lost between
  runs. The `just` recipes are plain `cargo build/run/test --target <triple>`.
- **Targets do not invalidate each other.** Because the build directories are
  separate, alternating between architectures (e.g. `just run-armv7` and
  `just run-x86_64`) does not cause rebuild thrashing — each keeps its own
  warm incremental cache.
- **Caveat — first build per target.** The *initial* build of a given triple
  is a full build (it must compile dependencies and link against that
  target's std from scratch). Every change after that is incremental.
- Editing `.cargo/config.toml` itself (e.g. changing the `linker`) is
  detected by Cargo and triggers a rebuild/relink as needed. Changing only
  the `runner` does not, since it affects execution rather than compilation.

## Notes

- Under qemu-user, `uname` reports the **host** kernel release. qemu's
  `-r <release>` flag can override this if deterministic output is needed.
- qemu-user emulates a single Linux process — it cannot emulate hardware
  (USB, network devices). That requires full-system emulation
  (`qemu-system-*`) and is intentionally out of scope here.
