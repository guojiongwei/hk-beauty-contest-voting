---
name: rails-migration-conventions
description: "数据库迁移编写规范与自检清单。新增或修改表结构、调整列类型、NULL 约束、默认值或索引时使用，确保与现有迁移风格一致。"
---

# 数据库迁移设计规范与自检清单

> 本文件记录本项目迁移文件的编写约定：新增或修改表结构时按此执行，保证命名、列类型、NULL 约束与索引设计保持一致。

## 1. 命名与版本约定

- 文件名采用 Rails 标准格式 `YYYYMMDDHHMMSS_动词_表名.rb`，动词统一用 `create_`，一张表一个迁移；
- 类名与文件名一一对应（`20231027000001_create_users.rb` → `CreateUsers`），依赖 Rails 的 Zeitwerk 自动加载约定；
- 统一继承 `ActiveRecord::Migration[7.1]`，显式声明版本，保证未来 Rails 升级时行为可预期；
- 全部使用 `change` 而不是手写 `up/down`：`create_table`、`add_index` 均可逆，`bin/rails db:rollback` 开箱可用。

## 2. 表设计规范

1. **主键**：使用默认 `bigint` 自增主键，不自定义业务主键。手机号、用户名属于可变业务属性，做外键会带来级联更新成本。
2. **列类型**：
   - 手机号、用户名、摘要、URL 用 `varchar`，不用整数（前导 0、国家码、不参与运算）；
   - 简介这类长度不可预估的文本用 `text`；
   - 时间统一 `datetime`，交由 `t.timestamps` 维护 `created_at` / `updated_at`；
   - 计数用 `integer`（`attempts`），并配 `default: 0`。
3. **NULL 与默认值**：
   - 业务必需字段一律 `null: false`，把完整性交给数据库，不依赖应用层；
   - 只有语义上确实允许“未知/未发生”的列才允许 NULL：`candidates.description`、`candidates.photo_url`（资料后补）、`verification_codes.used_at`（NULL = 未使用）；
   - 能确定初始值的列直接给 `default`：`purpose default 'register'`、`attempts default 0`，减少插入时的空值判断。
4. **长度限制**：`phone_number` 限 20（兼容国际号码）、`code_digest` / 摘要类限 100（bcrypt 固定 60 字符，留算法升级余量）、`purpose` 限 20。

## 3. 索引规范

| 索引 | 目的 |
| --- | --- |
| `users.username` 唯一 | 登录查询 + 数据库层防重复注册 |
| `users.phone_number` 唯一 | 手机号登录 + 防重复注册 |
| `votes (user_id, candidate_id)` 唯一 | 防刷票最终防线，同时支撑“查某用户已投候选人” |
| `votes.user_id` / `votes.candidate_id`（`t.references` 自带） | 外键与按用户/候选人统计 |
| `verification_codes (phone_number, purpose, created_at)` | “取该手机号该用途最新验证码”与 60 秒限流判断 |
| `verification_codes.expires_at` | 定时任务清理过期验证码，防止表膨胀 |

原则：

- **唯一约束必须落在数据库**，应用层 `uniqueness` 校验只做友好提示，不能作为唯一防线；
- 联合索引把**等值条件放前、排序字段放后**（`phone_number, purpose` 等值 → `created_at` 排序），可直接命中 `ORDER BY created_at DESC LIMIT 1`；
- 不给 `verification_codes.phone_number` 单独建唯一索引：同一手机号必然有多条历史记录；
- 索引不是越多越好，只为真实查询路径建索引，避免拖慢写入。

## 4. 关键业务约束的落点

- 防刷票：`(user_id, candidate_id)` 联合唯一索引 + 模型 `uniqueness` + 控制器捕获 `ActiveRecord::RecordNotUnique`，三层防护；
- 投票人身份：`votes.user_id` 通过 `t.references :user, null: false, foreign_key: true` 建立外键，保证不会出现指向不存在用户的脏数据；
- 手机号验证：验证码独立成表，因为未注册手机号没有 `users` 记录，且需要保留历史用于限流与审计。

## 5. 提交前自检

- [ ] 一张表一个迁移，命名与类名符合 Rails 约定
- [ ] 所有业务必需字段 `null: false`
- [ ] 能确定初始值的字段有 `default`
- [ ] 唯一业务约束有数据库唯一索引
- [ ] 联合索引字段顺序与真实查询一致
- [ ] 外键列有索引（`t.references` 默认自带）
- [ ] 迁移可在空库上 `db:migrate` 成功，且可 `db:rollback` 回滚
- [ ] 迁移后 `db/schema.rb` 已同步提交
