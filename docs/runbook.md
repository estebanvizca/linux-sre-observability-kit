# Incident runbooks

## HostDown

Check `./scripts/vm.sh status`, then `./scripts/vm.sh ssh sudo systemctl status prometheus-node-exporter`.
Inspect `sudo journalctl -u prometheus-node-exporter` inside the guest. Restart with
`./scripts/vm.sh ssh sudo systemctl restart prometheus-node-exporter`. Confirm the
node target is UP in Prometheus and HostDown resolves in Alertmanager.

## CPU, memory, or disk pressure

Use Grafana to identify the resource and time window. Inside the guest, inspect
`top`, `free -h`, `df -h` and `sudo journalctl --disk-usage`. Stop only the known
lab load generator. Do not remove arbitrary system files. Review log retention
before increasing the VM disk or memory. Wait for the alert's recovery condition.

## Backup failed or stale

Inspect `sudo journalctl -u sre-backup.service` and `/var/log/sre/backup.log` in the
VM. On the host, inspect `docker compose -f monitoring/docker-compose.yml logs rest-server`.
Confirm space, endpoint availability and secret file permissions. Do not initialize
a new repository to hide a connection or credential error. Run `make backup`,
then `make restore-drill`, and confirm backup age and exit code in Grafana.

## Restore failure

The drill keeps live paths intact and cleans its temporary restore tree. Read
its stderr for missing snapshot, repository corruption or checksum mismatch.
If application data changed during backup, quiesce the writer, rerun backup, and
repeat the drill. Never replace expected hashes merely to make a failing drill pass.
The repository password must be recovered from your independent secure copy if lost.

## Logs missing

Check `sudo systemctl status promtail` and `sudo journalctl -u promtail` in the VM.
Check Loki readiness at `http://127.0.0.1:3100/ready`. Verify the guest can reach
`10.0.2.2:3100` and journal group membership. Emit a marker using `logger` and
query `{job="systemd-journal"}` in Grafana Explore.

## TLS expiry or probe failure

Inspect the target's certificate chain and expiry, DNS, and outbound connectivity.
Renew the actual certificate if applicable. The default target is a public example;
replace it with an endpoint you operate before treating this alert as actionable.

## Idempotence and recovery evidence

Run `make provision` twice and inspect the second Ansible recap for `changed=0`.
Run `make verify` to generate `.cache/results.json`. Copy only reviewed, sanitized
measurements to the results document. Never publish secrets, raw VM logs or keys.

## Teardown

`make stop` stops the VM and containers without deleting persistent data.
`make destroy` also deletes the guest disk, retaining the base image, SSH key,
secrets and Docker volumes. Volume deletion and restic pruning require a separate,
explicit operator decision. Keep backups and their encryption password together
in your recovery plan, with access-controlled independent copies.
