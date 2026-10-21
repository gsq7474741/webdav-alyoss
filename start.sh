#!/bin/bash
set -Eeuo pipefail
umask 077

log() { printf '[webdav-oss] %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

# 只报告配置项名称，避免在错误日志中暴露凭证。
for name in OSS_BUCKET_NAME OSS_ACCESS_KEY_ID OSS_ACCESS_KEY_SECRET OSS_ENDPOINT WEBDAV_USERNAME WEBDAV_PASSWORD; do
    [[ -n "${!name:-}" ]] || die "缺少必填配置：${name}"
    [[ "${!name}" != *$'\n'* && "${!name}" != *$'\r'* ]] || die "配置不能包含换行：${name}"
done
[[ "$OSS_BUCKET_NAME" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] || die 'OSS_BUCKET_NAME 格式无效'
[[ "$OSS_ACCESS_KEY_ID" != *:* && "$OSS_ACCESS_KEY_SECRET" != *:* ]] || die 'OSS 凭证不能包含冒号'
[[ "$WEBDAV_USERNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.@-]*$ ]] || die 'WEBDAV_USERNAME 只能包含字母、数字、点、下划线、@ 和连字符'
(( $(printf '%s' "$WEBDAV_PASSWORD" | wc -c) <= 72 )) || die 'WEBDAV_PASSWORD 不能超过 bcrypt 的 72 字节限制'

export WEBDAV_SERVER_NAME="${WEBDAV_SERVER_NAME:-localhost}"
export WEBDAV_HTTPS_PORT="${WEBDAV_HTTPS_PORT:-9043}"
export SSL_ENABLED="${SSL_ENABLED:-true}"
OSS_MOUNT_TIMEOUT="${OSS_MOUNT_TIMEOUT:-30}"
[[ "$WEBDAV_SERVER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || die 'WEBDAV_SERVER_NAME 应填写域名或 IPv4 地址，不含协议、端口和路径'
[[ "$WEBDAV_HTTPS_PORT" =~ ^[0-9]{1,5}$ ]] || die 'WEBDAV_HTTPS_PORT 必须是有效端口'
(( 10#$WEBDAV_HTTPS_PORT >= 1 && 10#$WEBDAV_HTTPS_PORT <= 65535 )) || die 'WEBDAV_HTTPS_PORT 超出范围'
[[ "$OSS_MOUNT_TIMEOUT" =~ ^[1-9][0-9]{0,3}$ ]] || die 'OSS_MOUNT_TIMEOUT 必须是 1 到 3600 的整数'
(( OSS_MOUNT_TIMEOUT <= 3600 )) || die 'OSS_MOUNT_TIMEOUT 不能超过 3600 秒'
[[ "$SSL_ENABLED" == true || "$SSL_ENABLED" == false ]] || die 'SSL_ENABLED 只能填写 true 或 false'

if [[ "$OSS_ENDPOINT" != *://* ]]; then
    OSS_ENDPOINT="https://${OSS_ENDPOINT}"
fi
[[ "$OSS_ENDPOINT" =~ ^https?://[a-zA-Z0-9][a-zA-Z0-9.-]*(:[0-9]{1,5})?/?$ ]] || die 'OSS_ENDPOINT 应填写 OSS 端点域名，可带 http:// 或 https://'

apache_args=(-D FOREGROUND)
if [[ "$SSL_ENABLED" == true ]]; then
    [[ -s /etc/webdav/ssl/cert.pem && -s /etc/webdav/ssl/key.pem ]] || die '启用 SSL 时，必须在 ssl/ 目录提供 cert.pem 和 key.pem'
    apache_args+=(-D WEBDAV_TLS)
fi

install -d -m 755 /mnt/ossfs
install -d -o www-data -g www-data -m 700 /var/lib/dav
# 不修改只读挂载的证书，不对 OSS 文件递归执行 chown/chmod。
printf '%s:%s\n' "$OSS_ACCESS_KEY_ID" "$OSS_ACCESS_KEY_SECRET" > /etc/passwd-ossfs
chmod 600 /etc/passwd-ossfs
printf '%s\n' "$WEBDAV_PASSWORD" | htpasswd -ciB /etc/apache2/webdav.passwd "$WEBDAV_USERNAME"
chown root:www-data /etc/apache2/webdav.passwd
chmod 640 /etc/apache2/webdav.passwd
# envsubst 接收变量名列表，需保留字面量而不是在此处展开。
# shellcheck disable=SC2016
envsubst '${WEBDAV_SERVER_NAME} ${WEBDAV_HTTPS_PORT}' < /etc/webdav/webdav.conf.template > /etc/apache2/sites-available/webdav.conf

# envvars 是 Apache 软件包提供的文件，部分变量允许未定义。
set +u
# shellcheck source=/dev/null
source /etc/apache2/envvars
set -u
install -d -m 755 "$APACHE_RUN_DIR" "$APACHE_LOG_DIR"
install -d -o www-data -g www-data -m 755 "$APACHE_LOCK_DIR"
apache2 "${apache_args[@]}" -t

OSSFS_PID=''
APACHE_PID=''
# cleanup 由 EXIT trap 间接调用。
# shellcheck disable=SC2317
cleanup() {
    local status=$?
    trap - EXIT TERM INT
    if [[ -n "$APACHE_PID" ]]; then
        kill -TERM "$APACHE_PID" 2>/dev/null || true
        wait "$APACHE_PID" 2>/dev/null || true
    fi
    if [[ -n "$OSSFS_PID" ]]; then
        if mountpoint -q /mnt/ossfs; then
            fusermount -u /mnt/ossfs || true
        fi
        kill -TERM "$OSSFS_PID" 2>/dev/null || true
        wait "$OSSFS_PID" 2>/dev/null || true
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 0' TERM INT

log '正在挂载 OSS，等待挂载就绪'
ossfs "$OSS_BUCKET_NAME" /mnt/ossfs -f \
    -o "url=${OSS_ENDPOINT}" -o allow_other -o uid=33 -o gid=33 -o umask=0007 &
OSSFS_PID=$!
deadline=$((SECONDS + OSS_MOUNT_TIMEOUT))
until mountpoint -q /mnt/ossfs; do
    kill -0 "$OSSFS_PID" 2>/dev/null || die 'OSSFS 已退出，请检查端点、凭证、桶权限和 FUSE 配置'
    (( SECONDS < deadline )) || die 'OSS 挂载超时，请检查网络和端点配置'
    sleep 0.2
done

log 'OSS 挂载就绪，启动 WebDAV'
apache2 "${apache_args[@]}" &
APACHE_PID=$!
# 任一关键进程退出时停止整个容器，交给 Docker 重启，避免继续对本地目录写入。
if wait -n "$OSSFS_PID" "$APACHE_PID"; then
    log '关键进程意外退出'
else
    log '关键进程运行失败'
fi
exit 1
