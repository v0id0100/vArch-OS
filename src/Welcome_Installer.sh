#!/bin/bash
set -euo pipefail

############################################################
# This script is only used IN the Welcome Installer script.#
#                                                          #
#           It is not meant to be run as a regular user.   #
############################################################

if (( EUID != 0 )); then
    echo "This installer must be run as root."
    exit 1
fi

cleanup() {
    if mountpoint -q /mnt; then
        echo "Cleaning up target mount..."
        umount -R /mnt >/dev/null 2>&1 || true
    fi
    if cryptsetup status cryptroot >/dev/null 2>&1; then
        cryptsetup close cryptroot >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

### Setup User:
while true; do
    read -r -p "Welcome to vArch-OS. Please enter your username: " username
    if [[ -z "$username" ]]; then
        echo "Username cannot be empty."
    elif ! [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "Invalid username. Use lowercase letters, digits, - or _, starting with a letter or underscore (max 32 chars)."
    else
        break
    fi
done

while true; do
    read -r -sp "Please enter your password: " password
    echo
    read -r -sp "Please confirm your password: " password_confirm
    echo
    if [[ "$password" != "$password_confirm" ]]; then
        echo "Passwords do not match. Please try again."
    elif [[ -z "$password" ]]; then
        echo "Password cannot be empty."
    else
        break
    fi
done
unset password_confirm

### Setting Internet:

read -r -p "Do you use a wired connection? (Y/n): " wired_connection
wired_connection="${wired_connection:-y}"

if [[ "$wired_connection" =~ ^[yY]$ ]]; then
    echo "Wired connection. No additional setup required."
else
    device=$(nmcli device 2>/dev/null | awk '/wifi/{print $1; exit}')
    if [[ -z "$device" ]]; then
        echo "Error: No Wi-Fi adapter detected. Cannot continue without internet."
        exit 1
    fi
    rfkill unblock wifi; rfkill unblock all
    nmcli radio wifi on; nmcli device wifi rescan; nmcli device wifi list
    read -r -p "Please enter your Wi-Fi SSID: " ssid
    read -r -sp "Please enter your Wi-Fi password: " wifi_password
    echo
    if ! nmcli device wifi connect "$ssid" password "$wifi_password" ifname "$device"; then
        echo "Wi-Fi connection failed. Please check your credentials and try again."
        exit 1
    fi
fi

### Setting Timezone:
DEFAULT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York")
while true; do
    read -r -p "Please enter your timezone [$DEFAULT_TZ]: " timezone
    timezone="${timezone:-$DEFAULT_TZ}"
    if timedatectl set-timezone "$timezone" 2>/dev/null; then
        break
    else
        echo "Invalid timezone '$timezone'. Example: Europe/Madrid, America/New_York"
        echo "List all with: timedatectl list-timezones"
    fi
done

### Partitioning and Formatting:

echo "=== Disks available in system ======="
lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop" || true
echo "====================================="

# Auto-detect primary installation disk (prefer non-removable drives)
DEFAULT_DISK=$(lsblk -d -n -o NAME,TYPE,RM | awk '$2=="disk" && $3=="0" {print "/dev/"$1}' | head -1)
if [[ -z "$DEFAULT_DISK" ]]; then
    DEFAULT_DISK=$(lsblk -d -n -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | head -1)
fi
DEFAULT_DISK="${DEFAULT_DISK:-/dev/sda}"

while true; do
    read -r -p "Please enter the disk you want to partition [$DEFAULT_DISK]: " disk
    disk="${disk:-$DEFAULT_DISK}"
    if [[ -b "$disk" ]]; then
        break
    else
        echo "Device '$disk' not found or not a block device. Available disks:"
        lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop" || true
    fi
done

read -r -p "You are about to partition $disk. This will erase ALL data. Are you sure? (y/N): " confirm_partition
if [[ ! "$confirm_partition" =~ ^[yY]$ ]]; then
    echo "Partitioning aborted."
    exit 1
fi

echo "Partitioning $disk..."
echo "Creating GPT partition table and partitions..."
cat << 'EOF' | fdisk "$disk"
g
n
1
2048
+1G

n
2



p
t
1
1
w
EOF

# Let the kernel re-read the partition table
partprobe "$disk" 2>/dev/null || true
sleep 1

### Encrypting the Root Partition:
read -r -p "Do you want to encrypt the root partition? (Y/n): " encrypt
encrypt="${encrypt:-y}"

### Setting partition names dynamically
# NVMe and MMC devices use the form /dev/nvme0n1p1, others use /dev/sda1
if [[ $disk =~ nvme|mmcblk ]]; then
    partition1="${disk}p1"
    partition2="${disk}p2"
else
    partition1="${disk}1"
    partition2="${disk}2"
fi

# Verify partitions exist before continuing
if [[ ! -b "$partition1" ]] || [[ ! -b "$partition2" ]]; then
    echo "Error: expected partitions $partition1 and $partition2 not found."
    echo "Current partition table:"
    lsblk "$disk"
    exit 1
fi

if [[ "$encrypt" =~ ^[yY]$ ]]; then
    echo "Encrypting the root partition..."
    cryptsetup luksFormat "$partition2"
    echo "Opening the encrypted root partition..."
    cryptsetup open "$partition2" cryptroot
else
    echo "Skipping encryption for the root partition."
fi

### Formatting the Partitions:
read -r -p "Do you want to format the partitions? (Y/n): " format
format="${format:-y}"
if [[ "$format" =~ ^[yY]$ ]]; then
    echo "Formatting the EFI System Partition..."
    mkfs.fat -F32 "$partition1"
    echo "Formatting the Root Partition..."
    if [[ "$encrypt" =~ ^[yY]$ ]]; then
        mkfs.ext4 /dev/mapper/cryptroot
    else
        mkfs.ext4 "$partition2"
    fi
else
    echo "Formatting aborted."
    exit 1
fi

### Mounting:
echo "Mounting the Root Partition..."
if [[ "$encrypt" =~ ^[yY]$ ]]; then
    mount /dev/mapper/cryptroot /mnt
else
    mount "$partition2" /mnt
fi
mkdir -p /mnt/boot
echo "Mounting the EFI System Partition..."
mount "$partition1" /mnt/boot

### Installing base system:
pacstrap -K /mnt base linux linux-firmware linux-headers intel-ucode nano vim man-pages man-db bluez-utils bluez networkmanager sof-firmware sudo grub efibootmgr git zsh curl

### Configure the system:
genfstab -U /mnt > /mnt/etc/fstab

### Timezone in chroot:
arch-chroot /mnt /usr/bin/env timezone="$timezone" /bin/bash << 'EOF'
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
systemctl enable systemd-timesyncd
EOF

### Locale setup:
DEFAULT_LOCALE=$(locale 2>/dev/null | awk -F= '/^LANG=/{gsub(/"/, "", $2); print $2}')
case "$DEFAULT_LOCALE" in
    "" | "C" | "C.UTF-8" | "POSIX") DEFAULT_LOCALE="en_US.UTF-8" ;;
esac
read -r -p "Which language do you want to use? [$DEFAULT_LOCALE]: " locale
locale="${locale:-$DEFAULT_LOCALE}"

arch-chroot /mnt /usr/bin/env locale="$locale" /bin/bash << 'EOF'
echo "$locale UTF-8" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=$locale" > /etc/locale.conf
EOF

### Keymap setup:
DEFAULT_KEYMAP=$(localectl status 2>/dev/null | awk -F': ' '/VC Keymap/{print $2}')
DEFAULT_KEYMAP="${DEFAULT_KEYMAP:-us}"
read -r -p "Which keyboard layout do you want to use? [$DEFAULT_KEYMAP]: " keymap
keymap="${keymap:-$DEFAULT_KEYMAP}"

### mkinitcpio hooks (include encrypt hook only if encryption is enabled)
if [[ "$encrypt" =~ ^[yY]$ ]]; then
    HOOKS="base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck"
else
    HOOKS="base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck"
fi

arch-chroot /mnt /usr/bin/env keymap="$keymap" hooks="$HOOKS" /bin/bash << 'EOF'
echo "KEYMAP=$keymap" > /etc/vconsole.conf
locale-gen
sed -i "s/^HOOKS=.*/HOOKS=($hooks)/" /etc/mkinitcpio.conf
EOF

echo "Regenerating initramfs..."
arch-chroot /mnt /bin/bash << 'EOF'
mkinitcpio -p linux
EOF

### Hostname:
while true; do
    read -r -p "Please enter your desired hostname [vArch-OS]: " hostname
    hostname="${hostname:-vArch-OS}"
    if [[ "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
        break
    else
        echo "Invalid hostname. Use letters, digits and hyphens (not at start or end, max 63 chars)."
    fi
done

arch-chroot /mnt /usr/bin/env hostname="$hostname" /bin/bash << 'EOF'
echo "$hostname" > /etc/hostname
EOF

### Creating user account:
echo "Creating user account '$username'..."
arch-chroot /mnt /usr/bin/env username="$username" password="$password" /bin/bash << 'EOF'
useradd -m -G wheel,video,render -s /bin/zsh "$username"
echo "$username:$password" | chpasswd
EOF

unset password

### Wheel group and root lock:
arch-chroot /mnt /bin/bash << 'EOF'
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
passwd -l root
EOF

### Install GRUB bootloader:
arch-chroot /mnt /bin/bash << 'EOF'
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
EOF

### Configure GRUB:
if [[ "$encrypt" =~ ^[yY]$ ]]; then
    UUID=$(blkid -o value -s UUID "$partition2")
    arch-chroot /mnt /usr/bin/env UUID="$UUID" /bin/bash << 'EOF'
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"quiet cryptdevice=UUID=${UUID}:cryptroot root=/dev/mapper/cryptroot\"|" /etc/default/grub
sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR=\"vArch-OS\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
EOF
else
    arch-chroot /mnt /bin/bash << 'EOF'
sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR=\"vArch-OS\"|" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
EOF
fi

### Multilib repository:
echo "Enabling multilib repository..."
arch-chroot /mnt /bin/bash << 'EOF'
sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm
EOF

### Video Drivers:
echo "Installing video drivers..."
DETECTED_GPU=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | head -1 || true)
if echo "$DETECTED_GPU" | grep -qi intel; then
    DEFAULT_GPU="I"
elif echo "$DETECTED_GPU" | grep -qi amd; then
    DEFAULT_GPU="A"
else
    DEFAULT_GPU="I"
fi
[[ -n "$DETECTED_GPU" ]] && echo "Detected GPU: $DETECTED_GPU"

while true; do
    read -r -p "Do you have Intel or AMD graphics? (I/a) [$DEFAULT_GPU]: " gpu_choice
    gpu_choice="${gpu_choice:-$DEFAULT_GPU}"
    if [[ "$gpu_choice" =~ ^[iIaA]$ ]]; then
        break
    else
        echo "Invalid choice. Enter 'I' for Intel or 'A' for AMD."
    fi
done

if [[ "$gpu_choice" =~ ^[iI]$ ]]; then
    arch-chroot /mnt /bin/bash << 'EOF'
pacman -S mesa lib32-mesa vulkan-intel intel-media-driver --noconfirm
EOF
else
    arch-chroot /mnt /bin/bash << 'EOF'
pacman -S mesa lib32-mesa vulkan-radeon --noconfirm
EOF
fi

### Audio drivers:
echo "Installing audio drivers..."
arch-chroot /mnt /bin/bash << 'EOF'
pacman -S pipewire pipewire-alsa pipewire-pulse wireplumber --noconfirm
EOF

### KDE Plasma:
echo "Installing KDE Plasma desktop environment..."
arch-chroot /mnt /bin/bash << 'EOF'
pacman -S plasma-meta --noconfirm
EOF


echo "Installing KDE applications..."
arch-chroot /mnt /bin/bash << 'EOF'
pacman -S kde-applications --noconfirm
EOF

### Login manager:
arch-chroot /mnt /bin/bash << 'EOF'
pacman -S plasma-login-manager --noconfirm
EOF

### Additional packages:
arch-chroot /mnt /usr/bin/env username="$username" /bin/bash << 'EOF'
curl -o /tmp/packages.sh https://raw.githubusercontent.com/v0id0100/vArch-OS/refs/heads/v0id0100_v1/src/packages.sh
chmod +x /tmp/packages.sh
bash /tmp/packages.sh
rm -f /tmp/packages.sh
EOF

### Personalization files:
echo "Downloading and applying personalization..."
arch-chroot /mnt /usr/bin/env username="$username" /bin/bash << 'EOF'
USER="$username"
HOME_DIR="/home/$USER"

rm -rf "$HOME_DIR"/.config "$HOME_DIR"/.icons "$HOME_DIR"/.local "$HOME_DIR"/.zshrc "$HOME_DIR"/.gtkrc-2.0 "$HOME_DIR"/.oh-my-zsh
mkdir -p "$HOME_DIR"/.config "$HOME_DIR"/.icons "$HOME_DIR"/.local

# Install oh-my-zsh running as root but with HOME pointing to the user's dir.
# Avoids su/PAM issues inside arch-chroot; ownership is fixed with chown below.
HOME="$HOME_DIR" RUNZSH=no CHSH=no \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install zsh plugins
ZSH_CUSTOM="$HOME_DIR/.oh-my-zsh/custom/plugins"
git clone https://github.com/zsh-users/zsh-autosuggestions          "$ZSH_CUSTOM/zsh-autosuggestions"          || true
git clone https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/zsh-history-substring-search" || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting      "$ZSH_CUSTOM/zsh-syntax-highlighting"      || true

# Copy config directories from repo
git clone https://github.com/v0id0100/vArch-OS.git /tmp/vArch-OS-install
cd "/tmp/vArch-OS-install/Files needed"
cp -r .config "$HOME_DIR"
cp -r .icons  "$HOME_DIR"
cp -r .local  "$HOME_DIR"

# Download individual files (overwrites whatever oh-my-zsh created)
curl -sL https://raw.githubusercontent.com/v0id0100/vArch-OS/refs/heads/v0id0100_v1/Files%20needed/.zshrc    -o "$HOME_DIR/.zshrc"
curl -sL https://raw.githubusercontent.com/v0id0100/vArch-OS/refs/heads/v0id0100_v1/Files%20needed/.gtkrc-2.0 -o "$HOME_DIR/.gtkrc-2.0"

# FIX PERMISSIONS (Crucial: If skipped, the graphical desktop environment will fail on boot)
chown -R "$USER":"$USER" "$HOME_DIR"
rm -rf /tmp/vArch-OS-install
EOF

### Custom OS entries:
echo "Applying custom OS entries..."
arch-chroot /mnt /bin/bash << 'CHROOT_EOF'
cat << 'FILE_EOF' > /etc/os-release
NAME="vArch-OS"
PRETTY_NAME="vArch-OS"
ID=vArch-OS
BUILD_ID=v0id0100_v1
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://github.com/v0id0100/vArch-OS"
DOCUMENTATION_URL="https://github.com/v0id0100/vArch-OS/tree/v0id0100_v1"
SUPPORT_URL="https://github.com/v0id0100/vArch-OS/issues"
BUG_REPORT_URL="https://gitlab.archlinux.org/groups/archlinux/-/issues"
PRIVACY_POLICY_URL="https://terms.archlinux.org/docs/privacy-policy/"
LOGO=/usr/local/vArch-OS.png
FILE_EOF

sed -i 's|GRUB_DISTRIBUTOR="arch"|GRUB_DISTRIBUTOR="vArch-OS"|' /etc/default/grub
sed -i 's|#GRUB_BACKGROUND=.*|GRUB_BACKGROUND="/usr/local/vArch-OS.png"|' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF

### Enabling services:
echo "Enabling services..."
arch-chroot /mnt /bin/bash << 'EOF'
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable plasmalogin
EOF

echo "Finalizing installation and unmounting..."
umount -R /mnt || true
sync

echo "Installation complete! Please remove the installation media before rebooting."
sleep 3
echo "##############################"
echo "#         Thank you!         #"
echo "#        To Download         #"
echo "#          vArch-OS          #"
echo "##############################"
sleep 2
read -r -p "Press Enter to reboot..."
reboot
