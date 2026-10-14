# 5a-ui

无需网站账号，使用自己的服务器密码或 SSH 私钥，一键部署 3x-ui 和 VLESS + REALITY。可部署到 Cloudflare Workers 或 Vercel，也可在本地运行。

## 功能

- 密码和 SSH 私钥登录，支持加密私钥口令、用户名和自定义 SSH 端口。
- 自动安装固定版本的 3x-ui，生成 REALITY 密钥与客户端身份，返回 VLESS 链接和二维码。
- 自动探测可用的 TLS 1.3 REALITY 目标，无需购买域名或申请节点证书。
- 读取安装进度、服务状态、节点流量、CPU、内存及节点 TCP 端口可达性。
- 安装任务在服务器上通过 systemd 独立运行，网页关闭后继续。重复操作复用任务或节点，失败后可重试。
- 不覆盖已有的其他 3x-ui 安装。当前版本只管理本项目部署的节点。
- 网站不持久化 SSH 密码、私钥或口令；连接凭据仅在页面内存及当前后端请求中使用。

## 使用条件

目标服务器需要公网 IPv4/IPv6、Debian 11+ 或 Ubuntu 20.04+、x86_64/arm64 架构，以及正在运行的 systemd。使用 `root` 或具有**免密 sudo** 权限的用户。服务器需要能够访问软件源和 GitHub。

云平台安全组必须允许 SSH 端口，以及节点 TCP 端口（默认 `443`）。SSH 凭据无法修改云平台安全组。安装程序会为已启用的 UFW 添加节点端口规则，不停用防火墙。

默认 SSH 用户名是 `root`；部分云平台使用 `ubuntu` 或 `debian`，可在服务器 IP 旁的「用户名」中修改。支持选择或粘贴 OpenSSH、RSA、EC 私钥，以及 RSA/EC 的 PKCS#8 PEM 私钥；加密私钥需填写口令。

## 本地运行

需要 Node.js 22.12+、pnpm 11，以及运行测试时使用的 Python 3。

```sh
corepack enable
pnpm install
pnpm start
```

默认监听 `0.0.0.0:5000`。本机打开 `http://localhost:5000`，同一局域网中的设备打开终端输出的 Network 地址（`http://本机局域网IP:5000`）。前端和 API 随同一条命令启动，无需 Cloudflare、Vercel、额外服务或数据库。`pnpm dev` 使用相同的启动方式，并支持热更新。

5000 端口被占用时会报错，不会自动切换端口。macOS 的「隔空播放接收器」可能占用此端口，可在系统设置中关闭，或指定本机的局域网 IP 尝试启动：

```sh
LOCAL_HOST=192.168.1.100 pnpm start
```

将示例 IP 替换为本机实际地址；指定后通过该 IP 访问。

## 部署到 Cloudflare

```sh
pnpm install --frozen-lockfile
pnpm exec wrangler login
pnpm deploy:cloudflare
```

默认 Worker 名称为 `5a-ui`，可修改 `wrangler.jsonc` 的 `name`。静态页面和 API 都部署到同一个 Worker。配置已包含原生 IP 限流：每分钟最多 60 次请求、3 次安装请求；关闭应用日志记录。生产使用需确保 Workers 的 CPU 配额足以完成 SSH 握手与加密私钥解密，建议使用 Workers Paid。

项目更名后，部署会创建或更新名为 `5a-ui` 的 Worker，已有的其他名称 Worker 不会自动更名。

Cloudflare 的部分 CommonJS 加密接口与 Node.js 不同。项目使用测试过的 NIST P-256 密钥交换、AES-CTR 与 SHA-2 HMAC，并关闭 SSH 压缩和可选原生加速模块；标准 OpenSSH 服务支持此组合。Worker 使用自定义打包脚本，不需要另一台 SSH 中转服务器。

## 部署到 Vercel

在 Vercel 导入本项目仓库，框架使用 Vite。`vercel.json` 已配置构建命令、输出目录和 Node.js API Functions；不要改成 Edge Runtime。

安装请求只负责在用户服务器上启动后台任务，状态请求重新通过 SSH 读取结果，因此不依赖 Vercel 函数的持续运行，也不需要保存用户凭据。Vercel 版本的内置限流是实例内计数；公开使用时建议同时启用 Turnstile，并在 Vercel 平台设置分布式防滥用规则。

## 可选：Turnstile 人机验证

公开站点可配置 Cloudflare Turnstile。创建 widget 时添加实际站点域名，并配置两项服务器环境变量：

| 变量 | 用途 |
| --- | --- |
| `TURNSTILE_SITE_KEY` | 公开站点 key，由 `/api/config` 返回 |
| `TURNSTILE_SECRET_KEY` | 仅在后端校验验证结果，绝不进入前端构建 |

Cloudflare 将 site key 放入 Worker Variables，将 secret key 使用 `pnpm exec wrangler secret put TURNSTILE_SECRET_KEY` 设置。Vercel 在项目的环境变量中设置这两项后重新部署。本地开发可复制 `.env.example`，使用 `node --env-file=.env` 加载；`wrangler dev` 可使用 `.dev.vars`。

一次验证通过后会签发 30 分钟的短期证明，用于安装进度轮询。证明绑定访问者 IP、服务器 IP、SSH 端口和用户名，不包含 SSH 凭据，不替代 SSH 认证。未配置 Turnstile 时保留 IP 限流。

## 数据和权限

网页后端会接触用户提供的 SSH 登录凭据。开源代码不等于对任意公共实例的信任；希望完全掌握运行环境时，请自行部署。

- SSH 密码、私钥和口令不进入 URL、网站日志、数据库、浏览器 localStorage 或 sessionStorage。
- 首次连接采用首次信任（TOFU），显示 SHA-256 主机指纹；同一页面后续连接固定此指纹。可在高级设置中填写通过云平台控制台核对的已知指纹。
- 只允许公网 IP，拦截回环、内网、链路本地、保留和 IPv4 映射的私网地址。不提供任意命令执行接口。
- 所有带凭据的请求使用同源 POST JSON，API 响应禁止缓存。生产通过平台 HTTPS 访问。
- 3x-ui 面板在第一次启动前即通过 systemd `ExecStartPre` 绑定到 `127.0.0.1`，后续重启仍保持；同时关闭不需要的订阅服务。网站通过 SSH 调用本机管理 API。
- 3x-ui 管理密码、API token、REALITY 私钥与安装进度保存在**用户自己的服务器**上，文件由 root 持有，权限 `0600`，目录权限 `0700`。
- 返回网页的 VLESS 链接与二维码是节点访问凭据，请妥善保存。

服务器上的管理文件位于 `/var/lib/5a-ui/`；安装日志为 `install.log`（可能包含上游安装器生成的面板凭据，仅限 root 读取）。安装任务为 `5a-ui-install.service`，服务为 `x-ui.service`。安装器固定使用上游 `v3.10.0`，先校验安装脚本 SHA-256，上游再校验发布压缩包的校验和。

此前版本的管理目录、安装服务和节点标识不会自动迁移；这些节点会被识别为已有 3x-ui 安装，请使用原版本或现有面板继续管理。更名后已有的 Turnstile 短期证明需重新验证。

## 验证

```sh
pnpm check
pnpm test
pnpm test:worker
pnpm test:remote
pnpm check:cloudflare
```

`test:worker` 在真实 workerd 运行时中连接本地 SSH 服务，验证密码、私钥、加密私钥和主机指纹。Python 测试使用本地 HTTP 面板验证真实请求格式、重复部署复用、已有节点保护与状态中的凭据过滤。

已在 Oracle ARM64 主机上的独立 Ubuntu 24.04 环境完成真实安装、节点复用、REALITY 客户端 HTTPS 连接、流量统计与服务重启回归；Cloudflare 线上 SSH 也已验证。详见 [验证记录](docs/verification.md)。这些检查尚未覆盖所有支持的系统与云平台防火墙组合。端口探测只代表网站所在网络的 TCP 可达性；服务运行状态不等于用户本地客户端可用。

## 技术结构

```text
src/App.tsx                 页面、轮询、节点导出
src/server/                共用 API、SSH、校验与防滥用
scripts/remote/            在用户服务器运行的安装和管理脚本
src/server/remote.generated.ts  自动生成的脚本文本
src/worker.ts              Cloudflare 入口
api/                       Vercel Node.js 入口
scripts/dev.ts             本地 Vite + API 服务
```

修改 `scripts/remote/` 后运行 `pnpm generate`。不要直接修改生成文件。更新上游版本时须同步固定版本和脚本 SHA-256，并重新核对 API 契约。

## 开源许可

本项目采用 MIT License。通过安装器独立安装的 [3x-ui](https://github.com/MHSanaei/3x-ui) 和 Xray 保留各自的开源许可。
