# AGENTS.md

本文件面向在本仓库工作的 AI 助手与开发者，用于统一协作方式、代码风格与交付标准。

## 1. 项目简介

香港选美大赛投票系统后端，提供用户注册、登录、候选人查询与投票能力。

- 框架：Ruby on Rails 7.1（API 模式）
- 数据库：MySQL 8.x（本地 3306）
- 认证：JWT（无状态，Token 由前端保存）
- 接口前缀：`/api/v1`

## 2. 技术栈与依赖

| 组件 | 用途 |
| --- | --- |
| rails | Web 框架（API 模式） |
| mysql2 | MySQL 适配器 |
| puma | 应用服务器 |
| bcrypt | 密码摘要（`has_secure_password`） |
| jwt | Token 签发与校验 |
| rack-cors | 跨域支持 |

## 3. 目录约定

```
app/controllers/application_controller.rb     # 全局异常处理
app/controllers/api/v1/verification_codes_controller.rb # 注册验证码发送
app/models/verification_code.rb               # 验证码生成、限流与校验
app/controllers/api/v1/base_controller.rb     # JWT 认证基类
app/controllers/api/v1/*.rb                   # 业务控制器
app/models/*.rb                               # 模型与校验
config/routes.rb                              # 路由（api/v1 命名空间）
config/initializers/cors.rb                   # 跨域配置
db/migrate/*.rb                               # 数据库迁移
docs/API.md                                   # 接口文档
docs/DESIGN.md                                # 设计思路
```

## 4. 编码规范

1. 业务代码必须补充中文注释，尤其是核心分支、异常处理与查询优化处。
2. 控制器只负责参数接收、调用模型、渲染响应；复杂逻辑下沉到模型或 service。
3. 统一 JSON 结构：
   - 成功：`{ "data": ..., "message": "..." }`（按接口需要取舍）
   - 失败：`{ "error": "错误描述" }`
4. 所有异常必须被 `rescue_from` 统一捕获，禁止把 Rails 默认 HTML 错误页暴露给前端。
5. 列表接口必须避免 N+1 查询，使用 `pluck`、`includes` 等批量查询方式。
6. 数据库层必须保留唯一索引与联合唯一索引，应用层校验只作为友好提示，不作为唯一防线。
7. 不提交任何密钥、真实数据库密码、Token；敏感配置一律走环境变量。

## 5. 接口约定

- 认证头：`Authorization: Bearer <token>`
- 需要登录的接口：候选人列表、候选人详情、投票
- 状态码：
  - `200` 查询/登录/登出成功
  - `201` 注册、投票成功
  - `401` 未登录或 Token 失效
  - `404` 资源不存在
  - `422` 参数校验失败或重复投票
  - `429` 验证码发送过于频繁
  - `500` 服务端异常

## 6. Git 提交规范

采用 Conventional Commits，按阶段拆分提交，禁止一次性提交全部改动。

```
chore: 初始化 Rails API 工程与协作规范
feat: 添加数据库迁移与基础配置
feat: 添加用户/候选人/投票模型及校验
feat: 实现 JWT 认证与投票核心接口
docs: 补充 API 文档与设计说明
fix: 修复冒烟测试发现的问题
```

提交前检查：

1. `git status` 确认没有无关文件、密钥、日志。
2. 每个提交只包含一个可独立说明的变更主题。
3. 提交信息使用中文描述，保持简洁明确。

## 7. 常用命令

```bash
# 安装依赖
bundle install

# 创建并迁移数据库（需先在 config/database.yml 或环境变量中配置密码）
bin/rails db:create db:migrate

# 启动服务
bin/rails server -p 3000

# 路由检查
bin/rails routes
```

## 8. 禁止事项

- 禁止修改与本任务无关的业务逻辑。
- 禁止使用 `...`、`# 同上`、`# 省略` 等占位符交付代码。
- 禁止在前端可访问的响应中返回 `password_digest`。
- 禁止关闭数据库唯一索引来“绕过”重复投票问题。
