# Architecture and decisions

The QEMU guest uses user-mode NAT. SSH (2222), node_exporter (19100), and a
firewall-test port (18080) bind only to the operator's loopback. The guest sees
host loopback services through QEMU's gateway, 10.0.2.2. Linux host networking
lets Prometheus reach the forwarded exporter without exposing it to a bridge.

Ansible runs only against the explicit lab inventory. Four roles cover common
packages, hardening, log shipping, and backups. The VM lifecycle is separate
from configuration so the second playbook run can be inspected for idempotence.

Prometheus and Loki retain seven days. Grafana provisions data sources and a
dashboard from versioned files. Alertmanager has a local UI receiver with no
external delivery. Blackbox exporter probes the example public HTTPS target.
cAdvisor measures operator Docker containers, not services inside the VM.

restic encrypts snapshots before sending them over the QEMU-to-loopback REST
connection. Basic authentication protects the append-only server. This HTTP
connection is acceptable only inside this local lab boundary; remote deployments
need authenticated TLS. Backup and restore share a lock. Prometheus text files
are replaced atomically and remain readable by node_exporter.

The restore manifest captures expected content before a backup. Concurrent
application writes can cause the drill to fail rather than falsely claim a
consistent backup. Quiesce real applications before taking consistency-sensitive
snapshots. SHA-256 verifies selected files; restic verifies restored content.
