#!/bin/bash
set -euo pipefail

echo "=== Arch Linux Custom Installer ==="

# 1. Ask for user input
read -p "Enter your keyboard layout (e.g. us, uk, de) [default: us]: " keymap
keymap=${keymap:-us}

read -p "Enter timezone region [default: America]: " zone
zone=${zone:-America}

read -p "Enter timezone city (e.g. New_York, Los_Angeles): " city

# Validate and set timezone
if [ -f "/usr/share/zoneinfo/$zone/$city" ]; then
    ln -sf "/usr/share/zoneinfo/$zone/$city" /etc/localtime
    echo "Timezone set to $zone/$city"
else
    echo "❌ Invalid timezone: $zone/$city"
    exit 1
fi

hwclock --systohc

read -p "Enter system locale (e.g. en_US.UTF-8) [default: en_US.UTF-8]: " locale
locale=${locale:-en_US.UTF-8}
echo "$locale UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf
echo "KEYMAP=$keymap" > /etc/vconsole.conf

# Prompt for hostname and user setup
read -p "Enter computer hostname: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# 2. Prompt for partition information
read -p "Enter root partition (e.g. sda1, nvme0n1p3): " rootpart
rootpart="/dev/$rootpart"

read -p "Enter a separate home partition (leave blank to skip): " homepart
if [ -n "$homepart" ]; then
    homepart="/dev/$homepart"
fi

read -p "Use swap partition? (y/n): " USE_SWAP
if [[ "$USE_SWAP" == "y" ]]; then
    read -p "Enter swap partition (e.g. sda2, nvme0n1p2): " SWAP_PART
    SWAP_PART="/dev/$SWAP_PART"
fi

# 3. Mount partitions
echo "[*] Mounting root partition..."
mount "$rootpart" /mnt

if [ -n "$homepart" ]; then
    echo "[*] Mounting existing /home partition (no format)..."
    mkdir -p /mnt/home
    mount "$homepart" /mnt/home
fi

if [ -n "$SWAP_PART" ]; then
    echo "[*] Enabling swap partition..."
    swapon "$SWAP_PART"
fi

# 4. Install base system
echo "[*] Installing base system..."
pacstrap -K /mnt base linux linux-firmware base-devel git sudo os-prober grub networkmanager micro

# 5. Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Get root disk for GRUB
if [[ "$rootpart" =~ ^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
    DISK="${BASH_REMATCH[1]}"
elif [[ "$rootpart" =~ ^(/dev/sd[a-z])([0-9]+)$ ]]; then
    DISK="${BASH_REMATCH[1]}"
else
    echo "!! Could not determine root disk from $rootpart"
    exit 1
fi

# 6. Chroot setup
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$zone/$city /etc/localtime
hwclock --systohc

echo "$locale UTF-8" >> /etc/locale.gen
locale-gen

echo "LANG=$locale" > /etc/locale.conf
echo "KEYMAP=$keymap" > /etc/vconsole.conf
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

# 7. Switch to user and install yay
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
