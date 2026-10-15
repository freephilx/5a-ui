# cfnew 一键部署

- 用户指定来源：https://huarun.win/servers/cfnew，对应 byJoey/cfnew v3.1。它运行在 Cloudflare Workers/Pages，独立于 SSH 服务器部署；现有默认 3x-ui 与可选 3m-ui 保留。
- 增加 Cloudflare 入口，通过用户输入的账号 ID 和 API Token 在所属账号创建专用 Worker 与 KV C，生成随机 UUID，启用 workers.dev，返回管理/订阅链接。原生用 Dart HTTP；Web 用同源 Dart/TypeScript 后端，契约一致。
- 仅下载固定上游提交的明文代码并校验 SHA-256，不复制上游到项目或打包产物。版本 v3.1、提交 a327f9ca5adac1f605fb2cd33415daad1d75d444、兼容日期 2026-01-20。
- 分阶段请求避免云函数超时；校验资源归属，拒绝覆盖已有同名 Worker，失败保留可重试现场而不自动删除资源。只保留会话内 Token。默认生成原生 TLS VLESS 节点，第三方优选/家宽链式由用户在原面板按需启用。
- 验证输入/权限/冲突/故障重试/读回/跨语言契约、Flutter 流程与窄屏、本地 workerd 实际上游运行时；构建 Web/macOS 并打开新版。不擅自使用本机 Cloudflare 凭据发布，线上验收如未进行需明确记录。

## 完成情况

- 部署入口、四阶段流程、原生/Dart Web/云 TypeScript 后端、白名单契约与回读验证已实现。
- 已通过分析、类型、单元/契约测试与本地 workerd 实际上游回归；已补充失败重试和导航保留交互测试；正式 Web/macOS 构建、Cloudflare dry-run 和实际合成浏览器/原生入口验证通过，临时材料已清理。
- 未运行真实 Cloudflare 账号部署、代理握手、其他设备平台或 Pages 发布；限制见 `docs/cfnew-deployment.md`。
