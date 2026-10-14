# Flutter 跨平台首版

## 目标与范围

将现有 React 客户端迁移为 Flutter，保留已验证的 systemd 安装任务和服务器管理脚本。提供六个平台的工程入口，原生客户端内置 Dart SSH；本地 Web 与 Docker 使用 Dart API；Vercel 和 Cloudflare 保留必要的 TypeScript SSH 适配。

## 实施步骤

1. 对齐 FlClash dev 的 Flutter 3.47.6，通过 FVM 固定 SDK；阅读最新视觉实现。
2. 提取共享远端脚本模板，建立纯 Dart 核心包（契约、校验、结果解析、SSH）。
3. 实现 Flutter 自适应界面、密码/私钥连接、部署与轮询、主机指纹、节点链接和二维码、明暗主题。
4. 实现 Dart 本地 API/静态服务器及单命令启动，增加 Docker 打包。
5. 将 Vercel/Cloudflare 静态构建切换至 Flutter，保留 Turnstile 和现有 SSH 防护。
6. 验证 Dart/TS 契约、真实本地 SSH、Flutter 界面、Web/本机打包和现有回归；同步 README 与构建 CI。

## 验收

- Flutter 客户端在窄屏与桌面布局均可用，无占位按钮；密码与私钥不持久化。
- 原生应用通过 Dart SSH 执行，Web 通过同源 POST API；部署在远端 systemd 后台继续。
- Dart/TS 生成相同远端命令，使用相同响应结构与公共 IP 限制。
- 本地 Web 一条命令启动完整服务；Docker 与云平台构建入口完整。
- 如实记录未能在当前主机验证的平台，未使用生产服务器执行安装。

## 实施结果（2026-10-15）

六步首版实现已完成。Web 和 macOS 构建、Dart AOT 后端、Dart/TypeScript/Python 测试、真实本机 SSH 回归及 Cloudflare dry-run 已通过。当前仍需其他原生平台设备验收、Docker 镜像运行和新版本云部署验证，详见 `../docs/verification.md`（仓库根目录下的 `docs/verification.md`）。本轮未执行生产安装或发布。
