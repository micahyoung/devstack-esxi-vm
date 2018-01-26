# devstack-esxi-vm

Provision a VM for devstack on ESXi

## Requirements

* `state/env.sh` 

```bash

ESX_USERNAME=root
ESX_PASSWORD=<password>
ESX_HOST=<esx host ip>
ESX_THUMBPRINT=<esx thumbprint>
ESX_DATASTORE=<datastore name>
ESX_NETWORK=<probably "VM Network">
VM_NAME=<desired name for your new VM>
VM_PASSWORD=<desired password for ssh user>
VM_AUTHORIZED_KEY=<your SSH pubkey>
VM_IP=<desired VM IP ex: 10.10.0.4>
VM_NETMASK=<desired VM netmask ex: 255.255.255.0>
VM_GATEWAY=<desired VM gateway ex: 10.10.0.1>
VM_DNS_SERVERS=<desired VM DNS server ex: 8.8.8.8>
CPUS=2
MEMORY_MB=7168
DISK_SIZE=300G
```
