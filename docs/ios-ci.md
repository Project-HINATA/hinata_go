# iOS 发布 CI

`.github/workflows/ios.yml` 使用 GitHub 托管的 `macos-26` runner，固定选择镜像内的 Xcode 26.5，并通过 `subosito/flutter-action` 安装 Flutter 3.47.2。工作流同时设置全局 `xcode-select` 和 `DEVELOPER_DIR`，因为 Flutter 原生资源构建可能不继承后者。Fastlane 使用 runner 镜像预装版本，Homebrew 路径由 `brew --prefix` 获取，不依赖自托管机器的工具或 `/usr/local/bin`。

所有 iOS 发布共用 `ios-publish` 并发组，正在进行的构建不会被新提交取消，避免同时计算并上传相同 App Store 构建号。单个 job 最长运行 60 分钟。

推送到 `main` 仍只上传 TestFlight。手动运行可选择 `beta` 或 `production`；后者沿用现有 App Store 审核与发布流程。主 App、App Clip 和两个 Live Activity 扩展的签名及版本校验保持原流程。

签名沿用仓库 Secrets：`IOS_ASC_KEY_ID`、`IOS_ASC_ISSUER_ID`、`IOS_ASC_KEY_P8_BASE64`、`IOS_SIGNING_P12_BASE64`、`IOS_SIGNING_P12_PASSWORD`。证书导入临时 keychain，API 私钥仅写入临时文件，结束时清理。私有插件仍使用 `LOCAL_PLUGINS_*` 与 `CARDCIPHER_*` Secrets 拉取。无需自托管 runner 的登录凭据、已有 provisioning profile 或本地 Flutter 安装。

迁移前的失败运行已完成 archive，但在 exportArchive 写入 `.symbols` 文件时失败，并出现 Apple 接口 401；迁移后的导出及上传结果以新的 GitHub Actions 运行记录为准。

Runner 镜像参考：[GitHub macOS 26 软件清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)。更新 Xcode 固定版本前，应确认它仍包含在该镜像中。

## PR 原生回归

`native-checks.yml` 在 pull_request 上执行 macOS Swift 原生检查和 Flutter 格式/静态分析，独立于 iOS 发布流程。扫码用例使用模拟 HTTP 与认证/定位边界，编译真实共享 Swift 模型、API 与 view model；不读取发布签名密钥，不上传 TestFlight。请求退避与接口配合见 [原生 PRiSM 接口文档](prism-web-integration.md#native-scan-performance-and-prism-request-budgets)。
