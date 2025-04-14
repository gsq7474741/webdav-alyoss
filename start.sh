#!/bin/bash

# 设置日志输出函数
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# 创建OSS凭证文件
log_info "创建OSS凭证文件"
echo "${OSS_ACCESS_KEY_ID}:${OSS_ACCESS_KEY_SECRET}" > /etc/passwd-ossfs
chmod 600 /etc/passwd-ossfs

# 创建WebDAV用户
log_info "创建WebDAV用户: ${WEBDAV_USERNAME}"
htpasswd -bc /etc/apache2/webdav.passwd ${WEBDAV_USERNAME} ${WEBDAV_PASSWORD}

# 挂载OSS
log_info "正在挂载OSS桶: ${OSS_BUCKET_NAME} 到 /mnt/ossfs"

ossfs ${OSS_BUCKET_NAME} /mnt/ossfs -ourl=${OSS_ENDPOINT} -o allow_other -o uid=33 -o gid=33 -d -f -o dbglevel=info > /var/log/ossfs.log 2>&1 &
OSSFS_PID=$!
log_info "OSSFS进程启动，PID: ${OSSFS_PID}"

# 等待OSSFS挂载完成
sleep 5

# 检查OSSFS是否成功挂载
if mount | grep -q "/mnt/ossfs"; then
    log_info "OSSFS挂载成功"
    # 显示挂载信息
    log_info "OSSFS挂载信息:"
    mount | grep ossfs
    
    # 显示OSS目录内容
    log_info "OSS目录内容:"
    ls -la /mnt/ossfs
    
    # 确保WebDAV目录存在并链接到OSS挂载点
    log_info "创建WebDAV目录并链接到OSS"
    mkdir -p /var/www/webdav
    ln -sf /mnt/ossfs/* /var/www/webdav/ 2>/dev/null || true
    chown -R www-data:www-data /var/www/webdav
    
    # 显示WebDAV目录内容
    log_info "WebDAV目录内容:"
    ls -la /var/www/webdav
else
    log_error "OSSFS挂载失败"
    # 显示OSSFS日志
    log_error "OSSFS日志:"
    tail -n 50 /var/log/ossfs.log
    exit 1
fi

# 处理WebDAV配置文件中的环境变量
log_info "替换WebDAV配置文件中的环境变量"
sed -i "s/\${WEBDAV_SERVER_NAME}/${WEBDAV_SERVER_NAME}/g" /etc/apache2/sites-available/webdav.conf
sed -i "s/\${APACHE_LOG_DIR}/\/var\/log\/apache2/g" /etc/apache2/sites-available/webdav.conf

# 检查SSL证书和私钥是否存在
if [ "${SSL_ENABLED}" = "true" ]; then
    log_info "SSL已启用，检查SSL证书和私钥"
    if [ ! -f /etc/ssl/certs/webdav-cert.pem ] || [ ! -f /etc/ssl/private/webdav-key.pem ]; then
        log_error "SSL证书或私钥文件不存在，请将证书文件挂载到容器中"
        log_error "  - 证书文件应位于: /etc/ssl/certs/webdav-cert.pem"
        log_error "  - 私钥文件应位于: /etc/ssl/private/webdav-key.pem"
        log_error "如果你不需要SSL，请在.env文件中设置SSL_ENABLED=false"
        exit 1
    fi
    
    # 设置SSL证书和私钥的权限
    chmod 644 /etc/ssl/certs/webdav-cert.pem
    chmod 600 /etc/ssl/private/webdav-key.pem
    
    log_info "SSL配置正确，启用SSL模块"
    a2enmod ssl
else
    log_info "SSL未启用，使用HTTP模式"
    # 如果SSL未启用，则禁用HTTP到HTTPS的重定向
    sed -i '/RewriteEngine On/,/RewriteRule/d' /etc/apache2/sites-available/webdav.conf
fi

# 设置全局ServerName以避免警告
log_info "配置Apache ServerName"
echo "ServerName ${WEBDAV_SERVER_NAME}" >> /etc/apache2/apache2.conf

# 确保认证模块被正确启用
log_info "启用Apache认证模块"
for mod in authn_core authn_file authz_core authz_user auth_basic auth_digest dav dav_fs; do
    a2enmod $mod
done

# 创建WebDAV目录并设置权限
log_info "创建WebDAV目录并设置权限"
mkdir -p /var/www/webdav
chown -R www-data:www-data /var/www/webdav
chmod -R 755 /var/www/webdav

# 确保密码文件权限正确
log_info "设置密码文件权限"
chown www-data:www-data /etc/apache2/webdav.passwd
chmod 640 /etc/apache2/webdav.passwd

# 开启日志输出
log_info "配置Apache日志级别"
echo "LogLevel info" >> /etc/apache2/apache2.conf

# 启动Apache
log_info "启动Apache WebDAV服务"
apache2ctl -D FOREGROUND &
APACHE_PID=$!
log_info "Apache进程启动，PID: ${APACHE_PID}"

# 持续显示日志
log_info "开始监控日志"
log_info "===== OSSFS日志 =====" 
tail -f /var/log/ossfs.log &

# log_info "===== Apache错误日志 =====" 
# tail -f /var/log/apache2/error.log &

log_info "===== WebDAV错误日志 =====" 
tail -f /var/log/apache2/webdav-error.log &

log_info "===== WebDAV访问日志 =====" 
tail -f /var/log/apache2/webdav-access.log &

# 等待所有进程
wait
