#!/bin/bash
set -e

echo "=== Arch Linux Custom Installer ==="

# 1. Ask for user input
read -rp "Keyboard layout (e.g., us): " KBLAYOUT
read -rp "Timezone (e.g., Europe/London): " TIMEZONE
read -rp "System locale (e.g., en_US.UTF-8): " SYSLOCALE
read -rp "Computer hostname: " HOSTNAME
read -rp "Username: " USERNAME
read -rp "Root partition (e.g., /dev/sda1): " ROOT_PART
read -rp "Separate home partition? (y/n): " SEPARATE_HOME
[[ "$SEPARATE_HOME" == "y" ]] && read -rp "Home partition: " HOME_PART
read -rp "Use swap partition? (y/n): " USE_SWAP
[[ "$USE_SWAP" == "y" ]] && read -rp "Swap partition: " SWAP_PART

loadkeys "$KBLAYOUT"

# 2. Mount partitions
echo "[*] Mounting root partition..."
mount "$ROOT_PART" /mnt

if [[ "$SEPARATE_HOME" == "y" ]]; then
    echo "[*] Mounting existing /home partition (no format)..."
    mkdir -p /mnt/home
    mount "$HOME_PART" /mnt/home
fi

if [[ "$USE_SWAP" == "y" ]]; then
    echo "[*] Enabling swap partition..."
    swapon "$SWAP_PART"
fi

# 3. Install base system
echo "[*] Installing base system..."
pacstrap -K /mnt base linux linux-firmware base-devel git sudo os-prober grub networkmanager micro

# 4. Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Get root disk for GRUB
if [[ "$ROOT_PART" =~ ^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
    DISK="${BASH_REMATCH[1]}"
elif [[ "$ROOT_PART" =~ ^(/dev/sd[a-z])([0-9]+)$ ]]; then
    DISK="${BASH_REMATCH[1]}"
else
    echo "!! Could not determine root disk from $ROOT_PART"
    exit 1
fi

# 5–6. Arch-chroot setup
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$SYSLOCALE UTF-8" > /etc/locale.gen
locale-gen

echo "LANG=$SYSLOCALE" > /etc/locale.conf
echo "KEYMAP=$KBLAYOUT" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname

cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo "Set root password:"
passwd

useradd -m -G wheel -s /bin/bash $USERNAME
echo "Set password for $USERNAME:"
passwd $USERNAME

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

systemctl enable NetworkManager

echo "[*] Installing GRUB bootloader..."
grub-install --target=i386-pc "$DISK"
grub-mkconfig -o /boot/grub/grub.cfg
EOF

# 7. Switch to user and install yay-bin
arch-chroot /mnt /bin/bash <<EOF
runuser -u $USERNAME -- bash -c "
cd ~
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg --noconfirm -si
"
EOF

# 8. Ask for NVIDIA driver
read -rp "Install NVIDIA drivers? (y/n): " INSTALL_NVIDIA
if [[ "$INSTALL_NVIDIA" == "y" ]]; then
    arch-chroot /mnt /bin/bash <<EOF
pacman -Sy --noconfirm nvidia nvidia-utils opencl-nvidia
EOF
fi

# 9. Install i3, SDDM, PipeWire, and extras
arch-chroot /mnt /bin/bash <<EOF
pacman -Sy --noconfirm sddm i3-wm i3status pipewire pipewire-alsa pipewire-pulse wireplumber pavucontrol-qt xorg-server xorg-xinit xterm firefox

systemctl enable sddm

runuser -u $USERNAME -- bash -c "
systemctl --user enable pipewire
systemctl --user enable wireplumber
"
EOF

echo "=== All done. You can now reboot into your new Arch install. 🎉 ==="
