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
PASSWORD=$(/usr/bin/openssl passwd -6 'vagrant')
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
LUKS_ENCRYPTION=${LUKS_ENCRYPTION:-yes}
BTRFS_LAYOUT=${BTRFS_LAYOUT:-simple}
GRUB_PASSPHRASE=${GRUB_PASSPHRASE:-yes}
GRUB_BUILD_SCRIPT='/usr/local/bin/build-grub.sh'
TARGET_DIR='/mnt/btrfs'
DATA_TARGET_DIR='/mnt/btrfs-data'
COUNTRY=${COUNTRY:-US}
MIRRORLIST="https://archlinux.org/mirrorlist/?country=${COUNTRY}&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"

# cleanup (only important if this script fails and if execution is retried)
/usr/bin/umount -R ${TARGET_DIR} > /dev/null 2>&1 || /bin/true
/usr/bin/swapoff -a
if [[ $LUKS_ENCRYPTION == "yes" ]]; then
  test -b /dev/mapper/${SWAP_NAME} && /usr/bin/cryptsetup close /dev/mapper/${SWAP_NAME}
  test -b /dev/mapper/${ROOT_NAME} && /usr/bin/cryptsetup close /dev/mapper/${ROOT_NAME}
  test -b /dev/mapper/${DATA_NAME} && /usr/bin/cryptsetup close /dev/mapper/${DATA_NAME}
fi

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

if [[ $LUKS_ENCRYPTION == "yes" ]]; then
  echo ">>>> install-base.sh: Initializing LUKS partitions.."
  # grub decryption is very very slow in a VM with default settings for luksFormat and luksAddKey with grub-luks-keyfile
  # need to change --iter-time to speed up grub decryption
  # --iter-time 2000 luksFormat & --iter-time 2000 luksAddKey (default) = ~120s
  # --iter-time 1000 luksFormat & --iter-time 1 luksAddKey = ~30s
  # --iter-time 1 luksFormat & --iter-time 1 luksAddKey = ~1s
  # skip --iter-time and use the default settings when installing on a physical machine! this is most probably not secure
  echo -n "vagrant" | /usr/bin/cryptsetup --iter-time 1 luksFormat --type luks1 ${DISK}${SWAP_PARTITION} -
  echo -n "vagrant" | /usr/bin/cryptsetup --iter-time 1 luksFormat --type luks1 ${DISK}${ROOT_PARTITION} -
  echo -n "vagrant" | /usr/bin/cryptsetup --iter-time 1 luksFormat --type luks1 ${DISK}${DATA_PARTITION} -

  echo ">>>> install-base.sh: Opening LUKS devices.."
  echo -n "vagrant" | /usr/bin/cryptsetup open ${DISK}${SWAP_PARTITION} ${SWAP_NAME} -
  echo -n "vagrant" | /usr/bin/cryptsetup open ${DISK}${ROOT_PARTITION} ${ROOT_NAME} -
  echo -n "vagrant" | /usr/bin/cryptsetup open ${DISK}${DATA_PARTITION} ${DATA_NAME} -
fi

EFI_DEVICE=${DISK}${EFI_PARTITION}
if [[ $LUKS_ENCRYPTION == "yes" ]]; then
  SWAP_DEVICE=/dev/mapper/${SWAP_NAME}
  ROOT_DEVICE=/dev/mapper/${ROOT_NAME}
  DATA_DEVICE=/dev/mapper/${DATA_NAME}
else
  SWAP_DEVICE=${DISK}${SWAP_PARTITION}
  ROOT_DEVICE=${DISK}${ROOT_PARTITION}
  DATA_DEVICE=${DISK}${DATA_PARTITION}
fi

echo ">>>> install-base.sh: Initializing swap partition.."
/usr/bin/mkswap ${SWAP_DEVICE}
/usr/bin/swapon -d ${SWAP_DEVICE}

echo ">>>> install-base.sh: Creating filesystems.."
/usr/bin/mkfs.fat -F32 ${EFI_DEVICE}
/usr/bin/mkfs.btrfs -f -L root ${ROOT_DEVICE}
/usr/bin/mkfs.btrfs -f -L data ${DATA_DEVICE}

echo ">>>> install-base.sh: Mounting ${ROOT_DEVICE} to ${TARGET_DIR}.."
/usr/bin/mkdir -p ${TARGET_DIR}
/usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}

echo ">>>> install-base.sh: Mounting ${DATA_DEVICE} to ${DATA_TARGET_DIR}.."
/usr/bin/mkdir -p ${DATA_TARGET_DIR}
/usr/bin/mount ${DATA_DEVICE} ${DATA_TARGET_DIR}

echo ">>>> install-base.sh: Creating Btrfs subvolumes.."
case "$BTRFS_LAYOUT" in
  "simple")
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@
    /usr/bin/btrfs subvolume create ${DATA_TARGET_DIR}/@
    ;;
  "enhanced")
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@
    /usr/bin/mkdir -p ${TARGET_DIR}/@/boot/grub/
    # don't create subvolume for Grub BIOS modules
    # /usr/bin/btrfs subvolume create ${TARGET_DIR}/@boot-grub-i386-pc
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/boot/grub/x86_64-efi
    /usr/bin/mkdir -p ${TARGET_DIR}/@/var/lib
    # default location for virtual machine images managed with systemd-nspawn
    # The /var/lib/machine subvolume is created automatically by systemd. Unfortunately, without CoW disabled
    # https://cgit.freedesktop.org/systemd/systemd/commit/?id=113b3fc1a8061f4a24dd0db74e9a3cd0083b2251
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/var/lib/machines
    # default location for portable service images
    # The /var/lib/portables subvolume is created automatically by systemd.
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/var/lib/portables
    /usr/bin/mkdir -p ${TARGET_DIR}/@/var/lib/libvirt
    # default location for virtual machine images managed with libvirt
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/var/lib/libvirt/images
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@home
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@var-cache
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@var-log
    # create /var/cache and /var/tmp as subvolumes be able to start all services when booting into snapshots of /
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@var-tmp
    /usr/bin/mkdir ${TARGET_DIR}/@snapshots
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@snapshots/root
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@snapshots/home
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@snapshots/var-log
    /usr/bin/chmod 750 ${TARGET_DIR}/@snapshots/root
    /usr/bin/chmod 750 ${TARGET_DIR}/@snapshots/home
    /usr/bin/chmod 750 ${TARGET_DIR}/@snapshots/var-log
    /usr/bin/btrfs subvolume create ${DATA_TARGET_DIR}/@
    ;;
  "opensuse")
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@
    # Nested subvolumes of @
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/.snapshots
    /usr/bin/mkdir ${TARGET_DIR}/@/.snapshots/1
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/.snapshots/1/snapshot
    /usr/bin/mkdir -p ${TARGET_DIR}/@/boot/grub/
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/boot/grub/i386-pc
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/boot/grub/x86_64-efi
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/home
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/opt
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/root
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/srv
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/tmp
    /usr/bin/mkdir ${TARGET_DIR}/@/usr/
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/usr/local
    /usr/bin/btrfs subvolume create ${TARGET_DIR}/@/var
    echo ">>>> install-base.sh: Configuring 'first root filesystem' snapshot.."
    DATE=$(date +"%Y-%m-%d %H:%M:%S")
    cat <<-EOF > "${TARGET_DIR}/@/.snapshots/1/info.xml"
<?xml version="1.0"?>
<snapshot>
  <type>single</type>
  <num>1</num>
  <date>${DATE}</date>
  <description>first root filesystem</description>
</snapshot>
EOF
    echo ">>>> install-base.sh: Setting 'first root filesystem' snapshot as the default snapshot.."
    /usr/bin/btrfs subvolume set-default "$(/usr/bin/btrfs subvolume list ${TARGET_DIR} | grep "@/.snapshots/1/snapshot" | grep -oP '(?<=ID )[0-9]+')" ${TARGET_DIR}
    ;;
  *)
    echo ">>>> install-base.sh: Btrfs layout option not supported. Aborting script.."
    exit 1
    ;;
esac

echo ">>>> install-base.sh: Unmounting ${TARGET_DIR}.."
/usr/bin/umount ${TARGET_DIR}

echo ">>>> install-base.sh: Unmounting ${DATA_TARGET_DIR}.."
/usr/bin/umount ${DATA_TARGET_DIR}

echo ">>>> install-base.sh: Mounting Btrfs subvolumes to ${TARGET_DIR}.."
case "$BTRFS_LAYOUT" in
  "simple")
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@ ${ROOT_DEVICE} ${TARGET_DIR}
    ;;
  "enhanced")
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@ ${ROOT_DEVICE} ${TARGET_DIR}
    /usr/bin/mkdir ${TARGET_DIR}/.snapshots
    /usr/bin/chmod 0750 ${TARGET_DIR}/.snapshots
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@snapshots/root ${ROOT_DEVICE} ${TARGET_DIR}/.snapshots
    /usr/bin/mkdir ${TARGET_DIR}/home
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@home ${ROOT_DEVICE} ${TARGET_DIR}/home
    /usr/bin/mkdir ${TARGET_DIR}/home/.snapshots
    /usr/bin/chmod 0750 ${TARGET_DIR}/home/.snapshots
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@snapshots/home ${ROOT_DEVICE} ${TARGET_DIR}/home/.snapshots
    /usr/bin/mkdir -p ${TARGET_DIR}/var/cache
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@var-cache ${ROOT_DEVICE} ${TARGET_DIR}/var/cache
    /usr/bin/mkdir -p ${TARGET_DIR}/var/log
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@var-log ${ROOT_DEVICE} ${TARGET_DIR}/var/log
    /usr/bin/mkdir ${TARGET_DIR}/var/log/.snapshots
    /usr/bin/chmod 0750 ${TARGET_DIR}/var/log/.snapshots
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@snapshots/var-log ${ROOT_DEVICE} ${TARGET_DIR}/var/log/.snapshots
    /usr/bin/mkdir -p ${TARGET_DIR}/var/tmp
    # set sticky bit (https://www.thegeekdiary.com/unix-linux-what-is-the-correct-permission-of-tmp-and-vartmp-directories/)
    /usr/bin/chmod 1777 ${TARGET_DIR}/var/tmp
    /usr/bin/mount -o compress=lzo,discard,noatime,nodiratime,subvol=@var-tmp ${ROOT_DEVICE} ${TARGET_DIR}/var/tmp
    ;;
  "opensuse")
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}
    /usr/bin/mkdir ${TARGET_DIR}/.snapshots
    /usr/bin/mkdir -p ${TARGET_DIR}/boot/grub/i386-pc
    /usr/bin/mkdir -p ${TARGET_DIR}/boot/grub/x86_64-efi
    /usr/bin/mkdir ${TARGET_DIR}/home
    /usr/bin/mkdir ${TARGET_DIR}/opt
    /usr/bin/mkdir ${TARGET_DIR}/root
    /usr/bin/chmod 750 ${TARGET_DIR}/root
    /usr/bin/mkdir ${TARGET_DIR}/srv
    /usr/bin/mkdir ${TARGET_DIR}/tmp
    /usr/bin/mkdir -p ${TARGET_DIR}/usr/local
    /usr/bin/mkdir ${TARGET_DIR}/var
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/.snapshots -o subvol=@/.snapshots
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/boot/grub/i386-pc -o subvol=@/boot/grub/i386-pc
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/boot/grub/x86_64-efi -o subvol=@/boot/grub/x86_64-efi
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/home -o subvol=@/home
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/opt -o subvol=@/opt
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/root -o subvol=@/root
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/srv -o subvol=@/srv
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/tmp -o subvol=@/tmp
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/usr/local -o subvol=@/usr/local
    /usr/bin/mount ${ROOT_DEVICE} ${TARGET_DIR}/var -o subvol=@/var
    ;;
esac

case "$BTRFS_LAYOUT" in
  "enhanced")
    echo ">>>> install-base.sh: Disabling copy-on-write for some directories in /var .."
    /usr/bin/chattr +C ${TARGET_DIR}/var/lib/machines
    /usr/bin/chattr +C ${TARGET_DIR}/var/lib/portables
    /usr/bin/chattr +C ${TARGET_DIR}/var/lib/libvirt/images
    ;;
"simple"|"opensuse")
    echo ">>>> install-base.sh: Disabling copy-on-write for /var .."
    /usr/bin/chattr -R +C ${TARGET_DIR}/var
    ;;
esac

# don't configure Btrfs quotas
#echo ">>>> install-base.sh: Enabling quotas for Btrfs subvolumes.."
#/usr/bin/btrfs quota enable ${TARGET_DIR}/
#/usr/bin/btrfs quota enable ${TARGET_DIR}/var
#/usr/bin/btrfs quota enable ${TARGET_DIR}/home

echo ">>>> install-base.sh: Mounting EFI partition to ${TARGET_DIR}/boot/efi.."
/usr/bin/mkdir -p ${TARGET_DIR}/boot/efi
/usr/bin/mount ${EFI_DEVICE} ${TARGET_DIR}/boot/efi

echo ">>>> install-base.sh: Setting pacman ${COUNTRY} mirrors.."
curl -s "$MIRRORLIST" |  sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist

echo ">>>> install-base.sh: Bootstrapping the base installation.."
/usr/bin/pacstrap ${TARGET_DIR} base linux

case "$BTRFS_LAYOUT" in
  "opensuse")
    # TODO: Need to install openSUSE-patched version of grub. Otherwise, grub cannot boot!
    /usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm grub
    ;;
  *)
    if [[ $LUKS_ENCRYPTION == "yes" ]] && [[ $GRUB_PASSPHRASE == "no" ]]; then
      echo ">>>> install-base.sh: Installing base-devel group.."
      /usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm base-devel
      /usr/bin/install --mode=0755 /dev/null "${TARGET_DIR}${GRUB_BUILD_SCRIPT}"
      GRUB_BUILD_SCRIPT_SHORT=$(basename "$GRUB_BUILD_SCRIPT")
      cat <<-EOF > "${TARGET_DIR}${GRUB_BUILD_SCRIPT}"
echo ">>>> ${GRUB_BUILD_SCRIPT_SHORT}: Downloading grub bootloader.."
# Need to create build directory, because it didn't work with /tmp and arch-chroot
mkdir /build
chown nobody:nobody /build
cd /build
sudo -u nobody curl -L -O https://aur.archlinux.org/cgit/aur.git/snapshot/grub-luks-keyfile.tar.gz
sudo -u nobody tar -xvzf grub-luks-keyfile.tar.gz
echo ">>>> ${GRUB_BUILD_SCRIPT_SHORT}: Compiling grub bootloader.."
# https://grub.johnlane.ie
# https://wiki.archlinux.org/index.php/Arch_User_Repository#Build_and_install_the_package
# https://github.com/rmarquis/pacaur/commit/65d419cae99a7c27b97d32467167b3745c5c77b6
cd grub-luks-keyfile
sudo -u nobody makepkg --syncdeps --rmdeps --clean --skippgpcheck --log --noconfirm &>/dev/null
if [ $? -ne 0 ]; then
  echo ">>>> ${GRUB_BUILD_SCRIPT_SHORT}: grub-luks-keyfile couldn't been build. Connect via SSH and check the logfile."
fi
echo ">>>> ${GRUB_BUILD_SCRIPT_SHORT}: Installing grub bootloader.."
sudo -u nobody makepkg --install --noconfirm
rm -rf /build
EOF
      echo 'nobody ALL=(ALL) NOPASSWD: ALL' >> ${TARGET_DIR}/etc/sudoers.d/10_nobody
      /usr/bin/arch-chroot ${TARGET_DIR} ${GRUB_BUILD_SCRIPT}
      rm "${TARGET_DIR}${GRUB_BUILD_SCRIPT}"
      rm ${TARGET_DIR}/etc/sudoers.d/10_nobody
    else
      echo ">>>> install-base.sh: Installing grub bootloader.."
      /usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm grub
    fi
    ;;
esac
echo ">>>> install-base.sh: Installing basic packages.."
# Need to install netctl as well: https://github.com/archlinux/arch-boxes/issues/70
# Can be removed when Vagrant's Arch plugin will use systemd-networkd: https://github.com/hashicorp/vagrant/pull/11400
# Probably included in Vagrant 2.3.0?
/usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm efibootmgr btrfs-progs dhcpcd netctl sudo vim
/usr/bin/arch-chroot ${TARGET_DIR} ln -sf /usr/bin/vim /usr/bin/vi
/usr/bin/arch-chroot ${TARGET_DIR} pacman -S --noconfirm openssh

echo ">>>> install-base.sh: Generating the filesystem table.."
/usr/bin/genfstab -p ${TARGET_DIR} >> "${TARGET_DIR}/etc/fstab"

if [[ $LUKS_ENCRYPTION == "yes" ]]; then
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
  # need to change --iter-time to speed up grub decryption; see luksFormat above for more details
  # skip --iter-time and use the default settings when installing on a physical machine! this is most probably not secure
  echo -n "vagrant" | /usr/bin/cryptsetup --iter-time 1 luksAddKey ${DISK}${SWAP_PARTITION} ${TARGET_DIR}/root/crypt_keyfile.bin -
  echo -n "vagrant" | /usr/bin/cryptsetup --iter-time 1 luksAddKey ${DISK}${ROOT_PARTITION} ${TARGET_DIR}/root/crypt_keyfile.bin -
  echo -n "vagrant" | /usr/bin/cryptsetup --iter-time 1 luksAddKey ${DISK}${DATA_PARTITION} ${TARGET_DIR}/root/crypt_keyfile.bin -

  echo ">>>> install-base.sh: Backing up LUKS headers.."
  # https://gitlab.com/cryptsetup/cryptsetup/-/wikis/FrequentlyAskedQuestions#6-backup-and-data-recovery
  /usr/bin/cryptsetup luksHeaderBackup ${DISK}${ROOT_PARTITION} --header-backup-file /root/${ROOT_NAME}-luksHeaderBackup.img
  /usr/bin/cryptsetup luksHeaderBackup ${DISK}${DATA_PARTITION} --header-backup-file /root/${DATA_NAME}-luksHeaderBackup.img
fi

echo ">>>> install-base.sh: Configuring initramfs.."
/usr/bin/sed -i "s=^MODULES\=.*=MODULES\=(loop)=" ${TARGET_DIR}/etc/mkinitcpio.conf
/usr/bin/sed -i "s=^BINARIES\=.*=BINARIES\=(/usr/bin/btrfs)=" ${TARGET_DIR}/etc/mkinitcpio.conf
if [[ $LUKS_ENCRYPTION == "yes" ]]; then
  INITRAMFS_FILES="/root/crypt_keyfile.bin"
  if [[ $KEYMAP == "us" ]]; then
    # add openswap, opendata, encrypt, and resume hook
    INITRAMFS_HOOKS="base udev autodetect modconf block openswap opendata encrypt filesystems keyboard resume fsck"
  else
    # add openswap, opendata, encrypt, and resume hook
    INITRAMFS_HOOKS="base udev autodetect modconf block openswap opendata encrypt filesystems keyboard resume fsck"
  fi
else
  if [[ $KEYMAP == "us" ]]; then
    # add resume hook
    INITRAMFS_HOOKS="base udev autodetect modconf block filesystems keyboard resume fsck"
  else
    # add keymap and resume hook
    INITRAMFS_HOOKS="base udev autodetect modconf block filesystems keyboard keymap resume fsck"
  fi
fi
/usr/bin/sed -i "s=^FILES\=.*=FILES\=(${INITRAMFS_FILES})=" ${TARGET_DIR}/etc/mkinitcpio.conf
/usr/bin/sed -i "s=^HOOKS\=.*=HOOKS\=(${INITRAMFS_HOOKS})=" ${TARGET_DIR}/etc/mkinitcpio.conf

echo ">>>> install-base.sh: Creating new initramfs.."
/usr/bin/arch-chroot ${TARGET_DIR} mkinitcpio -p linux

echo ">>>> install-base.sh: Configuring grub.."
/usr/bin/sed -i "s=^GRUB_CMDLINE_LINUX_DEFAULT\=.*=GRUB_CMDLINE_LINUX_DEFAULT\='loglevel\=3'=" ${TARGET_DIR}/etc/default/grub
if [[ $LUKS_ENCRYPTION == "yes" ]]; then
  /usr/bin/sed -i "s=^GRUB_CMDLINE_LINUX\=.*=GRUB_CMDLINE_LINUX\='cryptdevice\=${DISK}${ROOT_PARTITION}:${ROOT_NAME} cryptkey\=rootfs:/root/crypt_keyfile.bin resume\=/dev/mapper/${SWAP_NAME}'=" ${TARGET_DIR}/etc/default/grub
  /usr/bin/sed -i "s=#GRUB_ENABLE_CRYPTODISK\=.*=GRUB_ENABLE_CRYPTODISK\='y'=" ${TARGET_DIR}/etc/default/grub
else
  /usr/bin/sed -i "s=^GRUB_CMDLINE_LINUX\=.*=GRUB_CMDLINE_LINUX\='resume\=${SWAP_DEVICE}'=" ${TARGET_DIR}/etc/default/grub
fi

echo ">>>> install-base.sh: Generating the system configuration script.."
/usr/bin/install --mode=0755 /dev/null "${TARGET_DIR}${CONFIG_SCRIPT}"

CONFIG_SCRIPT_SHORT=$(basename "$CONFIG_SCRIPT")
cat <<-EOF > "${TARGET_DIR}${CONFIG_SCRIPT}"
echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring hostname, timezone, and keymap.."
echo '${FQDN}' > /etc/hostname
/usr/bin/ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc
echo 'KEYMAP=${KEYMAP}' > /etc/vconsole.conf
echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring locale.."
/usr/bin/sed -i 's/#${LANGUAGE}/${LANGUAGE}/' /etc/locale.gen
/usr/bin/locale-gen
echo ">>>> ${CONFIG_SCRIPT_SHORT}: Configuring grub.."
/usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch
if [[ $LUKS_ENCRYPTION == "yes" ]] && [[ ${GRUB_PASSPHRASE} == "no" ]]; then
  cp /root/crypt_keyfile.bin /boot/efi/EFI/arch/crypt_keyfile.bin
  echo 'cryptomount -k (hd0,gpt1)/efi/arch/crypt_keyfile.bin (hd0,gpt3)' > /tmp/load.cfg
  grub-mkimage --directory=/usr/lib/grub/x86_64-efi --prefix='(crypto0)/@/boot/grub' \
    --output=/boot/efi/EFI/arch/grubx64.efi --format=x86_64-efi --compression=auto \
    --config=/tmp/load.cfg btrfs cryptodisk luks gcry_rijndael gcry_rijndael gcry_sha256 part_gpt fat normal configfile
fi
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
if [[ $LUKS_ENCRYPTION == "yes" ]] && [[ ${GRUB_PASSPHRASE} == "yes" ]]; then
  echo ">>>> install-base.sh: Basic installation complete. Type in grub passphrase to continue with $PACKER_BUILDER_TYPE configuration."
else
  echo ">>>> install-base.sh: Basic installation complete. Continueing with $PACKER_BUILDER_TYPE configuration.."
fi
/usr/bin/systemctl reboot
