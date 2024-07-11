#!/bin/bash

function installPre()
{
	#The package dhcp3-server was renamed some time ago to isc-dhcp-server.
	sudo apt install isc-dhcp-server tftp-hpa syslinux nfs-kernel-server initramfs-tools
}

function configTFTP()
{
	echo 'RUN_DAEMON="yes"' | sudo tee -a /etc/default/tftpd-hpa
	echo 'OPTIONS="-l -s /var/lib/tftpboot"' | sudo tee -a /etc/default/tftpd-hpa
	cat /etc/default/tftpd-hpa
	# 创建启动目录
	sudo mkdir -p /var/lib/tftpboot/pxelinux.cfg
	# 复制网络引导程序
	# sudo cp /usr/lib/syslinux/pxelinux.o /var/lib/tftpboot -> apt安装无该文件
	if [ ! -f "/var/lib/tftpboot/pxelinux.0" ]; then
		echo "File \"/var/lib/tftpboot/pxelinux.0\" doesn't exists"
		wget http://archive.ubuntu.com/ubuntu/dists/focal/main/uefi/grub2-amd64/current/grubnetx64.efi.signed -O /var/lib/tftpboot/pxelinux.0
	fi
	
	# 创建默认启动配置文件
	sudo touch /var/lib/tftpboot/pxelinux.cfg/default
	cat > /var/lib/tftpboot/pxelinux.cfg/default << EOF
	LABEL Ubuntu
	KERNEL vmlinuz
	APPEND root=/dev/nfs initrd=initrd.img nfsroot=10.10.101.1:/nfsroot ip=dhcp rw	
EOF
	cat /var/lib/tftpboot/pxelinux.cfg/default
}

function configDHCP()
{
	if [ -f "/etc/dhcp3/dhcpd.conf" ]; then
		echo "File \"/etc/dhcp3/dhcpd.conf\" exists"
	else
		mkdir -p /etc/dhcp3/ 
		sudo touch /etc/dhcp3/dhcpd.conf
		cat > /etc/dhcp3/dhcpd.conf	<< EOF
		allow booting;
		allow bootp;

		subnet 10.10.101.0 netmask 255.255.255.0 {
		range 10.10.101.2 10.10.101.254;
			option broadcast-address 10.10.101.255;
		option routers 10.10.101.1;
		filename "/pxelinux.0";
		}
EOF
	fi
	cat /etc/dhcp3/dhcpd.conf
	sudo service isc-dhcp-server restart
}

function configNFS()
{
	cat /etc/exports
	# 创建nfsroot dir
	sudo mkdir /nfsroot
	# 配置nfsserver导出root
	echo "/nfsroot             *(rw,no_root_squash,async,insecure,no_subtree_check)" > /etc/exports
	cat /etc/exports
	sudo exportfs -rv
	# 向initrd中添加网络启动支持
	if [ `grep -c "BOOT=nfs" /etc/initramfs-tools/initramfs.conf` -ne '0' ]; then
		echo "BOOT add "
	else
		cat >> /etc/initramfs-tools/initramfs.conf << EOF
		BOOT=nfs
		MODULES=netboot
EOF
	fi
	cat /etc/initramfs-tools/initramfs.conf
	# 生成新的initrd.img
	sudo mkinitramfs -o /var/lib/tftpboot/initrd.img
}

function deployRoofs()
{
	if [ -f "/var/lib/tftpboot/vmlinuz" ]; then
		echo "File \"/var/lib/tftpboot/vmlinuz\" exists"
	else
		sudo cp /boot/vmlinuz-`uname -r` /var/lib/tftpboot/vmlinuz
	fi
	sudo cp -ax ./linux-rootfs /nfsroot
}

#installPre
# configTFTP
# configDHCP
# configNFS
deployRoofs