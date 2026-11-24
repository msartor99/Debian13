# Debian 13 (Trixie) — KDE Plasma 6 & NASA Theme Post-Installation

Port of my FreeBSD 14/15 setup for **Debian 13 (Trixie)** with **KDE Plasma 6**, full **NVIDIA (Wayland)** support, **Swiss French (`fr_CH`)** localization, custom **NASA SDDM login theme**, and an **animated spinning Earth video wallpaper**.

---

## What the Script Does (`debian13_nasa_postinstall.sh`)

The script is **idempotent** (safe to run multiple times without creating duplicates) and automates:

1. **Debian Repositories:** Enables `contrib`, `non-free`, and `non-free-firmware`.
2. **System Update & Essential Packages:** Installs `curl`, `git`, `net-tools`, `x11-xkb-utils`, `xserver-xorg`, and **Qt6 / GStreamer** multimedia codecs.
3. **NVIDIA Driver & Wayland Support:**
   * Automatically installs `nvidia-driver` and `nvidia-kernel-dkms` if an NVIDIA GPU is detected.
   * Enables `nvidia-drm modeset=1 fbdev=1` and `NVreg_PreserveVideoMemoryAllocations=1` so **KDE Plasma 6 runs smoothly on Wayland** without black screens or suspend/resume glitches.
4. **Swiss French Localization:**
   * Sets the system locale to `fr_CH.UTF-8`.
   * Configures the Swiss French keyboard layout (`ch` / variant `fr`) across console, X11, and SDDM.
5. **SDDM Login Screen (NASA Theme):**
   * Downloads the NASA theme assets from this repository and patches them for **Qt6** (`QtVersion=6` and updated QML imports).
   * Disables the oversized on-screen virtual keyboard (`InputMethod=`) and enforces the Swiss keyboard layout (`setxkbmap -layout ch -variant fr`).
6. **Plasma 6 Video Wallpaper:**
   * Globally installs the **Smart Video Wallpaper Reborn** plugin for Plasma 6.
   * Downloads the spinning Earth video (`earth_nasa.mp4`) and applies it to the Plasma desktop.

---

## Quick Installation (as `root`)

After a fresh Debian 13 installation with KDE Plasma, log in as `root` (locally or via SSH/PuTTY) and run:

```bash
apt update && apt install -y curl
curl -fsSL https://githubusercontent.com -o /root/debian13_nasa_postinstall.sh
chmod +x /root/debian13_nasa_postinstall.sh
/root/debian13_nasa_postinstall.sh
```

> **Note:** Before running the script, edit the `TARGET_USER="msartor"` variable at the top of the file if your username is different (and adjust the locale/keymap section if you are outside French-speaking Switzerland).

---

## Post-Execution Steps

1. **Reboot the system** to load the updated kernel and NVIDIA proprietary driver:
   ```bash
   reboot
   ```
2. **At the SDDM Login Screen:**
   * The NASA theme appears without the virtual keyboard and with the Swiss (`CH`) keyboard layout active.
   * Select **Plasma (Wayland)** and log in.
3. **If the video wallpaper is not yet active** (for instance, if the script was executed before your first graphical login), simply re-run the script while logged into Plasma, or set it manually:
   * **Right-click the desktop** → *Configure Desktop and Wallpaper...* → Wallpaper Type: **Smart Video Wallpaper Reborn** → Add `~/Vidéos/Wallpapers/earth_nasa.mp4`.

---

## Quick Troubleshooting

* **Verify NVIDIA GPU and Wayland DRM modeset:**
  ```bash
  nvidia-smi
  cat /sys/module/nvidia_drm/parameters/modeset   # Should output Y
  ```
* **Preview the SDDM theme without rebooting:**
  ```bash
  sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/nasa-theme
  ```
* **Secure Boot:** If the NVIDIA kernel module fails to load at boot, disable *Secure Boot* in your BIOS/UEFI or sign the DKMS module with a MOK key.

# Debian13
use Debian 13.5 and configure Workstation spécial

# new script to install mame emulator for IRIX 5.3 and 6.

enter debian using local user (administrateur for me )

download file: https://github.com/msartor99/Debian13/blob/5887f1a66c904ba0fe74ca650c2461c794ffcd1a/install_mame.sh

make it executable : chmod +x install_mame.sh

you must found irix65.chd, ps2_keybc.zip and indy_4610.zip on the net ( archives.org ) and copy files to /home/administrateur

open terminal and run it : sudo ./install_mame.sh
