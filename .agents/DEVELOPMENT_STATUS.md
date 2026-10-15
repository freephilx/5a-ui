## 2026-10-15 | Phase: SSH 测试稳定性 | Status: 修复完成，本地验证通过

- **问题**: 提交 `237a2cf` 的 CI 在 Workers 加密 Ed25519 测试中随机失败；原生五平台构建均通过。定向复现确认 `ssh2@1.17.0` 的测试密钥生成器误删 Ed25519 公钥的有效前导零字节，生成 31 字节公钥并被解析器正确拒绝。
- **变更**: Dart / Workers 两套 SSH 测试共用 OpenSSH `ssh-keygen` 生成 Ed25519 主机及客户端密钥，保留六种认证覆盖；临时密钥读取后立即清理，README 补充测试环境依赖。
- **验证**: 本地生成资源检查、TypeScript 检查及 59 项测试、Dart / workerd 真实 SSH 验证通过；前导零公钥在未加密及加密后均可解析并通过签名验证。本机 FVM 3.47.6 的缺失引擎缓存与项目依赖已补齐。
- **下一步**: 修复提交推送后由 Check and build 复验完整检查与六平台构建；运行结果以对应提交的 GitHub Actions 为准。

## 2026-10-15 | Phase: 已有 3x-ui 接入 | Status: 实现完成，本地验证通过

- **目标**: 统一接入服务器已有的 3x-ui，不以是否由本项目部署作为管理条件。
- **变更**: 实现原生/systemd 与 Docker 多实例发现、SQLite 新旧客户端结构和 PostgreSQL 读取、入站与客户端流量/状态及常见协议分享；同步 Dart/TypeScript 契约、Flutter 实例选择与节点详情。已有实例直接接入，保留账号、节点、订阅及服务配置，旧失败标记不再绕过外部实例检查；AGENTS 与 README 已同步。
- **验证**: 152 项测试、Flutter analyze、TypeScript 检查、生成资源校验与 Web release 构建通过；真实临时 SQLite/WAL 和隔离模拟 API 浏览器验证通过，覆盖多实例、异常、只读保护、窄屏和二维码/复制。详见 `docs/verification.md`。
- **问题**: Docker 与 PostgreSQL 目前通过模拟验证，尚未完成真实环境接入验收；非常规安装布局和特殊分享配置需要后续适配。
- **下一步**: 在可用的隔离 Linux / Docker / PostgreSQL 环境补充真实接入验收；当前能力为读取与节点分享，后续再扩展配置编辑和服务启停。

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
