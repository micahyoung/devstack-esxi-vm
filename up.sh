#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

source state/env.sh
: ${ESX_USERNAME:?"!"}
: ${ESX_PASSWORD:?"!"}
: ${ESX_HOST:?"!"}
: ${ESX_THUMBPRINT:?"!"}
: ${ESX_DATASTORE:?"!"}
: ${ESX_NETWORK:?"!"}
: ${VM_NAME:?"!"}
: ${VM_PASSWORD:?"!"}
: ${VM_AUTHORIZED_KEY:?"!"}
: ${VM_IP:?"!"}
: ${VM_NETMASK:?"!"}
: ${CPUS:?"!"}
: ${MEMORY_MB:?"!"}
: ${DISK_SIZE:?"!"}

mkdir -p bin
if ! [ -f bin/govc ]; then
  curl -L https://github.com/vmware/govmomi/releases/download/v0.15.0/govc_linux_amd64.gz > bin/govc.gz
  gzip -d bin/govc.gz
  chmod +x bin/govc
fi


if ! [ -f bin/image.ova ]; then
  curl -L https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64.ova > bin/image.ova
fi

export GOVC_INSECURE=1
export GOVC_URL=$ESX_HOST
export GOVC_USERNAME=$ESX_USERNAME
export GOVC_PASSWORD=$ESX_PASSWORD
export GOVC_DATASTORE=$ESX_DATASTORE
export GOVC_NETWORK=$ESX_NETWORK
export GOVC_VM=$VM_NAME
#export GOVC_RESOURCE_POOL='*/Resources'

cat > bin/meta-data <<EOF
local-hostname: localhost
network-interfaces: |
  auto lo
  iface lo inet loopback

  auto ens224
  iface ens224 inet dhcp

  auto ens192
  iface ens192 inet static
    address $VM_IP
    netmask $VM_NETMASK
EOF

cat > bin/user-data <<EOF
#cloud-config
password: $VM_PASSWORD
chpasswd: { expire: False }
ssh_pwauth: True
ssh_authorized_keys:
  - $VM_AUTHORIZED_KEY
package_upgrade: true
packages: ['docker-ce']
apt:
  preserve_sources_list: true
  sources:
    docker-ce.list:
      source: "deb [arch=amd64] https://download.docker.com/linux/ubuntu \$RELEASE stable"
      keyid: 0EBFCD88
write_files:
- path: /etc/dpkg/dpkg.cfg.d/excludes
  content: |
    path-exclude=/lib/systemd/system/docker.service
- path: /etc/docker/daemon.json
  content: |
    {
      "hosts": ["tcp://127.0.0.1:2375","unix:///var/run/docker.sock"]
    }
- path: /lib/systemd/system/docker.service
  content: |
    [Unit]
    Description=Docker Application Container Engine
    Documentation=https://docs.docker.com
    After=network-online.target docker.socket firewalld.service
    Wants=network-online.target
    Requires=docker.socket
    
    [Service]
    Type=notify
    # the default is not to use systemd for cgroups because the delegate issues still
    # exists and systemd currently does not support the cgroup feature set required
    # for containers run by docker
    ExecStart=/usr/bin/dockerd --config-file=/etc/docker/daemon.json
    ExecReload=/bin/kill -s HUP \$MAINPID
    LimitNOFILE=1048576
    # Having non-zero Limit*s causes performance problems due to accounting overhead
    # in the kernel. We recommend using cgroups to do container-local accounting.
    LimitNPROC=infinity
    LimitCORE=infinity
    # Uncomment TasksMax if your systemd version supports it.
    # Only systemd 226 and above support this version.
    TasksMax=infinity
    TimeoutStartSec=0
    # set delegate yes so that systemd does not reset the cgroups of docker containers
    Delegate=yes
    # kill only the docker process, not all processes in the cgroup
    KillMode=process
    # restart the docker process if it exits prematurely
    Restart=on-failure
    StartLimitBurst=3
    StartLimitInterval=60s
    
    [Install]
    WantedBy=multi-user.target
EOF

xorrisofs -volid cidata -joliet -rock bin/user-data bin/meta-data > bin/cloud-init.iso
qemu-img convert -O vmdk bin/cloud-init.iso bin/cloud-init.vmdk

bin/govc import.ova \
  -name $VM_NAME \
  -options <(
      bin/govc import.spec bin/image.ova \
        | jq 'del(.Deployment)' \
        | jq 'del(.NetworkMapping)' \
    ) \
  bin/image.ova \
;
bin/govc import.vmdk -force=true bin/cloud-init.vmdk /$VM_NAME/
bin/govc vm.change -vm $VM_NAME -c $CPUS -m $MEMORY_MB -nested-hv-enabled=true -sync-time-with-host=true

bin/govc vm.disk.attach -disk /$VM_NAME/cloud-init.vmdk -link=false
bin/govc vm.disk.change -vm $VM_NAME -disk.key 2000 -size $DISK_SIZE
bin/govc device.remove floppy-8000 

bin/govc vm.network.add -vm $VM_NAME -net "VM Network" -net.adapter vmxnet3

bin/govc snapshot.create -vm $VM_NAME initial-snapshot
