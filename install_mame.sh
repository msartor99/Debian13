#!/bin/bash
# Kiosk SGI & VM Mac Installer (Debian GNOME Standard Desktop)
# VERSION 22 : LOCAL FILES AUTO-MOVE / INDY_4610
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

if [ "$EUID" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (use 'su -')." >&2
    exit 1
fi

REAL_USER="administrateur"
REAL_HOMEDIR="/home/$REAL_USER"

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
apt install -y mame wget curl alsa-utils zenity sudo \
               intel-microcode qemu-system-x86 ovmf xrdp xorgxrdp openssh-server \
               virt-manager libvirt-daemon-system libvirt-clients qemu-utils swtpm
log_status "Dependencies installed"

echo "=== 3. Configuring System Permissions ==="
for group in kvm libvirt audio video; do
    if getent group "$group" > /dev/null 2>&1; then
        /usr/sbin/usermod -aG "$group" "$REAL_USER"
    fi
done
log_status "Permissions verified"

echo "=== 4. Creating Directory Structure ==="
mkdir -p "$REAL_HOMEDIR/.mame/roms" "$REAL_HOMEDIR/.mame/chd" "$REAL_HOMEDIR/.mame/ini"
mkdir -p "$REAL_HOMEDIR/Virtual_Machines" "$REAL_HOMEDIR/.macvm"
mkdir -p "$REAL_HOMEDIR/Desktop" "$REAL_HOMEDIR/Bureau" "$REAL_HOMEDIR/.local/share/applications"

echo "=== 5. Moving Local Files to MAME Directories ==="
# Déplacement automatique du BIOS 4610
if [ -f "$REAL_HOMEDIR/indy_4610.zip" ]; then
    mv "$REAL_HOMEDIR/indy_4610.zip" "$REAL_HOMEDIR/.mame/roms/"
    echo "[i] BIOS indy_4610.zip moved to .mame/roms/"
fi

# Déplacement automatique du disque dur IRIX 6.5
if [ -f "$REAL_HOMEDIR/irix65.chd" ]; then
    mv "$REAL_HOMEDIR/irix65.chd" "$REAL_HOMEDIR/.mame/chd/"
    echo "[i] Hard drive irix65.chd moved to .mame/chd/"
fi

echo "=== 6. Preparing Mac OS X NVRAM ==="
if [ ! -f "$REAL_HOMEDIR/.macvm/OVMF_VARS_4M.fd" ]; then
    cp /usr/share/OVMF/OVMF_VARS_4M.fd "$REAL_HOMEDIR/.macvm/OVMF_VARS_4M.fd"
fi

echo "=== 7. Configuring MAME Audio ==="
cat << 'EOF' > "$REAL_HOMEDIR/.mame/ini/mame.ini"
sound                 alsa
audio_latency         3
EOF

echo "=== 8. Creating the UI Launcher Script ==="
cat << EOF > "$REAL_HOMEDIR/system-launcher.sh"
#!/bin/bash
gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true

CHOICE=\$(zenity --list \\
                --title "Multi-System Launcher" \\
                --text "Select the environment to start:" \\
                --column "Code" --column "Environment" \\
                "1" "Silicon Graphics : IRIX 6.5 (MAME indy_4610)" \\
                "2" "Apple : Mac OS X 10 (QEMU/KVM)" \\
                "3" "Exit" \\
                --width=500 --height=280 --hide-column=1)

case "\$CHOICE" in
    1) 
        # Lancement avec la rom indy_4610
        /usr/games/mame indy_4610 -sound alsa -hard1 "$REAL_HOMEDIR/.mame/chd/irix65.chd" 
        ;;
    2) 
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
            zenity --error --text="The Mac virtual machine is not configured.\nPlease place the disk images in the .macvm folder."
        fi
        ;;
    *) exit 0 ;;
esac

gsettings set org.gnome.desktop.session idle-delay 300 2>/dev/null || true
EOF
chmod +x "$REAL_HOMEDIR/system-launcher.sh"

echo "=== 9. Creating GNOME Desktop Shortcut ==="
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

cp "$REAL_HOMEDIR/.local/share/applications/sgi-launcher.desktop" "$REAL_HOMEDIR/Bureau/" 2>/dev/null || true
cp "$REAL_HOMEDIR/.local/share/applications/sgi-launcher.desktop" "$REAL_HOMEDIR/Desktop/" 2>/dev/null || true

chmod +x "$REAL_HOMEDIR"/Bureau/*.desktop 2>/dev/null || true
chmod +x "$REAL_HOMEDIR"/Desktop/*.desktop 2>/dev/null || true
gio set "$REAL_HOMEDIR/Bureau/sgi-launcher.desktop" metadata::trusted true 2>/dev/null || true
gio set "$REAL_HOMEDIR/Desktop/sgi-launcher.desktop" metadata::trusted true 2>/dev/null || true

echo "=== 10. Configuring RDP Bridge (xrdp) ==="
echo "gnome-session" > "$REAL_HOMEDIR/.xsession"

echo "=== 11. Applying File Ownership ==="
chown -R "$REAL_USER:$REAL_USER" "$REAL_HOMEDIR"

echo "=========================================================="
echo " CONFIGURATION COMPLETED SUCCESSFULLY                     "
echo "=========================================================="
echo "A 'System Launcher' icon is now available on the user's desktop."
echo ""
read -r -p "Do you want to reboot the system now? (y/n): " REBOOT_CHOICE

if [[ "$REBOOT_CHOICE" =~ ^[Yy](es)?$ ]]; then
    echo "[i] Rebooting system..."
    reboot
else
    echo "[i] Reboot skipped. You can reboot manually later."
    exit 0
fi
