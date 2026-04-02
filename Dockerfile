# 基于哪吒官方镜像
FROM ghcr.io/nezhahq/nezha:latest

# 切换为 root 以安装依赖
USER root

# 更新 apk 并安装 rclone 及必要的运行环境
RUN apk update && \
    apk add --no-cache rclone bash ca-certificates tzdata

# 将自定义的启动脚本复制到容器中
COPY entrypoint.sh /entrypoint.sh

# 赋予执行权限
RUN chmod +x /entrypoint.sh

# 覆盖官方入口点，使用封装了 rclone 同步逻辑的脚本
ENTRYPOINT ["/entrypoint.sh"]
