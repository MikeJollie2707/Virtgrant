# Virtgrant

These scripts build a libvirt Vagrant box from a local cloud-init image.

These scripts are tested with Debian cloud images. With few modifications, it should also work with Ubuntu cloud images. Other distro are not tested.

These scripts assume you're using `libvirt`.

## Use Case

You want to create several test VMs and you're using `libvirt`.

## Prerequisites

[`vagrant`](https://developer.hashicorp.com/vagrant/install) and [`vagrant-libvirt`](https://vagrant-libvirt.github.io/vagrant-libvirt/#installation) must be installed.

## Quickstart

```bash
./launch.sh --src-img path/to/image1 --dest-img path/to/image2 --disk-size SIZE
./build.sh path/to/image2 local/debian13
```

`SIZE` can be `20G` for example. See `qemu-img resize` for acceptable strings.

## Workflow

### Provision a temporary VM

The default cloud-init image from Debian is not suitable for packaging directly to Vagrant. It requires additional provisionings, which are powered by cloud-init.

The script `launch.sh` will provision a temporary VM. If success, you will have a `.qcow2` disk that is ready to be packaged to Vagrant. If fail, the script will attempt to cleanup itself.

**Note:** This script will launch `post-launch.sh` as one of the last thing it does.

Usage:

```sh
./launch.sh --src-img debian-13-generic-amd64.qcow2 --dest-img ./debian13-temp.qcow2 --disk-size 20G
```

Flags:

- `--src-img` (required): A path to where the cloud image is.
- `--dest-img` (required): Where the disk should be written. You should write to the current directory.
- `--disk-size` (required): How much space the resulting disk should occupy. This is equivalent to `qemu-img resize`.
- `--memory` (optional): How much memory in MB. Default to `2048`.
- `--vcpu` (optional): How much vCPU for the VM. Default to `2`.
- `--network` (optional): Which network to attach to. Default to `default`. It's best not to touch this flag.
- `--vm-name` (optional): The VM's name. Default to `--dest-img` but without the extension.
- `--user` (optional): The SSH user passed to `post-launch.sh`. Must match `user-data.yml`. Default to `debian`.

### Package into Vagrant

The script `build.sh` will package the disk created by [`launch.sh`](#provision-a-temporary-vm) into Vagrant local registry.

Usage:

```sh
./build.sh debian13-temp.qcow2 local/debian13
```

Parameters:

- `DISK` (required): A path to where the disk to package is. It should be the disk created by `launch.sh`.
- `NAME` (required): The name for the box in Vagrant. Since this is locally built, you should prefix with `local/`.

### Bring up VMs

`Vagrantfile` defines how many VMs and how they should be brought up. Once that is defined, use `vagrant up` to bring them up, `vagrant halt` to shut them down, and `vagrant destroy` to remove those VMs.

*It is worth noting that it will take a minute or two for VMs to get their IP addresses. If it hangs for more than two minutes, something is wrong with the networking.*

### Misc scripts

`post-launch.sh`: SSH to the temporary VM and perform some final setup. You shouldn't run this unless `launch.sh` somehow exit prematurely without destroying the VM.

`libvirt-restore-default-net.sh`: A shorthand to restore the `default` network in `libvirt`. Sometimes, if you prematurely remove the temporary VM before `launch.sh` get to delete it, it might delete the `default` network. This script should recover the `default` network.

## AI Usage

`gpt-5.6` is used to make scripts more resilient and can cleanup after itself. It is also used to diagnose and come up with `config/network-config.yml` to fix networking issue.
