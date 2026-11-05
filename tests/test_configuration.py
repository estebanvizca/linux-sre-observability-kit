"""Offline contracts for monitoring, provisioning and recovery configuration."""
import json
import subprocess
import unittest
from pathlib import Path

import yaml
from jinja2 import Environment, StrictUndefined

ROOT = Path(__file__).resolve().parents[1]

class ConfigurationTests(unittest.TestCase):
    def test_yaml_documents_parse(self):
        paths = list((ROOT / "ansible").rglob("*.yml")) + list((ROOT / "monitoring").rglob("*.yml"))
        for path in paths:
            with self.subTest(path=path):
                self.assertIsNotNone(yaml.safe_load(path.read_text()))

    def test_every_role_template_exists_and_renders(self):
        variables = yaml.safe_load((ROOT / "ansible/group_vars/all.yml").read_text())
        variables.update(restic_password="test-password", restic_rest_password="test-password")
        env = Environment(undefined=StrictUndefined)
        for role in (ROOT / "ansible/roles").iterdir():
            for task in yaml.safe_load((role / "tasks/main.yml").read_text()):
                if "ansible.builtin.template" not in task:
                    continue
                path = role / "templates" / task["ansible.builtin.template"]["src"]
                with self.subTest(path=path):
                    rendered = env.from_string(path.read_text()).render(**variables)
                    self.assertTrue(rendered)
                    if path.name.endswith(".sh.j2"):
                        subprocess.run(["bash", "-n"], input=rendered, text=True, check=True)

    def test_loopback_bindings(self):
        compose = yaml.safe_load((ROOT / "monitoring/docker-compose.yml").read_text())
        for name, service in compose["services"].items():
            with self.subTest(service=name):
                self.assertEqual(service["network_mode"], "host")
                self.assertNotIn(":latest", service["image"])
                if name != "loki":
                    self.assertIn("127.0.0.1", json.dumps(service))
        loki = yaml.safe_load((ROOT / "monitoring/loki/config.yml").read_text())
        self.assertEqual(loki["server"]["http_listen_address"], "127.0.0.1")

    def test_dashboard_datasources_resolve(self):
        sources = yaml.safe_load((ROOT / "monitoring/grafana/provisioning/datasources/default.yml").read_text())
        known = {source["uid"] for source in sources["datasources"]}
        dashboard = json.loads((ROOT / "monitoring/grafana/dashboards/sre-lab.json").read_text())
        for panel in dashboard["panels"]:
            self.assertIn(panel["datasource"]["uid"], known)

    def test_recovery_manifest_is_backed_up(self):
        variables = yaml.safe_load((ROOT / "ansible/group_vars/all.yml").read_text())
        for item in variables["restore_manifest"]:
            self.assertTrue(any(item.startswith(prefix + "/") for prefix in variables["backup_paths"]))
            self.assertNotIn(item, variables["backup_excludes"])

    def test_alerts_cover_failures(self):
        groups = yaml.safe_load((ROOT / "monitoring/prometheus/alerts.yml").read_text())["groups"]
        names = {rule["alert"] for group in groups for rule in group["rules"]}
        self.assertTrue({"HostDown", "HighCPU", "LowMemory", "DiskAlmostFull", "BackupStale",
                         "BackupFailed", "BackupMetricsMissing", "RestoreFailed", "TLSCertificateExpiring"} <= names)

if __name__ == "__main__":
    unittest.main()
