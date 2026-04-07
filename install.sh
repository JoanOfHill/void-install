# "Easy" Void Linux bootstrap and system install guide

# Boot into a Live USB

bash

# Check paritions, you should have a 1GB EFI system at /dev/nvme0n1p1 and a 1.9TB Linux system at /dev/nvme0n1p2

fdisk -l /dev/nvme0n1

# Create and open LUKS container

cryptsetup luksFormat --type luks1 /dev/nvme0n1p2
cryptsetup luksOpen /dev/nvme0n1p2 tyr
# Enter SSD volume password

# Create logical volume group and logical volumes

vgcreate tyr /dev/mapper/tyr
lvcreate --name root -L 250G tyr
lvcreate --name swap -L 32G tyr
lvcreate --name home -l 100%FREE tyr

# Create file systems

mkfs.ext4 -L root /dev/tyr/root
mkfs.ext4 -L home /dev/tyr/home
mkswap /dev/tyr/swap
swapon /dev/tyr/swap

# Setup chroot

mount /dev/tyr/root /mnt
mkdir -p /mnt/home
mount /dev/tyr/home /mnt/home

# Mount EFI system partition

mkfs.vfat /dev/nvme0n1p1
mkdir -p /mnt/boot/efi
mount /dev/nvme0n1p1 /mnt/boot/efi

# Copy XBPS repo keys

mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

# Install Void

xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt base-system cryptsetup grub-x86_64-efi lvm2 void-repo-nonfree void-repo-multilib void-repo-multilib-nonfree

# Install additional packages

PACKAGES=(
   python3-dbus libva-utils
   # Utilities
   opendoas rsync lynx vim nano wget curl unzip xz 7zip git xterm rxvt-unicode android-tools feh autoconf automake pkg-config
   # System Tools
   LACT htop nvtop gparted wireguard dmidecode
   # Accessories
   gvim Thunar engrampa mousepad keepassxc xarchiver
   # Filesystem
   udisks2 gvfs gvfs-afc gvfs-mtp gvfs-smb gvfs-gphoto2
   # System
   linux6.19 linux6.19-headers linux-firmware-network linux-firmware-amd mesa-dri vulkan-loader mesa-vulkan-radeon mesa-vaapi xf86-video-amdgpu
   # Services
   dbus elogind polkit bluez ufw NetworkManager chrony cronie
   # Fonts
   terminus-font xorg-fonts dejavu-fonts-ttf noto-fonts-ttf noto-fonts-cjk noto-fonts-emoji nerd-fonts nerd-fonts-ttf liberation-fonts-ttf
   # Audio
   helvum pipewire alsa-pipewire wireplumber
   # Internet
   mumble liferea hexchat firefox-esr thunderbird deluge deluge-gtk dino gajim protonmail-bridge
   # Office
   libreoffice gimp
   # Graphical Environment
   xorg xorg-video-drivers xorg-input-drivers lightdm lightdm-gtk3-greeter gtk+3 xdg-user-dirs xdg-desktop-portal xdg-desktop-portal-gtk network-manager-applet webp-pixbuf-loader libheif-pixbuf-loader
   # GUI Questionable
   light-locker gnome-themes-standard
   # Xfce4 specific
   xfce4 xfce4-pulseaudio-plugin
   # WindowMaker and dockapp specific
   WindowMaker wmsystemtray libX11-devel libXpm-devel libdockapp-devel libiconv-devel lm_sensors libsensors-devel
   # Multimedia
   rhythmbox vlc libaacs obs v4l2loopback tuxguitar picard
   # Steam
   steam libgcc-32bit libstdc++-32bit libdrm-32bit libglvnd-32bit mesa-dri-32bit
)

xbps-install -Sy -R https://repo-default.voidlinux.org/current -r /mnt "${PACKAGES[@]}"

# Generate fstab

xgenfstab /mnt > /mnt/etc/fstab

# Enter chroot

xchroot /mnt
bash
chown root:root /
chmod 755 /
passwd root
# Type root password

# Set hostname, timezone and system Locale

echo tyr > /etc/hostname
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "en_US.UTF-8 UTF-8" >> /etc/default/libc-locales
xbps-reconfigure -f glibc-locales

# GRUB Config

## Copy UUID of LUKS container
#blkid -o value -s UUID /dev/nvme0n1p2
## Edit /etc/default/grub and add the following
#GRUB_ENABLE_CRYPTODISK=y
## Append the following to  GRUB_CMDLINE_LINUX_DEFAULT= entry in /etc/default/grub and append it with the following
#rd.lvm.vg=tyr rd.luks.uuid=<UUID> rd.luks.allow-discards

SSD_LUKS_UUID=$(blkid -o value -s UUID /dev/nvme0n1p2)
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
sed -i "s/\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)/\1 rd.lvm.vg=tyr rd.luks.uuid=${SSD_LUKS_UUID} rd.luks.allow-discards/" /etc/default/grub

# LUKS Key setup

dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key
cryptsetup luksAddKey /dev/nvme0n1p2 /boot/volume.key
chmod 000 /boot/volume.key
chmod -R g-rwx,o-rwx /boot

## Edit /etc/crypttab and append it with
##tyr	/dev/nvme0n1p2	/boot/volume.key	luks,discard
#tyr	UUID=<UUID>	/boot/volume.key	luks,discard

# Inject UUID into crypttab
echo "tyr    UUID=${SSD_LUKS_UUID}    /boot/volume.key    luks,discard" >> /etc/crypttab

# Enable discard in LVM
sudo sed -i 's/^.*issue_discards =.*/\tissue_discards = 1/' /etc/lvm/lvm.conf

## Add keyfile
#touch /etc/dracut.conf.d/10-crypt.conf
## Add the following to 10-crypt.conf
#install_items+=" /boot/volume.key /etc/crypttab "

# Add keyfile
echo 'install_items+=" /boot/volume.key /etc/crypttab "' > /etc/dracut.conf.d/10-crypt.conf

# Install bootloader and generate initramfs

# grub-install /dev/nvme0n1
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="Void"
xbps-reconfigure -fa

# Enable weekly TRIM cron job
mkdir -p /etc/cron.weekly/
cat << 'EOF' > /etc/cron.weekly/fstrim
#!/bin/sh
fstrim /
EOF
chmod u+x /etc/cron.weekly/fstrim

# Enable services

ln -s /etc/sv/dbus /etc/runit/runsvdir/default/
ln -s /etc/sv/sshd /etc/runit/runsvdir/default/
ln -s /etc/sv/NetworkManager /etc/runit/runsvdir/default/
ln -s /etc/sv/lightdm /etc/runit/runsvdir/default/
ln -s /etc/sv/polkitd /etc/runit/runsvdir/default/
ln -s /etc/sv/ufw /etc/runit/runsvdir/default/
ln -s /etc/sv/chronyd /etc/runit/runsvdir/default/
ln -s /etc/sv/cronie /etc/runit/runsvdir/default/
ln -s /etc/sv/bluetoothd /etc/runit/runsvdir/default/

# Create standard user and set password

useradd -m -G wheel,audio,video,cdrom,input,lp,network,sudo,tty,floppy,dialout,storage,optical -s /bin/bash iryna
passwd iryna
# Type user password

# Configure doas

echo "permit persist :wheel" > /etc/doas.conf
chown root:root /etc/doas.conf
chmod 0400 /etc/doas.conf

# Exit the chroot, unmount everything, reboot and hope you didn't fuck anything up

exit
exit
umount -R /mnt
exit
reboot

# After reboot

# Remove old resolv.conf, symlink to runtime file and restart NetworkManager

rm -f /etc/resolv.conf
ln -s /run/NetworkManager/resolv.conf /etc/resolv.conf
sv restart NetworkManager

# Pipewire setup

mkdir -p /etc/xdg/autostart
ln -sf /usr/share/applications/pipewire.desktop /etc/xdg/autostart/
mkdir -p /etc/pipewire/pipewire.conf.d
ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/
mkdir -p /etc/alsa/conf.d
ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf /etc/alsa/conf.d
ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d

# SSD Setup
# Check if drives allow TRIM

lsblk --discard

# If yes, go to https://docs.voidlinux.org/config/ssd.html for setup info

# Add pre-existing 20TB HDD to filesystem (optional)
# Generate keyfile and add to HDD
mkdir /mnt/hd1
cryptsetup luksOpen /dev/sdb1
# Enter HDD volume password
mount /dev/mapper/hd1 /mnt/hd1
mkdir -p /etc/luks
dd bs=1 count=64 if=/dev/urandom of=/etc/luks/hd1.key
chmod 400 /etc/luks/hd1.key
cryptsetup luksAddKey /dev/sdb1 /etc/luks/hd1.key

# Add to crypttab and fstab
HDD_UUID=$(blkid -s UUID -o value /dev/sdb1)
echo "hd1    UUID=${HDD_UUID}    /etc/luks/hd1.key    luks" >> /etc/crypttab
echo "/dev/mapper/hd1    /mnt/hd1    ext4    defaults    0    2" >> /etc/fstab

## Determine HDD UUID
#blkid -s UUID -o value /dev/sdb1
## Append /etc/crypttab with the following:
#hd1	UUID=<UUID>	/etc/luks/hd1.key	luks
## Append /etc/fstab with the following:
#/dev/mapper/hd1	/mnt/hd1	ext4	defaults	0	2

# Discord install

cd ~/git
git clone https://github.com/void-linux/void-packages.git
cd void-packages
./xbps-src binary-bootstrap
echo XBPS_ALLOW_RESTRICTED=yes >> etc/conf
./xbps-src pkg discord
doas xbps-install --repository=$PWD/hostdir/binpkgs/nonfree discord

# WindowMaker config

# Clone dockapp repo
cd ~/git
git clone https://github.com/window-maker/dockapps.git

# Edit ~/GNUstep/Library/WindowMaker/autostart and add
light-locker &
