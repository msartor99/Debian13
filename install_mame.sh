#!/bin/bash
# Kiosk SGI & VM Mac Installer (Debian GNOME Standard Desktop)
# VERSION 20 : UNIVERSAL / OPTIONAL REBOOT / IDEMPOTENT
# Must be executed as root (via su -) on Debian 13.5

set -Eeuo pipefail

# ==========================================================
# DISCLAIMER OF LIABILITY (User must accept)
# ==========================================================
echo "******************************************************************"
echo "* DISCLAIMER OF LIABILITY                                        *"
echo "* This script modifies core system settings, configures hardware *"
echo "* access, and installs virtualization software.                  *"
echo "* The author assumes NO responsibility or liability for any      *"
echo "* system damage, data loss, or security breaches that may occur. *"
echo "* USE STRICTLY AT YOUR OWN RISK.                                 *"
echo "******************************************************************"
read -r -p "Do you accept these terms and wish to proceed? (y/n): " ACCEPT_TERMS

if [[ ! "$ACCEPT_TERMS" =~ ^[Yy](es)?$ ]]; then
    echo "[-] Installation aborted by the user."
    exit 1
fi

log_status() {
    echo "=== [OK] $1 ==="
}

echo "=========================================================="
echo "   START : SYSTEM CONFIGURATION (STANDARD GNOME)          "
echo "=========================================================="

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (use 'su -')." >&2
    exit 1
fi

# Define target user (change "administrateur" if needed)
REAL_USER="administrateur"
REAL_HOMEDIR="/home/$REAL_USER"

# Verify if target user exists
if ! id "$REAL_USER" &>/dev/null; then
    echo "[-] Error: User '$REAL_USER' does not exist."
    exit 1
fi

echo "=== 1. Enabling non-free-firmware repositories ==="
if grep -q "Components:.*main" /etc/apt/sources.list.d/debian.sources 2>/dev/null; then
    if ! grep -q "non-free-firmware" /etc/apt/sources.list.d/debian.sources; then
        sed -i 's/Components: main.*/Components: main non-free-firmware non-free/' /etc/apt/sources.list.d/debian.sources
    fi
elif [ -f /etc/apt/sources.list ]; then
    if ! grep -q "non-free-firmware" /etc/apt/sources.list; then
        sed -i -E 's/ main( |$)/ main non-free-firmware non-free\1/g' /etc/apt/sources.list
    fi
fi
apt update && apt upgrade -y
log_status "Repositories updated"

echo "=== 2. Installing Emulation Tools & Dependencies ==="
# GNOME is already installed, fetching only emulation and remote access packages
apt install -y mame wget curl alsa-utils zenity sudo \
               intel-microcode qemu-system-x86 ovmf xrdp xorgxrdp openssh-server \
               virt-manager libvirt-daemon-system libvirt-clients qemu-utils swtpm
log_status "Dependencies installed"

echo "=== 3. Configuring System Permissions ==="
# Granting virtualization and hardware access to the main user
usermod -aG kvm,libvirt,audio,video "$REAL_USER"
log_status "Permissions granted to $REAL_USER"

echo "=== 4. Creating Directory Structure ==="
mkdir -p "$REAL_HOMEDIR/.mame/roms" "$REAL_HOMEDIR/.mame/chd" "$REAL_HOMEDIR/.mame/ini"
mkdir -p "$REAL_HOMEDIR/Virtual_Machines" "$REAL_HOMEDIR/.macvm"
mkdir -p "$REAL_HOMEDIR/Desktop" "$REAL_HOMEDIR/Bureau" "$REAL_HOMEDIR/.local/share/applications"

echo "=== 5. Preparing Mac OS X NVRAM ==="
# Copies the blank UEFI firmware needed for macOS virtualization
if [ ! -f "$REAL_HOMEDIR/.macvm/OVMF_VARS_4M.fd" ]; then
    cp /usr/share/OVMF/OVMF_VARS_4M.fd "$REAL_HOMEDIR/.macvm/OVMF_VARS_4M.fd"
fi

echo "=== 6. Configuring MAME Audio ==="
cat << 'EOF' > "$REAL_HOMEDIR/.mame/ini/mame.ini"
sound                 alsa
audio_latency         3
EOF

echo "=== 7. Creating the UI Launcher Script ==="
# This script spawns the Zenity GUI to select a machine to run
cat << EOF > "$REAL_HOMEDIR/system-launcher.sh"
#!/bin/bash
# Disable GNOME screensaver while the emulator is running
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true

CHOICE=\$(zenity --list --center \\
                --title "Multi-System Launcher" \\
                --text "Select the environment to start:" \\
                --column "Code" --column "Environment" \\
                "1" "Silicon Graphics : IRIX 5.3 (MAME)" \\
                "2" "Silicon Graphics : IRIX 6.5 (MAME)" \\
                "3" "Apple : Mac OS X 10 (QEMU/KVM)" \\
                "4" "Exit" \\
                --width=500 --height=280 --hide-column=1 --window-icon=info \\
                --cancel-label="Cancel")

case "\$CHOICE" in
    1) /usr/games/mame indy_4613 -sound alsa -hard1 $REAL_HOMEDIR/.mame/chd/irix53.chd -fullscreen ;;
    2) /usr/games/mame indy_4613 -sound alsa -hard1 $REAL_HOMEDIR/.mame/chd/irix65.chd -fullscreen ;;
    3) 
        if [ -f "$REAL_HOMEDIR/.macvm/OpenCore.qcow2" ]; then
            qemu-system-x86_64 -enable-kvm -m 8192 -smp 4 -machine q35 -cpu host \\
                -device VGA,vgamem_mb=128 \\
                -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \\
                -drive if=pflash,format=raw,file=$REAL_HOMEDIR/.macvm/OVMF_VARS_4M.fd \\
                -drive id=OpenCoreBoot,if=virtio,format=qcow2,file=$REAL_HOMEDIR/.macvm/OpenCore.qcow2 \\
                -drive id=MacHDD,if=virtio,format=qcow2,file=$REAL_HOMEDIR/.macvm/osx10.qcow2 \\
                -usb -device usb-kbd -device usb-tablet \\
                -display gtk,zoom-to-fit=on -full-screen
        else
            zenity --error --center --text="The Mac virtual machine is not configured.\nPlease place the disk images in the .macvm folder."
        fi
        ;;
    *) exit 0 ;;
esac

# Re-enable the screen blanking (5 minutes) after closing the emulator
gsettings set org.gnome.desktop.session idle-delay 300 2>/dev/null || true
EOF
chmod +x "$REAL_HOMEDIR/system-launcher.sh"

echo "=== 8. Creating GNOME Desktop Shortcut ==="
cat << EOF > "$REAL_HOMEDIR/.local/share/applications/sgi-launcher.desktop"
[Desktop Entry]
Version=1.0
Name=System Launcher
Comment=Start SGI & Mac Emulators
Exec=$REAL_HOMEDIR/system-launcher.sh
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=Utility;
EOF

# Copying shortcut to desktop (Handling both French and English defaults)
cp "$REAL_HOMEDIR/.local/share/applications/sgi-launcher.desktop" "$REAL_HOMEDIR/Bureau/" 2>/dev/null || true
cp "$REAL_HOMEDIR/.local/share/applications/sgi-launcher.desktop" "$REAL_HOMEDIR/Desktop/" 2>/dev/null || true

# Authorizing desktop execution for GNOME security compliance
chmod +x "$REAL_HOMEDIR"/Bureau/*.desktop 2>/dev/null || true
chmod +x "$REAL_HOMEDIR"/Desktop/*.desktop 2>/dev/null || true
gio set "$REAL_HOMEDIR/Bureau/sgi-launcher.desktop" metadata::trusted true 2>/dev/null || true
gio set "$REAL_HOMEDIR/Desktop/sgi-launcher.desktop" metadata::trusted true 2>/dev/null || true

echo "=== 9. Configuring RDP Bridge (xrdp) ==="
# Ensure RDP sessions load the GNOME desktop properly
echo "gnome-session" > "$REAL_HOMEDIR/.xsession"

echo "=== 10. Applying File Ownership ==="
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOMEDIR"

echo "=========================================================="
echo " CONFIGURATION COMPLETED SUCCESSFULLY                     "
echo "=========================================================="
echo "A 'System Launcher' icon is now available on the user's desktop."
echo "If GNOME prompts you, right-click the icon and select 'Allow Launching'."
echo ""
read -r -p "Do you want to reboot the system now? (y/n): " REBOOT_CHOICE

if [[ "$REBOOT_CHOICE" =~ ^[Yy](es)?$ ]]; then
    echo "[i] Rebooting system..."
    reboot
else
    echo "[i] Reboot skipped. You can reboot manually later."
    exit 0
fi
