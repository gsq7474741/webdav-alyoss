FROM ubuntu:22.04

# 设置非交互式安装
ENV DEBIAN_FRONTEND=noninteractive

# 安装必要的软件包
RUN apt-get update && apt-get install -y \
    apache2 \
    apache2-utils \
    davfs2 \
    fuse \
    curl \
    libcurl3-gnutls \
    mime-support \
    libssl-dev \
    gdebi-core \
    wget \
    gnupg \
    lsb-release \
    ca-certificates \
    supervisor \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 下载并安装OSSFS
RUN wget "https://gosspublic.alicdn.com/ossfs/ossfs_1.91.5_ubuntu22.04_amd64.deb?spm=a2c4g.11186623.0.0.1a66251bwihHDx&file=ossfs_1.91.5_ubuntu22.04_amd64.deb" -O ossfs_1.91.5_ubuntu22.04_amd64.deb \
    && gdebi -n ossfs_1.91.5_ubuntu22.04_amd64.deb \
    && rm -f ossfs_1.91.5_ubuntu22.04_amd64.deb

# 启用Apache WebDAV模块和 SSL模块
RUN a2enmod dav dav_fs headers ssl rewrite

# 创建挂载点和数据目录
RUN mkdir -p /mnt/ossfs /var/www/webdav

# 配置Apache WebDAV
COPY webdav.conf /etc/apache2/sites-available/webdav.conf
RUN a2dissite 000-default.conf && a2ensite webdav.conf



# 复制启动脚本和配置文件
COPY start.sh /start.sh
# ENTRYPOINT ["/start.sh"]
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 设置权限
RUN chmod +x /start.sh && \
    chown -R www-data:www-data /var/www/webdav

# 暴露WebDAV端口
EXPOSE 80 443

# 使用supervisor启动服务
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
