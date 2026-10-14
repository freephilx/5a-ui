# 项目 Agent 约定

## 项目目标

- 项目名称统一为 `5a-ui`，用于管理 3x-ui 的一键部署和状态读取。
- 支持生成 Android、iOS、macOS、Windows、Linux 和 Web 应用。
- Web 支持本地直接启动、Docker 部署，以及 Vercel 和 Cloudflare 的完整一键部署，包括页面和执行 SSH 所需的后端能力。

## 技术架构

以下是后续开发和迁移的目标架构，不代表当前仓库已完成 Flutter 迁移。

- 优先使用 Flutter + Dart。Flutter 负责界面与交互，Dart 负责可复用的业务逻辑、SSH 操作、部署和状态查询。
- 能通过 Flutter + Dart 独立完成的平台应独立完成，非必要不同时引入 Flutter 和 JS/TS。
- Android、iOS、macOS、Windows、Linux 应用直接通过 Dart 执行 SSH；这些能力在应用内运行，不依赖额外的本地或远程后端服务。
- Flutter Web 运行在浏览器中，不能直接建立普通 SSH 连接，必须通过后端 API 执行 SSH。

| 运行方式 | 技术分工 |
| --- | --- |
| Android、iOS、macOS、Windows、Linux | Flutter 客户端 + 应用内 Dart SSH 实现 |
| 本地 Web | Flutter Web + 本地 Dart 后端，提供一条命令启动完整服务 |
| Docker | 打包 Flutter Web 静态产物与 Dart 后端，提供直接启动的部署方式 |
| Vercel、Cloudflare | Flutter Web + 必要的 JS/TS 平台后端适配，使用平台标准运行时承载完整服务，无需额外服务器 |

- JS/TS 仅用于 Dart 无法在目标平台标准运行时直接承担的必要适配，不将所有平台统一绑定到 TS 后端，也不扩展为另一套客户端。
- Dart 与 JS/TS 实现使用一致的接口约定、状态格式和共用服务器安装脚本，保持部署与状态查询行为一致；修改相关契约时同步更新受影响的实现和验证。
- 安装任务在目标服务器上通过 systemd 后台执行；客户端或 Web 后端负责启动任务和查询状态，关闭应用、页面或结束 API 请求不应中断安装。

## 视觉参考

- 本项目视觉参照 [FlClash 的 dev 分支](https://github.com/chen08209/FlClash/tree/dev)，本地参考仓库固定放在 `~/github/FlClash/`。
- 每次进行视觉设计、页面开发、样式调整或 UI 审查前，都必须先将参考仓库更新到远端 `dev` 分支的最新代码，再读取相关实现，不仅依赖既有印象或旧副本。
- 如果 `~/github/FlClash/` 不存在，直接执行 `mkdir -p ~/github`，再执行 `git clone --branch dev https://github.com/chen08209/FlClash.git ~/github/FlClash` 创建并获取代码。
- 如果目录已存在，确认它对应上述仓库，获取远端更新，切换到本地 `dev` 分支（不存在时从 `origin/dev` 创建跟踪分支），并将其快进到 `origin/dev` 的最新版本；保留已有本地改动，不强制覆盖。目录不是对应仓库或更新失败时，如实说明原因，不将旧副本视为最新代码。
- 参照最新代码中的配色、字体、间距、圆角、组件样式、导航布局、明暗主题及多端适配方式，结合 `5a-ui` 的部署和状态管理功能设计界面。

## Git 提交

- 在本项目执行提交时，必须先读取并使用项目级 [commit-now](.agents/skills/commit-now/SKILL.md) skill。
- 用户要求 `commit`、提交当前变更或调用 `$commit-now` 时，统一使用此 skill；不调用全局 `douban-commit-now` 或其他 commit helper skill。
- 提交授权、暂存范围、英文 Conventional Commits 信息生成、停止条件和提交结果验证，均按此 skill 执行。
