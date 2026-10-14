## 安装包说明

- Android：按 ABI 分别提供 APK 和通用 AAB。文件名含 `test-signed` 的包使用临时调试签名，仅用于测试；正式发布前需配置固定的 Android 签名。
- macOS：Universal DMG，包含 Intel 和 Apple Silicon 架构。当前使用 ad-hoc 签名，未做 Apple 公证。
- Windows：x64 安装程序与便携 ZIP，包含所需 VC++ 运行库；安装程序尚未做 Authenticode 签名。
- Linux：x64 / ARM64 的 DEB 和 tar.gz；需要 GTK 3 和桌面文件选择 portal。x64 基于 Ubuntu 22.04，ARM64 基于 Ubuntu 24.04 构建。
- iOS：`unsigned.ipa` 需使用自己的 Apple 证书和描述文件重新签名，不能直接用于 App Store 或设备安装。
- Web：静态 ZIP 需搭配后端；`web-linux-x64.tar.gz` 包含 Dart 后端，解压后运行 `./start.sh`，默认监听 `127.0.0.1:5000`。

下载后可使用 `SHA256SUMS` 校验文件。`pre-alpha` 为滚动预发布，每次覆盖此前全部附件；具体构建版本、提交和平台见上方记录。
