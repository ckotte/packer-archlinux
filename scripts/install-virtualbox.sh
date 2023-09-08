#!/usr/bin/bash -x

# https://wiki.archlinux.org/index.php/VirtualBox/Install_Arch_Linux_as_a_guest
echo ">>>> install-virtualbox.sh: Installing VirtualBox Guest Additions and NFS utilities.."
/usr/bin/pacman -S --noconfirm virtualbox-guest-utils-nox nfs-utils

echo ">>>> install-virtualbox.sh: Enabling VirtualBox Guest service.."
/usr/bin/systemctl enable vboxservice.service

# Add groups for VirtualBox folder sharing
echo ">>>> install-virtualbox.sh: Enabling VirtualBox Shared Folders.."
/usr/bin/usermod --append --groups vagrant,vboxsf vagrant

# Vagrant boot workaround
echo ">>>> install-virtualbox.sh: Configuring grub.."
# Move installed GRUB EFI executable to the default/fallback path. Otherwise, system won't boot automatically after imported to Vagrant.
# https://wiki.archlinux.org/title/GRUB#Default/fallback_boot_path
/usr/bin/mv /boot/efi/EFI/arch /boot/efi/EFI/BOOT
/usr/bin/mv /boot/efi/EFI/BOOT/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
# Need to re-configure grub when a passphrase shouldn't be used. Otherwise, grub can't find the keyfile.
if [[ $LUKS_ENCRYPTION == "yes" ]] && [[ ${GRUB_PASSPHRASE} == "no" ]]; then
    echo 'cryptomount -k "(hd0,gpt1)/efi/BOOT/crypt_keyfile.bin" (hd0,gpt3)' > /tmp/load.cfg
    /usr/bin/grub-mkimage --directory=/usr/lib/grub/x86_64-efi --prefix='(crypto0)/@/boot/grub' \
        --output="/boot/efi/EFI/BOOT/BOOTX64.EFI" --format=x86_64-efi --compression=auto \
        --config=/tmp/load.cfg btrfs cryptodisk luks gcry_rijndael gcry_rijndael gcry_sha256 part_gpt fat normal configfile
    /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
fi
# Just in case. Needed in the past to boot automatically after imported to Vagrant.
echo ">>>> install-virtualbox.sh: Adding grub to EFI shell autostart.."
echo '\EFI\BOOT\BOOTX64.EFI' > /boot/efi/startup.nsh
