# 设计思路

## 1. 目标与范围

为“香港选美大赛投票系统”提供后端 API，覆盖：

- 用户注册、登录、登出
- 候选人列表与详情
- 登录用户投票
- 统一的 JSON 错误响应

不在本期范围：候选人后台管理、图片上传、短信验证码、投票结果统计报表。

## 2. 技术选型

| 选择 | 理由 |
| --- | --- |
| Rails 7.1 API 模式 | 轻量、启动快，去掉视图与前端资源链路，只保留 JSON 接口能力 |
| MySQL 8 | 关系型数据清晰，唯一索引与事务能力成熟 |
| JWT | 无状态认证，前后端分离部署简单，服务端无需维护会话表 |
| bcrypt | Rails 原生 `has_secure_password` 配套，密码只存摘要 |
| rack-cors | 开发阶段允许跨域，方便前端本地联调 |

## 3. 数据模型

### users

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| id | bigint | 主键 |
| username | varchar | 非空、唯一索引 |
| phone_number | varchar | 非空、唯一索引 |
| password_digest | varchar | 非空 |
| created_at / updated_at | datetime | 自动维护 |

### candidates

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| id | bigint | 主键 |
| name | varchar | 非空 |
| description | text | 可空 |
| photo_url | varchar | 可空 |
| created_at / updated_at | datetime | 自动维护 |

### votes

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| id | bigint | 主键 |
| user_id | bigint | 非空、外键、索引 |
| candidate_id | bigint | 非空、外键、索引 |
| created_at / updated_at | datetime | 自动维护 |

核心索引：

```ruby
add_index :votes, [:user_id, :candidate_id], unique: true
```

该索引同时承担两个职责：

1. 业务约束：同一用户对同一候选人只能投一票；
2. 查询优化：按用户查已投候选人时可以直接命中索引。

## 4. 认证设计

### 登录流程

1. 前端提交手机号/用户名 + 密码；
2. 后端用 `has_secure_password` 的 `authenticate` 校验密码；
3. 校验通过后签发 JWT，payload 包含 `user_id`、`iat`、`exp`；
4. 前端保存 Token，后续请求携带 `Authorization: Bearer <token>`；
5. 后端解析并校验签名与过期时间，通过 `user_id` 还原 `current_user`。

### 关键实现

- 签名算法：HS256；
- 有效期：24 小时；
- 密钥：优先读取 `ENV["JWT_SECRET"]`，未配置时使用开发环境默认值；
- `decoded_token` 捕获 `JWT::ExpiredSignature` 与 `JWT::DecodeError`，统一交给 `authenticate_user!` 返回 401；
- `current_user` 使用 `defined?` 记忆化，单次请求只解析一次 Token、只查一次用户。

### 登出

JWT 是无状态令牌，服务端不维护黑名单。登出接口固定返回 200，由前端删除本地 Token。这样即使 Token 已过期，用户也能正常完成退出流程。

## 5. 投票与防刷票

### 三层防护

1. **数据库层**：`(user_id, candidate_id)` 联合唯一索引，是最终防线；
2. **模型层**：`validates :user_id, uniqueness: { scope: :candidate_id }`，提供友好错误信息；
3. **控制器层**：捕获 `ActiveRecord::RecordNotUnique`，处理并发下两个请求同时通过校验的情况。

### 为什么不能只做应用层校验

“先查询再插入”存在竞态窗口：两个并发请求可能同时查到“未投票”，然后都执行插入。只有数据库唯一索引能保证最终一致性。

### 投票人身份

`user_id` 一律来自 `current_user`，不接受前端传入，避免伪造投票人。

## 6. 性能设计

### 避免 N+1

候选人列表需要为每个候选人返回 `has_voted`。如果逐个调用 `current_user.votes.exists?(candidate_id: ...)`，N 个候选人会产生 N 次查询。

当前实现：

```ruby
voted_ids = current_user.votes.pluck(:candidate_id)
candidate.has_voted = voted_ids.include?(candidate.id)
```

只产生 2 次查询：

1. 查询候选人列表；
2. 查询当前用户已投候选人 ID。

`include?` 在内存数组中完成，不再访问数据库。

### 索引使用

- `votes.user_id` 索引：支持 `current_user.votes` 快速过滤；
- `votes.(user_id, candidate_id)` 唯一索引：支持已投 ID 查询与重复投票拦截；
- `users.username`、`users.phone_number` 唯一索引：支持登录查询与唯一性约束。

## 7. 异常与错误码

`ApplicationController` 通过 `rescue_from` 统一处理：

| 异常 | 状态码 | 响应 |
| --- | --- | --- |
| `ActiveRecord::RecordNotFound` | 404 | `{ "error": "资源不存在" }` |
| `ActiveRecord::RecordInvalid` | 422 | 第一条模型校验错误 |
| `ActiveRecord::RecordNotUnique` | 422 | `{ "error": "数据已存在，请勿重复提交" }` |
| `ActionController::ParameterMissing` | 400 | `{ "error": "缺少必要参数：xxx" }` |
| `StandardError` | 500 | `{ "error": "服务器内部错误，请稍后重试" }` |

说明：

- `rescue_from` 后注册的处理器优先级更高，因此 `StandardError` 最先注册、最后匹配；
- 500 响应不暴露堆栈，完整异常写入 Rails 日志；
- 投票接口在控制器内单独捕获 `RecordNotUnique`，返回业务文案“您已经投过票了”。

## 8. 安全设计

1. 密码使用 bcrypt 摘要存储，任何响应都不返回 `password_digest`；
2. 登录失败不区分账号不存在与密码错误，降低账号枚举风险；
3. JWT 校验签名与过期时间，防止伪造与重放（过期后失效）；
4. Strong Parameters 白名单，避免批量赋值；
5. 投票人身份取自 Token，不信任客户端传入的 `user_id`；
6. 手机号、用户名在数据库层唯一，防止重复注册。

## 9. 后续可扩展方向

- 增加短信验证码，降低手机号被冒用风险；
- 引入 Redis 做登录限流与投票频控；
- 候选人列表增加分页与缓存；
- 投票结果统计接口使用计数器缓存或异步汇总，避免实时聚合压力；
- 如需强制单设备登录，可引入 Token 版本号或黑名单机制。
