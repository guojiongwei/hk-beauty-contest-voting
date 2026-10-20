---
name: git-commit-workflow
description: "本仓库的分段提交工作流。需要提交代码、整理提交历史、按阶段拆分变更时使用，确保每次提交只包含一个独立主题。"
---

# Git 分段提交工作流

## 核心原则

1. 一个提交只表达一件事，禁止把所有改动堆进一个 commit。
2. 提交前必须执行 `git status` 与 `git diff --stat`，确认文件范围。
3. 禁止提交 `.env`、数据库密码、日志、临时脚本。
4. 未经用户明确要求，不执行 `git push`，不使用 `--force`。

## 推荐提交切分

| 阶段 | 提交信息 |
| --- | --- |
| 工程基座 | `chore: 初始化 Rails API 工程与协作规范` |
| 配置与迁移 | `feat: 添加数据库迁移与基础配置` |
| 模型 | `feat: 添加用户/候选人/投票模型及校验` |
| 控制器 | `feat: 实现 JWT 认证与投票核心接口` |
| 文档 | `docs: 补充 API 文档与设计说明` |
| 修复 | `fix: 修复 <具体问题>` |

## 执行步骤

```bash
git status
git diff --stat
git add <明确列出的文件>
git commit -m "<类型>: <中文说明>"
git status
```

## 提交信息规范

- 类型：`chore` / `feat` / `fix` / `docs` / `refactor` / `test`
- 描述说明“为什么改”，而不是简单罗列文件名。
- 不添加无意义的 `update`、`change` 之类描述。

## 检查清单

- [ ] 暂存区只包含本次主题相关文件
- [ ] 没有敏感信息
- [ ] 提交信息符合 Conventional Commits
- [ ] 提交后工作区状态符合预期
