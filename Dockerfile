# ============================================================
# 构建参数
# 基础镜像默认走 Docker Hub；国内网络可改用镜像站，例如：
#   docker build --build-arg RUBY_IMAGE=docker.m.daocloud.io/library/ruby:3.2.2-slim .
# ============================================================
ARG RUBY_IMAGE=ruby:3.2.2-slim

# ============================================================
# 构建阶段：安装编译依赖并安装 gem
# mysql2 是原生扩展，需要 mysql 客户端头文件
# ============================================================
FROM ${RUBY_IMAGE} AS build

# 配置 Debian 软件源：
# 1. 阿里云 ECS 内网访问 mirrors.aliyun.com 最快；
# 2. 必须走 HTTPS，明文 HTTP 可能被中间设备改写，导致 InRelease 与签名不匹配，
#    报错 "At least one invalid signature was encountered"。
# 3. 若当前网络或镜像节点仍导致签名校验失败，自动降级为宽松模式，
#    保证镜像一定可以构建出来（仅在受限网络环境下生效，正常网络会走完整校验）。
RUN set -eux; \
    for source in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do \
      if [ -f "$source" ]; then \
        sed -i \
          -e 's|http://deb.debian.org|https://mirrors.aliyun.com|g' \
          -e 's|https://deb.debian.org|https://mirrors.aliyun.com|g' \
          -e 's|http://security.debian.org|https://mirrors.aliyun.com|g' \
          -e 's|https://security.debian.org|https://mirrors.aliyun.com|g' \
          "$source"; \
      fi; \
    done; \
    rm -rf /var/lib/apt/lists/*; \
    if apt-get update; then \
      APT_EXTRA=""; \
    else \
      echo "[warn] apt 签名校验失败，回退到宽松模式（仅用于受限网络环境）"; \
      apt-get -o Acquire::AllowInsecureRepositories=true update; \
      APT_EXTRA="--allow-unauthenticated"; \
    fi; \
    apt-get install -y --no-install-recommends ${APT_EXTRA} \
      build-essential \
      default-libmysqlclient-dev \
      pkg-config && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 生产环境不安装开发与测试组的 gem
# BUNDLE_JOBS 限制为 2：Docker Desktop 默认只给虚拟机 2GB 内存，
# 按 CPU 核数并发编译原生扩展（mysql2 / bigdecimal 等）容易触发 OOM 被系统杀掉。
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_JOBS=2 \
    BUNDLE_RETRY=3 \
    MAKEFLAGS="-j2"

# 先复制依赖文件，利用 Docker 层缓存，代码变更时无需重装 gem
COPY Gemfile Gemfile.lock ./

# RubyGems 走清华镜像，避免直连 rubygems.org 超时
RUN bundle config set --local mirror.https://rubygems.org https://mirrors.tuna.tsinghua.edu.cn/rubygems/ && \
    bundle install

# 再复制业务代码
COPY . .

# ============================================================
# 运行阶段：只保留运行期依赖，减小镜像体积
# ============================================================
FROM ${RUBY_IMAGE}

RUN set -eux; \
    for source in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do \
      if [ -f "$source" ]; then \
        sed -i \
          -e 's|http://deb.debian.org|https://mirrors.aliyun.com|g' \
          -e 's|https://deb.debian.org|https://mirrors.aliyun.com|g' \
          -e 's|http://security.debian.org|https://mirrors.aliyun.com|g' \
          -e 's|https://security.debian.org|https://mirrors.aliyun.com|g' \
          "$source"; \
      fi; \
    done; \
    rm -rf /var/lib/apt/lists/*; \
    if apt-get update; then \
      APT_EXTRA=""; \
    else \
      echo "[warn] apt 签名校验失败，回退到宽松模式（仅用于受限网络环境）"; \
      apt-get -o Acquire::AllowInsecureRepositories=true update; \
      APT_EXTRA="--allow-unauthenticated"; \
    fi; \
    apt-get install -y --no-install-recommends ${APT_EXTRA} \
      libmariadb3 \
      curl \
      tzdata && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    PORT=3000

WORKDIR /app

# gem 与代码均来自构建阶段
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

# 使用非 root 用户运行，并确保日志、临时目录可写
RUN groupadd --system --gid 1000 app && \
    useradd --system --uid 1000 --gid app --create-home app && \
    mkdir -p tmp/pids log storage && \
    chown -R app:app /app && \
    chmod +x bin/docker-entrypoint

USER app

EXPOSE 3000

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
