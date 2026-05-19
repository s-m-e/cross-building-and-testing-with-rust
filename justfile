# crossdemo — build/test/run for x86_64, ARMv7 (32-bit) and ARMv8 (64-bit).
#
# Two parallel families of recipes demonstrate two cross-compilation methods:
#   host-*   uses the host's cross-toolchain + qemu-user (see .cargo/config.toml)
#   cross-*  uses `cross`, which works inside prebuilt Docker images

# Cargo target triples for the three supported platforms.
x86_64 := "x86_64-unknown-linux-gnu"
armv7  := "armv7-unknown-linux-gnueabihf"
armv8  := "aarch64-unknown-linux-gnu"

default:
    @just --list

# === host: host cross-toolchain + qemu-user ===============================
#
# These recipes use the cross-compilers installed on the host and run the
# ARM binaries under qemu-user, configured via the `linker`/`runner` keys in
# .cargo/config.toml.

# Build every target with the host toolchain.
host-build: (host-build-target x86_64) (host-build-target armv7) (host-build-target armv8)

# Build a release binary for a single target triple with the host toolchain.
host-build-target triple:
    cargo build --release --target {{triple}}

# Build only the native x86_64 binary.
host-build-x86_64: (host-build-target x86_64)

# Build only the ARMv7 (32-bit) binary.
host-build-armv7: (host-build-target armv7)

# Build only the ARMv8 (64-bit) binary.
host-build-armv8: (host-build-target armv8)

# Run the test suite for every target (x86_64 native, ARMv7/ARMv8 via qemu-user).
host-test: (host-test-target x86_64) (host-test-target armv7) (host-test-target armv8)

# Run the test suite for a single target triple (ARM via qemu-user).
host-test-target triple:
    cargo test --target {{triple}}

# Test only the native x86_64 build.
host-test-x86_64: (host-test-target x86_64)

# Test the ARMv7 (32-bit) build under qemu-user.
host-test-armv7: (host-test-target armv7)

# Test the ARMv8 (64-bit) build under qemu-user.
host-test-armv8: (host-test-target armv8)

# Build and run the binary for every target (x86_64 native, ARMv7/ARMv8 via qemu-user).
host-run: (host-run-target x86_64) (host-run-target armv7) (host-run-target armv8)

# Build and run the binary for a single target triple (ARM via qemu-user).
host-run-target triple:
    cargo run --target {{triple}}

# Run only the native x86_64 build.
host-run-x86_64: (host-run-target x86_64)

# Run the ARMv7 (32-bit) build under qemu-user.
host-run-armv7: (host-run-target armv7)

# Run the ARMv8 (64-bit) build under qemu-user.
host-run-armv8: (host-run-target armv8)

# Run an *already-built* release binary under host qemu-user, with no
# rebuild — handy for running an artifact produced by the `cross-*` recipes
# on the host's qemu. Build the binary first (`host-build-*` or
# `cross-build-*`); these recipes only execute what is already in target/.

# Run all three pre-built release binaries via the host.
host-exec: host-exec-x86_64 host-exec-armv7 host-exec-armv8

# Run the pre-built x86_64 binary directly (native, no emulation).
host-exec-x86_64:
    target/{{x86_64}}/release/crossdemo

# Run the pre-built ARMv7 (32-bit) binary under host qemu-user.
host-exec-armv7:
    qemu-arm -L /usr/arm-linux-gnueabihf target/{{armv7}}/release/crossdemo

# Run the pre-built ARMv8 (64-bit) binary under host qemu-user.
host-exec-armv8:
    qemu-aarch64 -L /usr/aarch64-linux-gnu target/{{armv8}}/release/crossdemo

# === cross: Docker-based cross-compilation ================================
#
# `cross` is a drop-in cargo replacement that builds, tests and runs each
# target inside a prebuilt Docker image carrying the toolchain *and* qemu.
# It needs no host cross-toolchain, no `rustup target add` and no qemu-user
# install — everything ships in the container. It also supplies its own
# `linker`/`runner` inside the container, ignoring the keys in
# .cargo/config.toml. Requires a running Docker daemon.
#
# Note: for the host triple (x86_64) cross may skip the container and build
# directly on the host.

# Build every target with cross.
cross-build: (cross-build-target x86_64) (cross-build-target armv7) (cross-build-target armv8)

# Build a single target triple with cross.
cross-build-target triple:
    cross build --release --target {{triple}}

# Build only the x86_64 binary with cross.
cross-build-x86_64: (cross-build-target x86_64)

# Build only the ARMv7 (32-bit) binary with cross.
cross-build-armv7: (cross-build-target armv7)

# Build only the ARMv8 (64-bit) binary with cross.
cross-build-armv8: (cross-build-target armv8)

# Test every target with cross (ARM via the image's bundled qemu).
cross-test: (cross-test-target x86_64) (cross-test-target armv7) (cross-test-target armv8)

# Test a single target triple with cross.
cross-test-target triple:
    cross test --target {{triple}}

# Test only the x86_64 build with cross.
cross-test-x86_64: (cross-test-target x86_64)

# Test the ARMv7 (32-bit) build with cross.
cross-test-armv7: (cross-test-target armv7)

# Test the ARMv8 (64-bit) build with cross.
cross-test-armv8: (cross-test-target armv8)

# Build and run every target with cross (ARM via the image's bundled qemu).
cross-run: (cross-run-target x86_64) (cross-run-target armv7) (cross-run-target armv8)

# Build and run a single target triple with cross.
cross-run-target triple:
    cross run --target {{triple}}

# Run only the x86_64 build with cross.
cross-run-x86_64: (cross-run-target x86_64)

# Run the ARMv7 (32-bit) build with cross.
cross-run-armv7: (cross-run-target armv7)

# Run the ARMv8 (64-bit) build with cross.
cross-run-armv8: (cross-run-target armv8)

# === utilities ============================================================

# Remove all build artifacts.
clean:
    cargo clean
