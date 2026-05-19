#!/bin/sh
# Assemble the emulation initramfs for one architecture and boot it under
# qemu-system full-system emulation, with an emulated network card attached.
# The guest loads the NIC driver and runs the crossdemo binary, whose
# `hardware` feature probes that card.
#
# Usage: emulate/run.sh <x86_64|armv7|aarch64>
# Driven by the justfile `emulate-run` / `emulate-exec` recipes.
set -eu

arch=${1:?usage: run.sh <x86_64|armv7|aarch64>}
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")

# Per-architecture settings:
#   triple   - Rust target triple (static musl, to match the Alpine guest)
#   qemu     - qemu-system command + machine/CPU
#   console  - kernel serial console
#   nic      - emulated network card; x86_64/aarch64 expose PCI so they get
#              an Intel e1000, the 32-bit ARM "virt" machine has no PCI host
#              so armv7 gets a virtio-net card on the MMIO transport
#   fw       - UEFI firmware; only aarch64 needs it (its Alpine kernel is an
#              EFI "zboot" image that qemu cannot direct-boot)
fw=
case "$arch" in
    x86_64)
        triple=x86_64-unknown-linux-musl
        qemu="qemu-system-x86_64 -enable-kvm -M q35"
        console=ttyS0
        nic="e1000,romfile=" ;;
    armv7)
        triple=armv7-unknown-linux-musleabihf
        qemu="qemu-system-arm -M virt -cpu cortex-a15"
        console=ttyAMA0
        nic="virtio-net-device" ;;
    aarch64)
        triple=aarch64-unknown-linux-musl
        qemu="qemu-system-aarch64 -M virt -cpu cortex-a57"
        console=ttyAMA0
        nic="e1000,romfile="
        fw="/usr/share/qemu-efi-aarch64/QEMU_EFI.fd" ;;
    *)
        echo "run.sh: unknown architecture '$arch'" >&2
        exit 2 ;;
esac

assets="$root/emulate/assets/$arch"
binary="$root/target/$triple/release/crossdemo"
build="$root/emulate/build/$arch"

[ -f "$assets/boot/vmlinuz" ] || { echo "run.sh: Alpine assets for $arch missing — run 'just emulate-setup'" >&2; exit 1; }
[ -d "$assets/modules" ]      || { echo "run.sh: kernel modules for $arch missing — run 'just emulate-setup'" >&2; exit 1; }
[ -f "$binary" ]              || { echo "run.sh: binary missing — run 'just emulate-build' first ($binary)" >&2; exit 1; }
[ -z "$fw" ] || [ -f "$fw" ]  || { echo "run.sh: UEFI firmware $fw missing — run 'sudo apt install qemu-efi-aarch64'" >&2; exit 1; }

# --- assemble the initramfs: Alpine root filesystem + binary + drivers -----
echo ">>> $arch: assembling initramfs"
rm -rf "$build"
mkdir -p "$build/root/lib/modules"
tar xzf "$assets/minirootfs.tar.gz" -C "$build/root"
cp -a "$assets/modules/." "$build/root/lib/modules/"
cp "$binary"        "$build/root/crossdemo"
cp "$here/init"     "$build/root/init"
chmod +x "$build/root/init" "$build/root/crossdemo"
( cd "$build/root" && find . | cpio -o -H newc 2>/dev/null | gzip ) > "$build/initramfs.cpio.gz"

# --- boot the guest --------------------------------------------------------
echo ">>> $arch: booting Alpine guest with an emulated NIC ($nic)"
echo
# `-display none -serial stdio -monitor none` puts the guest serial console
# on stdio with no QEMU monitor. `timeout --foreground` keeps qemu in the
# foreground process group so that, when launched from an interactive
# terminal, reading the serial console does not raise SIGTTIN and suspend it.
# shellcheck disable=SC2086
exec timeout --foreground 240 $qemu -m 512 \
    ${fw:+-bios "$fw"} \
    -kernel "$assets/boot/vmlinuz" \
    -initrd "$build/initramfs.cpio.gz" \
    -append "console=$console quiet" \
    -device "$nic" \
    -display none -serial stdio -monitor none -no-reboot
