# Validation results

Validation date: 2026-11-05.

## Available evidence

- Docker Compose configuration resolves successfully.
- Ansible site playbook passes syntax validation with the installed local environment.
- Offline tests cover template completeness/rendering, shell syntax, YAML parsing,
  loopback binding, dashboard data sources, manifest coverage and alert coverage.

## Unavailable evidence

The execution environment has no `/dev/kvm`, denies access to the Docker daemon,
and cannot resolve `api.github.com`. The cached VM is stopped. Therefore no live
provisioning, second-run idempotence, resource-pressure alerts, real firewall or
fail2ban behavior, Grafana rendering, log delivery, backup duration, restore duration,
or alert latency is claimed. GitHub publication and CI execution are unconfirmed.

Run `make vm provision verify` on a Linux host with the documented prerequisites.
The verification script emits measured seconds and writes `.cache/results.json`
only after all its checks succeed. Review that file before publishing measurements.
The CI workflow additionally runs Prometheus rule tests and Alertmanager validation
when Docker images and GitHub Actions are available.
