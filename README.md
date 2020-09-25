Packer Archlinux
================

Packer Archlinux is a [Packer](https://www.packer.io/) template and
installation script that can be used to generate a [Vagrant](https://www.vagrantup.com/)
base box for [Arch Linux](https://www.archlinux.org/). The template works
with the default VirtualBox provider as well as with
[VMware](https://www.vagrantup.com/vmware), [Parallels](https://github.com/Parallels/vagrant-parallels)
and [libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt) providers.

Overview
--------

My goal is to duplicate the configuration of my Arch Linux laptop:

* UEFI boot
* LUKS encrypted partitions with the Btrfs filesystem
* LUKS encrypted swap partition
* Includes the `base` meta package and `base-devel` group (needed to compile grub-luks-keyfile)
* OpenSSH is also installed and enabled on boot (needed for Packer and Vagrant)

The installation script follows the
[official installation guide](https://wiki.archlinux.org/index.php/Installation_Guide)
pretty closely, with a few tweaks to ensure functionality within a VM. Beyond
that, the only customizations to the machine are related to the vagrant user
and the steps recommended for any base box.

Usage
-----

### VirtualBox Provider

Assuming that you already have Packer,
[VirtualBox](https://www.virtualbox.org/), and Vagrant installed, you
should be good to clone this repo and go:

    $ git clone https://github.com/ckotte/packer-archlinux.git
    $ cd packer-archlinux/
    $ packer build -only=virtualbox-iso arch-template-luks-btrfs.json

Then you can import the generated box into Vagrant:

    $ vagrant box add arch output/packer_arch_virtualbox.box

### VMware Provider

Assuming that you already have Packer,
[VMware Fusion](https://www.vmware.com/products/fusion/) (or
[VMware Workstation](https://www.vmware.com/products/workstation/)), and
Vagrant with the VMware provider installed, you should be good to clone
this repo and go:

    $ git clone https://github.com/ckotte/packer-archlinux.git
    $ cd packer-archlinux/
    $ packer build -only=vmware-iso arch-template-luks-btrfs.json

Then you can import the generated box into Vagrant:

    $ vagrant box add arch output/packer_arch_vmware.box

### Parallels Provider

Assuming that you already have Packer,
[Parallels](http://www.parallels.com/), [Parallels SDK](http://www.parallels.com/eu/products/desktop/download/) and
Vagrant with the Parallels provider installed, you should be good to clone
this repo and go:

    $ git clone https://github.com/ckotte/packer-archlinux.git
    $ cd packer-archlinux/
    $ packer build -only=parallels-iso arch-template-luks-btrfs.json

Then you can import the generated box into Vagrant:

    $ vagrant box add arch output/packer_arch_parallels.box

### libvirt Provider

Assuming that you already have Packer, Vagrant with the
[vagrant-libvirt](https://github.com/vagrant-libvirt/vagrant-libvirt)
plugin, and [QEMU](https://www.qemu.org) installed, you should be good to clone
this repo and go:

    $ git clone https://github.com/ckotte/packer-archlinux.git
    $ cd packer-archlinux/
    $ packer build -only=qemu arch-template-luks-btrfs.json

Then you can import the generated box into Vagrant:

    $ vagrant box add arch output/packer_arch_libvirt.box

NOTE: libvirt support is limited to QEMU/KVM only.

### wrapacker

For convenience, there is a wrapper script named `wrapacker` that will run the
appropriate `packer build` command for you that will also automatically ensure
the latest ISO download URL and optionally use a mirror from a provided country
code in order to build the final box.

    $ wrapacker --country US --dry-run

For debugging purposes, execute:

    $ PACKER_LOG=1 ./wrapacker --country=US --provider=virtualbox --on-error=ask --force

    $ PACKER_LOG=1 PACKER_LOG_PATH="packer.log" ./wrapacker --country=US --provider=virtualbox --on-error=ask --force

See the `--help` flag for additional details.

### LUKS encryption

The box can be built with or without disk encryption via LUKS. Note: A LUKS1 header is used because grub cannot decrypt LUKS2 headers yet.

With packer:

~~~~
packer build -only=virtualbox-iso -var "ssh_timeout=20m" -var "country=DE" -var "write_zeros=false" -var "btrfs_layout=simple" -var "luks_encryption=no" -on-error=ask -force arch-template-luks-btrfs.json
~~~~

With wrapacker:

~~~~
./wrapacker --country=DE --provider=virtualbox --skip-write-zeros --luks=no --btrfs-layout=simple --on-error=ask --force arch-template-luks-btrfs.json
~~~~

### Btrfs layouts

The box can be built with different Btrfs layouts:
* current: My current (messed up) layout. One subvolume with nested subvolumes. Note: Not recommended!
* simple: Only one subvolume.
* enhanced: Several subvolumes.
* opensuse: openSUSE layout. Note: Cannot be booted because openSUSE-patched version of grub is needed.

With packer:

~~~~
packer build -only=virtualbox-iso -var "ssh_timeout=20m" -var "country=DE" -var "write_zeros=false" -var "btrfs_layout=current" -on-error=ask -force arch-template-luks-btrfs.json
~~~~

With wrapacker:

~~~~
./wrapacker --country=DE --provider=virtualbox --skip-write-zeros --btrfs-layout=current --on-error=ask --force arch-template-luks-btrfs.json
~~~~

### Grub

You need to enter a password ("vagrant") with grub every time the VM boots to unlock /boot if LUKS is used. It's possible to use grub-luks-keyfile and the keyfile to automatically unlock /boot in this case. Note: This is only for testing. This shouldn't be done outside a (Vagrant) Virtual Machine.

With packer:

~~~~
packer build -only=virtualbox-iso -var "ssh_timeout=20m" -var "country=DE" -var "write_zeros=false" -var "btrfs_layout=current" -var "grub_passphrase=no" -on-error=ask -force arch-template-luks-btrfs.json
~~~~

With wrapacker:

~~~~
./wrapacker --country=DE --provider=virtualbox --skip-write-zeros --grub-passphrase=no --btrfs-layout=current --on-error=ask --force arch-template-luks-btrfs.json
~~~~

### Installation Type

You can control the name of the box file. This is useful if you test different configuration options, but don't want to overwrite previously built boxes.

With packer:

~~~~
packer build -only=virtualbox-iso -var "ssh_timeout=20m" -var "country=DE" -var "write_zeros=false" -var "btrfs_layout=enhanced" -var "luks_encryption=yes" -var "grub_passphrase=no" -on-error=ask -force arch-template-luks-btrfs.json
~~~~

With wrapacker:

~~~~
./wrapacker --country=DE --provider=virtualbox --skip-write-zeros --grub-passphrase=no --luks=yes --btrfs-layout=enhanced --on-error=ask --force arch-template-luks-btrfs.json
~~~~

> This will create the file in packer_arch_luks_grub_enhanced_virtualbox-<DATE>.box output.

Known Issues
------------

### Vagrant Provisioners

The box purposefully does not include Puppet, Chef or Ansible for automatic Vagrant
provisioning.

However, this can be done via another repository with an extra Vagrantfile and the packer box imported.

~~~~
vagrant box add arch ../packer-archlinux/output/packer_arch_luks_grub_enhanced_virtualbox-2020.08.01.box --force
~~~~
