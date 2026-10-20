# 香港选美大赛投票系统 API 文档

- Base URL：`http://localhost:3000`
- 接口前缀：`/api/v1`
- 数据格式：`application/json`
- 认证方式：JWT，请求头格式为 `Authorization: Bearer <token>`

## 通用错误响应

| 状态码 | 场景 | 响应示例 |
| --- | --- | --- |
| 400 | 缺少必要参数 | `{ "error": "缺少必要参数：user" }` |
| 401 | 未登录或 Token 失效 | `{ "error": "请先登录或登录状态已过期" }` |
| 404 | 资源不存在 | `{ "error": "资源不存在" }` |
| 422 | 参数校验失败 | `{ "error": "手机号格式不正确" }` |
| 500 | 服务端异常 | `{ "error": "服务器内部错误，请稍后重试" }` |

---

## 1. 注册用户

### URL
POST /api/v1/users

### 认证
不需要

### Request 示例
```json
{
  "username": "alice",
  "phone_number": "13800138000",
  "password": "123456",
  "password_confirmation": "123456"
}
```

> 同时兼容嵌套写法：`{ "user": { "username": "alice", "phone_number": "13800138000", "password": "123456" } }`

### Response 示例

成功（201）：
```json
{
  "message": "注册成功",
  "data": {
    "id": 1,
    "username": "alice",
    "phone_number": "13800138000",
    "created_at": "2026-10-20T11:30:00.000Z"
  }
}
```

失败（422，手机号格式不正确）：
```json
{
  "error": "手机号格式不正确"
}
```

失败（422，用户名已存在）：
```json
{
  "error": "用户名已被占用"
}
```

失败（422，密码过短）：
```json
{
  "error": "密码长度不能少于 6 位"
}
```

失败（422，密码为空）：
```json
{
  "error": "密码不能为空"
}
```

失败（422，两次密码不一致）：
```json
{
  "error": "两次输入的密码不一致"
}
```

### 说明
- 手机号规则：1 开头、第二位 3-9、共 11 位数字。
- 用户名、手机号均有数据库唯一索引，重复注册会被拒绝。
- 响应中不会返回 `password_digest`。

---

## 2. 登录

### URL
POST /api/v1/sessions

### 认证
不需要

### Request 示例
使用手机号登录：
```json
{
  "phone_number": "13800138000",
  "password": "123456"
}
```

使用用户名登录：
```json
{
  "username": "alice",
  "password": "123456"
}
```

### Response 示例

成功（200）：
```json
{
  "message": "登录成功",
  "token": "eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoxLCJpYXQiOjE3OTI0OTU0MjIsImV4cCI6MTc5MjU4MTgyMn0.xxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "user": {
    "id": 1,
    "username": "alice",
    "phone_number": "13800138000",
    "created_at": "2026-10-20T11:30:00.000Z"
  }
}
```

失败（422，参数缺失）：
```json
{
  "error": "手机号/用户名和密码不能为空"
}
```

失败（401，账号或密码错误）：
```json
{
  "error": "手机号/用户名或密码错误"
}
```

### 说明
- Token 有效期 24 小时，前端需自行保存并在后续请求的 `Authorization` 头中携带。
- 登录失败不区分“账号不存在”和“密码错误”，避免账号枚举。

---

## 3. 登出

### URL
DELETE /api/v1/sessions/current

### 认证
不需要（即使 Token 已过期也允许调用）

### Request 示例
无请求体，可携带当前 Token：
```
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9...
```

### Response 示例

成功（200）：
```json
{
  "message": "登出成功"
}
```

### 说明
- JWT 为无状态令牌，后端不保存会话，登出由前端删除本地 Token 完成。
- 后端固定返回 200，保证前端退出流程不被 Token 状态阻塞。

---

## 4. 获取候选人列表

### URL
GET /api/v1/candidates

### 认证
需要，请求头：`Authorization: Bearer <token>`

### Request 示例
无请求体。

### Response 示例

成功（200）：
```json
{
  "data": [
    {
      "id": 1,
      "name": "陈晓华",
      "description": "2026 年度香港小姐候选人",
      "photo_url": "https://example.com/candidates/1.jpg",
      "has_voted": true,
      "created_at": "2026-10-20T11:00:00.000Z"
    },
    {
      "id": 2,
      "name": "李芷晴",
      "description": "热爱公益与舞台表演",
      "photo_url": "https://example.com/candidates/2.jpg",
      "has_voted": false,
      "created_at": "2026-10-20T11:01:00.000Z"
    }
  ]
}
```

失败（401，未登录）：
```json
{
  "error": "请先登录或登录状态已过期"
}
```

### 说明
- `has_voted` 表示当前登录用户是否已给该候选人投过票。
- 实现上先用 `current_user.votes.pluck(:candidate_id)` 一次性取出已投 ID，再在内存中判断，避免 N+1 查询。

---

## 5. 获取单个候选人

### URL
GET /api/v1/candidates/:id

### 认证
需要，请求头：`Authorization: Bearer <token>`

### Request 示例
```
GET /api/v1/candidates/1
```

### Response 示例

成功（200）：
```json
{
  "data": {
    "id": 1,
    "name": "陈晓华",
    "description": "2026 年度香港小姐候选人",
    "photo_url": "https://example.com/candidates/1.jpg",
    "has_voted": true,
    "created_at": "2026-10-20T11:00:00.000Z"
  }
}
```

失败（404，候选人不存在）：
```json
{
  "error": "资源不存在"
}
```

失败（401，未登录）：
```json
{
  "error": "请先登录或登录状态已过期"
}
```

### 说明
- 同样返回 `has_voted` 字段。
- 仅查询当前候选人对应的投票记录，不会加载该用户的全部投票。

---

## 6. 投票

### URL
POST /api/v1/votes

### 认证
需要，请求头：`Authorization: Bearer <token>`

### Request 示例
```json
{
  "candidate_id": 1
}
```

> 同时兼容嵌套写法：`{ "vote": { "candidate_id": 1 } }`

### Response 示例

成功（201）：
```json
{
  "message": "投票成功",
  "data": {
    "id": 10,
    "candidate_id": 1,
    "has_voted": true
  }
}
```

失败（422，重复投票）：
```json
{
  "error": "您已经投过票了"
}
```

失败（422，未选择候选人）：
```json
{
  "error": "请选择候选人"
}
```

失败（404，候选人不存在）：
```json
{
  "error": "资源不存在"
}
```

失败（401，未登录）：
```json
{
  "error": "请先登录或登录状态已过期"
}
```

### 说明
- 每个用户对同一候选人只能投一票，可以给不同候选人分别投票。
- 防重复投票有三层保障：
  1. 数据库联合唯一索引 `(user_id, candidate_id)`；
  2. 模型 `uniqueness` 校验；
  3. 控制器捕获 `ActiveRecord::RecordNotUnique` 并返回 422。
- `user_id` 从 Token 中获取，前端无法伪造投票人。
