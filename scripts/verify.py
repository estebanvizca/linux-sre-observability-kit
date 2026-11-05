#!/usr/bin/env python3
"""Live acceptance checks. Run only against the disposable local lab."""
import json
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def query(expression):
    params = urllib.parse.urlencode({"query": expression})
    response = get(9090, "/api/v1/query?" + params)
    if response.get("status") != "success":
        raise ValueError("Prometheus query failed")
    return response["data"]["result"]

def all_samples_equal(samples, expected):
    return bool(samples) and all(float(sample["value"][1]) == expected for sample in samples)

def healthy_targets(items):
    required = {"node", "prometheus", "cadvisor", "tls"}
    jobs = {target["labels"].get("job") for target in items}
    return items if required <= jobs and all(t["health"] == "up" for t in items) else None

def get(port, path):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=10) as response:
        return json.load(response)

def ssh(command):
    return subprocess.check_output([str(ROOT / "scripts/vm.sh"), "ssh", command], text=True)

def wait_for(check, timeout=180):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                return result
        except (OSError, ValueError) as error:
            last = error
        time.sleep(5)
    raise RuntimeError(f"Timed out waiting for acceptance check: {last}")

def main():
    (ROOT / ".cache/results.json").unlink(missing_ok=True)
    started = time.monotonic()
    evidence = {}
    ssh("sudo sshd -T | grep -qx 'passwordauthentication no' && "
        "sudo sshd -T | grep -qx 'permitrootlogin no' && "
        "sudo systemctl is-active nftables fail2ban promtail prometheus-node-exporter && "
        "sudo fail2ban-client status sshd && sudo nft list chain inet sre_lab input | grep 'policy drop'")
    evidence["hardening"] = "passed: effective SSH configuration, firewall policy, active services and SSH jail"
    targets = wait_for(lambda: healthy_targets(
        get(9090, "/api/v1/targets")["data"]["activeTargets"]))
    evidence["targets"] = [t["labels"] for t in targets]
    for target in targets:
        if target["labels"]["job"] == "tls":
            instance = json.dumps(target["labels"]["instance"])
            wait_for(lambda: all_samples_equal(query(f'probe_success{{job="tls",instance={instance}}}'), 1))
    evidence["https_probe"] = "probe_success=1"
    wait_for(lambda: query('container_cpu_usage_seconds_total{job="cadvisor",name=~"sre-observability-.+"}'))
    evidence["container_metrics"] = "named lab container CPU metrics present"
    assert get(3000, "/api/health")["database"] == "ok"
    labels = wait_for(lambda: get(3100, "/loki/api/v1/label/job/values").get("data"))
    assert "systemd-journal" in labels, labels
    marker = f"sre-acceptance-{time.time_ns()}"
    ssh(f"logger -t sre-acceptance {marker}")
    log_query = urllib.parse.urlencode({"query": '{job="systemd-journal"} |= "' + marker + '"'})
    wait_for(lambda: get(3100, "/loki/api/v1/query_range?" + log_query)["data"]["result"])
    evidence["logs"] = "fresh journal marker retrieved from Loki"
    for operation in ("backup", "restore-drill"):
        begin = time.monotonic()
        subprocess.run(["make", operation], cwd=ROOT, check=True)
        evidence[operation + "_seconds"] = round(time.monotonic() - begin, 3)
    wait_for(lambda: all_samples_equal(query("sre_backup_last_exit_code"), 0)
             and all_samples_equal(query("sre_restore_success"), 1))
    evidence["recovery_metrics"] = "backup exit=0 and restore success=1 scraped"
    # Stop the exporter, wait for the real rule, always recover the service.
    wait_for(lambda: not any(a["labels"].get("alertname") == "HostDown"
                            for a in get(9093, "/api/v2/alerts")), timeout=300)
    begin = time.monotonic()
    try:
        ssh("sudo systemctl stop prometheus-node-exporter")
        wait_for(lambda: any(a["labels"].get("alertname") == "HostDown"
                            for a in get(9093, "/api/v2/alerts")))
        evidence["alert_latency_seconds"] = round(time.monotonic() - begin, 3)
    finally:
        ssh("sudo systemctl start prometheus-node-exporter")
    wait_for(lambda: not any(a["labels"].get("alertname") == "HostDown"
                            for a in get(9093, "/api/v2/alerts")), timeout=300)
    evidence["elapsed_seconds"] = round(time.monotonic() - started, 3)
    output = ROOT / ".cache/results.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps(evidence, indent=2))

if __name__ == "__main__":
    main()
