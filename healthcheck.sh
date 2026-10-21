#!/bin/bash
set -euo pipefail
mountpoint -q /mnt/ossfs
url=http://127.0.0.1/
if [[ "${SSL_ENABLED:-true}" == true ]]; then
    url=https://127.0.0.1/
fi
# 本地探测自签名证书；401 同时验证服务存活且认证仍然生效。
status=$(curl --noproxy '*' -k -sS --max-time 3 -o /dev/null -w '%{http_code}' "$url")
[[ "$status" == 401 ]]
