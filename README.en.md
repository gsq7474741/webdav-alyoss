# WebDAV and Aliyun OSS

[中文文档](README.md) · [MIT license](LICENSE)

Expose an Aliyun OSS bucket through Apache WebDAV and ossfs, with Basic authentication, optional HTTPS, and Docker Compose deployment.

## Requirements and quick start

Use a Linux amd64 host with Docker Engine, Compose v2 or newer, and a working `/dev/fuse`. The container requires SYS_ADMIN and a FUSE-compatible AppArmor policy. The image uses Ubuntu 24.04 and ossfs 1.91.12; real FUSE mounts on ARM emulation or Docker Desktop require separate validation.

```bash
git clone https://github.com/gsq7474741/webdav-alyoss.git
cd webdav-alyoss
cp .env.example .env
# Edit the bucket, OSS credentials, endpoint, and WebDAV password.
docker compose config --quiet
docker compose up -d --build
docker compose logs --tail=100 webdav
```

The example disables TLS and binds only to 127.0.0.1 for initial local testing. Connect to `http://localhost:9090/` using your configured WebDAV credentials.

## Configuration

- `OSS_BUCKET_NAME`: an existing OSS bucket.
- `OSS_ACCESS_KEY_ID` and `OSS_ACCESS_KEY_SECRET`: credentials for a least-privilege RAM user.
- `OSS_ENDPOINT`: the bucket's regional endpoint. HTTPS is added if no scheme is given. Use an internal endpoint only where private network access is available.
- `WEBDAV_SERVER_NAME`: the hostname or IPv4 address clients use, without scheme, port, or path; defaults to localhost.
- `WEBDAV_USERNAME` and `WEBDAV_PASSWORD`: a separate login you choose for WebDAV, unrelated to OSS credentials. Usernames start with a letter or digit and may contain letters, digits, dots, underscores, @, and hyphens. Passwords use bcrypt and are limited to 72 bytes; single-quote values in .env to preserve dollar signs and spaces.
- `SSL_ENABLED`: true or false; defaults to true unless explicitly set.
- `BIND_ADDRESS`: defaults to 127.0.0.1. Set to 0.0.0.0 for remote access and configure TLS and firewall rules.
- `HTTP_PORT` / `HTTPS_PORT`: host ports, defaulting to 9090 / 9043. HTTPS_PORT is also used for redirects.
- `OSS_MOUNT_TIMEOUT`: mount readiness timeout in seconds, 1–3600, default 30.
- `TZ`: defaults to Asia/Shanghai.

To enable TLS, place a matching full certificate chain and private key in `ssl/cert.pem` and `ssl/key.pem`, set SSL_ENABLED=true, and recreate the container:

```bash
docker compose up -d --build --force-recreate
```

Certificates are mounted read-only. HTTP redirects use status 307 and the configured HTTPS port. Configure clients to use HTTPS directly so they do not send Basic credentials over HTTP first. Never share .env, private keys, access keys, or unredacted configuration output.

## Upgrading

Back up .env, certificates, and the old ./data directory before pulling updates. Existing environment variables and default ports are retained, but remote access now requires BIND_ADDRESS=0.0.0.0.

The old local ./data mapping has been removed. Files written locally outside the old OSS symlinks are not migrated automatically; inspect and migrate them yourself. The host directory is not deleted.

The WebDAV document root is now the OSS mount itself, so hidden files and files created after startup are accessible. Either Apache or ossfs exiting stops the container, allowing Docker to restart it. Inspect logs with `docker compose logs`.

OSS is not a fully POSIX local filesystem. Renames are not atomic, random writes may re-upload objects, and multiple writers are not coordinated. WebDAV locks are local to one container and are lost when that container is recreated.

## Validation

```bash
docker build -t webdav-alyoss:maintenance .
python -m unittest discover -s tests -v
```

Tests run real Apache containers and cover authentication, HTTP/TLS, WebDAV file operations and locking, configuration errors, mount failures, health checks, restart, and shutdown. Only the OSS mount process and mount checks are substituted. Actual OSS/FUSE connectivity, permissions, persistence, and desktop client compatibility require a test bucket.

GitHub Actions runs lint, builds, and regression tests for pushes and pull requests. Dependabot checks Docker and Actions versions monthly. OSSFS packages are pinned and verified with SHA-256.

See the [Chinese guide](README.md) for troubleshooting and migration details.
