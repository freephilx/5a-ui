## 2026-10-15 | Phase: GitHub Actions 打包 | Status: 完成

- **目标**: 参考最新 FlClash dev 的矩阵、Artifacts 和 tag 发布流程，为六平台提供可下载包。
- **变更**: 新增 Package workflow、标准库打包脚本、Windows 安装器和 Android 可选正式签名；支持六平台、手动选择、tag 版本校验、Artifacts 与 SHA-256；按 Mihomo 的滚动预发布方式，tag 直接发布正式版，非 tag 串行覆盖固定 pre-alpha，移动 tag、清理全部旧附件并记录来源；复用现有检查 workflow，显式安装 Android NDK r28c。
- **验证**: actionlint 和 19 项打包/发布测试通过，连同原有 Python 测试共 25 项通过；实际 macOS release / Universal DMG 构建成功。发布替换逻辑使用模拟 Git/GitHub 测试，未修改远端。
- **问题**: 新打包 workflow 尚未推送运行；平台正式证书未配置。上一轮 CI 的 Android 因 NDK 下载损坏失败，显式安装 NDK 的调整仍待 CI 复验。
- **下一步**: 推送后在 GitHub Actions 运行 Package；在对应平台验收产物，配置固定 Android 签名后发布。

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
