# 设计思路

## 1. 目标与范围

为“香港选美大赛投票系统”提供后端 API，覆盖：

- 手机号验证码发送（注册前置校验）
- 用户注册、登录、登出
- 候选人列表（分页）与详情
- 登录用户投票
- 统一的 JSON 错误响应

不在本期范围：候选人后台管理、图片上传、投票结果统计报表。

## 2. 技术选型

| 选择 | 理由 |
| --- | --- |
| Rails 7.1 API 模式 | 轻量、启动快，去掉视图与前端资源链路，只保留 JSON 接口能力 |
| MySQL 8 | 关系型数据清晰，唯一索引与事务能力成熟 |
| JWT | 无状态认证，前后端分离部署简单，服务端无需维护会话表 |
| bcrypt | Rails 原生 `has_secure_password` 配套，密码只存摘要 |
| Redis | 保存 JWT 白名单，使 Token 可被服务端主动撤销 |
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

### verification_codes

注册要求“手机号验证”，因此单独设计验证码表，而不是把验证码塞进 `users` 表。原因：

- 用户可能多次获取验证码，历史记录需要保留用于限流与审计；
- 未注册成功的手机号没有 `users` 记录，验证码无处存放；
- 验证码是短生命周期数据，独立成表便于按 `expires_at` 批量清理。

| 字段 | 类型 | NULL | 说明 |
| --- | --- | --- | --- |
| id | bigint | 否 | 主键 |
| phone_number | varchar(20) | 否 | 接收验证码的手机号，兼容国际号码长度 |
| code_digest | varchar(100) | 否 | bcrypt 摘要，禁止明文落库 |
| purpose | varchar(20) | 否 | 用途，默认 `register`，为登录、找回密码预留 |
| expires_at | datetime | 否 | 过期时间，签发时写入，默认 5 分钟 |
| used_at | datetime | 是 | 为空表示未使用，非空表示已被消费 |
| attempts | int | 否 | 错误次数，默认 0，达到 5 次后作废 |
| created_at / updated_at | datetime | 否 | 自动维护，`created_at` 同时用于 60 秒限流判断 |

索引：

```ruby
add_index :verification_codes,
          [:phone_number, :purpose, :created_at],
          name: "index_verification_codes_on_phone_purpose_created"
add_index :verification_codes, :expires_at
```

- `(phone_number, purpose, created_at)`：`verify!` 与 `issue!` 都是“取该手机号该用途的最新一条”，该索引让 `ORDER BY created_at DESC LIMIT 1` 直接走索引，避免全表扫描；
- `expires_at`：供定时任务删除过期记录，避免验证码表无限膨胀；
- 不给 `phone_number` 单独建唯一索引：同一手机号必然存在多条历史记录，唯一约束会直接冲突。

### 列类型与 NULL 的取舍

- 主键统一 `bigint`，为长期增长留出空间；
- 手机号、用户名使用 `varchar` 而非整数：手机号可能带前导 0 或国家码，且不参与算术运算；
- 密码、验证码摘要使用 `varchar(100)`：bcrypt 输出固定 60 字符，留出算法升级余量；
- 简介使用 `text`：长度不可预估，避免 `varchar` 上限截断；
- `description`、`photo_url` 允许 NULL：运营可能先建候选人、后补资料，用 NULL 表示“尚未填写”，与空字符串区分；
- `used_at` 允许 NULL：NULL 本身就是“未使用”的语义，比额外的布尔字段更省空间且不会出现两个字段互相矛盾；
- 其余业务字段一律 `NOT NULL` + 默认值，把“数据必须完整”的约束交给数据库，而不是只靠应用层。

## 4. 认证设计

### 注册与手机号验证流程

1. 前端调用 `POST /api/v1/verification_codes` 提交手机号；
2. 后端校验手机号格式，生成 6 位数字验证码，用 bcrypt 摘要写入 `code_digest`，同时写入 `expires_at`；
3. 生产环境通过短信服务商下发明文验证码，明文只在本次请求内存中存在，不落库；
4. 前端调用 `POST /api/v1/users`，携带手机号、验证码、用户名与密码；
5. 后端取该手机号“最新一条”验证码，依次校验：是否存在 → 是否已使用 → 是否过期 → 错误次数是否超限 → 摘要是否匹配；
6. 匹配失败时 `attempts + 1` 并返回 422；匹配成功后创建用户，创建成功才把 `used_at` 置为当前时间，验证码一次性失效。

限流与防暴力枚举：

| 规则 | 实现 | 目的 |
| --- | --- | --- |
| 60 秒内不可重复发送 | `issue!` 比较最新记录的 `created_at` | 防止短信轰炸与费用放大 |
| 5 分钟过期 | `expires_at = 5.minutes.from_now` | 缩短验证码可用窗口 |
| 最多错 5 次 | `attempts` 达到 `MAX_ATTEMPTS` 后直接拒绝 | 6 位数字只有 100 万种组合，必须限制尝试次数 |
| 一次性消费 | 注册成功后写 `used_at` | 防止同一验证码重复注册 |
| 先建用户后消费 | `user.save` 成功才 `consume!` | 用户信息校验失败时不浪费验证码 |

### 登录流程

1. 前端提交手机号/用户名 + 密码；
2. 后端用 `has_secure_password` 的 `authenticate` 校验密码；
3. 校验通过后签发 JWT，payload 包含 `user_id`、`jti`、`iat`、`exp`，并把 `jti` 写入 Redis 白名单；
4. 前端保存 Token，后续请求携带 `Authorization: Bearer <token>`；
5. 中间件校验签名、过期时间与 Redis 白名单后，通过 `user_id` 还原 `current_user`。

### Token 白名单与中间件

- 登录成功后签发 JWT（HS256，有效期 24 小时），payload 包含 `user_id`、`jti`、`iat`、`exp`；
- `jti` 是每条 Token 的唯一编号，写入 Redis：键 `jwt:token:<jti>`、值 `user_id`，TTL 与 Token 有效期一致；
- `JwtAuthenticationMiddleware`（`lib/middleware`）在请求进入控制器之前完成：提取 Bearer Token → 校验签名与过期时间 → 校验 Redis 白名单 → 把 `user_id`、payload、原始 Token 写入 Rack env；
- 中间件不直接渲染响应，只把失败原因写入 `env["jwt_error"]`，由 `BaseController#authenticate_user!` 统一转成 401/503。这样登录、发送验证码等公开接口即使携带过期 Token 也不会被误拦截；
- `current_user` 从 `env["current_user_id"]` 读取并记忆化，一次请求只查一次用户。

### 登出

登出时从 Token payload 取出 `jti` 并删除 Redis 键，该 Token 立即失效；只影响当前 Token，同一账号在其他设备上的登录状态保留。即使 Token 已过期、已撤销或未携带，接口仍固定返回 200，保证前端退出流程不被阻塞。

### Redis 不可用时的行为

Redis 校验失败时既不能放行，也不应伪装成“未登录”：中间件写入 503 状态，接口返回“认证服务暂不可用，请稍后重试”。登录写白名单时的 Redis 异常由 `ApplicationController` 的 `rescue_from Redis::BaseError` 统一兜底为 503。

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

### 分页设计

候选人数量会随赛事增长，列表接口必须分页，否则一次请求可能返回全部候选人并拖慢响应。

- 参数：`page`（默认 1）、`per_page`（默认 10，上限 50）；
- 实现：`limit(per_page).offset((page - 1) * per_page)`，并按 `id ASC` 排序保证翻页顺序稳定；
- `per_page` 强制夹在 `1..50`：既防止 0 或负数导致 SQL 异常，也防止前端传入过大的值造成慢查询；
- 响应附带 `meta`：`current_page`、`per_page`、`total_count`、`total_pages`、`has_next`、`has_prev`，前端无需自行推算；
- 页码超出总页数时返回空数组而不是 404，符合列表接口的常见语义。

候选人总量在千级以内时，`limit + offset` 足够；如果后续增长到十万级，可改为基于 `id` 的游标分页（`WHERE id > last_id LIMIT n`），避免深分页的偏移扫描成本。

### 索引使用

- `votes.user_id` 索引：支持 `current_user.votes` 快速过滤；
- `votes.(user_id, candidate_id)` 唯一索引：支持已投 ID 查询与重复投票拦截；
- `users.username`、`users.phone_number` 唯一索引：支持登录查询与唯一性约束；
- `verification_codes.(phone_number, purpose, created_at)` 联合索引：支持“取最新验证码”与 60 秒限流判断；
- `verification_codes.expires_at` 索引：支持过期数据清理。

## 7. 异常与错误码

`ApplicationController` 通过 `rescue_from` 统一处理：

| 异常 | 状态码 | 响应 |
| --- | --- | --- |
| `ActiveRecord::RecordNotFound` | 404 | `{ "error": "资源不存在" }` |
| `ActiveRecord::RecordInvalid` | 422 | 第一条模型校验错误 |
| `ActiveRecord::RecordNotUnique` | 422 | `{ "error": "数据已存在，请勿重复提交" }` |
| `ActionController::ParameterMissing` | 400 | `{ "error": "缺少必要参数：xxx" }` |
| `Redis::BaseError` | 503 | `{ "error": "认证服务暂不可用，请稍后重试" }` |
| `StandardError` | 500 | `{ "error": "服务器内部错误，请稍后重试" }` |

说明：

- `rescue_from` 后注册的处理器优先级更高，因此 `StandardError` 最先注册、最后匹配；
- 500 响应不暴露堆栈，完整异常写入 Rails 日志；
- 投票接口在控制器内单独捕获 `RecordNotUnique`，返回业务文案“您已经投过票了”；
- 验证码相关错误由 `VerificationCode::VerificationError` 承载：发送过于频繁返回 429，其余校验失败返回 422。

## 8. 安全设计

1. 密码使用 bcrypt 摘要存储，任何响应都不返回 `password_digest`；
2. 登录失败不区分账号不存在与密码错误，降低账号枚举风险；
3. JWT 校验签名与过期时间，防止伪造与重放（过期后失效）；
4. Strong Parameters 白名单，避免批量赋值；
5. 投票人身份取自 Token，不信任客户端传入的 `user_id`；
6. 手机号、用户名在数据库层唯一，防止重复注册；
7. 验证码只存 bcrypt 摘要，接口响应默认不回显明文（仅开发环境返回 `debug_code` 便于联调）；
8. 验证码 5 分钟过期、60 秒发送间隔、最多错 5 次、一次性消费，限制短信轰炸与暴力枚举；
9. JWT 的 `jti` 写入 Redis 白名单，登出或后台封禁时删除键即可让 Token 立即失效；
10. 白名单按 Token 粒度存储，登出不会影响同一账号在其他设备上的登录状态。

## 9. 后续可扩展方向

- 验证码表按月归档，并增加定时任务清理过期记录；
- 在 Redis 中增加登录限流与投票频控键，并缓存候选人列表；
- 接入真实短信服务商，并增加图形验证码或人机校验作为发送前置条件；
- 投票结果统计接口使用计数器缓存或异步汇总，避免实时聚合压力；
- 如需强制单设备登录，可在登录时删除该用户的其他 `jti`，只保留最新一条；
- 多实例部署时 Redis 天然共享白名单，无需额外的会话同步机制。
- 数据量增长后把候选人列表改为游标分页。
