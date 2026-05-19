//! Platform introspection for the `crossdemo` binary.
//!
//! Everything that is actually interesting lives here so that it can be
//! exercised by the test suite; `main.rs` is just a thin wrapper.

use std::ffi::CStr;
use std::fmt;

/// Program name, taken from the Cargo manifest at build time.
pub const NAME: &str = env!("CARGO_PKG_NAME");
/// Program version, taken from the Cargo manifest at build time.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Architecture as reported by Rust's built-in `target_arch`, e.g. `x86_64`,
/// `arm` (ARMv7, 32-bit) or `aarch64` (ARMv8, 64-bit).
pub fn arch() -> &'static str {
    std::env::consts::ARCH
}

/// A human-friendly architecture family derived from [`arch`].
pub fn arch_family() -> &'static str {
    match arch() {
        "x86_64" | "x86" => "x86",
        "arm" => "ARM (32-bit, ARMv7)",
        "aarch64" => "ARM (64-bit, ARMv8)",
        other => other,
    }
}

/// Pointer width of the target in bits (32 on ARMv7, 64 on x86_64 / ARMv8).
pub fn pointer_bits() -> usize {
    std::mem::size_of::<usize>() * 8
}

/// Which C library this binary is built against, determined at compile time.
pub fn libc_kind() -> &'static str {
    if cfg!(target_env = "musl") {
        "musl"
    } else if cfg!(target_env = "gnu") {
        "glibc (GNU C Library)"
    } else {
        "unknown"
    }
}

/// How the C runtime is linked. musl builds are static by default, glibc
/// builds are dynamic by default; this reflects the `crt-static` feature.
pub fn linkage() -> &'static str {
    if cfg!(target_feature = "crt-static") {
        "static"
    } else {
        "dynamic"
    }
}

/// Runtime glibc version, e.g. `"2.35"`.
///
/// Only available when linked against glibc, which exposes
/// `gnu_get_libc_version()`. Returns `None` on musl or other libc flavours.
#[cfg(target_env = "gnu")]
pub fn glibc_version() -> Option<String> {
    extern "C" {
        fn gnu_get_libc_version() -> *const libc::c_char;
    }
    // SAFETY: `gnu_get_libc_version` returns a pointer to a static,
    // NUL-terminated string owned by glibc.
    unsafe {
        let ptr = gnu_get_libc_version();
        if ptr.is_null() {
            None
        } else {
            Some(CStr::from_ptr(ptr).to_string_lossy().into_owned())
        }
    }
}

/// Runtime glibc version. Always `None` when not linked against glibc.
#[cfg(not(target_env = "gnu"))]
pub fn glibc_version() -> Option<String> {
    None
}

/// Convert a NUL-terminated C string field into an owned [`String`].
///
/// `c_char` is signed on x86_64 but unsigned on ARM, so we deliberately work
/// through a `*const c_char` pointer rather than the field's array type.
fn c_field(field: &[libc::c_char]) -> String {
    // SAFETY: `field` is a fixed-size buffer that the kernel fills with a
    // NUL-terminated string.
    unsafe { CStr::from_ptr(field.as_ptr()).to_string_lossy().into_owned() }
}

/// Result of the `uname(2)` system call.
struct Uname {
    sysname: String,
    release: String,
    version: String,
    machine: String,
}

fn uname() -> Option<Uname> {
    // SAFETY: `uname` only writes into the `utsname` struct we hand it.
    unsafe {
        let mut uts: libc::utsname = std::mem::zeroed();
        if libc::uname(&mut uts) != 0 {
            return None;
        }
        Some(Uname {
            sysname: c_field(&uts.sysname),
            release: c_field(&uts.release),
            version: c_field(&uts.version),
            machine: c_field(&uts.machine),
        })
    }
}

/// A snapshot of everything the program knows about its platform.
pub struct PlatformInfo {
    pub name: &'static str,
    pub version: &'static str,
    pub arch: &'static str,
    pub arch_family: &'static str,
    pub pointer_bits: usize,
    pub libc_kind: &'static str,
    pub linkage: &'static str,
    pub glibc_version: Option<String>,
    /// `(sysname, release, version, machine)` from `uname(2)`, if available.
    pub kernel: Option<(String, String, String, String)>,
}

impl PlatformInfo {
    /// Gather platform information for the current process.
    pub fn collect() -> Self {
        let kernel = uname().map(|u| (u.sysname, u.release, u.version, u.machine));
        PlatformInfo {
            name: NAME,
            version: VERSION,
            arch: arch(),
            arch_family: arch_family(),
            pointer_bits: pointer_bits(),
            libc_kind: libc_kind(),
            linkage: linkage(),
            glibc_version: glibc_version(),
            kernel,
        }
    }
}

impl fmt::Display for PlatformInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let title = format!("{} {}", self.name, self.version);
        writeln!(f, "{title}")?;
        writeln!(f, "{}", "=".repeat(title.len()))?;

        writeln!(f, "Architecture:")?;
        writeln!(f, "  reported by Rust : {}", self.arch)?;
        writeln!(f, "  family           : {}", self.arch_family)?;
        writeln!(f, "  pointer width    : {}-bit", self.pointer_bits)?;
        if let Some((_, _, _, machine)) = &self.kernel {
            writeln!(f, "  machine (uname)  : {machine}")?;
        }

        writeln!(f, "Operating system:")?;
        match &self.kernel {
            Some((sysname, release, version, _)) => {
                writeln!(f, "  kernel           : {sysname} {release}")?;
                writeln!(f, "  kernel version   : {version}")?;
            }
            None => writeln!(f, "  kernel           : <uname(2) unavailable>")?,
        }

        writeln!(f, "C library:")?;
        writeln!(f, "  type             : {}", self.libc_kind)?;
        writeln!(f, "  linkage          : {}", self.linkage)?;
        match &self.glibc_version {
            Some(v) => writeln!(f, "  glibc version    : {v}")?,
            None => writeln!(f, "  glibc version    : n/a (not linked against glibc)")?,
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Sanity check: collecting platform info never panics and the basics
    /// are populated.
    #[test]
    fn collect_is_well_formed() {
        let info = PlatformInfo::collect();
        assert_eq!(info.name, "crossdemo");
        assert!(!info.version.is_empty());
        assert!(info.pointer_bits == 32 || info.pointer_bits == 64);
    }

    /// Architecture-specific behaviour: the assertions in this single test
    /// differ depending on which target the binary was compiled for, so the
    /// test genuinely exercises something different on x86_64, ARMv7 and
    /// ARMv8.
    #[test]
    fn arch_specific_expectations() {
        let bits = pointer_bits();
        let family = arch_family();

        #[cfg(target_arch = "x86_64")]
        {
            assert_eq!(bits, 64, "x86_64 must be 64-bit");
            assert_eq!(family, "x86");
            assert_eq!(arch(), "x86_64");
        }

        #[cfg(target_arch = "arm")]
        {
            assert_eq!(bits, 32, "ARMv7 must be 32-bit");
            assert_eq!(family, "ARM (32-bit, ARMv7)");
            assert_eq!(arch(), "arm");
        }

        #[cfg(target_arch = "aarch64")]
        {
            assert_eq!(bits, 64, "ARMv8 must be 64-bit");
            assert_eq!(family, "ARM (64-bit, ARMv8)");
            assert_eq!(arch(), "aarch64");
        }

        // Guard against being compiled for an unintended architecture.
        #[cfg(not(any(
            target_arch = "x86_64",
            target_arch = "arm",
            target_arch = "aarch64"
        )))]
        panic!("unsupported architecture: {}", arch());
    }

    /// glibc builds must report a version; non-glibc builds must not.
    #[test]
    fn glibc_version_matches_libc_kind() {
        match glibc_version() {
            Some(v) => {
                assert!(cfg!(target_env = "gnu"));
                assert!(v.chars().next().is_some_and(|c| c.is_ascii_digit()));
            }
            None => assert!(!cfg!(target_env = "gnu")),
        }
    }
}
