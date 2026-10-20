# 香港选美大赛投票系统

手机号验证码注册、JWT 登录、候选人浏览与一人一票投票，前端页面由 Rails 直接托管。

- 技术栈：Rails 7.1（API 模式）、MySQL 8、Redis、Puma
- 认证：JWT + Redis 白名单，登出即时撤销
- 接口前缀 `api/v1`，详见 [docs/API.md](docs/API.md)；设计说明见 [docs/DESIGN.md](docs/DESIGN.md)

## 一、安装 Docker

macOS：

```bash
brew install --cask docker
open -a Docker          # 图标变绿即就绪
docker version && docker compose version
```

Linux（国内源）：

```bash
curl -fsSL https://get.docker.com | sh -s -- --mirror Aliyun
sudo systemctl enable --now docker
sudo usermod -aG docker $USER && newgrp docker
docker compose version
```

拉取镜像慢时配置加速器 `/etc/docker/daemon.json`，然后重启 Docker：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live",
    "https://hub.rat.dev"
  ]
}
```

> Docker Desktop 内存低于 4GB 时并行编译原生 gem 容易 OOM（退出码 137），建议在 Settings → Resources 调到 4GB 以上。

## 二、安装环境所需镜像

部署只需基础镜像 `ruby:3.2.2-slim`。apt 依赖与 Ruby gem 都在构建阶段自动安装，且已切换阿里云 apt 源与清华 RubyGems 源，本地无需执行 `bundle install`。

```bash
docker pull ruby:3.2.2-slim
docker run --rm ruby:3.2.2-slim ruby -v   # 期望 ruby 3.2.2
```

加速器不生效时，改从镜像站拉取后打回官方 tag：

```bash
docker pull docker.m.daocloud.io/library/ruby:3.2.2-slim
docker tag  docker.m.daocloud.io/library/ruby:3.2.2-slim ruby:3.2.2-slim
```

也可以不打 tag，直接在 `.env` 里设 `RUBY_IMAGE=docker.m.daocloud.io/library/ruby:3.2.2-slim`。

内网离线导入：

```bash
docker save -o ruby-3.2.2-slim.tar ruby:3.2.2-slim   # 有网机器
scp ruby-3.2.2-slim.tar user@服务器:/tmp/
docker load -i /tmp/ruby-3.2.2-slim.tar              # 目标服务器
```

仅本地自测才需要额外拉取数据库与缓存（正式部署连外部服务）：

```bash
docker pull mysql:8.0
docker pull redis:7-alpine
```

## 三、准备外部 MySQL 与 Redis

```sql
CREATE DATABASE hk_beauty_contest_voting_production
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'hk_beauty_contest_voting'@'%' IDENTIFIED BY '你的密码';
GRANT ALL PRIVILEGES ON hk_beauty_contest_voting_production.*
  TO 'hk_beauty_contest_voting'@'%';
FLUSH PRIVILEGES;
```

Redis 需允许远程并设置密码（`redis.conf`）：

```
bind 0.0.0.0
requirepass 你的密码
```

同时放行 3306 / 6379 端口。若 MySQL、Redis 与容器同机，`.env` 中的地址可填 `host.docker.internal`（compose 已加 `host-gateway` 映射）。

## 四、配置 .env

```bash
cp .env.example .env
openssl rand -hex 64   # 填入 SECRET_KEY_BASE
openssl rand -hex 64   # 填入 JWT_SECRET
```

| 变量 | 说明 |
| --- | --- |
| `APP_PORT` | 宿主机映射端口，默认 3000 |
| `DB_HOST` / `DB_PORT` / `DB_USERNAME` | 外部 MySQL 连接信息 |
| `HK_BEAUTY_CONTEST_VOTING_DATABASE_PASSWORD` | 生产库密码变量名，注意不是 `DB_PASSWORD` |
| `REDIS_URL` | 形如 `redis://:密码@主机:6379/0` |
| `SECRET_KEY_BASE` / `JWT_SECRET` | 留空会生成临时值，重启后已签发 Token 全部失效 |
| `SMS_DEBUG_MODE` | 演示环境返回验证码明文，正式上线设为 false |
| `FORCE_SSL` | 由 Nginx 终止 SSL 后再设为 true |

`.env` 已被 `.gitignore` 忽略，禁止提交到仓库。

## 五、启动与验证

```bash
docker compose up -d --build
docker compose ps                   # 状态应为 healthy
docker compose logs -f web          # 看到 Puma listening on 0.0.0.0:3000
curl -i http://127.0.0.1:3000/up    # 200 表示健康检查通过
```

浏览器访问 `http://服务器IP:3000` 即可看到投票页面。容器启动时会自动执行 `db:prepare` 完成建库与迁移。

## 六、常用运维

```bash
docker compose restart web          # 重启应用
docker compose down                 # 停止并删除容器
docker compose up -d --build        # 代码更新后重新上线
docker compose logs -f --tail=100   # 查看日志
docker image prune -f               # 清理悬空镜像
```

## 七、本地开发

```bash
bundle install
redis-server                        # JWT 白名单依赖
bin/rails db:create db:migrate
bin/rails server -p 3000
```
