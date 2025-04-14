# SSL 证书说明

此目录用于存放 WebDAV 服务器的 SSL 证书文件。

## 文件要求

需要准备以下两个文件：

1. `cert.pem` - SSL 证书文件
2. `key.pem` - SSL 私钥文件

## 生成自签名证书（仅用于测试）

如果你只是在测试环境中使用，可以使用以下命令生成自签名证书：

```bash
# 生成私钥和证书
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout key.pem -out cert.pem

# 或者使用以下命令生成（指定主题信息）
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout key.pem -out cert.pem \
  -subj "/C=CN/ST=YourState/L=YourCity/O=YourOrganization/OU=YourUnit/CN=localhost"
```

## 生产环境

在生产环境中，建议使用由受信任的证书颁发机构（CA）签发的证书，如 Let's Encrypt、DigiCert 等。

## 注意事项

- 确保证书和私钥文件的权限设置正确，私钥文件应该只有所有者可读
- 证书应该包含你在 .env 文件中设置的 WEBDAV_SERVER_NAME 域名
- 如果你使用的是自签名证书，客户端可能会显示安全警告
