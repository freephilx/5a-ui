---
name: commit-now
description: 在本项目中检查 Git 变更、生成英文 Conventional Commits 信息并直接执行一次本地 git commit。用户明确要求 commit、提交当前变更或调用 commit-now 时使用。
---

# Commit Now

## 调用契约

- 用户明确要求提交本项目当前变更，或明确调用 `commit-now`，才视为执行提交的授权。
- 仅引用、创建或修改本 skill 不构成提交授权。
- 不把调用词后的附加文本自动当作 commit message、路径或参数；用户明确指定的提交范围和约束优先。
- 自行分析实际 diff 并完成以下提交流程，不调用其他 commit helper skill。

## 工作流

1. 运行 `git rev-parse --show-toplevel`、`git status --short` 和 `git diff --name-only --diff-filter=U`，确认仓库、变更状态及是否存在未解决冲突。后续命令在仓库根目录执行。
2. 运行 `git diff --staged --stat` 与 `git diff --staged` 检查暂存内容。
3. 暂存区为空但工作区有变更时：
   - 先检查未暂存 diff 和未跟踪文件内容，排除明显密钥、凭证及不应提交的临时文件或生成物。
   - 用户未限定范围且确认内容属于当前工作区变更后执行 `git add -A`；用户限定范围时仅暂存指定内容。
   - 重新读取完整 staged diff。
4. staged diff 仍为空时停止，报告没有可提交的变更。
5. 根据 staged diff 生成一条英文 Conventional Commits 信息。
6. 执行 `git commit -m "<message>"`；需要 body 或 footer 时使用多个 `-m` 参数。
7. 运行 `git show --stat --oneline --decorate -1` 和 `git status --short` 验证提交结果。
8. 报告 commit SHA、subject、提交范围和剩余未提交变更。

## Commit Message 规则

```text
<type>(<scope>): <description>

[optional body]

[optional footer]
```

- 全部文本使用英文，subject 使用祈使语气且末尾不加句号。
- 选择最准确的 `feat`、`fix`、`docs`、`style`、`refactor`、`test`、`chore`、`build`、`ci` 或 `perf`。
- 使用具体模块作为 scope；范围分散时可省略。
- 仅在必要时添加 body，说明动机、影响或不明显的行为变化。
- 破坏性变更使用 `!` 和 `BREAKING CHANGE:` footer。
- 只描述 staged diff 中实际存在的内容，不编造测试、issue 或迁移信息。

## 停止条件

- staged 内容包含疑似密钥、凭证、个人数据或明显不应提交的生成物。
- 当前不在 Git 仓库、存在未解决冲突，或无法安全判断提交范围。
- 用户限定的提交范围与现有 staged 内容冲突；保留现场并说明冲突。
- commit hook 或 `git commit` 失败。保留现场并报告错误，不使用 `--no-verify` 绕过。

## 安全边界

- 不执行 `git commit --amend`、force push 或破坏性 Git 命令。
- 不修改代码来消除 warning 或满足个人偏好。
- 暂存区已存在内容时只提交 staged diff，不自动加入其余工作区变更。
