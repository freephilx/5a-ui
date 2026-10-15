# cfnew 部署

通过侧栏“Cloudflare”或概览“部署 cfnew”进入。填写 Cloudflare 账号 ID、API Token 和 Worker 名称后，点击“一键部署 cfnew”。UUID 自动随机生成；访问凭据与说明中可复制或修改。账号需先在 Cloudflare 控制台启用 workers.dev 子域名。

Token 限定到目标账号，授予 **Workers Scripts 编辑**、**Workers KV Storage 编辑**权限。应用使用当前账号额度，不修改套餐、DNS 或已有 Worker；原生端直接调用 Cloudflare，Web 端由当前 5a-ui 后端调用，因此 Web 部署需可信。Token 只存在本次会话，不加入本机服务器保存记录、部署信息导出、Worker 代码或环境变量。完成后可以清除 Token。

部署依次完成账号/同名检查、KV 准备、固定源码下载与校验、上传、开启 workers.dev、配置回读和公开管理接口验证。返回管理页面、通用订阅、Clash/Mihomo 订阅及 Cloudflare 控制台地址。后续协议、优选和配置管理使用 **cfnew 自带面板**，并非在 5a-ui 中复刻其全部管理能力。

## 来源与默认值

- 用户提供的 [项目介绍](https://huarun.win/servers/cfnew) 指向 [byJoey/cfnew](https://github.com/byJoey/cfnew)。接入基于 v3.1，固定提交 `a327f9ca5adac1f605fb2cd33415daad1d75d444` 的明文脚本。
- 兼容日期 `2026-01-20`。源码 SHA-256：`3063f650b1337d3e689cae5fb7b4b7a18b4a3c0a8e7ac5a17b16156edcb4e92c`。版本清单在 `contracts/cfnew-release.json`，通过生成工具同步 Dart/TypeScript；升级需重新核对与验收，不能直接跟随 main。
- KV 绑定 `C`，UUID 以 Worker secret `u` 上传。默认开启 VLESS、原生地址、仅 TLS；关闭第三方优选、家宽链式和优选管理 API。可以在 cfnew 管理页面调整。Worker 请求日志默认关闭，避免记录包含 UUID 的路径。
- 上游未提供明确许可证文件，本项目不捆绑、镜像或复制其源码；实际部署时从固定上游地址下载并验证，再上传到用户账号。上游自身仍包含远程资源及可选第三方来源，启用相关功能时需自行选择可信来源。
- 5a-ui 当前提供 **Workers** 一键部署，不提供 Pages 上传入口，也不自动绑定自定义域名。

## 失败与恢复

阶段间分别请求，避免把完整部署放入一个长请求。暂停会等待当前请求结束；关闭应用后已创建的云资源仍会保留。用相同账号、Worker 名称和 UUID 重试，系统会核对部署归属并复用 KV/Worker，不重复上传已确认的代码，也不重置 KV 配置。可导出部署信息以保留名称、UUID 和链接；导出文件含访问凭据，应妥善保存。

未知同名 Worker、不同 UUID、不同版本、绑定改变或权限不足均停止。Cloudflare 上传接口没有本项目可用的原子“仅创建”条件，因此仍应使用默认随机名称，避免同时从其他工具创建同名 Worker。网络失败不会自动删除云资源，也不会把未确认的请求当作成功；如放弃部署，可在 Cloudflare 控制台删除本次专用 Worker 和对应 `5a-ui-…` KV，勿删除其他服务使用的存储。

“已部署，访问待验证”表示 Cloudflare 已确认资源，但当前网络尚未读到可用的 cfnew 管理接口。可点击“重新验证访问”。即使管理接口验证成功，也不代表已验证所有地区可达性或代理转发握手；workers.dev 的访问条件、Cloudflare 额度和上游限制仍适用。

## 验证

本地自动测试覆盖参数白名单、同源/验证码限制、权限拒绝、源码校验、同名保护、资源归属、阶段回读、故障恢复和 Dart/TypeScript 一致性。`pnpm test:cfnew-runtime` 会下载固定上游到内存，使用本地 workerd 和临时 KV 检查真实管理接口、TLS VLESS 与 Clash 订阅、拒绝错误路径、配置保存回读；不创建 Cloudflare 线上资源，也不进行代理出站连接。实际平台验收见 [verification.md](verification.md)。
