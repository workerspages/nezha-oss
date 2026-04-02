# 基于哪吒官方镜像
FROM ghcr.io/nezhahq/nezha:latest

# 切换为 root 以安装依赖
USER root

# 使用 apt-get 更新并安装 rclone 及必要的运行环境，并清理缓存以减小镜像体积
RUN apt-get update && \
    apt-get install -y --no-install-recommends rclone bash ca-certificates tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 将自定义的启动脚本复制到容器中
COPY entrypoint.sh /entrypoint.sh

# 赋予执行权限
RUN chmod +x /entrypoint.sh

# 覆盖官方入口点，使用封装了 rclone 同步逻辑的脚本
ENTRYPOINT ["/entrypoint.sh"]
