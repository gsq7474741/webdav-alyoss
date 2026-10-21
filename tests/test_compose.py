"""检查真实 Compose 解析，避免密码插值和默认绑定地址回归。"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ComposeTests(unittest.TestCase):
    def test_example_and_literal_password(self):
        with tempfile.TemporaryDirectory() as folder:
            env = Path(folder) / "test.env"
            content = (ROOT / ".env.example").read_text(encoding="utf-8")
            env.write_text(content + "\nWEBDAV_PASSWORD='literal $ # password'\n", encoding="utf-8")
            result = subprocess.run(
                ["docker", "compose", "--env-file", str(env), "config", "--format", "json"],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=30,
            )
            environment = subprocess.run(
                ["docker", "compose", "--env-file", str(env), "config", "--environment"],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=30,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        service = json.loads(result.stdout)["services"]["webdav"]
        # config JSON 会把 $ 转义成 $$；这里检查原始插值环境的字面值。
        self.assertEqual(environment.returncode, 0, environment.stderr)
        self.assertIn("WEBDAV_PASSWORD=literal $ # password", environment.stdout.splitlines())
        self.assertEqual(service["environment"]["SSL_ENABLED"], "false")
        self.assertTrue(all(port["host_ip"] == "127.0.0.1" for port in service["ports"]))
        self.assertTrue(service["volumes"][0]["read_only"])

    def test_missing_required_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            env = Path(folder) / "test.env"
            content = (ROOT / ".env.example").read_text(encoding="utf-8")
            env.write_text(content.replace("OSS_BUCKET_NAME=your-bucket-name", "OSS_BUCKET_NAME="), encoding="utf-8")
            result = subprocess.run(
                ["docker", "compose", "--env-file", str(env), "config", "--quiet"],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", timeout=30,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("OSS_BUCKET_NAME", result.stderr)
