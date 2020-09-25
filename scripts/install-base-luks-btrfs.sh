#!/usr/bin/env bash

# stop on errors
set -eu

if [[ $PACKER_BUILDER_TYPE == "qemu" ]]; then
  DISK='/dev/vda'
else
  DISK='/dev/sda'
fi

FQDN='vagrant-arch.vagrantup.com'
KEYMAP='us'
LANGUAGE='en_US.UTF-8'
PASSWORD=$(/usr/bin/openssl passwd -crypt 'vagrant')
TIMEZONE='Europe/Berlin'

CONFIG_SCRIPT='/usr/local/bin/arch-config.sh'
EFI_PARTITION="1"
SWAP_PARTITION="2"
ROOT_PARTITION="3"
DATA_PARTITION="4"
EFI_SIZE="550M"
SWAP_SIZE="2G"
ROOT_SIZE="24G"
DATA_SIZE="0"
SWAP_NAME="cryptArchSwap"
ROOT_NAME="cryptArchSystem"
DATA_NAME="cryptData"
TARGET_DIR='/mnt'
COUNTRY=${COUNTRY:-US}
MIRRORLIST="https://www.archlinux.org/mirrorlist/?country=${COUNTRY}&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"

# cleanup (only important if this script fails and if execution is retried)
/usr/bin/umount -R ${TARGET_DIR} > /dev/null 2>&1 || /bin/true
/usr/bin/swapoff -a
test -b /dev/mapper/${SWAP_NAME} && /usr/bin/cryptsetup close /dev/mapper/${SWAP_NAME}
test -b /dev/mapper/${ROOT_NAME} && /usr/bin/cryptsetup close /dev/mapper/${ROOT_NAME}
test -b /dev/mapper/${DATA_NAME} && /usr/bin/cryptsetup close /dev/mapper/${DATA_NAME}

echo ">>>> install-base.sh: Clearing partition table on ${DISK}.."
/usr/bin/sgdisk --zap-all ${DISK}

echo ">>>> install-base.sh: Destroying magic strings and signatures on ${DISK}.."
/usr/bin/dd if=/dev/zero of=${DISK} bs=512 count=2048
/usr/bin/wipefs --all ${DISK}

echo ">>>> install-base.sh: Creating partitions on ${DISK}.."
/usr/bin/sgdisk --new=${EFI_PARTITION}:0:+${EFI_SIZE} --typecode=1:ef00 ${DISK}
/usr/bin/sgdisk --new=${SWAP_PARTITION}:0:+${SWAP_SIZE} --typecode=1:8200 ${DISK}
/usr/bin/sgdisk --new=${ROOT_PARTITION}:0:+${ROOT_SIZE} --typecode=1:8300 ${DISK}
/usr/bin/sgdisk --new=${DATA_PARTITION}:0:${DATA_SIZE} --typecode=1:8300 ${DISK}

echo ">>>> install-base.sh: Initializing LUKS partitions.."
echo -n "vagrant" | /usr/bin/cryptsetup luksFormat --type luks1 ${DISK}${SWAP_PARTITION} -
echo -n "vagrant" | /usr/bin/cryptsetup luksFormat --type luks1 ${DISK}${ROOT_PARTITION} -
echo -n "vagrant" | /usr/bin/cryptsetup luksFormat --type luks1 ${DISK}${DATA_PARTITION} -

echo ">>>> install-base.sh: Opening LUKS devices.."
echo -n "vagrant" | /usr/bin/cryptsetup open ${DISK}${SWAP_PARTITION} ${SWAP_NAME} -
echo -n "vagrant" | /usr/bin/cryptsetup open ${DISK}${ROOT_PARTITION} ${ROOT_NAME} -
echo -n "vagrant" | /usr/bin/cryptsetup open ${DISK}${DATA_PARTITION} ${DATA_NAME} -

echo ">>>> install-base.sh: Initializing swap partition.."
/usr/bin/mkswap /dev/mapper/${SWAP_NAME}
/usr/bin/swapon -d /dev/mapper/${SWAP_NAME}

echo ">>>> install-base.sh: Creating filesystems.."
/usr/bin/mkfs.fat -F32 ${DISK}${EFI_PARTITION}
/usr/bin/mkfs.btrfs /dev/mapper/${ROOT_NAME}
/usr/bin/mkfs.btrfs /dev/mapper/${DATA_NAME}

echo ">>>> install-base.sh: Mounting /dev/mapper/${ROOT_NAME} to ${TARGET_DIR}.."
/usr/bin/mount /dev/mapper/${ROOT_NAME} ${TARGET_DIR}

echo ">>>> install-base.sh: Creating Btrfs subvolumes.."
/usr/bin/btrfs subvolume create ${TARGET_DIR}/@
# don't create grub subvolumes
# /usr/bin/mkdir -p ${TARGET_DIR}/@/boot/grub/
# /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/boot/grub/i386-pc
# /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/boot/grub/x86_64-efi
/usr/bin/btrfs subvolume create ${TARGET_DIR}/@/home
/usr/bin/btrfs subvolume create ${TARGET_DIR}/@/var

echo ">>>> install-base.sh: Unmounting ${TARGET_DIR}.."
/usr/bin/umount ${TARGET_DIR}

echo ">>>> install-base.sh: Mounting Btrfs subvolumes to ${TARGET_DIR}.."
/usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@ /dev/mapper/${ROOT_NAME} ${TARGET_DIR}
#/usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@/boot/grub/i386-pc /dev/mapper/${ROOT_NAME} ${TARGET_DIR}/boot/grub/i386-pc
#/usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@/boot/grub/x86_64-efi /dev/mapper/${ROOT_NAME} ${TARGET_DIR}/sx86_64-efi
#/usr/bin/mkdir ${TARGET_DIR}/home
/usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@/home /dev/mapper/${ROOT_NAME} ${TARGET_DIR}/home
#/usr/bin/mkdir ${TARGET_DIR}/var
/usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@/var /dev/mapper/${ROOT_NAME} ${TARGET_DIR}/var

echo ">>>> install-base.sh: Creating nested Btrfs subvolumes.."
/usr/bin/btrfs subvolume create ${TARGET_DIR}/var/cache
/usr/bin/btrfs subvolume create ${TARGET_DIR}/var/log
/usr/bin/btrfs subvolume create ${TARGET_DIR}/var/tmp
/usr/bin/mkdir -p ${TARGET_DIR}/var/lib
# default location for virtual machine images managed with systemd-nspawn
# /var/lib/machine subvolume is created by systemd automatically. Unfortunately, without CoW disabled
# https://cgit.freedesktop.org/systemd/systemd/commit/?id=113b3fc1a8061f4a24dd0db74e9a3cd0083b2251
/usr/bin/btrfs subvolume create ${TARGET_DIR}/var/lib/machines
/usr/bin/mkdir -p ${TARGET_DIR}/var/lib/libvirt
# default location for virtual machine images managed with libvirt
/usr/bin/btrfs subvolume create ${TARGET_DIR}/var/lib/libvirt/images
# set sticky bit (https://www.thegeekdiary.com/unix-linux-what-is-the-correct-permission-of-tmp-and-vartmp-directories/)
/usr/bin/chmod 1777 ${TARGET_DIR}/var/tmp
/usr/bin/btrfs subvolume create ${TARGET_DIR}/.snapshots
/usr/bin/btrfs subvolume create ${TARGET_DIR}/home/.snapshots
/usr/bin/btrfs subvolume create ${TARGET_DIR}/var/.snapshots
/usr/bin/chmod 750 ${TARGET_DIR}/.snapshots
/usr/bin/chmod 750 ${TARGET_DIR}/home/.snapshots
/usr/bin/chmod 750 ${TARGET_DIR}/var/.snapshots

echo ">>>> install-base.sh: Disabling copy-on-write for /var Btrfs subvolumes.."
/usr/bin/chattr +C ${TARGET_DIR}/var
/usr/bin/chattr +C ${TARGET_DIR}/var/cache
/usr/bin/chattr +C ${TARGET_DIR}/var/lib
/usr/bin/chattr +C ${TARGET_DIR}/var/lib/machines
/usr/bin/chattr +C ${TARGET_DIR}/var/lib/libvirt
/usr/bin/chattr +C ${TARGET_DIR}/var/lib/libvirt/images
/usr/bin/chattr +C ${TARGET_DIR}/var/log
/usr/bin/chattr +C ${TARGET_DIR}/var/tmp

# don't configure Btrfs quotas
#echo ">>>> install-base.sh: Enabling quotas for Btrfs subvolumes.."
#/usr/bin/btrfs quota enable ${TARGET_DIR}/
#/usr/bin/btrfs quota enable ${TARGET_DIR}/var
#/usr/bin/btrfs quota enable ${TARGET_DIR}/home

echo ">>>> install-base.sh: Mounting EFI partition to ${TARGET_DIR}/boot/efi.."
/usr/bin/mkdir -p ${TARGET_DIR}/boot/efi
/usr/bin/mount ${DISK}${EFI_PARTITION} ${TARGET_DIR}/boot/efi

echo ">>>> install-base.sh: Setting pacman ${COUNTRY} mirrors.."
curl -s "$MIRRORLIST" |  sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist

echo ">>>> install-base.sh: Bootstrapping the base installation.."
/usr/bin/pacstrap ${TARGET_DIR} base linux

echo ">>>> install-base.sh: Installing basic packages.."
# Need to install netctl as well: https://github.com/archlinux/arch-boxes/issues/70
# Can be removed when Vagrant's Arch plugin will use systemd-networkd: https://github.com/hashicorp/vagrant/pull/11400
# Probably included in Vagrant 2.3.0?
/usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm grub efibootmgr btrfs-progs dhcpcd netctl sudo vim
/usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm openssh

echo ">>>> install-base.sh: Generating the filesystem table.."
/usr/bin/genfstab -p ${TARGET_DIR} >> "${TARGET_DIR}/etc/fstab"

echo ">>>> install-base.sh: Adding filesystem table entry for tmpfs.."
echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> "${TARGET_DIR}/etc/fstab"

echo ">>>> install-base.sh: Configuring additional initramfs hooks for LUKS partitions.."
cat <<-EOF > "${TARGET_DIR}/etc/initcpio/hooks/opendata"
run_hook ()
{
    cryptsetup open --key-file /root/crypt_keyfile.bin --type luks ${DISK}${DATA_PARTITION} ${DATA_NAME}
}
EOF
cat <<-EOF > "${TARGET_DIR}/etc/initcpio/hooks/openswap"
run_hook ()
{
    cryptsetup open --key-file /root/crypt_keyfile.bin --type luks ${DISK}${SWAP_PARTITION} ${SWAP_NAME}
}
EOF
cat <<-EOF > "${TARGET_DIR}/etc/initcpio/install/opendata"
build ()
{
    add_runscript
}
help ()
{
cat<<HELPEOF
   This opens the data encrypted partition ${DISK}${DATA_PARTITION} in /dev/mapper/${DATA_NAME}
HELPEOF
}
EOF
cat <<-EOF > "${TARGET_DIR}/etc/initcpio/install/openswap"
build ()
{
    add_runscript
}
help ()
{
cat<<HELPEOF
   This opens the swap encrypted partition ${DISK}${SWAP_PARTITION} in /dev/mapper/${SWAP_NAME}
HELPEOF
}
EOF

echo ">>>> install-base.sh: Creating keyfile.."
/usr/bin/dd bs=512 count=4 if=/dev/urandom of="${TARGET_DIR}/root/crypt_keyfile.bin"
/usr/bin/chmod 000 ${TARGET_DIR}/root/crypt_keyfile.bin
/usr/bin/chmod 600 ${TARGET_DIR}/boot/initramfs-*

echo ">>>> install-base.sh: Adding keyfile to LUKS devices.."
echo -n "vagrant" | /usr/bin/cryptsetup luksAddKey ${DISK}${SWAP_PARTITION} ${TARGET_DIR}/root/crypt_keyfile.bin -
echo -n "vagrant" | /usr/bin/cryptsetup luksAddKey ${DISK}${ROOT_PARTITION} ${TARGET_DIR}/root/crypt_keyfile.bin -
echo -n "vagrant" | /usr/bin/cryptsetup luksAddKey ${DISK}${DATA_PARTITION} ${TARGET_DIR}/root/crypt_keyfile.bin -

echo ">>>> install-base.sh: Configuring initramfs.."
/usr/bin/sed -i "s=^MODULES\=.*=MODULES\=(loop)=" ${TARGET_DIR}/etc/mkinitcpio.conf
/usr/bin/sed -i "s=^BINARIES\=.*=BINARIES\=(/usr/bin/btrfs)=" ${TARGET_DIR}/etc/mkinitcpio.conf
/usr/bin/sed -i "s=^FILES\=.*=FILES\=(/root/crypt_keyfile.bin)=" ${TARGET_DIR}/etc/mkinitcpio.conf
/usr/bin/sed -i "s=^HOOKS\=.*=HOOKS\=(base udev autodetect modconf block keyboard keymap openswap opendata encrypt filesystems resume fsck)=" ${TARGET_DIR}/etc/mkinitcpio.conf

echo ">>>> install-base.sh: Configuring grub.."
/usr/bin/sed -i "s=^GRUB_CMDLINE_LINUX_DEFAULT\=.*=GRUB_CMDLINE_LINUX_DEFAULT\='loglevel\=3'=" ${TARGET_DIR}/etc/default/grub
/usr/bin/sed -i "s=^GRUB_CMDLINE_LINUX\=.*=GRUB_CMDLINE_LINUX\='cryptdevice\=${DISK}${ROOT_PARTITION}:${ROOT_NAME} cryptkey\=rootfs:/root/crypt_keyfile.bin resume\=/dev/mapper/${SWAP_NAME}'=" ${TARGET_DIR}/etc/default/grub
/usr/bin/sed -i "s=#GRUB_ENABLE_CRYPTODISK\=.*=GRUB_ENABLE_CRYPTODISK\='y'=" ${TARGET_DIR}/etc/default/grub

echo ">>>> install-base.sh: Generating the system configuration script.."
/usr/bin/install --mode=0755 /dev/null "${TARGET_DIR}${CONFIG_SCRIPT}"

CONFIG_SCRIPT_SHORT=`basename "$CONFIG_SCRIPT"`
cat <<-EOF > "${TARGET_DIR}${CONFIG_SCRIPT}"
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring hostname, timezone, and keymap.."
  echo '${FQDN}' > /etc/hostname
  /usr/bin/ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  hwclock --systohc
  echo 'KEYMAP=${KEYMAP}' > /etc/vconsole.conf
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring locale.."
  /usr/bin/sed -i 's/#${LANGUAGE}/${LANGUAGE}/' /etc/locale.gen
  /usr/bin/locale-gen
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Creating initramfs.."
  /usr/bin/mkinitcpio -p linux
  # needs to be executed inside the chroot
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring grub.."
  /usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch
  /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
  # additinal step is necessary if VirtualBox is used
  # add grub to EFI shell autostart:
  # - Grub boot doesn't work anymore after the VM got exported by packer
  # - The system just boots in the EFI shell on a new system deployed via Vagrant (probably because the EFI information doesn't get exported!?)
  echo '\EFI\arch\grubx64.efi' > /boot/efi/startup.nsh
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Setting root pasword.."
  /usr/bin/usermod --password ${PASSWORD} root
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring network.."
  # Disable systemd Predictable Network Interface Names and revert to traditional interface names
  # https://wiki.archlinux.org/index.php/Network_configuration#Revert_to_traditional_interface_names
  /usr/bin/ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules
  /usr/bin/systemctl enable dhcpcd@eth0.service
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring sshd.."
  /usr/bin/sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
  /usr/bin/systemctl enable sshd.service

  # Vagrant-specific configuration
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Creating vagrant user.."
  /usr/bin/groupadd -g 1234 vagrant
  /usr/bin/useradd --password ${PASSWORD} --comment 'Vagrant User' --create-home --uid 1234 --gid 1234 vagrant
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring vagrant cache btrfs volume.."
  /usr/bin/btrfs subvolume create /home/vagrant/.cache
  chown vagrant.vagrant /home/vagrant/.cache
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring sudo.."
  echo 'Defaults env_keep += "SSH_AUTH_SOCK"' > /etc/sudoers.d/10_vagrant
  echo 'vagrant ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/10_vagrant
  /usr/bin/chmod 0440 /etc/sudoers.d/10_vagrant
  echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring ssh access for vagrant.."
  /usr/bin/install --directory --owner=vagrant --group=vagrant --mode=0700 /home/vagrant/.ssh
  /usr/bin/curl --output /home/vagrant/.ssh/authorized_keys --location https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub
  /usr/bin/chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys
  /usr/bin/chmod 0600 /home/vagrant/.ssh/authorized_keys
EOF

echo ">>>> install-base.sh: Entering chroot and configuring system.."
/usr/bin/arch-chroot ${TARGET_DIR} ${CONFIG_SCRIPT}
rm "${TARGET_DIR}${CONFIG_SCRIPT}"

echo ">>>> install-base.sh: Completing installation.."
/usr/bin/sleep 3
/usr/bin/umount -R ${TARGET_DIR}
/usr/bin/swapoff -a
/usr/bin/systemctl reboot
echo ">>>> install-base.sh: Basic installation complete. Type in grub passphrase to continue with $PACKER_BUILDER_TYPE configuration."
