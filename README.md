# WebDAV-阿里云OSS 集成

[![English](https://img.shields.io/badge/ClickMe-English_README-blue.svg)](README.en.md)

![版本](https://img.shields.io/badge/版本-1.0.0-blue.svg)
![许可证](https://img.shields.io/badge/许可证-MIT-green.svg)

这个项目提供了一个简单而强大的解决方案，将阿里云对象存储服务(OSS)与WebDAV协议集成，让你可以通过WebDAV客户端访问和管理阿里云OSS中的文件。

## 功能特点

- 🔄 将阿里云OSS桶挂载为本地文件系统
- 🌐 通过WebDAV协议提供对OSS文件的访问
- 🔒 基本身份验证保护
- 🔐 支持SSL加密，提供安全的HTTPS访问
- 🐳 完全容器化，使用Docker快速部署
- 🔧 简单的环境变量配置

## 快速开始

### 前提条件

- [Docker](https://www.docker.com/get-started) 和 [Docker Compose](https://docs.docker.com/compose/install/)
- 阿里云OSS账号和访问凭证
- （可选）如果需要SSL，准备SSL证书和私钥文件

### 国内镜像源配置

如果在构建过程中遇到无法拉取 Docker 镜像的问题，可以配置国内 Docker 镜像源。

在 Linux 系统上，编辑 `/etc/docker/daemon.json` 文件（如果不存在则创建）：

```json
{
  "registry-mirrors": [
    "https://docker-0.unsee.tech",
    "https://docker-cf.registry.cyou",
    "https://docker.1panel.live",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://registry.docker-cn.com",
    "https://docker.hpcloud.cloud",
    "https://docker.m.daocloud.io",
    "https://docker.unsee.tech",
    "http://mirrors.ustc.edu.cn",
    "https://docker.chenby.cn",
    "http://mirror.azure.cn",
    "https://dockerpull.org",
    "https://dockerhub.icu",
    "https://hub.rat.dev",
    "https://proxy.1panel.live",
    "https://docker.1panel.top",
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run",
    "https://docker.ketches.cn"
  ]
}
```

在 Windows 系统上，可以通过 Docker Desktop 的设置面板添加镜像源：

1. 右键点击系统托盘中的 Docker 图标
2. 选择 "Settings"
3. 在左侧菜单中选择 "Docker Engine"
4. 在右侧的 JSON 配置中添加上述的 "registry-mirrors" 配置
5. 点击 "Apply & Restart" 保存并重启 Docker

配置完成后，可以使用以下命令验证镜像源是否生效：

```bash
docker info
```

在输出中应该能看到已配置的镜像源。

### 安装步骤

1. 克隆此仓库：

```bash
git clone https://github.com/yourusername/webdav-alyoss.git
cd webdav-alyoss
```

2. 复制环境变量示例文件并根据你的配置进行修改：

```bash
cp .env.example .env
# 编辑.env文件，填入你的OSS和WebDAV配置
```

3. （可选）如果需要SSL，将SSL证书和私钥文件放入`ssl`目录：

```bash
# 创建ssl目录（如果不存在）
mkdir -p ssl

# 将你的证书和私钥文件复制到ssl目录
# 并重命名为cert.pem和key.pem
cp /path/to/your/certificate.crt ssl/cert.pem
cp /path/to/your/private.key ssl/key.pem
```

4. 启动服务：

```bash
docker-compose up -d
```

> ⚠️ **注意：如果你修改了配置文件（如 .env、webdav.conf、docker-compose.yml 等），请务必先执行：**
>
> ```bash
> docker-compose down
> docker-compose up -d --build
> ```
>
> 这样才能确保配置变更生效。

5. 访问WebDAV服务：

- HTTP模式：`http://localhost:9090`（如果启用了SSL，会自动重定向到HTTPS）
- HTTPS模式：`https://localhost:9043`（如果启用了SSL）

使用在`.env`文件中配置的用户名和密码进行认证。

## 配置说明

在`.env`文件中配置以下环境变量：

| 变量名 | 描述 | 示例 |
|--------|------|------|
| OSS_BUCKET_NAME | 阿里云OSS桶名称 | my-bucket |
| OSS_ACCESS_KEY_ID | 阿里云访问密钥ID | LTAI5tXXXXXXXXXXXXXX |
| OSS_ACCESS_KEY_SECRET | 阿里云访问密钥Secret | XXXXXXXXXXXXXXXXXXXXXXXX |
| OSS_ENDPOINT | OSS端点地址 | oss-cn-beijing-internal.aliyuncs.com |
| WEBDAV_SERVER_NAME | WebDAV服务器域名 | your.webdav.domain.com |
| WEBDAV_USERNAME | WebDAV用户名 | admin |
| WEBDAV_PASSWORD | WebDAV密码 | strong-password |
| SSL_ENABLED | 是否启用SSL | true 或 false |
| TZ | 时区设置 | Asia/Shanghai |

## 客户端连接

你可以使用以下WebDAV客户端连接到服务：

- **Windows**: Windows资源管理器 (网络驱动器)
- **macOS**: Finder (连接到服务器)
- **Linux**: davfs2
- **移动设备**: 各种WebDAV客户端应用

连接URL: 
- HTTP: `http://your-server-ip:9090`
- HTTPS: `https://your-server-ip:9043` (如果启用了SSL)

## 项目结构

```plaintext
webdav-alyoss/
├── Dockerfile          # Docker镜像构建文件
├── docker-compose.yml  # Docker Compose配置
├── start.sh            # 容器启动脚本
├── supervisord.conf    # Supervisor配置
├── webdav.conf         # Apache WebDAV配置
├── .env                # 环境变量配置
├── .env.example        # 环境变量示例文件
├── ssl/                # SSL证书目录
│   ├── cert.pem        # SSL证书文件
│   ├── key.pem         # SSL私钥文件
│   └── README.md       # SSL证书说明
├── README.md           # 中文项目说明文档
└── README.en.md        # 英文项目说明文档
```

## 安全注意事项

- 请勿在生产环境中使用默认密码
- 强烈建议启用SSL，使用HTTPS保护WebDAV连接
- 在生产环境中使用受信任的SSL证书，而非自签名证书
- 定期更新阿里云访问密钥
- 限制OSS访问权限至必要的最小范围

## 故障排除

如果遇到问题，请检查以下日志：

```bash
# 查看容器日志
docker-compose logs

# 查看OSSFS日志
docker exec webdav-oss cat /var/log/ossfs.log

# 查看WebDAV日志
docker exec webdav-oss cat /var/log/apache2/webdav-error.log
```

## 贡献

欢迎提交问题和拉取请求！

## 许可证

本项目采用MIT许可证 - 详情请参阅 [LICENSE](LICENSE) 文件。

## 致谢

- [ossfs](https://github.com/aliyun/ossfs) - 用于将OSS挂载为文件系统
- [Apache HTTP Server](https://httpd.apache.org/) - 提供WebDAV服务
