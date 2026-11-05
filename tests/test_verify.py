"""Regression checks for acceptance failures that a healthy scrape can hide."""
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verify", Path(__file__).resolve().parents[1] / "scripts/verify.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class AcceptanceTests(unittest.TestCase):
    def test_missing_scrape_job_is_not_success(self):
        targets = [{"labels": {"job": "node"}, "health": "up"}]
        self.assertIsNone(verify.healthy_targets(targets))
        targets.extend({"labels": {"job": job}, "health": "up"}
                       for job in ("tls", "prometheus", "cadvisor"))
        self.assertEqual(verify.healthy_targets(targets), targets)
        targets[0]["health"] = "down"
        self.assertIsNone(verify.healthy_targets(targets))

    def test_missing_or_failed_probe_is_not_success(self):
        for samples in ([], [{"value": [0, "0"]}],
                        [{"value": [0, "1"]}, {"value": [0, "0"]}]):
            with self.subTest(samples=samples):
                self.assertFalse(verify.all_samples_equal(samples, 1))
        self.assertTrue(verify.all_samples_equal([{"value": [0, "1"]}], 1))

    def test_query_rejects_api_error(self):
        with patch.object(verify, "get", return_value={"status": "error"}):
            with self.assertRaises(ValueError):
                verify.query("probe_success")

    def test_exporter_is_restarted_when_alert_check_fails(self):
        # Exercise the real main() cleanup path without waiting or changing a VM.
        targets = [{"labels": {"job": job, "instance": "localhost"}, "health": "up"}
                   for job in ("node", "tls", "prometheus", "cadvisor")]
        def get(port, path):
            if "targets" in path:
                return {"data": {"activeTargets": targets}}
            if port == 3000:
                return {"database": "ok"}
            if port == 3100:
                return {"data": ["systemd-journal"]} if "label" in path else {"data": {"result": [1]}}
            if port == 9093:
                if any("stop prometheus-node-exporter" in call.args[0] for call in ssh.call_args_list):
                    raise RuntimeError("alert check failed")
                return []
        with patch.object(verify.Path, "unlink"), patch.object(verify, "ssh") as ssh, \
             patch.object(verify, "get", side_effect=get), \
             patch.object(verify, "query", side_effect=lambda expr: [{"value": [0, "0" if expr == "sre_backup_last_exit_code" else "1"]}]), \
             patch.object(verify.subprocess, "run"), \
             patch.object(verify, "wait_for", side_effect=lambda check, **kwargs: check()):
            with self.assertRaisesRegex(RuntimeError, "alert check failed"):
                verify.main()
            self.assertEqual(ssh.call_args.args, ("sudo systemctl start prometheus-node-exporter",))
