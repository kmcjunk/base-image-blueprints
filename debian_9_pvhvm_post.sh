#!/bin/bash

# fix bootable flag
parted -s /dev/xvda set 1 boot on

# Debian puts these in the wrong order from what we need
# should be ConfigDrive, None but preseed populates with
# None, Configdrive which breaks user-data scripts
cat > /etc/cloud/cloud.cfg.d/90_dpkg.cfg <<'EOF'
# to update this file, run dpkg-reconfigure cloud-init
datasource_list: [ ConfigDrive, None ]
EOF

# Add to install python3-nova-agent
cat > /etc/apt/sources.list.d/ospc.list <<'EOF'
deb http://mirror.rackspace.com/ospc/debian/ all main
EOF

curl -s http://mirror.rackspace.com/ospc/public.gpg.key | sudo apt-key add -

apt-get update
apt-get install -y python3-nova-agent xe-guest-utilities

# our cloud-init config
cat > /etc/cloud/cloud.cfg.d/10_rackspace.cfg <<'EOF'
datasource_list: [ ConfigDrive, None ]
manage-resolv-conf: False
disable_root: False
ssh_pwauth: True
ssh_deletekeys: False
resize_rootfs: noblock
preserve_hostname: true
manage_etc_hosts: localhost
apt_preserve_sources_list: True
ssh_genkeytypes: ['rsa', 'dsa', 'ecdsa', 'ed25519']
network:
  config: disabled
growpart:
  mode: auto
  devices: ['/']
system_info:
  distro: debian
EOF

# cloud-init kludges
echo -n > /etc/udev/rules.d/70-persistent-net.rules
echo -n > /lib/udev/rules.d/75-persistent-net-generator.rules

# minimal network conf that does dhcp causes boot delay if left out
cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback
EOF

cat > /etc/hosts <<'EOF'
127.0.0.1	localhost

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# set some stuff
echo 'net.ipv4.conf.eth0.arp_notify = 1' >> /etc/sysctl.conf
echo 'vm.swappiness = 0' >> /etc/sysctl.conf

cat >> /etc/sysctl.conf <<'EOF'
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
EOF

cat > /etc/fstab <<'EOF'
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/xvda1	/               ext4    errors=remount-ro,noatime,barrier=0 0       1
EOF

# keep grub2 from using UUIDs and regenerate config
sed -i 's/#GRUB_DISABLE_LINUX_UUID.*/GRUB_DISABLE_LINUX_UUID="true"/g' /etc/default/grub
update-grub

# remove cd-rom from sources.list
sed -i '/.*cdrom.*/d' /etc/apt/sources.list

# Update to nova-agent service file
cat > /lib/systemd/system/python3-nova-agent.service <<'EOF'
[Unit]
DefaultDependencies=no
Description=Nova Agent for xenstore
Before=cloud-init.service

[Service]
Type=notify
TimeoutStartSec=360
ExecStart=/usr/bin/nova-agent --no-fork True -o /var/log/nova-agent.log -l info

[Install]
WantedBy=multi-user.target
EOF

mkdir /etc/systemd/system/network-online.target.d
cat > /etc/systemd/system/network-online.target.d/python3-nova-agent.conf <<'EOF'
[Unit]
After=python3-nova-agent.service
EOF

# Ensure the agent is started at boot
systemctl enable python3-nova-agent
systemctl enable xe-linux-distribution
systemctl daemon-reload

# ssh permit rootlogin
sed -i '/^PermitRootLogin/s/prohibit-password/yes/g' /etc/ssh/sshd_config

# do this here so we have our mirror set
cat > /etc/apt/sources.list <<'EOF'
deb http://mirror.rackspace.com/debian stretch main
deb-src http://mirror.rackspace.com/debian stretch main

deb http://mirror.rackspace.com/debian-security/ stretch/updates main
deb-src http://mirror.rackspace.com/debian-security/ stretch/updates main
EOF

# update all the things
apt-get update && apt-get -y dist-upgrade

# clean up
passwd -d root
apt-get -y clean
apt-get -y autoremove
rm -f /etc/ssh/ssh_host_*
rm -f /var/cache/apt/archives/*.deb
rm -f /var/cache/apt/*cache.bin
rm -f /var/lib/apt/lists/*_Packages
rm -f /etc/hostname
rm -f /root/.bash_history
rm -f /root/.nano_history
rm -f /root/.lesshst
rm -f /root/.ssh/known_hosts
find /var/log -type f -exec truncate -s 0 {} \;
find /tmp -type f -delete
