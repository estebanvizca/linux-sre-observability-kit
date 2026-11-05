#cloud-config
# Cloud-init for the disposable SRE lab VM.
# The public key is injected by scripts/vm.sh; no secret is stored here.
hostname: sre-lab
fqdn: sre-lab.local
manage_etc_hosts: true
timezone: UTC

users:
  - name: sre
    gecos: SRE Lab Administrator
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    lock_passwd: true
    ssh_authorized_keys:
      - __SSH_PUBKEY__

ssh_pwauth: false
disable_root: true
package_update: false
package_upgrade: false

runcmd:
  - [systemctl, enable, --now, ssh]
  - [timedatectl, set-ntp, true]
