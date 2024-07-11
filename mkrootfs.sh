#!/bin/bash

current_dir=$(cd $(dirname $0); pwd)
script_name="$(basename "${0}")"
custom_file_dir="${current_dir}/custom_file"
custom_sources_list="${custom_file_dir}/sources.list"
custom_package_list="${custom_file_dir}/custom_package_list"
custom_netconfig="${custom_file_dir}/00-installer-config-static.yaml"
user_name="dar"
user_passwd="."

distrubution="focal"
mirrors_url="http://mirrors.ustc.edu.cn/ubuntu/"
arch="amd64"
rootfs_folder="${current_dir}/linux-rootfs"

function precheck()
{
    if [ ! "$(command -v debootstrap)" ]; then
        sudo apt install debootstrap -y
    fi
}

function downloadBase()
{
    if [ -d "$rootfs_folder" ]; then
        echo "directory \"$rootfs_folder\" exists"
        rm -rf $rootfs_folder/*
    fi
    sudo debootstrap --arch=${arch} ${distrubution} ${rootfs_folder} ${mirrors_url}
}

function cleanup() {
	set +e
	for attempt in $(seq 10); do
		mount | grep -q "${rootfs_folder}/sys" && umount ${rootfs_folder}/sys
		mount | grep -q "${rootfs_folder}/proc" && umount ${rootfs_folder}/proc
		mount | grep -q "${rootfs_folder}/dev" && umount ${rootfs_folder}/dev
        mount | grep -q "${rootfs_folder}/dev/pts" && umount .${rootfs_folder}/dev/pts
		mount | grep -q "${rootfs_folder}"
		if [ $? -ne 0 ]; then
			break
		fi
		sleep 1
	done
}
trap cleanup EXIT

function mountRootfs()
{
    mount /sys ${rootfs_folder}/sys -o bind
	mount /proc ${rootfs_folder}/proc -o bind
	mount /dev ${rootfs_folder}/dev -o bind
    mount /dev/pts ${rootfs_folder}/dev/pts -o bind
}

function umountRootfs () {
    umount ${rootfs_folder}/sys
	umount ${rootfs_folder}/proc
	umount ${rootfs_folder}/dev/pts
	umount ${rootfs_folder}/dev

    rm -rf ${rootfs_folder}/var/lib/apt/lists/*
	rm -rf ${rootfs_folder}/dev/*
	rm -rf ${rootfs_folder}/var/log/*
	rm -rf ${rootfs_folder}/var/cache/apt/archives/*.deb
	rm -rf ${rootfs_folder}/var/tmp/*
	rm -rf ${rootfs_folder}/tmp/*
}


function userCustomize(){
    mountRootfs

    # instead apt sources
	LC_ALL=C chroot ${rootfs_folder} mv /etc/apt/sources.list /etc/apt/sources.list_bak
    cp -rf "${custom_sources_list}" "${rootfs_folder}"/etc/apt/
    # apt update
    set +e
    LC_ALL=C chroot ${rootfs_folder} apt update || true
    set -e
    # update package 
    echo "apt install package list"
    package_list=$(cat "${custom_package_list}")
    	if [ ! -z "${package_list}" ]; then
        set +e
        #--no-install-recommends
        sudo LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot ${rootfs_folder} apt -y --fix-broken install
		sudo LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot ${rootfs_folder} apt-get -y install ${package_list}
        set -e
	else
		echo "ERROR: Package list is empty"
	fi
    # netplan yaml
    cp -rf "${custom_netconfig}" "${rootfs_folder}"/etc/netplan/
    # set timezone
    sudo rm -rf "${rootfs_folder}"/etc/localtime 
    LC_ALL=C chroot ${rootfs_folder} ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    # add user 
    LC_ALL=C chroot ${rootfs_folder} useradd -s '/bin/bash' -m -G adm,sudo ${user_name} || true
    LC_ALL=C chroot ${rootfs_folder} echo "${user_name}:${user_passwd}" | chpasswd
    # fstab
    sudo echo "/dev/nfs       /               nfs    defaults          1       1" > ${rootfs_folder}/etc/fstab
    # add service for startup
    sudo cp -rf $custom_file_dir/usr_config.sh ${rootfs_folder}/etc/
    sudo cp -rf $custom_file_dir/usr_config.service ${rootfs_folder}/etc/systemd/system/
    LC_ALL=C chroot ${rootfs_folder} systemctl enable usr_config.service

    umountRootfs
}

# precheck
# downloadBase
userCustomize