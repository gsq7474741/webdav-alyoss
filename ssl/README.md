# TLS 证书说明

启用 `SSL_ENABLED=true` 时，在本目录准备：

- `cert.pem`：包含完整证书链的 PEM 文件。
- `key.pem`：与证书匹配、无口令的 PEM 私钥。

证书必须包含客户端实际访问的域名。Compose 将整个目录以只读方式挂载到 `/etc/webdav/ssl`；启动脚本不会修改证书或私钥权限。请在主机上妥善设置私钥权限。这些文件已被 Git 和 Docker 构建上下文排除。

## 本机测试证书

在本目录执行以下命令，生成仅用于 localhost 的一天期自签名证书：

```bash
openssl req -x509 -nodes -days 1 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
chmod 600 key.pem
```

自签名证书需要客户端显式信任。远程部署请使用受信任 CA 签发且域名匹配的证书。

## 更新证书

替换主机上的两个文件后，执行 `docker compose restart webdav`，使 Apache 重新读取证书。先检查证书有效期、完整链以及私钥是否匹配。
