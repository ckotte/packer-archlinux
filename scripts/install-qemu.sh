#!/usr/bin/bash -x

# https://wiki.archlinux.org/index.php/QEMU#Preparing_an_(Arch)_Linux_guest
echo ">>>> install-qemu.sh: Installing QEMU Guest Agent.."
/usr/bin/pacman -S --noconfirm qemu-guest-agent

# NOTE: The QEMU Guest Agent is now enabled by an udev rule
# echo ">>>> install-qemu.sh: Enabling QEMU Guest Agent service.."
# /usr/bin/systemctl enable qemu-guest-agent.service

echo ">>>> install-qemu.sh: Installing nfs-utils.."
/usr/bin/pacman -S --noconfirm nfs-utils
