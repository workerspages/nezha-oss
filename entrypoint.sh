#!/bin/bash
set -e

# ==========================================
# 目录与变量初始化
# ==========================================
DATA_DIR="/dashboard/data"
CONFIG_DIR="/root/.config/rclone"
CONFIG_FILE="${CONFIG_DIR}/rclone.conf"

mkdir -p "${CONFIG_DIR}"
mkdir -p "${DATA_DIR}"

# 读取默认值
SYNC_INTERVAL=${SYNC_INTERVAL:-5}
S3_REGION=${S3_REGION:-us-east-1}
S3_PATH=${S3_PATH:-nezha}
WEBDAV_VENDOR=${WEBDAV_VENDOR:-other}
WEBDAV_PATH=${WEBDAV_PATH:-nezha}

# 如果没有设置存储类型，则默认退化为本地模式
STORAGE_TYPE=${STORAGE_TYPE:-local}

echo "[Init] 检查存储配置..."

# ==========================================
# 本地模式拦截
# ==========================================
if [ "${STORAGE_TYPE}" = "local" ]; then
    echo "[Init] 存储类型设为 local 或未设置，跳过云端同步配置，仅使用本地数据运行。"
    echo "[App] 启动 nezha 面板主程序..."
    # 使用 exec 直接替换当前 bash 进程，不再执行后续任何云端同步代码
    exec /dashboard/app
fi

echo "[Init] 正在生成 rclone 配置文件..."

# ==========================================
# 构建底层存储远端 (backend)
# ==========================================
cat <<EOF > "${CONFIG_FILE}"
[backend]
EOF

if [ "${STORAGE_TYPE}" = "s3" ]; then
    if [ -z "${S3_ENDPOINT}" ] || [ -z "${S3_ACCESS_KEY}" ] || [ -z "${S3_SECRET_KEY}" ] || [ -z "${S3_BUCKET}" ]; then
        echo "[Error] 选择了 S3 存储，但缺少必需的 S3 环境变量！"
        exit 1
    fi
    cat <<EOF >> "${CONFIG_FILE}"
type = s3
provider = Other
endpoint = ${S3_ENDPOINT}
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
region = ${S3_REGION}
EOF
    REMOTE_TARGET="backend:${S3_BUCKET}/${S3_PATH}"

elif [ "${STORAGE_TYPE}" = "webdav" ]; then
    if [ -z "${WEBDAV_URL}" ] || [ -z "${WEBDAV_USER}" ] || [ -z "${WEBDAV_PASS}" ]; then
        echo "[Error] 选择了 WebDAV 存储，但缺少必需的 WEBDAV 环境变量！"
        exit 1
    fi
    # WebDAV 密码需要经过 rclone obscure 混淆后才能写入配置
    OBSCURED_PASS=$(rclone obscure "${WEBDAV_PASS}")
    cat <<EOF >> "${CONFIG_FILE}"
type = webdav
url = ${WEBDAV_URL}
vendor = ${WEBDAV_VENDOR}
user = ${WEBDAV_USER}
pass = ${OBSCURED_PASS}
EOF
    REMOTE_TARGET="backend:${WEBDAV_PATH}"

else
    echo "[Error] 未知的 STORAGE_TYPE，必须为 's3'、'webdav' 或 'local'。"
    exit 1
fi

# ==========================================
# 构建加密层 (secure) - 按需套壳
# ==========================================
if [ -n "${ENCRYPT_PASSWORD}" ]; then
    echo "[Init] 检测到加密密钥，正在启用 AES-256 加密层..."
    OBSCURED_ENC_PASS=$(rclone obscure "${ENCRYPT_PASSWORD}")
    
    cat <<EOF >> "${CONFIG_FILE}"

[secure]
type = crypt
remote = ${REMOTE_TARGET}
password = ${OBSCURED_ENC_PASS}
EOF

    # 处理加密盐值
    if [ -n "${ENCRYPT_SALT}" ]; then
        OBSCURED_SALT=$(rclone obscure "${ENCRYPT_SALT}")
        echo "password2 = ${OBSCURED_SALT}" >> "${CONFIG_FILE}"
    fi

    FINAL_TARGET="secure:"
else
    FINAL_TARGET="${REMOTE_TARGET}"
fi

# ==========================================
# 阶段 1：冷启动数据恢复
# ==========================================
echo "[Sync] 容器启动，正在从云端 (${FINAL_TARGET}) 恢复历史数据到本地..."
# 忽略由空目录引发的报错，确保初次运行能顺利通过
rclone copy "${FINAL_TARGET}" "${DATA_DIR}" -v || echo "[Warning] 拉取结束，如果是初次部署请忽略上方报错。"

# ==========================================
# 阶段 2：启动面板服务
# ==========================================
echo "[App] 启动 nezha 面板主程序..."
/dashboard/app &
NEZHA_PID=$!

# ==========================================
# 阶段 3：启动后台定时增量备份循环
# ==========================================
echo "[Sync] 启动后台同步守护进程，间隔：${SYNC_INTERVAL} 分钟。"
(
    while true; do
        sleep $((SYNC_INTERVAL * 60))
        echo "[Sync] 正在将本地数据同步至云端 (${FINAL_TARGET})..."
        # 使用 sync 保持远端与本地绝对一致（处理删除和修改）
        rclone sync "${DATA_DIR}" "${FINAL_TARGET}" -v || echo "[Warning] 本次同步遇到网络波动，将在下个周期重试。"
    done
) &

# ==========================================
# 进程守护
# ==========================================
# 挂起脚本，监听主程序存活状态
wait ${NEZHA_PID}
