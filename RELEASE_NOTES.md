# Agnes Harness Desktop 0.1.0 Preview

Agnes Harness 的非官方 macOS 桌面封装，现发布首个社区预览版。无需终端或额外安装 Node.js。

**本版尚未经过 Apple 公证，也没有 Developer ID 签名。首次打开可能被 macOS 拦截，请先阅读安装说明。**

## 下载与安装

- 安装包：`Agnes-Harness-Desktop-0.1.0-macOS-arm64.dmg`
- 仅限 Apple Silicon（M 系列）Mac；已实测 macOS 26.6.2。
- 下载后打开 DMG，把应用拖入“应用程序”。
- 初次被拦截时，在确认来源可信且文件未被篡改后，按“系统设置 → 隐私与安全性 → 仍要打开”操作。参考 [Apple 官方说明](https://support.apple.com/en-us/102445)。
- 详细步骤见附件 `INSTALL.md`。

## 本版功能

- 内置 Node.js 24.20.0 和完整 Agnes 运行包。
- 独立桌面窗口、Dock 与菜单栏入口。
- 自动启动后台，支持正常退出与重新启动。
- 原生工作文件夹选择，支持文件上传和下载面板。
- 保留 Agnes 的会话、插件、模型设置、审批与轨迹界面。
- 使用独立数据目录，不迁移旧版数据。

## 验证与已知限制

已验证中文 Demo 对话、工作目录选择、退出后会话恢复，5 组后台生命周期测试通过。DMG 校验通过，并已从只读镜像启动验证。

本地 Demo 不具备真实推理能力。实际工作需要配置自己的模型账户。真实模型、语音、所有第三方插件、其他 macOS 版本和长期运行尚未完整实测；没有自动更新。

不提供 Windows、Linux 或 Intel Mac 安装包。本版属于开发预览，可能存在兼容性问题。

## 校验与来源

附件 `SHA256SUMS.txt` 提供安装包与源码包的 SHA-256。

内置图像编解码库 libvips 及其依赖保留各自许可，包含 LGPL 组件。源码包中的 `third-party/sharp-libvips/` 提供版本、许可文本和对应源码入口，另附 `sharp-libvips-1.2.4-build-source.tar.gz` 构建源码。

上游：[AgnesAI-Labs/agnes-harness](https://github.com/AgnesAI-Labs/agnes-harness)，固定提交 `43085b2bc2dfa519dd39b78e67224cb1f0d36320`。桌面源码和构建脚本随本项目公开，许可证及第三方声明保留在应用资源和源码中。本项目不代表 Agnes AI 官方发布。
