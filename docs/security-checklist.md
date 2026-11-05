# Security checklist

Implemented configuration (not a compliance certification):

- Key-only administrator; root SSH and password authentication disabled.
- nftables input/forward default drop; SSH and lab exporter explicitly allowed.
- fail2ban SSH jail and automatic security updates.
- Unprivileged application and log agent accounts.
- Root-only restic environment and locked backup/restore operations.
- Encrypted, authenticated append-only repository.
- Loopback listeners and ignored local secrets, VM disks and SSH keys.
- Seven-day metric/log retention and bounded guest journal.

Operational checks still require a live VM: effective sshd policy, firewall
blocking a real listener, fail2ban ban/unban behavior, second-run idempotence,
image/config compatibility, fresh log ingestion and restored checksums.

The administrator has passwordless sudo for this disposable lab. The host's
Docker group is privileged, and cAdvisor mounts host paths with elevated access.
Other local host users can reach unauthenticated metric/log APIs. SSH host keys
are not pinned. No CIS certification, internet exposure, multi-tenant isolation,
off-host disaster recovery or production security support is claimed.
