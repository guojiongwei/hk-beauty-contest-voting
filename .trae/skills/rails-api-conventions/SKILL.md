---
name: rails-api-conventions
description: "本仓库 Rails API 编码规范与检查清单。新增或修改模型、控制器、路由、JWT 认证、投票逻辑时必须先加载，确保与现有代码风格一致。"
---

# Rails API 编码规范

## 适用场景

- 新增/修改控制器、模型、路由、迁移
- 调整 JWT 认证、错误响应、投票业务逻辑
- 排查 N+1、重复投票、参数校验问题

## 分层职责

| 层 | 职责 | 禁止 |
| --- | --- | --- |
| Controller | 参数接收、调用模型、渲染 JSON | 复杂业务计算、直接拼 SQL |
| Model | 校验、关联、领域规则 | 读取 request/response |
| BaseController | JWT 解析、当前用户、登录拦截 | 具体业务分支 |

## 控制器写法

1. 统一继承 `Api::V1::BaseController`（需要登录的接口）或 `ApplicationController`（公开接口）。
2. 需要登录时在类顶部声明：

```ruby
before_action :authenticate_user!
```

3. 渲染统一使用显式状态码：

```ruby
render json: { data: payload }, status: :ok
render json: { error: "错误描述" }, status: :unprocessable_entity
```

4. 参数必须显式提取，禁止直接 `params` 透传给模型：

```ruby
params.require(:user).permit(:username, :phone_number, :password, :password_confirmation)
```

## 查询规范

- 列表接口先批量取关联 ID，再在内存中判断，避免逐条查询：

```ruby
voted_ids = current_user.votes.pluck(:candidate_id)
```

- 关联预加载使用 `includes`，禁止在循环中触发查询。
- 只查询必要字段时使用 `select` 或 `pluck`。

## 错误处理规范

1. 全局异常在 `ApplicationController` 通过 `rescue_from` 捕获。
2. 业务异常使用明确状态码：重复投票 `422`、未登录 `401`、资源不存在 `404`。
3. 重复投票必须同时有：
   - 模型校验 `uniqueness`
   - 数据库联合唯一索引
   - 控制器 `rescue ActiveRecord::RecordNotUnique`

## 安全规范

- 永远不要渲染 `password_digest`。
- JWT 密钥从 `ENV["JWT_SECRET"]` 读取，提供开发环境兜底值。
- 密码最短长度 6 位，使用 `has_secure_password`。
- 手机号在入库前做格式校验与去空格。

## 提交前自检

- [ ] 是否有 N+1 查询
- [ ] 是否覆盖异常分支
- [ ] 是否补充中文注释
- [ ] 是否需要同步 `docs/API.md`
