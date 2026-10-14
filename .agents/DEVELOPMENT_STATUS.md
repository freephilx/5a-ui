## 2026-10-15 | Phase: Flutter 迁移 | Status: 本地首版完成，跨平台验收待补

- **目标**: 完成 Flutter 跨平台首版及 Dart SSH/Web 后端。
- **变更**: Flutter 3.47.6 / FVM 固定；六平台工程、自适应 UI、密码与私钥 SSH、部署轮询、指纹固定、节点二维码与导出；共享 Dart 核心、Dart Web 服务、Docker 和云平台配置、CI 与文档。
- **验证**: Web/macOS 构建、Dart AOT 后端、99 项自动测试、真实本机 Dart/workerd SSH 与 Cloudflare dry-run 通过。完整记录见 `docs/verification.md`。
- **问题**: Docker daemon 不可用；Android/iOS/Linux/Windows 尚未本机打包；尚未运行新 CI 或发布 Flutter 版本；真实 Turnstile 和新安装端到端验收待补。
- **下一步**: 在对应平台运行 CI/设备构建，启动 Docker 后验证镜像，在隔离服务器完成新客户端安装全流程。

## 2026-10-14 | Phase: Flutter 迁移 | Status: 开始实施

- **目标**: 完成 Flutter 跨平台首版及 Dart SSH/Web 后端。
- **变更**: 计划见 plan-2026-10-14-flutter-app.md；已有 React + TypeScript API 与服务器脚本可复用。
- **问题**: 待验证全部构建环境；不使用生产服务器做安装测试。
- **下一步**: 固定 FVM、实现共享 Dart 包和 Flutter UI、接入部署与回归（已在上方首版实现）。
