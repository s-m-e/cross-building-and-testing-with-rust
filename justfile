# crossdemo — build for x86_64, ARMv7 (32-bit) and ARMv8 (64-bit).

# Cargo target triples for the three supported platforms.
x86_64 := "x86_64-unknown-linux-gnu"
armv7  := "armv7-unknown-linux-gnueabihf"
armv8  := "aarch64-unknown-linux-gnu"

# Build release binaries for all three targets.
default: build

# Build for every supported target.
build: (build-target x86_64) (build-target armv7) (build-target armv8)

# Build a release binary for a single target triple, installing the
# matching Rust standard library first if necessary.
build-target triple:
    cargo build --release --target {{triple}}

# Build only the native x86_64 binary.
x86_64: (build-target x86_64)

# Build only the ARMv7 (32-bit) binary.
armv7: (build-target armv7)

# Build only the ARMv8 (64-bit) binary.
armv8: (build-target armv8)

# Run the test suite for every target: x86_64 natively, ARMv7 and ARMv8
# under qemu-user (see the `runner` keys in .cargo/config.toml).
test: (test-target x86_64) (test-target armv7) (test-target armv8)

# Run the test suite for a single target triple. ARM targets are executed
# transparently under qemu-user via the configured Cargo runner.
test-target triple:
    cargo test --target {{triple}}

# Test only the native x86_64 build.
test-x86_64: (test-target x86_64)

# Test the ARMv7 (32-bit) build under qemu-user.
test-armv7: (test-target armv7)

# Test the ARMv8 (64-bit) build under qemu-user.
test-armv8: (test-target armv8)

# Build and run the binary for every target: x86_64 natively, ARMv7 and
# ARMv8 under qemu-user (see the `runner` keys in .cargo/config.toml).
run: (run-target x86_64) (run-target armv7) (run-target armv8)

# Build and run the binary for a single target triple. ARM targets are
# executed transparently under qemu-user via the configured Cargo runner.
run-target triple:
    cargo run --target {{triple}}

# Run only the native x86_64 build.
run-x86_64: (run-target x86_64)

# Run the ARMv7 (32-bit) build under qemu-user.
run-armv7: (run-target armv7)

# Run the ARMv8 (64-bit) build under qemu-user.
run-armv8: (run-target armv8)

# Remove all build artifacts.
clean:
    cargo clean
