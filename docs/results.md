# Validation results

Validation date: 2026-11-05. Continued from commit `ca3cbcc`.

## Environment and permissions

- Docker Engine 29.9.2, overlayfs image store; Docker socket accessible through the docker group.
- QEMU 11.1.2; `/dev/kvm` readable and writable. QEMU monitor reported
  `kvm support: enabled`; Ubuntu guest reported `systemd-detect-virt: kvm`.
- Ubuntu 24.04 cloud-init completed; guest kernel `6.8.0-147-generic`.
- GitHub CLI available at `~/.local/bin/gh`, authenticated as `estebanvizca`.
- The existing cached VM was used. This run does not prove a fresh image download
  or provisioning on every supported host.

## Checks that passed

- `make check test`: shell syntax, Compose configuration, Ansible syntax and 10 unit tests.
- Containerized `promtool check config`, `promtool test rules` and `amtool check-config`.
- `make provision`: first completed run `ok=54 changed=40 failed=0 unreachable=0`.
- A subsequent sequential `make provision`: `ok=42 changed=0 failed=0 unreachable=0`.
- `make verify`: all four scrape jobs healthy, successful external HTTPS probe,
  named lab container CPU metrics, a new journal marker retrieved from Loki,
  backup and isolated restore with restic verification and seven SHA-256 matches,
  recovery metrics scraped, HostDown delivered to Alertmanager and then resolved.
- node_exporter was checked active after the drill.
- Grafana API: healthy database and provisioned Linux SRE Lab dashboard with seven panels.
- Live firewall: a temporary systemd HTTP server on guest port 8080 responded to a
  guest-local request; HTTP through host port 18080 timed out. The server was stopped
  in cleanup. SSH and exporter forwarding remained usable.

Measured wall times from the successful acceptance run (includes command overhead):

| Operation | Seconds |
| --- | ---: |
| Backup | 2.431 |
| Restore drill | 1.299 |
| Exporter stop to HostDown observed in Alertmanager | 75.484 |
| Full acceptance, including alert resolution | 101.863 |

The reviewed [machine-readable report](evidence/live-2026-11-05.json) is copied from
`.cache/results.json`. Raw logs, credentials and VM artifacts remain ignored locally.
These are small lab workload measurements, not production performance guarantees.

## Failures found and corrected

- cAdvisor 0.49.1 served its endpoint but failed container registration with Docker's
  overlayfs image store (`mount-id` missing). Pinned `ghcr.io/google/cadvisor:0.60.6`
  produced CPU metrics for all seven lab containers. Upstream added containerd
  snapshotter support in [0.54.0](https://github.com/google/cadvisor/releases/tag/v0.54.0).
- Loki listened on loopback gRPC but advertised a LAN address, returning HTTP 500 to
  Promtail. Setting `common.instance_addr: 127.0.0.1` restored ingestion and queries.
- Acceptance previously checked scrape health without checking HTTPS probe success
  or actual container metrics. It now rejects missing scrape jobs, failed/absent
  probes, absent named container metrics and unsuccessful recovery metrics.
- `example.com` DNS queries timed out on this host, including an explicit public
  resolver query. `https://github.com` resolved and returned HTTP 200 with
  `probe_success=1`; it is now the documented example target. No DNS bypass or TLS
  verification disablement was used. The original target was not verified successfully.
- Publishing now checks the authenticated account, main branch, origin fetch/push
  destinations and accidentally tracked local-state paths before pushing.

## Publication and limits

Publication and GitHub Actions are checked separately after the reviewed commit is
pushed; the Actions run is the authoritative remote CI result.

Tracked files and all 55 blobs in the initial history were checked for private-key
headers, common GitHub/AWS token patterns and exact local secret values: no matches.
Local secrets, SSH private keys and generated results are ignored. This is a scoped
secret check, not a guarantee that every possible secret format can be detected.

Not exercised: automatic fail2ban attack/ban/unban, CPU/memory/disk pressure alerts,
fresh VM creation, visual browser rendering/screenshots, host-loss recovery or
production load. The SSH jail was checked active; that alone is not a ban test.
CI validates configuration and rules, not nested KVM integration.
