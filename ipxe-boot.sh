#!/bin/bash 

# 设置网卡名称和其他网络信息
INTERFACE="enp4s0"
IP_ADDRESS="192.168.2.2"
GATEWAY="192.168.2.1"
DHCP_START="192.168.2.3"
DHCP_END="192.168.2.20"
DISTRIBUTION_VERSION="20.04"
DISTRIBUTION_MIN_VERSION="6"
DISTRIBUTION_TYPE="desktop" # live-server
ROOTFS_NAME="ubuntu-$DISTRIBUTION_VERSION.$DISTRIBUTION_MIN_VERSION-$DISTRIBUTION_TYPE-amd64"
IMAGE_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/$DISTRIBUTION_VERSION/$ROOTFS_NAME.iso"
ROOTFS_PATH="/home/dar/$ROOTFS_NAME.iso"
BOOT_OPTION_TIMEOUT="5000"

function configServerIp () {
# 编写 YAML 配置文件
cat <<EOF > /etc/netplan/50-$INTERFACE-init.yaml
network:
    ethernets:
        $INTERFACE:
            dhcp4: no
            addresses: [$IP_ADDRESS/24]
            gateway4: $GATEWAY
    version: 2
    renderer: NetworkManager
EOF
    # 应用配置
    sudo netplan apply
    # 验证更改
    ip addr show $INTERFACE
}

function mkPxeBoot()
{
    mkdir -pv /pxeboot/{config,firmware,os-images}
}

function compileIpxe()
{
    if [ -d "/tmp/ipxe" ]; then
        echo "clear ipxe directory"
        rm -rf /tmp/ipxe
    fi
    mkdir /tmp/ipxe    
    git clone https://github.com/ipxe/ipxe.git /tmp/ipxe
    
    sudo apt-get install zlib1g-dev liblzma-dev -y

cat <<EOF > /tmp/ipxe/src/bootconfig.ipxe
#!ipxe
dhcp
chain tftp://$IP_ADDRESS/config/boot.ipxe
EOF

cd /tmp/ipxe/src
make -j$(nproc) bin/ipxe.pxe bin/undionly.kpxe bin/undionly.kkpxe bin/undionly.kkkpxe bin-x86_64-efi/ipxe.efi EMBED=bootconfig.ipxe
sudo cp -v bin/{ipxe.pxe,undionly.kpxe,undionly.kkpxe,undionly.kkkpxe} bin-x86_64-efi/ipxe.efi /pxeboot/firmware/
}

function configDhcp()
{
    sudo apt install dnsmasq -y
cat <<EOF > /etc/dnsmasq.conf
interface=$INTERFACE

bind-interfaces

domain=linux-console.local
dhcp-range=$INTERFACE,$DHCP_START,$DHCP_END,255.255.255.0,8h

dhcp-option=option:router,$GATEWAY

dhcp-option=option:dns-server,1.1.1.1

dhcp-option=option:dns-server,8.8.8.8

enable-tftp

tftp-root=/pxeboot

# boot config for UEFI systems

dhcp-match=set:efi-x86_64,option:client-arch,7

dhcp-match=set:efi-x86_64,option:client-arch,9

dhcp-boot=tag:efi-x86_64,firmware/ipxe.efi

EOF

service tftpd-hpa stop
sudo systemctl restart dnsmasq
# sudo systemctl status dnsmasq
}

function configNfs()
{
    sudo apt install nfs-kernel-server -y
cat <<EOF > /etc/exports
/pxeboot           *(ro,sync,no_wdelay,insecure_locks,no_root_squash,insecure,no_subtree_check)
EOF
    sudo exportfs -av
}

function deployRootfs()
{
    if [ ! -f "$ROOTFS_PATH" ]; then
        echo "start download image $IMAGE_URL "
        wget $IMAGE_URL -o $ROOTFS_PATH
        echo "end download image $IMAGE_URL"
    fi

    echo $ROOTFS_PATH
    mount -o loop $ROOTFS_PATH /mnt
    mkdir -pv /pxeboot/os-images/$ROOTFS_NAME
    rsync -avz /mnt/ /pxeboot/os-images/$ROOTFS_NAME/
    umount /mnt
}

function configPxeboot()
{
cat <<EOF > /pxeboot/config/boot.ipxe
#!ipxe

set server_ip  $IP_ADDRESS

set root_path  /pxeboot

menu Select an OS to boot

item $ROOTFS_NAME        Install $ROOTFS_NAME

choose --default exit --timeout $BOOT_OPTION_TIMEOUT option && goto \${option}

:$ROOTFS_NAME

set os_root os-images/$ROOTFS_NAME

kernel tftp://${IP_ADDRESS}/os-images/$ROOTFS_NAME/casper/vmlinuz

initrd tftp://${IP_ADDRESS}/os-images/$ROOTFS_NAME/casper/initrd

imgargs vmlinuz initrd=initrd boot=casper maybe-ubiquity netboot=nfs ip=dhcp nfsroot=${IP_ADDRESS}:/pxeboot/os-images/$ROOTFS_NAME quiet splash ---

boot
EOF
}

function clean()
{
    rm -rf /etc/netplan/50-$INTERFACE-init.yaml
    rm -rf /pxeboot
    sudo systemctl disable dnsmasq
}

configServerIp
mkPxeBoot
compileIpxe
configDhcp
configNfs
deployRootfs
configPxeboot
