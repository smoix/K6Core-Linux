#!/bin/sh
set -e

# $1 is the path to the target root filesystem directory (passed by Buildroot)
TARGET_DIR="$1"
BOARD_DIR="$(dirname "$0")"

echo "=== Running K6Core Post-Build Script ==="

# 1. Edit /etc/passwd to change root's default login shell to /bin/zsh
if [ -f "${TARGET_DIR}/etc/passwd" ]; then
    echo "Updating root login shell to /bin/zsh in /etc/passwd..."
    sed -i 's|^root:x:0:0:root:/root:/bin/sh|root:x:0:0:root:/root:/bin/zsh|' "${TARGET_DIR}/etc/passwd"
else
    echo "Warning: /etc/passwd not found!"
fi

# 2. Append /bin/zsh to /etc/shells if not already present
if [ -f "${TARGET_DIR}/etc/shells" ]; then
    if ! grep -q "/bin/zsh" "${TARGET_DIR}/etc/shells"; then
        echo "Appending /bin/zsh to /etc/shells..."
        echo "/bin/zsh" >> "${TARGET_DIR}/etc/shells"
    fi
else
    echo "Creating /etc/shells with /bin/zsh..."
    echo "/bin/zsh" > "${TARGET_DIR}/etc/shells"
fi

# 3. Configure eth0 network interface to run DHCP at boot via /etc/network/interfaces
if [ -f "${TARGET_DIR}/etc/network/interfaces" ]; then
    if ! grep -q "eth0" "${TARGET_DIR}/etc/network/interfaces"; then
        echo "Configuring eth0 for DHCP in /etc/network/interfaces..."
        cat <<EOF >> "${TARGET_DIR}/etc/network/interfaces"

# Auto-configure eth0 on boot via DHCP
auto eth0
iface eth0 inet dhcp
EOF
    fi
else
    echo "Creating /etc/network/interfaces and configuring eth0 for DHCP..."
    mkdir -p "${TARGET_DIR}/etc/network"
    cat <<EOF > "${TARGET_DIR}/etc/network/interfaces"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF
fi

# 4. Copy GRUB configuration
echo "Copying grub.cfg to target /boot/grub/grub.cfg..."
mkdir -p "${TARGET_DIR}/boot/grub"
cp -f "${BOARD_DIR}/grub.cfg" "${TARGET_DIR}/boot/grub/grub.cfg"

# 5. Install ALSA mixer restore/save init script
echo "Installing S45alsa init script for persistent ALSA mixer state..."
mkdir -p "${TARGET_DIR}/etc/init.d"
cp -f "${BOARD_DIR}/S45alsa" "${TARGET_DIR}/etc/init.d/S45alsa"
chmod 755 "${TARGET_DIR}/etc/init.d/S45alsa"

# 6. Copy sample media into /root for testing mpg123/ALSA playback
SAMPLE_DIR="/workspace/sample"
if [ -d "${SAMPLE_DIR}" ]; then
    echo "Copying sample/ to target /root/sample..."
    mkdir -p "${TARGET_DIR}/root/sample"
    cp -a "${SAMPLE_DIR}/." "${TARGET_DIR}/root/sample/"
    chmod -R a+rX "${TARGET_DIR}/root/sample"
else
    echo "Warning: sample directory not found at ${SAMPLE_DIR}, skipping."
fi

# 7. GUI variant only: install xorg.conf and root's .xinitrc if X.org was built
if [ -f "${TARGET_DIR}/usr/bin/Xorg" ]; then
    echo "Xorg detected: installing xorg.conf and root .xinitrc (startfluxbox)..."
    mkdir -p "${TARGET_DIR}/etc/X11"
    cp -f "${BOARD_DIR}/xorg.conf" "${TARGET_DIR}/etc/X11/xorg.conf"
    cp -f "${BOARD_DIR}/xinitrc" "${TARGET_DIR}/root/.xinitrc"
    chmod 644 "${TARGET_DIR}/etc/X11/xorg.conf"
    chmod 755 "${TARGET_DIR}/root/.xinitrc"

    # Buildroot's xserver_xorg-server package auto-installs this init script
    # (since neither nodm nor xdm is enabled) to launch a bare Xorg at boot.
    # It bypasses .xinitrc entirely (no startx/xinit), so Fluxbox never
    # starts -- just a blank, unusable X session. Remove it so the intended
    # flow (log in on tty1, run "startx" manually) is the only way X starts.
    if [ -f "${TARGET_DIR}/etc/init.d/S40xorg" ]; then
        echo "Removing auto-start S40xorg init script (X must be started manually via startx)..."
        rm -f "${TARGET_DIR}/etc/init.d/S40xorg"
    fi

    # Desktop wallpaper (set by .xinitrc via feh), a nicer default Fluxbox
    # style (it ships ~30 of its own, but defaults to the plain "bloe" one),
    # a curated menu (the stock one has a dead "firefox" stub -- we don't
    # ship Firefox -- and never lists dillo/leafpad), and a style overlay
    # that stops the style's own background: directive from repainting over
    # feh's wallpaper on every startup (RootTheme.cc calls fbsetbg with the
    # style's background unconditionally unless an overlay says otherwise).
    #
    # session.menuFile/styleOverlay point at absolute /usr/share/fluxbox/...
    # paths rather than the ~/.fluxbox/... ones Fluxbox's own init template
    # uses by default, so there's no dependency on undocumented first-run
    # copy-to-homedir behavior -- these files are just read directly.
    if [ -f "${TARGET_DIR}/usr/bin/fluxbox" ]; then
        echo "Installing desktop wallpaper, Fluxbox style/menu/overlay..."
        mkdir -p "${TARGET_DIR}/usr/share/pixmaps"
        cp -f "${BOARD_DIR}/k6core-default.png" "${TARGET_DIR}/usr/share/pixmaps/k6core-default.png"
        cp -f "${BOARD_DIR}/fluxbox-menu" "${TARGET_DIR}/usr/share/fluxbox/menu"
        cp -f "${BOARD_DIR}/fluxbox-overlay" "${TARGET_DIR}/usr/share/fluxbox/overlay"
        if [ -f "${TARGET_DIR}/usr/share/fluxbox/init" ]; then
            sed -i \
                -e 's|^session\.menuFile:.*|session.menuFile:\t/usr/share/fluxbox/menu|' \
                -e 's|^session\.styleFile:.*|session.styleFile:\t/usr/share/fluxbox/styles/zimek_darkblue|' \
                -e '/^session\.styleFile:/a\
session.styleOverlay:\t/usr/share/fluxbox/overlay' \
                "${TARGET_DIR}/usr/share/fluxbox/init"
        fi
    fi
fi

# 8. Copy GRUB 1st stage boot.img to binaries directory (required for genimage)
if [ -f "${TARGET_DIR}/lib/grub/i386-pc/boot.img" ]; then
    echo "Copying boot.img to binaries directory..."
    cp -f "${TARGET_DIR}/lib/grub/i386-pc/boot.img" "${BINARIES_DIR}/"
else
    echo "Error: GRUB boot.img not found in target filesystem!"
    exit 1
fi

# 9. USB auto-mount (usbmount) NTFS support: the in-kernel NTFS3 driver
# registers itself as fstype "ntfs3", but usbmount calls plain `mount -tntfs`
# (blkid reports NTFS drives as TYPE="ntfs"). Install a /sbin/mount.ntfs
# helper -- which BusyBox's mount falls back to once CONFIG_FEATURE_MOUNT_HELPERS
# is on (see board/k6core/busybox.fragment) -- to redirect it to -tntfs3, and
# add "ntfs" to usbmount's FILESYSTEMS whitelist so it attempts the mount at all.
if [ -f "${TARGET_DIR}/etc/usbmount/usbmount.conf" ]; then
    echo "Installing /sbin/mount.ntfs helper and enabling ntfs in usbmount.conf..."
    mkdir -p "${TARGET_DIR}/sbin"
    cat > "${TARGET_DIR}/sbin/mount.ntfs" <<'EOF'
#!/bin/sh
exec mount -tntfs3 "$@"
EOF
    chmod 755 "${TARGET_DIR}/sbin/mount.ntfs"
    sed -i 's|^FILESYSTEMS="vfat ext2 ext3 ext4 hfsplus"$|FILESYSTEMS="vfat ext2 ext3 ext4 hfsplus ntfs"|' \
        "${TARGET_DIR}/etc/usbmount/usbmount.conf"
fi

echo "=== K6Core Post-Build Script Complete ==="
