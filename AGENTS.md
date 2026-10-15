# 项目 Agent 约定

## 项目目标

- 项目名称统一为 `5a-ui`，用于管理 3x-ui / 3m-ui 的一键部署与连接后功能；一键部署默认选择 3x-ui 并创建节点，用户可选 3m-ui（Mihomo）。
- 支持用户选择 cfnew，在 Cloudflare Workers 创建独立服务与 KV 配置存储；其账号/API Token 部署流程独立于服务器 SSH，不混用 3x-ui / 3m-ui 接口。
- 管理能力不以安装来源为条件：服务器上已有的 3x-ui / 3m-ui（手动安装、其他脚本安装、Docker 或本项目部署）均应可以接入，同一服务器支持多实例、多入站和多客户端。两类面板分别使用其真实接口、认证和配置模型，不将 Xray 接口用于 Mihomo。
- 接入已有实例时保留其账号、节点、订阅和服务配置；`.managed` 只用于识别本项目未完成安装的恢复流程，不能作为读取或管理已有服务的门槛。无法识别或读取时应明确说明，不能误判为未安装后覆盖部署。
- 支持生成 Android、iOS、macOS、Windows、Linux 和 Web 应用。
- Web 支持本地直接启动、Docker 部署，以及 Vercel 和 Cloudflare 的完整一键部署，包括页面和执行 SSH 所需的后端能力。

## 技术架构

以下为本项目采用的架构，各平台的实际验证范围记录在 `docs/verification.md`。

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

## Flutter 版本管理

- 本项目 Flutter SDK 版本必须与 [FlClash 的 dev 分支](https://github.com/chen08209/FlClash/tree/dev) 的正式构建版本保持一致，以其 `.github/workflows/build.yaml` 中的 `FLUTTER_VERSION` 为准。首次配置或调整版本前，先按下方参考仓库更新规则获取最新代码。
- 统一通过 FVM 管理和切换 Flutter SDK，在本项目根目录执行 `fvm use <FlClash 使用的 Flutter 版本>`，并将生成的项目版本配置 `.fvmrc` 纳入版本控制。
- Flutter 和 Dart 命令统一使用 `fvm flutter ...`、`fvm dart ...`，确保依赖安装、开发、分析、测试和构建使用项目指定的 SDK。
- 本项目 `.fvmrc` 是本地和 CI 的版本来源。GitHub Actions 使用 `flutter-action` 安装该版本；云平台与 Docker 构建也读取该配置。

## 开发与验证

- `lib/` 为 Flutter 客户端，`packages/five_a_core/` 为纯 Dart 核心与原生 SSH，`server/` 为本地和 Docker 使用的 Dart 后端。
- `src/server/`、`api/` 和 `src/worker.ts` 仅承载 Vercel/Cloudflare 的必要 TypeScript 适配。
- 远端脚本源文件位于 `scripts/remote/`；修改后运行 `fvm dart run tool/generate.dart`，同步生成 Dart 和 TypeScript 资源，不直接编辑生成文件。
- 共用接口样例和公网地址规则位于 `contracts/`；改动契约时同步运行 Dart、TypeScript 及跨语言一致性测试。
- 开发计划与当前进展记录在 `.agents/`。本地完整 Web 服务通过 `fvm dart run tool/dev.dart` 启动。

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
