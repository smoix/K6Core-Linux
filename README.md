# K6Core Linux: Minimal Distribution for AMD K6 CPUs

**K6Core** is an optimized and (rather) minimal, Linux distribution designed specifically for an **AMD K6 and up** processor running on an **ALi Aladdin V** chipset motherboard — e.g. a **Gigabyte GA-5AX** or **Asus P5A** — with compatibility for VIA MVP3 chipset boards as well. It is built completely from source using **Buildroot 2025.02.1** in a Docker-based compilation environment. Pre-built images are also available.

> [!IMPORTANT]
> **Default login**: `root` / `k6core` — on the local console (`tty1`) or over SSH (`dropbear` starts automatically; the board gets its address via DHCP on `eth0`).

---

## Table of Contents
1. [Hardware-Specific Drivers & Optimizations](#1-hardware-specific-drivers--optimizations)
2. [OS Details & Packages](#2-os-details--packages)
3. [Build Instructions](#3-build-instructions)
4. [Flashing Guide](#4-flashing-guide)
5. [Disk Sizing, Alignment, and Write-Reduction](#5-disk-sizing-alignment-and-write-reduction)
6. [Build & Caching Architecture](#6-build--caching-architecture)

---

## 1. Hardware-Specific Drivers & Optimizations

* **CPU Support (`-march=k6` / `CONFIG_MK6=y`)**: Targets the base AMD K6 instruction set — i586 baseline plus MMX — while strictly omitting the `CMOV` instruction (unsupported across the entire K6 line, up to and including K6-III+) and not emitting 3DNow! (that would require `-march=k6-2`/`k6-3` instead). Since 3DNow! is simply unused rather than actively avoided, the resulting binaries run correctly on every K6-family CPU: the original K6 and K6 "Little Foot", K6-2 and K6-2+, and K6-III and K6-III+. This instruction-set target isn't actually AMD-specific — it should also run on a genuine Intel **Pentium MMX (P55C)**.
* **System Memory Layout (`CONFIG_NOHIGHMEM=y`)**: Configures a flat 32-bit low memory layout since the 512MB RAM of the system fits entirely below the kernel's 896MB high memory split. This optimizes kernel memory mappings.
* **ALi Aladdin V Chipset**:
  * `CONFIG_PCI=y` (PCI bus support)
  * `CONFIG_AGP=y` & `CONFIG_AGP_ALI=y` (ALi Aladdin V AGP controller support)
  * `CONFIG_ATA=y` & `CONFIG_PATA_ALI=y` (Native ALi IDE controller driver for ultra-reliable CompactFlash PIO/DMA transfers)
* **VIA MVP3 Chipset Compatibility**: `CONFIG_AGP_VIA=y` (VIA MVP3/Apollo Pro AGP support) and `CONFIG_PATA_VIA=y` (VIA southbridge PATA/IDE controller support), for boards built around the VIA MVP3 chipset instead of ALi Aladdin V.
* **Legacy ISA Bus (`CONFIG_ISA=y`)**: Enables support for the GA-5AX's onboard ISA slots, alongside `CONFIG_ISAPNP=y` for auto-detection of ISA Plug and Play expansion cards.
* **Graphics (`CONFIG_FB_3DFX=y` / `CONFIG_FB_RADEON=y` / `CONFIG_FB_NVIDIA=y`)**: Native frame-buffer console support (`tdfxfb`, `radeonfb`, `nvidiafb`) for a 3dfx Voodoo 3, ATI Radeon 7000, or NVIDIA GeForce 1/2/3 graphics card, enabling high-resolution console terminals at boot regardless of which one is installed.
* **Creative Sound Blaster Live! (`CONFIG_SND_EMU10K1=y`)**: Native ALSA drivers for the EMU10k1 processor, enabling high-fidelity 16-bit audio.
* **Onboard AC97 Audio Fallback**: `CONFIG_SND_ALI5451=y` (ALi M5451 companion audio chip, common on Aladdin V-era boards) and `CONFIG_SND_VIA82XX=y` (VIA VT82C686-family AC97, common on MVP3-era boards), for systems without a discrete Sound Blaster Live! card installed.
* **3Com 3c905-C Fast EtherLink XL PCI (`CONFIG_VORTEX=y`)**: Native Ethernet driver (built from `3c59x.c`) supporting full 100Mbps speed.
* **Realtek RTL8139/8139C+ Fast Ethernet PCI (`CONFIG_8139TOO=y` / `CONFIG_8139CP=y`)**: Support for the ubiquitous budget Realtek NICs common on Socket 7-era boards, as an alternative to the 3Com card.
* **Advanced Power Management (`CONFIG_APM=y`)**: The GA-5AX predates reliable ACPI, so APM is required for the kernel to issue a clean soft poweroff via the BIOS instead of just halting.
* **Legacy Peripherals**: Floppy disk support (`CONFIG_BLK_DEV_FD=y`) for the onboard floppy header, parallel port support (`CONFIG_PARPORT=y`, `CONFIG_PARPORT_PC=y`) for legacy printers, and gameport/joystick support (`CONFIG_GAMEPORT=y`, `CONFIG_JOYSTICK_ANALOG=y`) via the Sound Blaster Live!'s game/MIDI port.

---

## 2. OS Details & Packages

* **Default Shell**: `zsh` for user `root`
* **Networking**: Runs `dhcpcd` automatically on `eth0` at boot.
* **Pre-installed Packages**: `zsh`, `bash`, `vim`, `htop`, `curl`, `dhcpcd`, `alsa-utils` (providing `alsamixer`/`amixer` to configure your Sound Blaster Live! card), `pciutils` (`lspci`), `usbutils` (`lsusb`), `usbmount`, `hdparm` (CF card benchmarking/tuning), and `mpg123` (MP3 playback).
* **USB Auto-Mount**: Plugging in a USB drive mounts it automatically (via `usbmount`'s `eudev` rules) to `/media/usb0` through `/media/usb7`, and unplugging it unmounts it. `vfat`, `ext2`/`ext3`/`ext4`, `hfsplus`, and `ntfs` filesystems are supported (exFAT is not). NTFS drives are handled by the in-kernel read-write `NTFS3` driver; since it registers itself as fstype `ntfs3` rather than the `ntfs` that `blkid`/`usbmount` report, a `/sbin/mount.ntfs` helper (installed by `post-build.sh`) redirects the mount, via BusyBox's mount-helpers feature (`CONFIG_FEATURE_MOUNT_HELPERS`, off by default, enabled through `board/k6core/busybox.fragment`). The kernel enables both UHCI (VIA southbridges) and OHCI (ALi southbridges) host controllers to cover both supported chipset families.
* **Persistent ALSA Mixer State**: The `S45alsa` init script unmutes all mixer controls to a sane 80% on first boot (no saved state yet) and restores your saved levels on every subsequent boot via `alsactl restore`. Any changes you make with `alsamixer`/`amixer` are saved to `/var/lib/alsa/asound.state` on clean shutdown/reboot via `alsactl store`, so `mpg123 file.mp3` should just work without you needing to unmute anything by hand after the first boot.
* **Sample Media**: If a `sample/` directory exists at the repo root, its contents are copied into `/root/sample` on the target filesystem during the build — a convenient place to drop an MP3 for testing `mpg123`/ALSA playback.

---

## 3. Build Instructions

### Prerequisites
* Docker Desktop installed and running.

### Compilation
Run the compilation script from the workspace root, optionally naming a variant (defaults to `headless`):
```bash
./build.sh            # headless console image                -> disk.img / k6core-latest.img.zip
./build.sh gui        # X11 + Fluxbox desktop, real hardware   -> disk-gui.img / k6core-gui-latest.img.zip
```
This script will:
1. Initialize the persistent Docker cache volume for the chosen variant.
2. Build the compilation container (shared by both variants).
3. Fetch, configure, and compile Buildroot 2025.02.1 and Linux Kernel 6.6.x using the variant's `defconfig`.
4. Output the final flashable raw image directly to your workspace root.

### GUI Variant Details
`configs/k6core_gui_defconfig` builds on top of the headless config and adds:
* **No auto-start**: You need to run `startx` manually in order to have a GUI, easier if you have to debug something.
* **X.Org (modular server)**: `BR2_PACKAGE_XSERVER_XORG_SERVER_MODULAR=y`, needed because graphics drivers are separate packages from the server.
* **Supported graphics cards**: 3dfx Voodoo 3 gets a native 2D driver (`xf86-video-tdfx`). ATI Radeon 7000 and NVIDIA GeForce 1/2/3 have no dedicated driver installed — `xf86-video-ati` requires GBM/Mesa3D/DRM for no real benefit on a GPU this old, and `xf86-video-nv` (2.1.22, its final upstream release, from 2013) calls `xf86DisableRandR()`, an internal xorg-server API removed since server ABI 1.20, so it fails to load ("symbol not found") on any current xorg-server with no config-level fix. Both instead rely on the kernel's `CONFIG_FB_RADEON`/`CONFIG_FB_NVIDIA` framebuffer drivers plus the generic `xf86-video-fbdev` DDX, which also serves as the catch-all fallback for the Voodoo 3. `/etc/X11/xorg.conf` (installed by `post-build.sh` only when `Xorg` is detected in the target) leaves the driver unset so Xorg autoprobes whichever card is actually installed, and its `Module` section preloads the helper modules (`fbdevhw`, `vgahw`, `int10`, `exa`, `shadow`, `shadowfb`) that `tdfx`/`fbdev` need at load time.
* **Input driver**: `xf86-input-evdev`, which covers both USB and PS/2 devices uniformly via the kernel's generic input subsystem.
* **DDC/I2C monitor detection** (`CONFIG_FB_3DFX_I2C`/`CONFIG_FB_RADEON_I2C`, both on by default in their own Kconfig entries; `CONFIG_FB_NVIDIA_I2C` needs an explicit enable) lets the kernel ask the actual connected monitor for its native mode. Without it, all three framebuffer drivers above fall back to a hardcoded 640x480@60 8bpp mode (confirmed from `tdfxfb.c`'s `mode_option` fallback) — usable, but cramped.
* **Fluxbox** as the window manager: it bundles its own toolbar/workspace-switcher, so it needs no separate panel package, and is much lighter than a full GTK-based desktop stack — which matters on a slow K6.
* **PCManFM** as the file manager, **xterm** as the terminal, **Dillo** as the web browser (its own tiny FLTK toolkit, not GTK — renders old-school HTML/CSS only, no JS, which is the only class of browser actually usable on this hardware), and **Leafpad** as a GTK2 text editor. xterm is bumped to version 411 via a `Dockerfile` patch to Buildroot's own package recipe, since the pinned 389 has a musl-libc bug (its manual `posix_openpt`/`grantpt`/`unlockpt` pty setup fails with "open ttydev: I/O error" — [Gentoo bug 689080](https://bugs.gentoo.org/689080)), fixed upstream in patch #391.
* **DejaVu** TrueType fonts. Without them, the only fonts on the system are legacy X11 bitmap fonts (`.pcf`, the 1990s X11 "misc" collection) — Xft/Fluxbox tolerates that via a bitmap-font fallback, but GTK2/Pango (Leafpad, PCManFM) handles it far more fragilely, to the point of rendering a blank window.

---

## 4. Flashing Guide

### macOS

Follow these precise steps to safely flash the raw `disk.img` to your physical CompactFlash card on a Mac.

#### Step 1: Identify your CompactFlash Card Reader
Insert your CF card reader with the CF card plugged in. Open your Mac Terminal and run:
```bash
diskutil list
```
Review the output to find your CF card. Look for a disk matching around 4.0 GB (e.g., `disk3` or `disk4`). 
> [!CAUTION]
> **Verify this carefully!** Selecting the wrong disk (like your Mac's internal drive) will erase all its data.

#### Step 2: Unmount the CF Card
Assuming your CF card is identified as **/dev/diskX** (replace `X` with your actual card index, e.g., `disk4`):
```bash
diskutil unmountDisk /dev/diskX
```

#### Step 3: Flash the Image using `dd`
To maximize flash speeds, write to the raw disk device (`rdisk` instead of `disk`) and use a block size of 1MB:
```bash
sudo dd if=disk.img of=/dev/rdiskX bs=1M status=progress
```
*Input your macOS administrator password when prompted.*

#### Step 4: Eject the CF Card
Once the progress indicator shows the copy is complete, eject your card cleanly:
```bash
diskutil eject /dev/diskX
```
Your CompactFlash card is now bootable and ready to be plugged into your AMD K6 PC!

### Windows and Linux

[balenaEtcher](https://www.balena.io/etcher) is free (Apache-2.0, no cost for personal or commercial use) and available for both Windows and Linux. It flashes straight from the `.zip` release asset — no need to extract `disk.img`/`disk-gui.img` first — and only lists removable drives as flash targets, which helps avoid picking the wrong one.

#### Step 1: Install balenaEtcher
Download and install it from [balena.io/etcher](https://www.balena.io/etcher) for your platform.

#### Step 2: Select the Image
Insert your CF card reader with the CF card plugged in, open balenaEtcher, and click **Flash from file**. Select the downloaded `k6core-latest.img.zip` (headless) or `k6core-gui-latest.img.zip` (GUI) — Etcher unzips it on the fly.

#### Step 3: Select the Target
Click **Select target** and pick your CF card from the list.
> [!CAUTION]
> **Verify this carefully!** Etcher only lists removable drives, but if you have multiple card readers or USB drives connected, double-check the size (around 4.0 GB) and device name before continuing.

#### Step 4: Flash
Click **Flash!**. Enter your administrator password if prompted (required to write to the raw device). Etcher writes the image and then verifies it automatically — wait for both to complete.

#### Step 5: Eject
Once Etcher reports success, eject the CF card through your OS's normal "safely remove"/"eject" action before unplugging it.

Your CompactFlash card is now bootable and ready to be plugged into your AMD K6 PC!

---

## 5. Disk Sizing, Alignment, and Write-Reduction

* **3.7GB Disk Image Constraint**: Physical "4GB" CompactFlash cards vary slightly in their exact sector count depending on manufacturer tolerances. To guarantee that `disk.img` safely fits *any* 4GB CF card, the image size is strictly limited to exactly **3,699,999,744 bytes (~3.7GB decimal)**.
* **1MB Alignment (Sector 2048)**: Aligns the primary root partition at a 1MB boundary. This alignment protects the underlying flash memory cells from write amplification caused by partition-to-flash-erase-block misalignment.
* **Non-Journaled EXT4**: Disables the journal (`-O ^has_journal`) while retaining EXT4's modern extents, fast multi-block allocator, and speedy fsck. This completely eliminates the double-write wear penalty of journaling filesystems, dramatically extending the life of your CompactFlash card.
* **Flash-Friendly Mount Options**: Mounts the filesystem with `noatime,nodiratime` to prevent write wear when reading files, and uses `commit=60` to cache writes and flush them every 60 seconds.

---

## 6. Build & Caching Architecture

The compilation is performed inside a lightweight Ubuntu-based Docker container. This guarantees build reproducibility and eliminates dependency conflicts on macOS.

* **Out-of-Tree Builds (`make O=...`)**: Buildroot remains clean and unmodified in `/buildroot` while all compilation objects, cache files, and configurations are written to `/root/buildroot-output`.
* **Persistent Docker Cache Volume**: A Docker volume (`k6core-build-cache` for the headless variant, `k6core-gui-build-cache` for the GUI variant — see below) is mapped to `/root/buildroot-output`. This volume caches the entire compiler toolchain and compilation objects across runs, reducing subsequent build times to under 30 seconds.
* **Two Variants, One Script**: `build.sh` is parameterized by variant rather than duplicated. Both variants share the same `Dockerfile`/builder image and the same `board/k6core/` scripts — only the Buildroot `defconfig`, the cache volume, and the output image filename differ. This keeps driver/config changes (like everything in section 1) from drifting out of sync between variants.
