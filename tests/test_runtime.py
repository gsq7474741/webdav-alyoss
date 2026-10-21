"""用真实容器和 Apache 测试 WebDAV；仅替换需要云端凭证的 OSS 挂载进程。"""
import base64
import http.client
import json
import os
from pathlib import Path
import ssl
import subprocess
import time
import unittest
import uuid

IMAGE = os.environ.get("TEST_IMAGE", "webdav-alyoss:maintenance")
FIXTURES = Path(__file__).parent / "fixtures"
PASSWORD = r"test password $&/#\!"
BASE_ENV = {
    "OSS_BUCKET_NAME": "test-bucket",
    "OSS_ACCESS_KEY_ID": "test-access-key",
    "OSS_ACCESS_KEY_SECRET": "test-secret-do-not-log",
    "OSS_ENDPOINT": "oss-cn-hangzhou.aliyuncs.com",
    "WEBDAV_SERVER_NAME": "localhost",
    "WEBDAV_USERNAME": "tester",
    "WEBDAV_PASSWORD": PASSWORD,
    "SSL_ENABLED": "false",
    "OSS_MOUNT_TIMEOUT": "3",
    "PATH": "/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
}


def docker(*args, check=True):
    result = subprocess.run(
        ["docker", *args], capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=60,
    )
    if check and result.returncode:
        raise AssertionError(result.stderr or result.stdout)
    return result


class RuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cert_volume = "webdav-test-certs-" + uuid.uuid4().hex
        docker("volume", "create", cls.cert_volume)
        try:
            docker(
                "run", "--rm", "--mount",
                f"type=volume,source={cls.cert_volume},target=/certs",
                "--entrypoint", "/bin/bash", IMAGE, "-c",
                "openssl req -x509 -nodes -days 1 -newkey rsa:2048 "
                "-keyout /certs/key.pem -out /certs/cert.pem "
                "-subj /CN=localhost >/dev/null 2>&1 && chmod 600 /certs/key.pem",
            )
        except Exception:
            docker("volume", "rm", cls.cert_volume, check=False)
            raise

    @classmethod
    def tearDownClass(cls):
        docker("volume", "rm", cls.cert_volume)

    def setUp(self):
        self.containers = []

    def tearDown(self):
        for name in self.containers:
            docker("rm", "-f", name, check=False)

    def create(self, env=None, certificates=True):
        name = "webdav-test-" + uuid.uuid4().hex
        variables = BASE_ENV | (env or {})
        args = [
            "create", "--name", name,
            "-p", "127.0.0.1::80", "-p", "127.0.0.1::443",
        ]
        for key, value in variables.items():
            args.extend(["-e", f"{key}={value}"])
        if certificates:
            args += [
                "--mount",
                f"type=volume,source={self.cert_volume},target=/etc/webdav/ssl,readonly",
            ]
        args += [
            "--entrypoint", "/bin/bash", IMAGE, "-c",
            "chmod +x /test-bin/*; exec /start.sh",
        ]
        docker(*args)
        self.containers.append(name)
        docker("cp", str(FIXTURES), f"{name}:/test-bin")
        docker("start", name)
        return name

    def state(self, name):
        return json.loads(docker("inspect", "--format", "{{json .State}}", name).stdout)

    def wait_exit(self, name):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            state = self.state(name)
            if not state["Running"]:
                return state["ExitCode"]
            time.sleep(0.1)
        self.fail("容器未按预期退出：" + docker("logs", name).stdout)

    def port(self, name, tls=False):
        ports = json.loads(
            docker("inspect", "--format", "{{json .NetworkSettings.Ports}}", name).stdout
        )
        return int(ports["443/tcp" if tls else "80/tcp"][0]["HostPort"])

    def request(self, name, method="GET", path="/", body=None, headers=None,
                auth=True, tls=False):
        request_headers = dict(headers or {})
        if auth:
            token = base64.b64encode(f"tester:{PASSWORD}".encode()).decode()
            request_headers["Authorization"] = "Basic " + token
        port = self.port(name, tls)
        if tls:
            connection = http.client.HTTPSConnection(
                "127.0.0.1", port, timeout=3, context=ssl._create_unverified_context(),
            )
        else:
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
        try:
            connection.request(method, path, body=body, headers=request_headers)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def ready(self, name, tls=False):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                if self.request(name, auth=False, tls=tls)[0] == 401:
                    return
            except (OSError, http.client.HTTPException, KeyError):
                pass
            if not self.state(name)["Running"]:
                break
            time.sleep(0.1)
        self.fail("服务未就绪：" + docker("logs", name).stdout + docker("logs", name).stderr)

    def test_http_authentication_and_file_operations(self):
        name = self.create(certificates=False)
        self.ready(name)
        self.assertEqual(self.request(name, auth=False)[0], 401)
        self.assertEqual(
            self.request(name, auth=False, headers={"Authorization": "Basic bad"})[0], 401,
        )
        self.assertEqual(self.request(name)[0], 200)
        self.assertEqual(self.request(name, path="/.hidden")[2], b"hidden file\n")
        self.assertEqual(self.request(name, "OPTIONS")[0], 200)
        self.assertEqual(self.request(name, "PROPFIND", headers={"Depth": "1"})[0], 207)
        self.assertEqual(self.request(name, "MKCOL", "/files")[0], 201)
        self.assertEqual(self.request(name, "PUT", "/files/test.txt", b"payload")[0], 201)
        self.assertEqual(self.request(name, path="/files/test.txt")[2], b"payload")
        self.assertEqual(
            docker("exec", name, "cat", "/mnt/ossfs/files/test.txt").stdout, "payload",
        )
        root = f"http://127.0.0.1:{self.port(name)}"
        self.assertEqual(
            self.request(name, "COPY", "/files/test.txt",
                         headers={"Destination": root + "/files/copy.txt"})[0], 201,
        )
        self.assertEqual(
            self.request(name, "MOVE", "/files/copy.txt",
                         headers={"Destination": root + "/files/moved.txt"})[0], 201,
        )
        self.assertEqual(self.request(name, path="/files/moved.txt")[2], b"payload")
        self.assertEqual(self.request(name, "DELETE", "/files/moved.txt")[0], 204)
        self.assertEqual(self.request(name, path="/files/moved.txt")[0], 404)
        docker("exec", name, "sh", "-c", "printf later > /mnt/ossfs/later.txt")
        self.assertEqual(self.request(name, path="/later.txt")[2], b"later")
        docker("exec", name, "/healthcheck.sh")
        self.assertEqual(
            docker("exec", name, "stat", "-c", "%a", "/etc/passwd-ossfs").stdout.strip(),
            "600",
        )
        self.assertNotEqual(docker(
            "exec", name, "curl", "--noproxy", "*", "-k", "-s", "--max-time", "1",
            "https://127.0.0.1/", check=False,
        ).returncode, 0)
        arguments = docker("exec", name, "cat", "/tmp/mock-ossfs-arguments").stdout
        self.assertIn("url=https://oss-cn-hangzhou.aliyuncs.com", arguments)
        logs = docker("logs", name)
        self.assertNotIn(BASE_ENV["OSS_ACCESS_KEY_SECRET"], logs.stdout + logs.stderr)
        self.assertNotIn(PASSWORD, logs.stdout + logs.stderr)

    def test_webdav_locks(self):
        name = self.create()
        self.ready(name)
        self.request(name, "PUT", "/locked.txt", b"locked")
        body = (
            '<?xml version="1.0"?><d:lockinfo xmlns:d="DAV:">'
            '<d:lockscope><d:exclusive/></d:lockscope>'
            '<d:locktype><d:write/></d:locktype></d:lockinfo>'
        )
        status, headers, _ = self.request(
            name, "LOCK", "/locked.txt", body,
            {"Content-Type": "application/xml", "Timeout": "Second-60"},
        )
        self.assertEqual(status, 200)
        token = headers["Lock-Token"]
        self.assertEqual(self.request(name, "PUT", "/locked.txt", b"conflict")[0], 423)
        self.assertEqual(
            self.request(name, "UNLOCK", "/locked.txt", headers={"Lock-Token": token})[0],
            204,
        )

    def test_tls_readonly_certificates_and_redirect(self):
        name = self.create({"SSL_ENABLED": "true", "WEBDAV_HTTPS_PORT": "9443"})
        self.ready(name, tls=True)
        status, headers, _ = self.request(
            name, "PUT", "/file%20name.txt?test=1", b"data", auth=False,
        )
        self.assertEqual(status, 307)
        self.assertEqual(
            headers["Location"], "https://localhost:9443/file%20name.txt?test=1",
        )
        self.assertEqual(self.request(name, "PUT", "/secure.txt", b"secure", tls=True)[0], 201)
        self.assertEqual(self.request(name, path="/secure.txt", tls=True)[2], b"secure")
        self.assertEqual(
            docker("exec", name, "stat", "-c", "%a", "/etc/webdav/ssl/key.pem").stdout.strip(),
            "600",
        )
        docker("exec", name, "/healthcheck.sh")

    def test_restart_rebuilds_configuration(self):
        name = self.create({
            "http_proxy": "http://127.0.0.1:9",
            "https_proxy": "http://127.0.0.1:9",
            "no_proxy": "", "NO_PROXY": "",
        })
        self.ready(name)
        docker("restart", "--time", "10", name)
        self.ready(name)
        docker("exec", name, "/healthcheck.sh")
        rendered = docker("exec", name, "cat",
                          "/etc/apache2/sites-available/webdav.conf").stdout
        self.assertEqual(rendered.count("ServerName localhost"), 1)
        self.assertNotIn("${WEBDAV_SERVER_NAME}", rendered)

    def test_invalid_configuration_fails_before_mount(self):
        cases = [
            {"OSS_ACCESS_KEY_SECRET": ""},
            {"WEBDAV_SERVER_NAME": "https://example.com:9043"},
            {"WEBDAV_SERVER_NAME": "host\nInjected on"},
            {"WEBDAV_USERNAME": "-bad"},
            {"WEBDAV_PASSWORD": "bad\npassword"},
            {"WEBDAV_PASSWORD": "a" * 73},
            {"SSL_ENABLED": "yes"},
            {"OSS_ENDPOINT": "example.com,allow_other"},
            {"OSS_MOUNT_TIMEOUT": "0"},
            {"WEBDAV_HTTPS_PORT": "65536"},
        ]
        for env in cases:
            with self.subTest(env=list(env)):
                name = self.create(env)
                self.assertEqual(self.wait_exit(name), 1)
                logs = docker("logs", name)
                self.assertNotIn("正在挂载", logs.stdout + logs.stderr)

    def test_missing_tls_certificate_fails(self):
        name = self.create({"SSL_ENABLED": "true"}, certificates=False)
        self.assertEqual(self.wait_exit(name), 1)

    def test_mount_failure_and_timeout_exit(self):
        for mode in ("fail", "timeout"):
            with self.subTest(mode=mode):
                name = self.create({"MOCK_OSSFS_MODE": mode, "OSS_MOUNT_TIMEOUT": "1"})
                self.assertEqual(self.wait_exit(name), 1)

    def test_ossfs_crash_stops_container(self):
        name = self.create()
        self.ready(name)
        docker("exec", name, "touch", "/tmp/crash-ossfs")
        self.assertEqual(self.wait_exit(name), 1)

    def test_apache_crash_stops_container(self):
        name = self.create()
        self.ready(name)
        docker("exec", name, "sh", "-c", 'kill -TERM "$(cat /var/run/apache2/apache2.pid)"')
        self.assertEqual(self.wait_exit(name), 1)
        self.assertIn("mock OSSFS stopped", docker("logs", name).stdout)

    def test_stop_unmounts_and_exits_cleanly(self):
        name = self.create()
        self.ready(name)
        docker("stop", "--time", "10", name)
        self.assertEqual(self.state(name)["ExitCode"], 0)
        logs = docker("logs", name).stdout
        self.assertIn("mock OSSFS unmounted", logs)
        self.assertIn("mock OSSFS stopped", logs)

    def test_healthcheck_requires_mount(self):
        name = self.create()
        self.ready(name)
        docker("exec", name, "rm", "/tmp/fake-mounted")
        self.assertNotEqual(docker("exec", name, "/healthcheck.sh", check=False).returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
