FROM ubuntu:26.04

ARG OSSFS_VERSION=1.91.12
ARG OSSFS_SHA256=7bb78689901217b77a3e012611e9e65619c77f153b50914119a17a714a748911
ENV TZ=Asia/Shanghai

# 上游 Ubuntu 安装包仅提供 amd64；不在其他架构上安装错误的二进制文件。
RUN test "$(dpkg --print-architecture)" = amd64 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        apache2 apache2-utils ca-certificates curl fuse gettext-base openssl tzdata util-linux \
    && curl -fL --retry 3 \
        "https://github.com/aliyun/ossfs/releases/download/v${OSSFS_VERSION}/ossfs_${OSSFS_VERSION}_ubuntu24.04_amd64.deb" \
        -o /tmp/ossfs.deb \
    && echo "${OSSFS_SHA256}  /tmp/ossfs.deb" | sha256sum -c - \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends /tmp/ossfs.deb \
    && rm -f /tmp/ossfs.deb \
    && rm -rf /var/lib/apt/lists/* \
    && a2enmod dav dav_fs headers ssl rewrite \
    && a2dissite 000-default.conf \
    && mkdir -p /etc/webdav/ssl /mnt/ossfs /var/lib/dav

COPY webdav.conf /etc/webdav/webdav.conf.template
COPY webdav-ports.conf /etc/apache2/ports.conf
COPY start.sh healthcheck.sh /
RUN chmod 755 /start.sh /healthcheck.sh \
    && ln -s /etc/apache2/sites-available/webdav.conf /etc/apache2/sites-enabled/webdav.conf

EXPOSE 80 443
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 CMD ["/healthcheck.sh"]
ENTRYPOINT ["/start.sh"]
