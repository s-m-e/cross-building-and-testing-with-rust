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

# Run the test suite on the host.
test:
    cargo test

# Build and run the binary on the host.
run:
    cargo run

# Remove all build artifacts.
clean:
    cargo clean
