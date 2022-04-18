#!/bin/bash
# TODO:
# Import .config and etc
# Create prompt for HOSTNAME, Locale


# * Packages
PKGS_BASE="base base-devel linux-firmware linux-zen amd-ucode neovim dhcpcd efibootmgr booster"
PKGS_VIDEO="xf86-video-amdgpu vulkan-radeon mesa mesa-vdpau libva-mesa-driver opencl-amd opencl-icd-loader vulkan-icd-loader lib32-{mesa,mesa-vdpau,libva-mesa-driver,vulkan-icd-loader,opencl-icd-loader,vulkan-radeon}"
PKGS_SOUND="pipewire{,-pulse,-alsa,-jack} wireplumber playerctl easyeffects carla"
PKGS_DESKTOP="xdg-desktop-portal{,-wlr} xorg-xwayland qt{5-wayland,6-wayland} libnotify python{2,3,-pip} imagemagick sway foot{,-terminfo} mpv imv nerd-fonts-victor-mono bashmount udisks2 jmptfs"
PKGS_MISC="obs-studio-git steam ungoogled-chromium discord-canary libxcrypt-compat davinci-resolve-studio"
PKGS_GAMING="wine-staging lutris mangohud goverlay rumtricks gamemode lib32-{gamemode,mangohub}"
PKGS_VM="qemu virt-manager dnsmasq dmidecode iptables-nft"

makeDisks () {
    read -p "Choose disk to use [/dev/sdc]: `echo $'\n'`" DISK
    DISK=${DISK:-/dev/sdc}
    DISK_BOOT="${DISK}1"
    DISK_ROOT="${DISK}2"
    
    wipefs -a $DISK
    parted -s $DISK \
    mklabel gpt \
    mkpart "BOOT" fat32 1MiB 256MiB \
    set 1 esp on \
    mkpart "ROOT" ext4 256MiB 100% \
    print
    
    mkfs.vfat $DISK_BOOT && mkfs.ext4 $DISK_ROOT
    mount $DISK_ROOT /mnt
    mkdir -p /mnt/boot/
    mount $DISK_BOOT /mnt/boot/
}

makeUsers () {
    read -p "Type username [glo]: " USERNAME
    USERNAME=${USERNAME:-glo}
    
    read -p "Type ${USERNAME}'s password" -s USER_PASSWORD
    read -p "And again" -s RETRY_USER_PASSWORD
    if [ "$USER_PASSWORD" = "$RETRY_USER_PASSWORD" ]; then
        echo "Correct password, continuing"
    else
        echo "Incorrect password, try again"
        makeUsers
    fi
    
    read -p "Type ROOT password" -s ROOT_PASSWORD
    read -p "And again" -s RETRY_ROOT_PASSWORD
    if [ "$ROOT_PASSWORD" = "$RETRY_ROOT_PASSWORD" ]; then
        echo "Correct password, continuing"
    else
        echo "Incorrect password, try again"
        makeUsers
    fi
}

makeLocale () {
    read -p "Type Timezone [Europe/Paris]: " ZONE
    ZONE=${ZONE:-Europe/Paris}
    TIMEZONE="/usr/share/zoneinfo/${ZONE}"
    
    if [ -f "$TIMEZONE" ]; then
        echo "$TIMEZONE exists, continuing"
    else
        echo "$TIMEZONE is incorrect timezone, try again"
        makeLocale
    fi
}

makePostScript () {
    cat > /mnt/root/2_chroot.sh <<EOF
# USERS
useradd -m -G users,wheel ${USERNAME}
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
echo "root:${ROOT_PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" > /etc/sudoers.d/wheel

# LOCALE
echo en_US.UTF-8 UTF-8 > /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
ln -sf $TIMEZONE /etc/localtime
hwclock --systohc --utc

# NETWORK
echo mommy > /etc/hostname

# BOOT
efibootmgr -v -d /dev/sdc -p 1 -c -L "ArchZen" -l /vmlinuz-linux-zen -u 'root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK_ROOT}) rw initrd=\amd-ucode.img initrd=\booster-linux-zen.img'

# AUR helper
pacman-key --recv-key FBA220DFC880C036 --keyserver keyserver.ubuntu.com
pacman-key --lsign-key FBA220DFC880C036
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
printf "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf
sed -i '/#\[multilib\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
sed -i '/#\[multilib-testing\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
sed -i '/#\[community-testing\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf
sed -i '/#\[testing\]/,/#Include = \/etc\/pacman.d\/mirrorlist/ s/#//' /etc/pacman.conf

pacman -Syyu
pacman -S paru

# Packages
runuser -l $USERNAME -c 'paru -S ${PKGS_VIDEO}'
runuser -l $USERNAME -c 'paru -S ${PKGS_SOUND}'
runuser -l $USERNAME -c 'paru -S ${PKGS_DESKTOP}'
runuser -l $USERNAME -c 'paru -S ${PKGS_MISC}'
runuser -l $USERNAME -c 'paru -S ${PKGS_GAMING}'
runuser -l $USERNAME -c 'paru -S ${PKGS_VM}'

# Services
systemctl enable dhcpcd bluetooth libvirtd
usermod -a -G libvirt ${USERNAME}
virsh net-list --all
virsh net-start default

# Exit from chroot
exit
EOF
    
    chmod +x /mnt/root/2_chroot.sh
}

makeArch () {
    pacstrap -i /mnt $PKGS_BASE
    genfstab -U /mnt > /mnt/etc/fstab
    
    makePostScript
    arch-chroot /mnt /root/2_chroot.sh
}

makeDisks
makeUsers
makeLocale
makePostScript

printf "\n
DISK: $DISK
BOOT: $DISK_BOOT
ROOT: $DISK_ROOT

USERNAME: $USERNAME
PASSWORD: $USER_PASSWORD
ROOT PASSWORD:  $ROOT_PASSWORD

TIMEZONE: $TIMEZONE
LOCALE: CONSTANT
HOSTNAME: CONSTANT

PKGS:
$PKGS_BASE

$PKGS_VIDEO

$PKGS_SOUND

$PKGS_DEKSTOP

$PKGS_MISC

$PKGS_GAMING

$PKGS_VM
\n"

makeArch
