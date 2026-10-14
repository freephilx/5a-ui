# 验证记录

## GitHub Actions 打包（2026-10-15）

- 参考 FlClash dev `53838773` 的构建矩阵、Artifacts 和 tag 汇总方式。新增独立 Package workflow，支持手动选择平台和 `v*` tag，版本由 `.fvmrc` / `pubspec.yaml` 提供。
- 包含 Android 分 ABI APK / AAB、iOS 未签名 IPA、macOS Universal DMG、Windows x64 安装器 / ZIP、Linux x64 / ARM64 DEB / tar.gz，以及 Web 静态包和 Linux x64 完整服务包。版本 tag 构建成功后直接公开发布正式 Release；非 tag 构建发布到固定 `pre-alpha`，标为 Pre-release，不占用正式版 Latest。
- 核对 [Mihomo 的 Prerelease-Alpha](https://github.com/MetaCubeX/mihomo/releases/tag/Prerelease-Alpha) 及 Alpha 分支 workflow，采用其移动预发布 tag、清理旧附件后上传的方式。所有非 tag 打包串行执行；单平台构建也完整替换旧附件，发布说明记录当前提交、平台与构建链接。实际覆盖发布仍待远端运行验证。
- `actionlint 1.7.7` 检查两份工作流通过；19 项打包/发布测试及原有 6 项 Python 测试通过。覆盖版本与 tag 对齐、手动 tag 仍为正式版、不同分支/版本共用 pre-alpha、首次发布、旧附件清理、正式版不移动 tag、不清理附件、API/推送失败停止操作，以及平台选择、签名、归档内容、权限、符号链接和 SHA-256。发布相关测试模拟 Git/GitHub 调用，不修改远端。
- 本机实际完成 macOS release 构建及 DMG 打包，验证 app / Dart AOT / Flutter 引擎均包含 arm64 和 x86_64；DMG 完整性、应用签名与 SHA-256 校验通过。
- 上一版提交 `f6c5eb1` 的 [GitHub Actions 检查](https://github.com/freephilx/5a-ui/actions/runs/38601664459) 中，verify、iOS、macOS、Windows、Linux 均通过；Android 在自动下载 NDK 28.2.13676358 时因 ZIP 损坏失败。当前检查和打包流程改为参照 FlClash 显式安装 NDK r28c，尚未推送复验。
- 本轮未执行新 workflow、发布 tag 或创建远端 Release。Windows 安装器、Linux DEB 和 iOS IPA 的归档逻辑经过测试，实际跨平台安装包仍需 GitHub runner 构建和对应设备验收；Android 正式签名、Apple 公证和 iOS 重签、Windows Authenticode 尚未验证。

## Flutter 首版（本地，2026-10-15）

本轮将客户端迁移为 Flutter，增加应用内 Dart SSH 和本地 / Docker Dart 后端。Flutter 由 FVM 固定为 3.47.6，与 FlClash dev 正式构建配置一致；参考仓库已更新至 `53838773`。下面记录的是新实现的本机验证，后面的历史线上验证不代表 Flutter 版本已发布。

### 自动检查与真实本地 SSH

- `fvm flutter analyze` 通过。
- Flutter 5 项测试通过：320×740、390×844、1280×900 的连接与校验、节点结果和详情、主题设置及清除凭据；取消请求后的过期响应丢弃；轮询固定主机指纹并在就绪后停止。
- Dart 核心 28 项、Dart 后端 5 项、TypeScript 55 项和 Python 6 项测试通过。
- 共享契约覆盖输入校验、公网地址限制、IPv4 映射 IPv6 和远端结果过滤；Dart 与 TypeScript 生成的安装和状态命令逐字一致。
- 本机临时 SSH 服务验证 Dart 的密码、Ed25519 OpenSSH、加密 Ed25519 OpenSSH、加密 RSA PKCS#8、EC PKCS#8 和加密 RSA PEM。错误认证、主机指纹变化、输出上限、sudo 错误、超时和取消均通过。私钥解码改为独立 isolate 后重新通过验证。
- 真实 workerd 本机 SSH 回归通过上述六种认证方式，以及主机指纹、跨站请求和私网 IP 拒绝检查。

### 构建与运行

- Flutter Web release 构建和 `pnpm build` 云平台构建入口通过，渲染引擎随静态产物打包。
- macOS debug 构建通过，实际启动并检查界面；初始窗口按屏幕空间设置为最大 1200×800，允许缩小并切换移动布局。
- Dart 后端 AOT 编译通过。独立可执行文件的 `/api/health`、`/api/config`、首页和前端路由返回正常，私网目标返回 `PRIVATE_HOST`。
- `fvm dart run tool/dev.dart --skip-build` 启动的完整 Web 服务正常；真实浏览器验证连接表单、错误提示和清除输入，未发现控制台警告或错误。
- Cloudflare `wrangler deploy --dry-run` 通过，包含 Flutter 静态资源和 Worker 配置；未执行远端发布。
- Compose 配置、GitHub Actions YAML、构建脚本语法、生成资源新鲜度、TypeScript 检查和 diff 空白检查通过。

### 当前验证边界

- Android、iOS、Linux、Windows 已有工程与 CI 构建任务，尚未在本机完成打包或真机验收；本轮 CI 尚未推送运行。
- Docker 配置已完成，但本机 Docker daemon 不可用，尚未构建或运行镜像。
- Flutter 版本尚未部署至 Cloudflare 或 Vercel。Turnstile 后端有自动测试，未做真实 widget 全流程验证。
- 本轮未在用户服务器上执行新安装；继续使用下方历史验证过的 systemd 任务与管理脚本，抽取后的启动、状态模板有跨语言一致性测试。
- 当前客户端一次管理一台服务器，凭据和节点结果只在本次会话内存中保留。

## 历史 React / TypeScript 版本（2026-10-14）

以下是迁移前的验证与部署记录。

### 自动检查

- TypeScript 类型检查和 Vite 生产构建通过。
- 28 项 API 与输入校验测试通过。
- 6 项 Python 测试通过，覆盖实际 HTTP 请求、重试复用、已有节点保护、敏感信息过滤和订阅服务关闭。
- 真实 workerd 连接 SSH：密码、Ed25519 OpenSSH、加密 RSA PEM、加密 Ed25519 OpenSSH、加密 RSA PKCS#8、EC PKCS#8 均通过；错误主机指纹、跨站请求、私网 IP 被拒绝。

### 远程安装与连接

在用户提供的 Oracle ARM64 主机上，用临时 Ubuntu 24.04 容器运行完整 systemd 与 SSH。容器使用独立文件系统、网络和 cgroup；SSH 仅映射到宿主机回环地址，由本地 SSH 隧道连接。应用输入校验仍使用公网 IP，只有测试用的 SSH 传输地址映射到隧道。没有开放额外的公网端口。

- workerd 执行实际 SSH 安装：3x-ui 3.10.0、Xray 26.10.10。
- 安装任务在 SSH 请求结束后继续运行，后续请求读取进度，最终返回运行状态与 VLESS URI。
- 重复安装返回同一节点，无重复创建。
- 使用真实 Xray 客户端完成 REALITY 握手，通过 SOCKS 代理访问 HTTPS 网站成功。
- API 返回实际上传和下载流量，服务重启后状态与节点恢复正常。
- 面板监听回环地址，默认订阅端口 2096 关闭；更新后的首次安装也完成复验。
- 浏览器上传一次性私钥后，成功读取节点、展示二维码和复制链接。

宿主机本身已有 3x-ui。部署到 Cloudflare 后，使用指定 Oracle 凭据验证线上 API：读取状态返回 `existing`，安装接口返回 `EXISTING_INSTALLATION`。宿主机没有创建本项目安装目录，原有 Caddy、3x-ui 和 3m-ui 的进程保持不变，健康检查正常。

验证结束后已移除临时容器、测试镜像和远程构建目录，关闭本地测试服务与 SSH 隧道，删除一次性测试密钥。

### 页面操作改版（2026-10-14）

- 页面收敛为服务器连接、节点结果两个区域，用户名直接可见，高级设置和使用帮助默认折叠。
- 使用独立本地模拟 API 验证密码、粘贴私钥、文件选择、口令输入、缺少私钥提示、隐藏高级字段校验及清除凭据；未连接真实 SSH 服务器。
- 验证未安装、已有安装、认证失败、安装失败重试、进度自动轮询、暂停与恢复、端口不可达，以及二维码、复制链接和运行详情。
- 检查桌面双栏及 320、390 像素手机单栏布局，修正窄屏横向溢出。生产构建与 28 项现有测试通过；真实本地 API 拒绝私网 IP，错误提示和清除操作正常。
- 改版已部署到现有 Cloudflare 站点，线上页面与配置加载正常。上述界面验证不替代前面的真实服务器安装回归。

### 页面精简（仅本地，2026-10-14）

- 首页改为单列表单，移除介绍标语和空结果面板；操作后才显示进度与节点，帮助和更多设置默认收起。
- 本地隔离模拟 API 验证私钥缺失提示、粘贴私钥与口令、隐藏字段校验、清除凭据、进度轮询与暂停恢复、已有安装和失败重试入口、二维码及连接详情；未操作真实服务器。
- 320 像素窄屏无横向溢出，类型检查、构建及 28 项现有测试通过。
- 更新已由本地 5000 端口服务加载；没有部署到 Cloudflare 或 Vercel。

### 当时的验证范围

- Cloudflare 实际部署与线上 SSH 已验证；Vercel 已提供部署配置，尚未实际发布。
- 完整安装和客户端验证在 Ubuntu 24.04 ARM64 隔离环境完成，尚未覆盖 Debian、AMD64 或全新云主机的公网防火墙组合。
- 公网站点启用了原生限流。当前 Cloudflare API Token 缺少 `Turnstile Sites Write` 权限，创建 widget 返回 403；代码已支持 Turnstile，但公网站点尚未配置。
- 加密私钥经过本地 workerd 验证；不同 Cloudflare 套餐的 CPU 配额仍需部署者确认。
