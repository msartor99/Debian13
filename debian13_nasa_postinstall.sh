#!/bin/bash
set -euo pipefail

# --- CONFIGURATION ---
# Automatically detect the primary user created during installation (UID 1000)
TARGET_USER=$(id -un 1000 2>/dev/null || true)

REPO_URL="https://githubusercontent.com"
THEME_NAME="nasa-theme"
SDDM_THEME_DIR="/usr/share/sddm/themes/$THEME_NAME"
WALLPAPER_DIR="/usr/share/wallpapers/NASA"
VIDEO_URL="https://file-examples.com"
VIDEO_FILE="$WALLPAPER_DIR/earth_nasa.mp4"
VIDEO_PLUGIN_REPO="https://github.com"
VIDEO_PLUGIN_ID="luisbocanegra.smart.video.wallpaper.reborn"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

echo "=== 1. Enabling contrib / non-free repositories ==="
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    sed -i -E 's/^Components:.*$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
elif [ -f /etc/apt/sources.list ]; then
    sed -i -E 's/\bmain\b.*/main contrib non-free non-free-firmware/' /etc/apt/sources.list
fi

echo "=== 2. Updating system and installing base tools & Qt6 multimedia codecs ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get full-upgrade -y
apt-get install -y curl git net-tools x11-xkb-utils xserver-xorg locales \
    qml6-module-qtmultimedia gstreamer1.0-libav gstreamer1.0-plugins-good gstreamer1.0-plugins-bad

echo "=== 3. Installing and configuring NVIDIA drivers (RTX 2060 + Plasma 6 Wayland) ==="
if lspci | grep -qi "NVIDIA"; then
    apt-get install -y linux-headers-amd64 build-essential dkms
    apt-get install -y nvidia-kernel-dkms nvidia-driver firmware-misc-nonfree

    # Enable DRM KMS (required for KDE Plasma 6 on Wayland)
    echo "options nvidia-drm modeset=1 fbdev=1" > /etc/modprobe.d/nvidia-drm.conf

    # Preserve video memory across suspend/resume on Wayland
    echo "options nvidia NVreg_PreserveVideoMemoryAllocations=1" > /etc/modprobe.d/nvidia-power.conf
    systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true

    # Update initramfs to apply kernel module options at boot
    update-initramfs -u
else
    echo "No NVIDIA GPU detected, skipping driver installation."
fi

echo "=== 4. Configuring locale (fr_CH.UTF-8) and Swiss French keyboard layout ==="
sed -i 's/^# *\(fr_CH.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
update-locale LANG=fr_CH.UTF-8

cat <<KBD > /etc/default/keyboard
XKBMODEL="pc105"
XKBLAYOUT="ch"
XKBVARIANT="fr"
XKBOPTIONS=""
BACKSPACE="guess"
KBD

mkdir -p /etc/X11/xorg.conf.d
cat <<XORG > /etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "ch"
        Option "XkbModel" "pc105"
        Option "XkbVariant" "fr"
EndSection
XORG

udevadm trigger --subsystem-match=input --action=change || true

echo "=== 5. Downloading NASA SDDM theme and spinning Earth video ==="
mkdir -p "$SDDM_THEME_DIR" "$WALLPAPER_DIR"

for file in Main.qml theme.conf metadata.desktop nasa1920.png nasa2560login.jpg nasa2560login.png; do
    curl -fsSL "$REPO_URL/$file" -o "$SDDM_THEME_DIR/$file" || echo "Optional file skipped: $file"
done

# Patch SDDM theme for Qt6 / Plasma 6 compatibility
if [ -f "$SDDM_THEME_DIR/metadata.desktop" ] && ! grep -q "^QtVersion=" "$SDDM_THEME_DIR/metadata.desktop"; then
    echo "QtVersion=6" >> "$SDDM_THEME_DIR/metadata.desktop"
fi

if [ -f "$SDDM_THEME_DIR/Main.qml" ]; then
    sed -i 's/import QtQuick 2\.[0-9]*/import QtQuick/' "$SDDM_THEME_DIR/Main.qml"
    sed -i 's/import QtQuick\.Controls 2\.[0-9]*/import QtQuick.Controls/' "$SDDM_THEME_DIR/Main.qml"
fi

# Copy static fallback wallpapers
cp -f "$SDDM_THEME_DIR/nasa1920.png" "$WALLPAPER_DIR/" 2>/dev/null || true
cp -f "$SDDM_THEME_DIR/nasa2560login.jpg" "$WALLPAPER_DIR/" 2>/dev/null || true

# Idempotent download of the spinning Earth video
if [ ! -s "$VIDEO_FILE" ]; then
    echo "Downloading spinning Earth video wallpaper..."
    curl -fsSL "$VIDEO_URL" -o "$VIDEO_FILE"
fi

echo "=== 6. Installing Smart Video Wallpaper Reborn plugin globally (Plasma 6) ==="
rm -rf /tmp/smart-video
git clone --depth 1 "$VIDEO_PLUGIN_REPO" /tmp/smart-video
if [ -d "/usr/share/plasma/wallpapers/$VIDEO_PLUGIN_ID" ]; then
    kpackagetool6 --global -t Plasma/Wallpaper -u /tmp/smart-video || true
else
    kpackagetool6 --global -t Plasma/Wallpaper -i /tmp/smart-video
fi
rm -rf /tmp/smart-video

echo "=== 7. Configuring SDDM (NASA Theme, X11 display server, no virtual keyboard, CH layout) ==="
mkdir -p /etc/sddm.conf.d
cat <<SDDM > /etc/sddm.conf.d/zz-nasa-override.conf
[General]
DisplayServer=x11
InputMethod=

[Theme]
Current=$THEME_NAME
SDDM

if [ -f /usr/share/sddm/scripts/Xsetup ]; then
    sed -i '/setxkbmap/d' /usr/share/sddm/scripts/Xsetup
    echo "setxkbmap -layout ch -variant fr" >> /usr/share/sddm/scripts/Xsetup
    chmod +x /usr/share/sddm/scripts/Xsetup
fi

echo "=== 8. Applying Plasma 6 video wallpaper for primary user (UID 1000) ==="
if [ -n "$TARGET_USER" ] && id "$TARGET_USER" >/dev/null 2>&1; then
    echo "Detected primary user: $TARGET_USER (UID 1000)"
    USER_HOME=$(getent passwd 1000 | cut -d: -f6)
    
    # Support both English (Videos) and French (Vidéos) XDG user directories
    if [ -d "$USER_HOME/Vidéos" ]; then
        TARGET_VIDEO_DIR="$USER_HOME/Vidéos/Wallpapers"
    else
        TARGET_VIDEO_DIR="$USER_HOME/Videos/Wallpapers"
    fi

    mkdir -p "$TARGET_VIDEO_DIR"
    cp -f "$VIDEO_FILE" "$TARGET_VIDEO_DIR/earth_nasa.mp4"
    chown -R 1000:1000 "$TARGET_VIDEO_DIR"

    DBUS_SOCK="/run/user/1000/bus"
    if [ -S "$DBUS_SOCK" ] && [ -s "$VIDEO_FILE" ]; then
        su - "$TARGET_USER" -c "DBUS_SESSION_BUS_ADDRESS=unix:path=$DBUS_SOCK plasma-apply-wallpaperimage --plugin '$VIDEO_PLUGIN_ID' '$VIDEO_FILE'" || true
        echo "Plasma 6 video wallpaper applied for $TARGET_USER."
    else
        echo "No active graphical session for $TARGET_USER: video saved to $TARGET_VIDEO_DIR/earth_nasa.mp4."
    fi
else
    echo "Warning: No user with UID 1000 found. Skipping user-level wallpaper setup."
fi

echo "=== Done! Please reboot your system to load the kernel and NVIDIA drivers. ==="
