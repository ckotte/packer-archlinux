#!/usr/bin/bash -x

# https://wiki.archlinux.org/index.php/VirtualBox/Install_Arch_Linux_as_a_guest
echo ">>>> install-virtualbox.sh: Installing VirtualBox Guest Additions and NFS utilities.."
/usr/bin/pacman -S --noconfirm virtualbox-guest-utils-nox nfs-utils

echo ">>>> install-virtualbox.sh: Enabling VirtualBox Guest service.."
/usr/bin/systemctl enable vboxservice.service

# Add groups for VirtualBox folder sharing
echo ">>>> install-virtualbox.sh: Enabling VirtualBox Shared Folders.."
/usr/bin/usermod --append --groups vagrant,vboxsf vagrant
