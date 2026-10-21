# WebDAV 与阿里云 OSS 集成

[English](README.en.md) · [MIT 许可证](LICENSE)

通过 Apache WebDAV 访问由 ossfs 挂载的阿里云 OSS 桶，支持基础认证、HTTP/HTTPS 和 Docker Compose 部署。容器启动时会校验配置并等待挂载就绪；Apache 或 ossfs 退出时，容器会停止并由 Docker 重启。

## 环境要求

- Linux 主机、Docker Engine 和 Docker Compose v2 或更新版本。
- 主机提供 `/dev/fuse`。容器需要 `SYS_ADMIN` 能力及允许 FUSE 挂载的 AppArmor 配置。
- 当前镜像使用 Ubuntu 24.04 和 ossfs 1.91.12，上游 Ubuntu 预编译包仅提供 amd64。Compose 指定 `linux/amd64`；ARM 主机的模拟运行及 Docker Desktop 下的真实 FUSE 挂载需要自行验证。
- 一个已创建的 OSS 桶，以及仅能访问所需桶或路径的 RAM 用户凭证。

## 本机快速开始

```bash
git clone https://github.com/gsq7474741/webdav-alyoss.git
cd webdav-alyoss
cp .env.example .env
```

编辑 `.env`，替换 OSS 桶、访问凭证、端点和 WebDAV 密码。示例默认 `SSL_ENABLED=false`，仅绑定本机 `127.0.0.1`，首次测试无需证书。

```bash
docker compose config --quiet
docker compose up -d --build
docker compose ps
docker compose logs --tail=100 webdav
```

在 WebDAV 客户端中填写 `http://localhost:9090/`，输入 `WEBDAV_USERNAME` 和 `WEBDAV_PASSWORD`。认证失败返回 401，目录查询 PROPFIND 正常返回 207。

`docker compose config` 不加 `--quiet` 会输出解析后的凭证，不要把完整输出贴到 Issue。

## 域名、用户名和密码如何填写

| 配置项 | 含义 | 本机测试示例 | 远程访问示例 |
| --- | --- | --- | --- |
| WEBDAV_SERVER_NAME | 客户端实际访问的域名或 IPv4，不含协议、端口、路径 | localhost | dav.example.com |
| WEBDAV_USERNAME | 自己设置的 WebDAV 登录名，与阿里云账号无关 | webdav | myuser |
| WEBDAV_PASSWORD | 自己设置的 WebDAV 登录密码，与 OSS 密钥无关 | 自设强密码 | 自设强密码 |
| BIND_ADDRESS | Docker 发布端口时绑定的主机地址 | 127.0.0.1 | 0.0.0.0 |

用户名支持字母、数字、点、下划线、@ 和连字符，首字符为字母或数字。密码支持空格和 `$`、`#` 等符号，在 `.env` 中用单引号包裹可保留字面值。认证使用 bcrypt，密码最多 72 字节。

远程连接时还需开放主机防火墙或云服务器安全组中的 HTTPS 端口，并使域名解析到服务器。服务端的 `localhost` 仅表示服务器自身；其他设备应使用服务器的域名或 IP。

## 启用 HTTPS

1. 将证书完整链保存为 `ssl/cert.pem`，私钥保存为 `ssl/key.pem`，证书需匹配访问域名。目录会以只读方式挂载，启动脚本不会修改证书权限。
2. 修改 `.env`：

```dotenv
SSL_ENABLED=true
WEBDAV_SERVER_NAME=dav.example.com
BIND_ADDRESS=0.0.0.0
HTTPS_PORT=9043
```

3. 重新创建容器：

```bash
docker compose up -d --build --force-recreate
```

客户端连接 `https://dav.example.com:9043/`。启用 HTTPS 时，HTTP 会以 307 重定向到配置的 HTTPS 端口，保留请求方法。客户端仍应直接填写 HTTPS 地址，避免先通过 HTTP 发送基础认证信息。自签名测试证书的生成方法见 [证书说明](ssl/README.md)。

## 其他配置

| 配置项 | 说明 |
| --- | --- |
| OSS_BUCKET_NAME | 已存在的 OSS 桶名 |
| OSS_ACCESS_KEY_ID / OSS_ACCESS_KEY_SECRET | RAM 用户访问密钥，不能填写 WebDAV 用户名和密码 |
| OSS_ENDPOINT | 桶所属地域的端点，如 oss-cn-hangzhou.aliyuncs.com；省略协议时使用 HTTPS |
| HTTP_PORT / HTTPS_PORT | 主机发布端口，默认 9090 / 9043；HTTPS_PORT 也用于 HTTP 重定向 |
| SSL_ENABLED | 仅接受 true 或 false；缺省为 true，示例文件显式设为 false |
| OSS_MOUNT_TIMEOUT | 等待 OSS 挂载的秒数，默认 30，可设 1–3600 |
| TZ | 容器时区，默认 Asia/Shanghai |

只有同地域 ECS 等具备对应内网访问条件的主机才使用 `-internal` 端点。家用电脑或其他云主机一般使用公网端点。

WebDAV 直接访问 `/mnt/ossfs` 挂载点，上传、新建目录和删除操作均作用于 OSS。OSS 不提供与本地文件系统完全相同的语义：重命名并非原子操作，随机写可能重传整个对象，不适合数据库文件或多实例并发写同一文件。WebDAV 锁保存在当前容器的本地锁数据库中，重建容器会丢失锁，也无法协调其他实例。

## 从旧版本升级

备份 `.env`、证书和旧版本的 `./data` 目录，再拉取更新并执行：

```bash
git pull --ff-only
docker compose up -d --build --force-recreate
```

- 原有 OSS 和 WebDAV 环境变量继续可用。默认端口仍为 9090 和 9043。
- 新版本默认只绑定 `127.0.0.1`；已有远程客户端需要在 `.env` 添加 `BIND_ADDRESS=0.0.0.0`。
- `SSL_ENABLED=false` 时不再加载 HTTPS 监听和证书配置；为 true 时必须提供证书。
- 旧的 `./data:/var/www/webdav/data` 本地目录映射已移除。旧版在该目录或软链接之外产生的本地文件不会自动迁移到 OSS；请先检查并自行备份、迁移，升级不会删除主机上的 `./data`。
- 新版本通过 PID 1 启动脚本管理 Apache 和 ossfs，日志统一通过 `docker compose logs` 查看。
- 更新基础镜像和系统包可执行 `docker compose build --pull --no-cache`，然后重新创建容器。

## 故障排查

```bash
docker compose ps
docker compose logs --tail=100 webdav
docker compose exec webdav /healthcheck.sh
```

- **缺少配置**：根据错误提示在 `.env` 填写对应项，修改后重新创建容器。
- **挂载失败或超时**：检查桶地域、端点、RAM 权限、网络及主机 `/dev/fuse`。网络较慢时可增大 `OSS_MOUNT_TIMEOUT`。
- **证书错误**：确认两个文件非空、证书与私钥匹配、域名正确、证书未过期。
- **无法从其他设备访问**：检查 `BIND_ADDRESS`、客户端域名、端口、防火墙和安全组。
- **401**：检查 WebDAV 用户名和密码；它们与阿里云凭证是两组独立配置。
- **构建时下载失败**：优先检查 Docker、Ubuntu 软件源和 GitHub 连接。需要镜像加速时使用自己信任的镜像服务。

提交 Issue 时提供脱敏配置、Docker/Compose 版本和相关错误行。不要上传 `.env`、访问密钥、私钥或含用户文件信息的完整日志。

## 开发与验证

```bash
docker build -t webdav-alyoss:maintenance .
python -m unittest discover -s tests -v
```

测试启动真实 Docker 容器和 Apache，覆盖认证、HTTP/HTTPS、重定向、WebDAV 文件操作和锁、配置校验、挂载失败、健康检查及进程清理。测试仅用本地替身替换 ossfs 挂载及挂载状态检查，不需要 OSS 密钥；真实 FUSE 挂载、云端权限、同步与客户端兼容性仍需在测试桶上验证。测试容器只发布到本机随机端口，结束后清理容器和测试证书卷。

GitHub Actions 在推送和 PR 时执行脚本检查、镜像构建及上述回归测试；Dependabot 每月检查基础镜像和 Actions 版本。ossfs 安装包固定版本并校验 SHA-256，升级时需同时核对版本和摘要。

## 致谢与许可证

本仓库代码采用 [MIT 许可证](LICENSE)。使用的 [ossfs](https://github.com/aliyun/ossfs) 与 [Apache HTTP Server](https://httpd.apache.org/) 分别遵循其上游许可证。
