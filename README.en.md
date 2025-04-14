# WebDAV-Aliyun OSS Integration

[![中文](https://img.shields.io/badge/点我-中文README-red.svg)](README.md)

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

This project provides a simple yet powerful solution to integrate Aliyun Object Storage Service (OSS) with the WebDAV protocol, allowing you to access and manage files in Aliyun OSS through WebDAV clients.

## Features

- 🔄 Mount Aliyun OSS bucket as a local filesystem
- 🌐 Access OSS files via WebDAV protocol
- 🔒 Basic authentication protection
- 🔐 SSL encryption support for secure HTTPS access
- 🐳 Fully containerized for quick deployment with Docker
- 🔧 Simple configuration via environment variables

## Quick Start

### Prerequisites

- [Docker](https://www.docker.com/get-started) and [Docker Compose](https://docs.docker.com/compose/install/)
- Aliyun OSS account and access credentials
- (Optional) SSL certificate and private key files if you need SSL

### Installation Steps

1. Clone this repository:

```bash
git clone https://github.com/yourusername/webdav-alyoss.git
cd webdav-alyoss
```

1. Copy the environment variables example file and modify it according to your configuration:

```bash
cp .env.example .env
# Edit the .env file with your OSS and WebDAV configuration
```

1. (Optional) If you need SSL, place your SSL certificate and private key files in the `ssl` directory:

```bash
# Create ssl directory if it doesn't exist
mkdir -p ssl

# Copy your certificate and key files to the ssl directory
# and rename them to cert.pem and key.pem
cp /path/to/your/certificate.crt ssl/cert.pem
cp /path/to/your/private.key ssl/key.pem
```

1. Start the service:

```bash
docker-compose up -d
```

> ⚠️ **Note:** If you change any configuration files (such as .env, webdav.conf, docker-compose.yml, etc.), always run:
>
> ```bash
> docker-compose down
> docker-compose up -d --build
> ```
>
> This ensures your configuration changes take effect.

1. Access the WebDAV service:

- HTTP mode: `http://localhost:9090` (will automatically redirect to HTTPS if SSL is enabled)
- HTTPS mode: `https://localhost:9043` (if SSL is enabled)

Connect using any WebDAV client with the username and password configured in the `.env` file.

## Configuration

Configure the following environment variables in the `.env` file:

| Variable Name | Description | Example |
|---------------|-------------|---------|
| OSS_BUCKET_NAME | Aliyun OSS bucket name | my-bucket |
| OSS_ACCESS_KEY_ID | Aliyun access key ID | LTAI5tXXXXXXXXXXXXXX |
| OSS_ACCESS_KEY_SECRET | Aliyun access key secret | XXXXXXXXXXXXXXXXXXXXXXXX |
| OSS_ENDPOINT | OSS endpoint address | oss-cn-beijing-internal.aliyuncs.com |
| WEBDAV_USERNAME | WebDAV username | admin |
| WEBDAV_PASSWORD | WebDAV password | strong-password |
| TZ | Timezone setting | Asia/Shanghai |

## Client Connection

You can connect to the service using the following WebDAV clients:

- **Windows**: Windows Explorer (Network Drive)
- **macOS**: Finder (Connect to Server)
- **Linux**: davfs2
- **Mobile Devices**: Various WebDAV client apps

Connection URLs:
- HTTP: `http://your-server-ip:9090`
- HTTPS: `https://your-server-ip:9043` (if SSL is enabled)

## Project Structure

```plaintext
webdav-alyoss/
├── Dockerfile          # Docker image build file
├── docker-compose.yml  # Docker Compose configuration
├── start.sh            # Container startup script
├── supervisord.conf    # Supervisor configuration
├── webdav.conf         # Apache WebDAV configuration
├── .env                # Environment variables configuration
├── .env.example        # Environment variables example file
├── ssl/                # SSL certificates directory
│   ├── cert.pem        # SSL certificate file
│   ├── key.pem         # SSL private key file
│   └── README.md       # SSL certificates guide
├── README.md           # Chinese documentation
└── README.en.md        # English documentation
```

## Security Considerations

- Do not use default passwords in production environments
- Strongly recommended to enable SSL and use HTTPS for secure WebDAV connections
- Use trusted SSL certificates from a Certificate Authority in production, not self-signed certificates
- Regularly update your Aliyun access keys
- Limit OSS access permissions to the minimum necessary scope

## Troubleshooting

If you encounter issues, check the following logs:

```bash
# View container logs
docker-compose logs

# View OSSFS logs
docker exec webdav-oss cat /var/log/ossfs.log

# View WebDAV logs
docker exec webdav-oss cat /var/log/apache2/webdav-error.log
```

## Contributing

Issues and pull requests are welcome!

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [ossfs](https://github.com/aliyun/ossfs) - For mounting OSS as a filesystem
- [Apache HTTP Server](https://httpd.apache.org/) - For providing WebDAV service
