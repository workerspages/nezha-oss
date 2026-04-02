# ==========================================
# 第一阶段：提取环境 (只作为文件提供者，不在此环境运行命令)
# ==========================================
FROM ghcr.io/nezhahq/nezha:latest AS nezha-base

# ==========================================
# 第二阶段：构建最终镜像 (采用官方 Debian 轻量版底包)
# ==========================================
FROM debian:bookworm-slim

# 切换为 root 以安装依赖和修改权限
USER root

# 更新软件源并安装 rclone 以及必需的系统依赖环境
# 加上 --no-install-recommends 并且清理缓存，可以最大幅度减小最终镜像大小
RUN apt-get update && \
    apt-get install -y --no-install-recommends rclone bash ca-certificates tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 从第一阶段的官方镜像中，将整个 /dashboard 目录（包含 app 主程序、静态资源等）完整拷贝到新镜像
COPY --from=nezha-base /dashboard /dashboard

# 将自定义的启动和备份控制脚本复制到容器中
COPY entrypoint.sh /entrypoint.sh

# 赋予执行权限：确保核心脚本和哪吒的二进制主程序都可以正常执行
RUN chmod +x /entrypoint.sh && \
    chmod +x /dashboard/app

# 设置工作目录，哪吒主程序要求在此目录下启动以读写 data
WORKDIR /dashboard

# 接管官方的入口点，使用我们的自定义同步脚本来拉起整个服务
ENTRYPOINT ["/entrypoint.sh"]
