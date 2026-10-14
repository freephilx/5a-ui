# 项目 Agent 约定

## Git 提交

- 在本项目执行提交时，必须先读取并使用项目级 [commit-now](.agents/skills/commit-now/SKILL.md) skill。
- 用户要求 `commit`、提交当前变更或调用 `$commit-now` 时，统一使用此 skill；不调用全局 `douban-commit-now` 或其他 commit helper skill。
- 提交授权、暂存范围、英文 Conventional Commits 信息生成、停止条件和提交结果验证，均按此 skill 执行。
