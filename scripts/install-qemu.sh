#!/usr/bin/bash -x

# https://wiki.archlinux.org/index.php/QEMU#Preparing_an_(Arch)_Linux_guest
echo ">>>> install-virtualbox.sh: Installing QEMU Guest Agent.."
/usr/bin/pacman -S --noconfirm qemu-guest-agent

echo ">>>> install-virtualbox.sh: Enabling QEMU Guest Agent service.."
/usr/bin/systemctl enable qemu-ga.service
