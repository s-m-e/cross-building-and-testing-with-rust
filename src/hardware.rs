//! Network-hardware probing — compiled only with the `hardware` feature.
//!
//! This module identifies the **first physical network interface** on the
//! system and the hardware behind it, by reading Linux sysfs. It is
//! deliberately name-agnostic: it does not look for `eth0` or any particular
//! name, it picks whichever physical interface sorts first. That makes it
//! work unchanged on a real host (`enp0s31f6`, ...) and inside an emulated
//! VM (`eth0`).
//!
//! Everything here is plain file/symlink reading — no extra dependencies and
//! no special privileges. On a machine with no physical NIC the probe simply
//! returns `None`.

use std::fs;
use std::path::Path;

/// Root of the kernel's network-interface view.
const SYS_NET: &str = "/sys/class/net";

/// A physical network interface and the hardware behind it.
pub struct NetworkDevice {
    /// Interface name as the kernel assigned it (e.g. `eth0`, `enp0s31f6`).
    pub interface: String,
    /// Kernel driver bound to the device (e.g. `e1000`, `virtio_net`).
    pub driver: Option<String>,
    /// PCI `vendor:device` IDs (hex, no `0x`), when on a PCI-like bus.
    pub pci_id: Option<(String, String)>,
    /// Friendly chip name, if the PCI ID is one we recognise.
    pub model: Option<&'static str>,
}

/// Probe the first physical network interface.
///
/// "Physical" means the interface has a `device` symlink in sysfs, which
/// rules out `lo`, bridges (`docker0`, `virbr0`), and other virtual
/// interfaces. Interfaces are visited in sorted order, so the result is
/// stable. Returns `None` when no physical interface exists.
pub fn probe_first_nic() -> Option<NetworkDevice> {
    let mut names: Vec<String> = fs::read_dir(SYS_NET)
        .ok()?
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();

    for name in names {
        let device = Path::new(SYS_NET).join(&name).join("device");
        // The `device` symlink is what marks a real, bus-attached interface.
        if !device.exists() {
            continue;
        }
        let driver = fs::read_link(device.join("driver"))
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()));
        let pci_id = read_pci_id(&device);
        let model = pci_id.as_ref().and_then(|(v, d)| lookup_model(v, d));
        return Some(NetworkDevice {
            interface: name,
            driver,
            pci_id,
            model,
        });
    }
    None
}

/// Read the `vendor` and `device` sysfs attributes (e.g. `0x8086`, `0x100e`)
/// and return them as bare hex strings without the `0x` prefix.
fn read_pci_id(device: &Path) -> Option<(String, String)> {
    let strip = |s: String| s.trim().trim_start_matches("0x").to_string();
    let vendor = strip(fs::read_to_string(device.join("vendor")).ok()?);
    let dev = strip(fs::read_to_string(device.join("device")).ok()?);
    Some((vendor, dev))
}

/// Map the handful of NIC chips QEMU commonly emulates to friendly names.
///
/// `vendor` and `device` are bare lowercase hex strings (see [`read_pci_id`]).
pub fn lookup_model(vendor: &str, device: &str) -> Option<&'static str> {
    match (vendor, device) {
        ("8086", "100e") => Some("Intel 82540EM Gigabit Ethernet (e1000)"),
        ("8086", "10d3") => Some("Intel 82574L Gigabit Ethernet (e1000e)"),
        ("8086", "1209") => Some("Intel 8255x 10/100 Ethernet (eepro100)"),
        ("1af4", "1000") => Some("Virtio network device, PCI legacy (virtio-net)"),
        ("1af4", "1041") => Some("Virtio network device, PCI modern (virtio-net)"),
        // QEMU's virtio devices on the MMIO transport report a virtio vendor
        // of "QEMU" (0x554d4551) and the virtio device ID (1 = network).
        ("554d4551", "0001") => Some("Virtio network device, MMIO transport (virtio-net)"),
        ("10ec", "8139") => Some("Realtek RTL8139 10/100 Ethernet (8139cp/8139too)"),
        ("1022", "2000") => Some("AMD PCnet32 LANCE (pcnet)"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Probing must never panic, whatever the host looks like, and any
    /// interface it returns must at least have a non-empty name.
    #[test]
    fn probe_never_panics() {
        if let Some(nic) = probe_first_nic() {
            assert!(!nic.interface.is_empty());
        }
    }

    /// The known-chip table resolves QEMU's e1000 and rejects nonsense.
    #[test]
    fn known_models_resolve() {
        assert!(lookup_model("8086", "100e").is_some());
        assert!(lookup_model("1af4", "1000").is_some());
        assert!(lookup_model("554d4551", "0001").is_some());
        assert!(lookup_model("dead", "beef").is_none());
    }
}
