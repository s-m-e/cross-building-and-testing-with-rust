#!/bin/sh
# Download the Alpine guest assets used by the emulation track: a kernel, a
# root filesystem, and the kernel-module subtree that holds the NIC drivers.
#
# Run once via `just emulate-setup`. Everything lands in emulate/assets/,
# which is gitignored — these files are large and reproducible, so they are
# never committed.
set -eu

VER=3.23.4
BRANCH=v3.23
MIRROR=https://dl-cdn.alpinelinux.org/alpine

here=$(cd "$(dirname "$0")" && pwd)

for arch in x86_64 armv7 aarch64; do
    dst="$here/assets/$arch"
    base="$MIRROR/$BRANCH/releases/$arch"

    # Alpine ships a VM-tuned "virt" kernel for x86_64 and aarch64, but only
    # "lts"/"rpi" for 32-bit ARM — armv7 therefore uses the generic "lts"
    # kernel. Assets are stored under flavour-neutral names.
    case "$arch" in
        armv7) flavor=lts ;;
        *)     flavor=virt ;;
    esac

    echo ">>> $arch: downloading Alpine $VER kernel ($flavor) + root filesystem"
    rm -rf "$dst"
    mkdir -p "$dst/boot"
    curl -fSL --retry 3 -o "$dst/boot/vmlinuz"      "$base/netboot/vmlinuz-$flavor"
    curl -fSL --retry 3 -o "$dst/modloop.sqfs"      "$base/netboot/modloop-$flavor"
    curl -fSL --retry 3 -o "$dst/minirootfs.tar.gz" "$base/alpine-minirootfs-$VER-$arch.tar.gz"

    # The NIC drivers are kernel modules inside Alpine's squashfs "modloop".
    # squashfs is itself a module, so the modloop cannot be mounted inside
    # the guest — extract the driver subtree (net + virtio + pci) and the
    # module metadata here, and discard the rest of the (large) modloop.
    echo ">>> $arch: extracting NIC kernel modules"
    rm -rf "$dst/modloop-tmp"
    unsquashfs -n -f -d "$dst/modloop-tmp" "$dst/modloop.sqfs" >/dev/null
    kver=$(ls "$dst/modloop-tmp/modules" | grep -E '^[0-9]')
    src="$dst/modloop-tmp/modules/$kver"
    out="$dst/modules/$kver"
    mkdir -p "$out/kernel/drivers"
    cp -a "$src/kernel/drivers/net"    "$out/kernel/drivers/net"
    cp -a "$src/kernel/drivers/virtio" "$out/kernel/drivers/virtio"
    cp -a "$src/kernel/drivers/pci"    "$out/kernel/drivers/pci" 2>/dev/null || true
    cp -a "$src/kernel/net"            "$out/kernel/net"
    cp -a "$src"/modules.* "$out/"
    rm -rf "$dst/modloop-tmp" "$dst/modloop.sqfs"
    echo ">>> $arch: ready (kernel $kver)"
done

echo "Alpine guest assets ready under emulate/assets/."
