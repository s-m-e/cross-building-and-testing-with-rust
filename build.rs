//! Build script: bake the *compile-time* glibc version into the binary.
//!
//! `gnu_get_libc_version()` (used at runtime in `src/lib.rs`) reports the
//! glibc that is actually loaded when the program runs. This script captures
//! a different number — the glibc the program was *built against* — by
//! preprocessing `<features.h>` with the target's C compiler and reading the
//! `__GLIBC__` / `__GLIBC_MINOR__` macros.
//!
//! The result is exposed to the crate as the `GLIBC_BUILD_VERSION`
//! environment variable, read back with `option_env!`. The variable is only
//! emitted for glibc (`gnu`) targets and only when the probe succeeds, so a
//! musl target or a missing compiler simply yields `None` rather than a
//! build failure.

use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    // Only glibc targets have the __GLIBC__ macros; skip musl and others.
    if env::var("CARGO_CFG_TARGET_ENV").as_deref() != Ok("gnu") {
        return;
    }

    if let Some(version) = probe_glibc_build_version() {
        println!("cargo:rustc-env=GLIBC_BUILD_VERSION={version}");
    }
}

/// Preprocess `<features.h>` with the target's C compiler and extract the
/// `__GLIBC__.__GLIBC_MINOR__` version. Returns `None` on any failure so the
/// build degrades gracefully to "unknown".
fn probe_glibc_build_version() -> Option<String> {
    let out_dir = env::var("OUT_DIR").ok()?;
    let probe = Path::new(&out_dir).join("glibc_probe.c");
    fs::write(&probe, "#include <features.h>\n").ok()?;

    // `cc` selects the compiler that matches the Cargo target (host gcc for
    // x86_64, arm-linux-gnueabihf-gcc for ARMv7, etc.). `-E -dM` only runs
    // the preprocessor and dumps every #define, so this works for the ARM
    // cross targets without executing anything.
    let compiler = cc::Build::new().get_compiler();
    let output = Command::new(compiler.path())
        .args(compiler.args())
        .args(["-E", "-dM"])
        .arg(&probe)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let defines = String::from_utf8(output.stdout).ok()?;

    let major = macro_value(&defines, "__GLIBC__")?;
    let minor = macro_value(&defines, "__GLIBC_MINOR__")?;
    Some(format!("{major}.{minor}"))
}

/// Find a `#define <name> <value>` line in preprocessor output and return the
/// value.
fn macro_value(defines: &str, name: &str) -> Option<String> {
    defines.lines().find_map(|line| {
        let rest = line.strip_prefix("#define ")?;
        let rest = rest.strip_prefix(name)?;
        // Ensure an exact name match (e.g. not `__GLIBC_MINOR__` for `__GLIBC__`).
        let value = rest.strip_prefix(' ')?;
        Some(value.trim().to_string())
    })
}
