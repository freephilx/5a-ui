# 5a-ui

使用自己的服务器密码或 SSH 私钥，一键部署 3x-ui 和 VLESS + REALITY，读取安装进度与节点状态。Flutter 客户端面向 Android、iOS、macOS、Windows、Linux 和 Web。

## 功能

- 密码、OpenSSH / RSA / EC 私钥登录；支持加密私钥与 RSA / EC PKCS#8。
- 一键部署、安装进度轮询、失败重试、已有节点复用，以及已有其他 3x-ui 安装保护。
- 查看服务运行状态、CPU、内存、节点流量和节点 TCP 端口可达性。
- 复制 VLESS 链接、显示二维码、导出节点文件。
- 自适应桌面侧栏和移动端导航，支持系统、浅色和深色主题；视觉参考 FlClash dev。
- 安装通过目标服务器的 systemd 后台执行。关闭应用、停止本地后端或暂停刷新都不会中断已启动的安装。
- SSH 密码、私钥、口令与节点结果只保留在当前会话内存；不写入本地存储或数据库。当前版本一次管理一台服务器。

## 技术结构

| 平台 | 客户端与 SSH 执行方式 |
| --- | --- |
| Android / iOS / macOS / Windows / Linux | Flutter + 应用内 Dart SSH，无额外后端 |
| 本地 Web | Flutter Web + Dart API，一条命令启动 |
| Docker | Flutter Web 静态文件 + 编译后的 Dart 服务 |
| Vercel | Flutter Web + Node.js API Functions |
| Cloudflare | Flutter Web + Workers 平台适配，直接建立 SSH 连接 |

Dart 和 TypeScript 使用同一份远端脚本模板、公网地址限制和接口样例。`contracts/` 及跨语言测试检查接口与生成命令是否一致。服务端 SSH 凭据仅在当前请求内使用，不提供任意命令执行接口。

## Flutter 与 FVM

Flutter 与 FlClash dev 的正式构建版本一致，目前为 **3.47.6**。本项目 `.fvmrc` 是本地、GitHub Actions、Docker 和云平台构建的统一版本来源。

```sh
fvm install
fvm flutter pub get
```

本地统一使用 `fvm flutter` 和 `fvm dart`。GitHub Actions 从 `.fvmrc` 读取版本，通过 `subosito/flutter-action` 安装。云平台构建机没有 Flutter 时，构建脚本自动获取指定版本的 SDK。

## 本地 Web：一条命令

```sh
fvm dart run tool/dev.dart
```

该命令生成共享脚本、安装 Dart 依赖、构建 Flutter Web 并启动 Dart 后端，无需 Node.js、pnpm 或额外服务器。默认地址为 `http://127.0.0.1:5000`。

端口被占用时可指定 `PORT=5050`；需要局域网访问时指定 `LOCAL_HOST=0.0.0.0`：

```sh
PORT=5050 fvm dart run tool/dev.dart
# Web 已构建且没有修改前端时，可跳过构建
fvm dart run tool/dev.dart --skip-build
```

Web 的前端与 API 使用同一地址。此启动方式运行构建产物；修改前端后重新启动构建即可。已安装 Node/pnpm 时，`pnpm start` 是相同命令的别名。

## 原生应用

安装目标平台所需的 Flutter 工具链后运行：

```sh
fvm flutter run -d macos
fvm flutter run -d windows
fvm flutter run -d linux
# Android / iOS：先查看设备，再指定目标
fvm flutter devices
fvm flutter run -d <device-id>
```

发布构建：

```sh
fvm flutter build apk --release
fvm flutter build appbundle
fvm flutter build ipa
fvm flutter build macos --release
fvm flutter build windows --release
fvm flutter build linux --release
```

iOS 需在 Xcode 中配置自己的开发团队和签名；Android 商店发布需配置自己的发布签名。原生应用的 SSH 在应用内执行，不需要启动 `server/`。macOS 已配置出站网络和用户选中文件读写权限；Android 已配置网络权限。

## GitHub Actions 打包

参考 FlClash 的平台矩阵、Artifacts 和 tag 汇总流程，使用独立的 **Package** workflow（`.github/workflows/build.yaml`）。SDK 仍从 `.fvmrc` 读取，版本号和构建号来自 `pubspec.yaml`。

- **tag 构建 → 正式版**：推送 `v*` tag 时构建全部平台。tag 必须与 `pubspec.yaml` 的版本一致，例如 `version: 0.2.0+2` 对应 `v0.2.0`。全部成功后汇总安装包与 `SHA256SUMS`，直接公开发布对应版本的正式 Release（非草稿、非预发布）；手动在版本 tag 上运行也按此规则发布。
- **非 tag 构建 → pre-alpha**：在 Actions → Package → Run workflow 选择分支及 `all` 或某个平台。成功后覆盖固定的 [pre-alpha Release](https://github.com/freephilx/5a-ui/releases/tag/pre-alpha)，标记为 Pre-release，不占用正式版 Latest。参照 [Mihomo 的滚动预发布](https://github.com/MetaCubeX/mihomo/releases/tag/Prerelease-Alpha)，始终只保留最新一轮产物；`pre-alpha` tag 同步指向该次提交，包名固定使用 `5a-ui-pre-alpha-…`，发布说明记录提交与构建链接。
- 覆盖 `pre-alpha` 时会删除此前的全部附件，再上传本次产物和校验文件；只选单个平台时，Release 也只保留该平台的本次产物。需要完整六平台下载时选择 `all`。所有非 tag 打包共用串行队列，避免不同分支或平台相互覆盖上传过程。
- 每次构建同时保留 Actions Artifacts 14 天。首次使用手动入口前，workflow 需要合入默认分支。打包前复用 **Check and build** 的分析、测试和契约检查；普通分支 push / PR 仍执行检查，不自动触发打包。
- 应用内部版本号和构建号仍使用 `pubspec.yaml`，以满足各平台安装器的版本格式；GitHub 发布渠道由是否为版本 tag 决定，tag 包名使用对应版本号。

| 平台 | 打包产物 |
| --- | --- |
| Android | armeabi-v7a / arm64-v8a / x86_64 APK，以及 AAB |
| iOS | arm64 `unsigned.ipa`，需自行重新签名后安装 |
| macOS | Universal DMG，同时包含 Intel 和 Apple Silicon |
| Windows | x64 安装 EXE、便携 ZIP，附带 VC++ 运行库 |
| Linux | x64 / arm64 DEB、tar.gz；需要 GTK 3 和桌面文件选择 portal |
| Web | 静态 ZIP，以及含 Dart 后端的 Linux x64 完整服务 tar.gz |

Linux x64 和 Web 服务基于 Ubuntu 22.04 构建，Linux ARM64 基于 Ubuntu 24.04。Linux ARM64 按 FlClash 的方式使用 `flutter-action` 的 `master` 安装通道检出 `.fvmrc` 指定的精确 tag，仍然使用固定 SDK 版本。

Web 完整服务包解压后运行 `./start.sh`，默认地址为 `http://127.0.0.1:5000`，无需安装 Flutter 或 Dart。静态 ZIP 必须配合本项目后端 API 使用，不能独立执行 SSH。

### 签名配置

在仓库 Settings → Secrets and variables → Actions 配置以下四项后，Android release 包使用固定密钥签名：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 文件的单行 Base64 |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_STORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_PASSWORD` | key 密码 |

四项必须同时配置。未配置时仍能打包，但 APK / AAB 名称带 `test-signed`，使用 CI 临时调试签名，不能用于正式分发或保证跨构建覆盖升级。keystore 仅写入 runner 临时目录，完成后删除，不进入仓库或产物。本地正式签名使用同名的 alias/password 环境变量及 `ANDROID_KEYSTORE_PATH` 文件路径。

macOS 当前使用 ad-hoc 签名，未公证；Windows 安装程序未配置 Authenticode；iOS 未签名。工作流不会自动申请证书或发布到应用商店。

## Docker

```sh
docker compose up --build -d
```

访问 `http://127.0.0.1:5000`。镜像构建读取 `.fvmrc`，同时编译 Flutter Web 和 Dart 服务；运行镜像使用非 root 用户，不需要 Node.js。

如通过 HTTPS 反向代理访问，请在 `.env` 中设置 `PUBLIC_ORIGIN=https://你的域名`，使同源校验与访问地址一致。需要对外开放监听时调整 Compose 端口绑定，并由反向代理提供 HTTPS。

## Cloudflare

需要 Node.js 22.12+ 和 pnpm 11。

```sh
pnpm install --frozen-lockfile
pnpm exec wrangler login
pnpm deploy:cloudflare
```

部署命令构建 Flutter Web，并将 `build/web` 和 SSH Worker 一同发布，无需额外服务器。Worker 名称为 `5a-ui`；配置包含每分钟 60 次请求、3 次安装的原生 IP 限流，并关闭应用日志记录。

Workers 使用 NIST P-256 密钥交换、AES-CTR 和 SHA-2 HMAC，关闭 SSH 压缩和可选原生加速模块。生产部署需确保 CPU 配额支持 SSH 握手与加密私钥解密，建议使用 Workers Paid。

通过 Workers Builds 部署时，将构建命令设为 `pnpm build`，部署命令设为 `pnpm exec wrangler deploy`。

## Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Ffreephilx%2F5a-ui)

导入仓库后选择 **Other** 框架。`vercel.json` 已配置 Flutter 构建命令、`build/web` 输出目录和 Node.js API Functions；不要使用 Edge Runtime。页面和 SSH 后端随一次部署一同发布。

也可在项目根目录使用 Vercel CLI 部署：

```sh
npx vercel --prod
```

安装请求只负责启动远端后台任务，状态请求重新连接 SSH，因此无需让函数持续运行，也无需保存凭据。

## 服务器要求

- 公网 IPv4 / IPv6，Debian 11+ 或 Ubuntu 20.04+，x86_64 / arm64，正在运行的 systemd。
- `root` 或具有**免密 sudo** 权限的用户，服务器可访问软件源和 GitHub。
- 云平台安全组允许 SSH 端口与节点 TCP 端口（默认 443）。安装器会为启用的 UFW 添加规则，不停用防火墙。

当前只管理本项目部署的节点，不覆盖其他 3x-ui 安装。管理文件位于 `/var/lib/5a-ui/`，安装任务为 `5a-ui-install.service`，节点服务为 `x-ui.service`。3x-ui 固定使用 `v3.10.0`，安装脚本校验 SHA-256。

## 隐私与访问控制

- Web 后端会接触用户输入的 SSH 凭据，使用公共实例时应信任该实例运营者；可选择自行部署或使用原生应用。
- 凭据不进入 URL、应用日志、数据库或浏览器存储；API 响应禁止缓存，只接受同源 POST JSON。
- 首次连接记录并展示 SHA-256 主机指纹，当前会话后续连接固定该指纹；也可预填已核对的主机指纹。
- 只允许公网 IP，拦截回环、内网、链路本地、保留地址及 IPv4 映射的私网地址。
- 面板绑定 `127.0.0.1`，网站和原生应用通过 SSH 读取面板；面板密码、API token 与 REALITY 私钥保存在用户服务器的 root 专用文件中。
- 复制或导出的节点链接、二维码也是访问凭据，请妥善保存。
- 本地和 Vercel 的限流为实例内计数；Cloudflare 使用平台限流。反向代理后的 Dart 服务按连接来源 IP 计数。
- Web 渲染引擎随静态文件部署；缺少的文字字形可能从 `fonts.gstatic.com` 加载，不包含连接凭据。

## 可选 Turnstile

Web 后端支持以下环境变量；两项需同时配置，原生应用不需要此验证：

| 变量 | 用途 |
| --- | --- |
| `TURNSTILE_SITE_KEY` | 公开 widget key，由 `/api/config` 提供给页面 |
| `TURNSTILE_SECRET_KEY` | 仅后端使用的校验密钥 |
| `PUBLIC_ORIGIN` | Dart 服务位于反向代理后时的完整外部源地址 |

Cloudflare 使用 Worker Variables 和 `pnpm exec wrangler secret put TURNSTILE_SECRET_KEY`；Vercel 使用项目环境变量；Docker Compose 可从 `.env` 读取。本地 Dart 启动时继承环境变量。

验证成功后签发 30 分钟证明，用于安装进度轮询。证明绑定访问来源、服务器 IP、SSH 端口和用户名，不包含 SSH 密码，不替代 SSH 认证。

## 开发与验证

```sh
fvm flutter pub get
(cd packages/five_a_core && fvm dart pub get)
(cd server && fvm dart pub get)
fvm dart run tool/generate.dart --check
fvm flutter analyze
fvm flutter test
(cd packages/five_a_core && fvm dart pub get && fvm dart test)
(cd server && fvm dart pub get && fvm dart test)
pnpm install --frozen-lockfile
pnpm check
pnpm test
pnpm test:ssh
pnpm test:worker
pnpm test:remote
pnpm check:cloudflare
```

`test:ssh` 使用临时本机 SSH 服务验证 Dart 的密码、私钥、指纹与错误处理。`test:worker` 在 workerd 中验证相同 SSH 能力。它们不访问用户服务器、不执行真实安装。跨语言测试逐字比较 Dart 与 TypeScript 生成的远端命令。

GitHub Actions 的 Check and build 检查共享契约、客户端和后端测试；Package 负责版本打包与上传。`pnpm test:remote` 同时运行打包脚本测试。实际已完成的验证及未验证的平台见 [验证记录](docs/verification.md)。

```text
lib/                         Flutter 界面、轮询、平台入口
packages/five_a_core/         契约、校验、结果解析、原生 Dart SSH
server/                      本地 / Docker Dart API 与静态服务
contracts/                   两种后端共用的输入样例与地址规则
scripts/remote/              共用安装、状态查询及 systemd 任务脚本
tool/generate.dart           生成两种语言内嵌的远端资源
tool/dev.dart                本地完整 Web 启动命令
src/server/                  Vercel / Cloudflare TypeScript 适配
src/worker.ts                Cloudflare 入口
api/                         Vercel 入口
```

修改 `scripts/remote/` 或地址规则后运行 `fvm dart run tool/generate.dart`，不要直接编辑生成文件。升级 3x-ui 时同步版本、SHA-256 与 API 契约验证。

## 开源许可

本项目采用 MIT License。独立安装的 [3x-ui](https://github.com/MHSanaei/3x-ui) 和 Xray 保留各自的开源许可。
