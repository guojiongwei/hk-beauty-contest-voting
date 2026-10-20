---
name: rails-model-conventions
description: "Active Record 模型编写规范与自检清单。新增或修改模型、关联、校验、领域方法或敏感字段处理时使用，确保遵循 Rails 约定优于配置。"
---

# Active Record 模型设计规范与自检清单

> 本文件记录本项目模型层的编写约定：新增或修改模型时按此执行，保证关联、校验与敏感字段处理保持一致。

## 1. 约定优于配置

- 类名 `User` / `Candidate` / `Vote` / `VerificationCode` 自动映射 `users` / `candidates` / `votes` / `verification_codes`，不写 `self.table_name`；
- `has_many :votes` 依据 `votes.user_id` 外键自动推断，不写 `foreign_key:`；
- `has_many :candidates, through: :votes` 依据 `votes.candidate_id` 自动推断中间表；
- 时间戳、主键、类型转换全部交给 Active Record，模型里不重复声明。

## 2. 关联设计

| 模型 | 关联 | 说明 |
| --- | --- | --- |
| User | `has_many :votes, dependent: :destroy` | 用户注销时清理其投票，避免孤儿记录 |
| User | `has_many :candidates, through: :votes` | 便捷查询“我投过哪些候选人” |
| Candidate | `has_many :votes, dependent: :destroy` | 候选人下架时清理关联投票 |
| Vote | `belongs_to :user` / `belongs_to :candidate` | Rails 7 默认 `belongs_to` 必填，与数据库 `null: false` 一致 |

原则：`dependent` 必须显式声明，行为可预期；数据库外键负责兜底，应用层负责清理时机。

## 3. 校验分层

1. **存在性**：`presence`，对应数据库 `null: false`；
2. **格式**：手机号 `PHONE_NUMBER_REGEX = /\A1[3-9]\d{9}\z/`，常量定义在 `User` 上，供验证码模型复用，避免两处正则漂移；
3. **长度**：用户名 ≤ 50、密码 ≥ 6，与迁移中的 `varchar` 长度呼应；
4. **唯一性**：`uniqueness` 只做友好提示，最终防线是数据库唯一索引；
5. **业务规则**：验证码的过期、一次性、错误次数、60 秒限流全部收敛在 `VerificationCode` 的领域方法里，控制器不重复实现。

所有校验错误文案使用中文，控制器直接取 `errors.map(&:message).first`，不把英文属性名前缀暴露给前端。

## 4. 密码与敏感数据

- `User` 使用 `has_secure_password`，自动获得 `authenticate`、`password_confirmation` 与 bcrypt 摘要；
- 数据库中只存 `password_digest`，任何序列化都不得输出摘要；
- `VerificationCode` 同样只存 `code_digest`，明文验证码只存在于本次请求的内存中（`attr_reader :plain_code`），配合 `BCrypt::Password.new(code_digest) == input` 比对；
- `BCrypt::Errors::InvalidHash` 兜底返回 `false`，避免脏数据导致 500。

## 5. 领域方法（VerificationCode）

| 方法 | 职责 |
| --- | --- |
| `issue!` | 校验 60 秒发送间隔后创建验证码，超限抛 `VerificationError` |
| `verify!` | 取最新记录，依次判断存在、已使用、已过期、错误次数、摘要是否匹配；不匹配则 `attempts + 1` |
| `consume!` | 注册成功后写入 `used_at`，实现一次性消费 |
| `expired?` / `used?` | 语义化状态判断，避免控制器里出现裸时间比较 |

设计考量：先建用户、后消费验证码，保证用户信息校验失败时验证码不被白白作废。

## 6. 提交前自检

- [ ] 表名、外键、中间表全部依赖约定，没有多余配置
- [ ] 关联声明了 `dependent`
- [ ] 数据库 `NOT NULL` 的列在模型中有 `presence` 校验
- [ ] 唯一性校验与数据库唯一索引成对出现
- [ ] 错误文案为中文，且不含英文属性名前缀
- [ ] 没有把 `password_digest`、`code_digest` 暴露给接口层
- [ ] 复杂业务规则收敛在模型方法中，控制器只负责参数与响应
