# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure('2') do |config|
  config.vm.define 'test-virtualbox' do |no1|
    no1.vm.box = 'packer-arch'
    no1.vm.hostname = 'test'

    # bridged adapter instead of NAT
    # no1.vm.network 'public_network'

    no1.vm.synced_folder '.', '/vagrant'
  end

  config.vm.define 'test-libvirt' do |no2|
    no2.vm.box = 'packer-arch'
    no2.vm.hostname = 'test'

    no2.vm.provider 'libvirt' do |libvirt|
      libvirt.loader = '/usr/share/edk2-ovmf/x64/OVMF.fd'
    end

    no2.vm.synced_folder '.', '/vagrant', type: 'nfs', nfs_udp: false
  end
end
