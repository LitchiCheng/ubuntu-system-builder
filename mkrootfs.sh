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
	pushd "${rootfs_folder}" > /dev/null 2>&1

	for attempt in $(seq 10); do
		mount | grep -q "${rootfs_folder}/sys" && umount ./sys
		mount | grep -q "${rootfs_folder}/proc" && umount ./proc
		mount | grep -q "${rootfs_folder}/dev" && umount ./dev
        mount | grep -q "${rootfs_folder}/dev/pts" && umount ./dev/pts
		mount | grep -q "${rootfs_folder}"
		if [ $? -ne 0 ]; then
			break
		fi
		sleep 1
	done
	popd > /dev/null
}
trap cleanup EXIT

function userCustomize(){
    pushd "${rootfs_folder}" > /dev/null 2>&1
	# cp "/usr/bin/qemu-aarch64-static" "usr/bin/"
	# chmod 755 "usr/bin/qemu-aarch64-static"
	mount /sys ./sys -o bind
	mount /proc ./proc -o bind
	mount /dev ./dev -o bind
    mount /dev/pts ./dev/pts -o bind
    # instead apt sources
	LC_ALL=C chroot . mv /etc/apt/sources.list /etc/apt/sources.list_bak
    cp -rf "${custom_sources_list}" "${rootfs_folder}"/etc/apt/
    # apt update
    set +e
    LC_ALL=C chroot . apt update || true
    set -e
    # update package 
    echo "apt install package list"
    package_list=$(cat "${custom_package_list}")
    	if [ ! -z "${package_list}" ]; then
        set +e
        #--no-install-recommends
        sudo LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot . apt -y --fix-broken install
		sudo LC_ALL=C DEBIAN_FRONTEND=noninteractive chroot . apt-get -y install ${package_list}
        set -e
	else
		echo "ERROR: Package list is empty"
	fi
    # netplan yaml
    cp -rf "${custom_netconfig}" "${rootfs_folder}"/etc/netplan/
    # set timezone
    sudo rm -rf "${rootfs_folder}"/etc/localtime 
    LC_ALL=C chroot . ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    # add user 
    LC_ALL=C chroot . useradd -s '/bin/bash' -m -G adm,sudo ${user_name}
    LC_ALL=C chroot . echo "${user_name}:${user_passwd}" | chpasswd
    # fstab
    sudo echo "/nfsroot/etc/fstab /dev/nfs       /               nfs    defaults          1       1" > ${rootfs_folder}/etc/fstab
    # add service for startup
    sudo cp -rf $custom_file_dir/usr_config.sh ${rootfs_folder}/etc/startup/
    sudo cp -rf $custom_file_dir/usr_config.service ${rootfs_folder}/etc/systemd/system/
    LC_ALL=C chroot . systemctl enable usr_config.service

    umount ./sys
	umount ./proc
	umount ./dev/pts
	umount ./dev
    rm -rf var/lib/apt/lists/*
	rm -rf dev/*
	rm -rf var/log/*
	rm -rf var/cache/apt/archives/*.deb
	rm -rf var/tmp/*
	rm -rf tmp/*

    popd > /dev/null
}

precheck
downloadBase
userCustomize